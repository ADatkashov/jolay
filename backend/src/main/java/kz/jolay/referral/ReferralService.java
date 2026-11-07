package kz.jolay.referral;

import kz.jolay.common.ApiException;
import kz.jolay.common.AppSettings;
import kz.jolay.notifications.Notifier;
import kz.jolay.wallet.LedgerService;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Referral codes and the one-off wallet bonus for an invited customer's first completed ride. */
@Service
public class ReferralService {
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // no 0/O/1/I
    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcClient jdbc;
    private final AppSettings settings;
    private final LedgerService ledger;
    private final Notifier notifier;

    public ReferralService(JdbcClient jdbc, AppSettings settings, LedgerService ledger, Notifier notifier) {
        this.jdbc = jdbc; this.settings = settings; this.ledger = ledger; this.notifier = notifier;
    }

    /** The user's own code, generated on first use. */
    @Transactional
    public String codeFor(UUID userId) {
        String existing = stored(userId);
        if (existing != null) return existing;
        for (int attempt = 0; attempt < 10; attempt++) {
            StringBuilder sb = new StringBuilder("J");
            for (int i = 0; i < 7; i++) sb.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
            try {
                if (jdbc.sql("UPDATE users SET referral_code=:c WHERE id=:u AND referral_code IS NULL").param("c", sb.toString()).param("u", userId).update() == 1) return sb.toString();
                return stored(userId);
            } catch (DuplicateKeyException collision) { /* try another code */ }
        }
        throw new IllegalStateException("Could not allocate a referral code");
    }

    private String stored(UUID userId) {
        return (String) jdbc.sql("SELECT referral_code FROM users WHERE id=:u").param("u", userId).query().singleRow().get("referral_code");
    }

    /** Links a freshly registered user to the inviter. Rejects unknown codes so that a typo is noticed at sign-up. */
    @Transactional
    public void attach(UUID newUserId, String code) {
        if (code == null || code.isBlank()) return;
        UUID referrer = jdbc.sql("SELECT id FROM users WHERE referral_code=:c AND deleted_at IS NULL").param("c", code.trim().toUpperCase()).query(UUID.class).optional()
                .orElseThrow(() -> ApiException.badRequest("invalid_referral_code", "This referral code does not exist"));
        if (referrer.equals(newUserId)) throw ApiException.badRequest("invalid_referral_code", "You cannot use your own code");
        jdbc.sql("UPDATE users SET referred_by=:r WHERE id=:u AND referred_by IS NULL").param("r", referrer).param("u", newUserId).update();
    }

    public Map<String, Object> summary(UUID userId) {
        String code = codeFor(userId);
        var row = jdbc.sql("SELECT count(*) AS rewarded, COALESCE(sum(referrer_amount),0) AS earned FROM referral_rewards WHERE referrer_id=:u").param("u", userId).query().singleRow();
        int invited = jdbc.sql("SELECT count(*) FROM users WHERE referred_by=:u").param("u", userId).query(Integer.class).single();
        boolean enabled = "true".equalsIgnoreCase(settings.get("referral.enabled"));
        return Map.of("code", code, "enabled", enabled, "invited", invited, "rewarded", row.get("rewarded"), "earned", row.get("earned"),
                "referrerBonus", settings.getDecimal("referral.referrer_bonus"), "refereeBonus", settings.getDecimal("referral.referee_bonus"));
    }

    /** Called inside the ride-completion transaction. Pays both sides once, when every condition holds; otherwise does nothing. */
    public void onRideCompleted(UUID rideId) {
        if (!"true".equalsIgnoreCase(settings.get("referral.enabled"))) return;
        var ride = jdbc.sql("SELECT r.customer_id, r.final_fare, u.referred_by FROM rides r JOIN users u ON u.id=r.customer_id WHERE r.id=:r").param("r", rideId).query().listOfRows().get(0);
        UUID referee = (UUID) ride.get("customer_id"), referrer = (UUID) ride.get("referred_by");
        if (referrer == null) return;
        BigDecimal fare = (BigDecimal) ride.get("final_fare");
        if (fare == null || fare.compareTo(settings.getDecimal("referral.min_fare")) < 0) return;
        // only the first completed ride counts, and only once per invited user
        if (jdbc.sql("SELECT count(*) FROM rides WHERE customer_id=:c AND status='COMPLETED' AND id<>:r").param("c", referee).param("r", rideId).query(Integer.class).single() > 0) return;
        if (jdbc.sql("SELECT count(*) FROM referral_rewards WHERE referee_id=:c").param("c", referee).query(Integer.class).single() > 0) return;
        if (jdbc.sql("SELECT count(*) FROM referral_rewards WHERE referrer_id=:c").param("c", referrer).query(Integer.class).single() >= settings.getInt("referral.max_rewards_per_referrer")) return;
        if (jdbc.sql("SELECT count(*) FROM users WHERE id=:r AND status='ACTIVE' AND deleted_at IS NULL").param("r", referrer).query(Integer.class).single() == 0) return;

        BigDecimal toReferrer = settings.getDecimal("referral.referrer_bonus"), toReferee = settings.getDecimal("referral.referee_bonus");
        UUID promo = ledger.systemAccount("PROMO");
        List<LedgerService.Leg> legs = new java.util.ArrayList<>();
        if (toReferrer.signum() > 0) legs.add(new LedgerService.Leg(ledger.userAccount(referrer, "CUSTOMER_WALLET"), toReferrer));
        if (toReferee.signum() > 0) legs.add(new LedgerService.Leg(ledger.userAccount(referee, "CUSTOMER_WALLET"), toReferee));
        if (legs.isEmpty()) return;
        legs.add(new LedgerService.Leg(promo, toReferrer.add(toReferee).negate()));
        ledger.post("BONUS", "REFERRAL", rideId, "referral-" + referee, "Referral bonus", legs);
        jdbc.sql("INSERT INTO referral_rewards(referee_id,referrer_id,ride_id,referrer_amount,referee_amount) VALUES (:e,:r,:ride,:ra,:ea)")
                .param("e", referee).param("r", referrer).param("ride", rideId).param("ra", toReferrer).param("ea", toReferee).update();
        notifier.notify(referrer, "REFERRAL_REWARD", "referral-" + referee + "-referrer", Map.of("amount", toReferrer.toPlainString()));
        notifier.notify(referee, "REFERRAL_REWARD", "referral-" + referee + "-referee", Map.of("amount", toReferee.toPlainString()));
    }
}
