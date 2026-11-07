package kz.jolay.promo;

import kz.jolay.common.ApiException;
import kz.jolay.common.Money;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Promo codes. A code is checked when the rider asks for an estimate and again, under a row lock, when the ride is requested; the use is then
 * RESERVED and only APPLIED when the ride completes (the discount is computed on the FINAL fare). The platform pays the discount: see
 * PaymentService for the ledger legs.
 */
@Service
public class PromoService {
    public record Promo(UUID id, String code, String kind, BigDecimal value, BigDecimal maxDiscount, BigDecimal minFare) {
        /** Discount for a given gross fare; zero when the fare is below the code's minimum. Never exceeds the fare. */
        public BigDecimal discountFor(BigDecimal fare) {
            if (fare == null || fare.compareTo(minFare) < 0) return Money.ZERO;
            BigDecimal d = "PERCENT".equals(kind) ? Money.scale(fare.multiply(value).divide(new BigDecimal("100"), 2, java.math.RoundingMode.DOWN)) : Money.scale(value);
            if (maxDiscount != null && d.compareTo(maxDiscount) > 0) d = Money.scale(maxDiscount);
            return d.min(fare);
        }
    }

    private final JdbcClient jdbc;
    public PromoService(JdbcClient jdbc) { this.jdbc = jdbc; }

    public static String normalize(String code) { return code == null ? null : code.trim().toUpperCase(); }

    /** Checks everything about the code and the rider that does not depend on the fare. {@code lock} serialises redemptions of the same code. */
    public Promo check(String rawCode, UUID userId, boolean lock) {
        String code = normalize(rawCode);
        var row = jdbc.sql("SELECT * FROM promo_codes WHERE code=:c" + (lock ? " FOR UPDATE" : "")).param("c", code).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.badRequest("promo_not_found", "This promo code does not exist"));
        UUID id = (UUID) row.get("id");
        if (!Boolean.TRUE.equals(row.get("active"))) throw ApiException.badRequest("promo_inactive", "This promo code is not active");
        boolean outOfWindow = jdbc.sql("SELECT (:s::timestamptz IS NOT NULL AND now() < :s::timestamptz) OR (:e::timestamptz IS NOT NULL AND now() >= :e::timestamptz)")
                .param("s", row.get("starts_at")).param("e", row.get("ends_at")).query(Boolean.class).single();
        if (outOfWindow) throw ApiException.badRequest("promo_expired", "This promo code is not valid now");
        Integer max = (Integer) row.get("max_redemptions");
        if (max != null && jdbc.sql("SELECT count(*) FROM promo_redemptions WHERE promo_id=:p AND status IN ('RESERVED','APPLIED')").param("p", id).query(Integer.class).single() >= max)
            throw ApiException.badRequest("promo_exhausted", "This promo code has been fully used");
        if (jdbc.sql("SELECT count(*) FROM promo_redemptions WHERE promo_id=:p AND user_id=:u AND status IN ('RESERVED','APPLIED')").param("p", id).param("u", userId).query(Integer.class).single() >= (Integer) row.get("per_user_limit"))
            throw ApiException.badRequest("promo_already_used", "You have already used this promo code");
        if (Boolean.TRUE.equals(row.get("first_ride_only")) && jdbc.sql("SELECT count(*) FROM rides WHERE customer_id=:u AND status='COMPLETED'").param("u", userId).query(Integer.class).single() > 0)
            throw ApiException.badRequest("promo_first_ride_only", "This promo code is only for a first ride");
        return new Promo(id, (String) row.get("code"), (String) row.get("kind"), (BigDecimal) row.get("value"), (BigDecimal) row.get("max_discount"), (BigDecimal) row.get("min_fare"));
    }

    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    public void reserve(Promo p, UUID userId, UUID rideId) {
        jdbc.sql("INSERT INTO promo_redemptions(promo_id,user_id,ride_id) VALUES (:p,:u,:r)").param("p", p.id()).param("u", userId).param("r", rideId).update();
    }

    /** Completion: fixes the discount on the final fare and marks the use as applied. Returns zero when the ride has no promo. */
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    public BigDecimal applyOnCompletion(UUID rideId, BigDecimal finalFare) {
        var red = jdbc.sql("""
                SELECT x.id, p.kind, p.value, p.max_discount FROM promo_redemptions x JOIN promo_codes p ON p.id=x.promo_id WHERE x.ride_id=:r AND x.status='RESERVED'""")
                .param("r", rideId).query().listOfRows().stream().findFirst().orElse(null);
        if (red == null) return Money.ZERO;
        BigDecimal d = new Promo(null, null, (String) red.get("kind"), (BigDecimal) red.get("value"), (BigDecimal) red.get("max_discount"), Money.ZERO).discountFor(finalFare);
        jdbc.sql("UPDATE promo_redemptions SET status='APPLIED', discount=:d WHERE id=:id").param("d", d).param("id", red.get("id")).update();
        return d;
    }

    /** Ride cancelled / expired / failed: the rider gets the use back. */
    public void release(UUID rideId) {
        jdbc.sql("UPDATE promo_redemptions SET status='RELEASED' WHERE ride_id=:r AND status='RESERVED'").param("r", rideId).update();
    }
}
