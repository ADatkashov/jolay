package kz.jolay.payments;

import kz.jolay.common.ApiException;
import kz.jolay.common.AppSettings;
import kz.jolay.common.Money;
import kz.jolay.notifications.Notifier;
import kz.jolay.wallet.LedgerService;
import kz.jolay.wallet.LedgerService.Leg;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Driver and partner payouts through the ledger. Request: DRIVER_WALLET / PARTNER_WALLET -> PAYOUT_CLEARING (funds are held immediately, so they cannot be spent twice).
 * Paid by finance: PAYOUT_CLEARING -> EXTERNAL_BANK (money leaves the platform). Rejected: PAYOUT_CLEARING -> DRIVER_WALLET (released).
 * The bank transfer itself is performed by finance outside the system; "pay" records the bank reference.
 */
@Service
public class PayoutService {
    private final JdbcClient jdbc;
    private final LedgerService ledger;
    private final AppSettings settings;
    private final Notifier notifier;

    public PayoutService(JdbcClient jdbc, LedgerService ledger, AppSettings settings, Notifier notifier) { this.jdbc = jdbc; this.ledger = ledger; this.settings = settings; this.notifier = notifier; }

    @Transactional
    public UUID request(UUID driverId, BigDecimal rawAmount, String destination) { return request(driverId, rawAmount, destination, "DRIVER_WALLET"); }

    /** walletType is DRIVER_WALLET (approved driver) or PARTNER_WALLET (approved partner); it is stored so release/payment use the same account. */
    @Transactional
    public UUID request(UUID driverId, BigDecimal rawAmount, String destination, String walletType) {
        BigDecimal amount = Money.scale(rawAmount);
        if (amount.compareTo(settings.getDecimal("payouts.min_amount")) < 0) throw ApiException.badRequest("payout_below_minimum", "Amount is below the minimum payout");
        if (destination == null || !destination.replaceAll("\\s", "").matches("[A-Za-z0-9]{8,40}")) throw ApiException.badRequest("invalid_destination", "Invalid payout destination");
        boolean partner = "PARTNER_WALLET".equals(walletType);
        if (jdbc.sql(partner ? "SELECT status='APPROVED' FROM partners WHERE owner_id=:d" : "SELECT verification='APPROVED' FROM drivers WHERE user_id=:d").param("d", driverId).query(Boolean.class).optional().orElse(false) == false)
            throw ApiException.forbidden(partner ? "partner_not_approved" : "driver_not_approved", partner ? "Partner account is not approved" : "Driver account is not approved");
        UUID id = UUID.randomUUID();
        try {
            jdbc.sql("INSERT INTO payouts(id,driver_id,amount,destination,wallet_type) VALUES (:id,:d,:a,:dest,:w)").param("w", walletType).param("id", id).param("d", driverId).param("a", amount).param("dest", destination.replaceAll("\\s", "")).update();
        } catch (org.springframework.dao.DuplicateKeyException e) { throw ApiException.conflict("payout_already_requested", "You already have a payout in progress"); }
        UUID drv = ledger.userAccount(driverId, walletType);
        if (ledger.balance(drv).compareTo(amount) < 0) throw ApiException.conflict("insufficient_funds", "Wallet balance is lower than the requested payout");
        // DRIVER_WALLET has no CHECK against negative balances, so the balance check above is the guard (row lock is taken by the posting below).
        UUID tx = ledger.post("PAYOUT", "PAYOUT", id, "payout-hold-" + id, "Payout requested", List.of(new Leg(drv, amount.negate()), new Leg(ledger.systemAccount("PAYOUT_CLEARING"), amount)));
        jdbc.sql("UPDATE payouts SET hold_tx=:t WHERE id=:id").param("t", tx).param("id", id).update();
        return id;
    }

    @Transactional
    public void pay(UUID reviewer, UUID payoutId, String reference) {
        var p = lock(payoutId);
        BigDecimal amount = (BigDecimal) p.get("amount");
        UUID tx = ledger.post("PAYOUT", "PAYOUT", payoutId, "payout-paid-" + payoutId, "Payout paid: " + reference,
                List.of(new Leg(ledger.systemAccount("PAYOUT_CLEARING"), amount.negate()), new Leg(ledger.systemAccount("EXTERNAL_BANK"), amount)));
        jdbc.sql("UPDATE payouts SET status='PAID', reference=:r, reviewed_by=:u, reviewed_at=now(), final_tx=:t WHERE id=:id").param("r", reference).param("u", reviewer).param("t", tx).param("id", payoutId).update();
        notifier.notify((UUID) p.get("driver_id"), "PAYOUT_PAID", "payout-" + payoutId + "-paid", Map.of("payoutId", payoutId.toString(), "amount", amount));
    }

    @Transactional
    public void reject(UUID reviewer, UUID payoutId, String reason) {
        var p = lock(payoutId);
        BigDecimal amount = (BigDecimal) p.get("amount");
        UUID drv = ledger.userAccount((UUID) p.get("driver_id"), (String) p.get("wallet_type"));
        UUID tx = ledger.post("PAYOUT", "PAYOUT", payoutId, "payout-released-" + payoutId, "Payout rejected: " + reason,
                List.of(new Leg(ledger.systemAccount("PAYOUT_CLEARING"), amount.negate()), new Leg(drv, amount)));
        jdbc.sql("UPDATE payouts SET status='REJECTED', note=:n, reviewed_by=:u, reviewed_at=now(), final_tx=:t WHERE id=:id").param("n", reason).param("u", reviewer).param("t", tx).param("id", payoutId).update();
        notifier.notify((UUID) p.get("driver_id"), "PAYOUT_REJECTED", "payout-" + payoutId + "-rejected", Map.of("payoutId", payoutId.toString(), "reason", reason));
    }

    private Map<String, Object> lock(UUID id) {
        var p = jdbc.sql("SELECT id, driver_id, amount, status, wallet_type FROM payouts WHERE id=:id FOR UPDATE").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("payout_not_found", "Payout not found"));
        if (!"REQUESTED".equals(p.get("status"))) throw ApiException.conflict("payout_not_open", "Payout was already processed");
        return p;
    }
}
