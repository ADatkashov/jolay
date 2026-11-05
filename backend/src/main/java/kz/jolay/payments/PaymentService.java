package kz.jolay.payments;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import kz.jolay.common.ApiException;
import kz.jolay.common.Money;
import kz.jolay.notifications.Notifier;
import kz.jolay.risk.RiskService;
import kz.jolay.wallet.LedgerService;
import kz.jolay.wallet.LedgerService.Leg;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class PaymentService {
    private static final Logger log = LoggerFactory.getLogger(PaymentService.class);
    private final JdbcClient jdbc;
    private final LedgerService ledger;
    private final Notifier notifier;
    private final ObjectMapper mapper;
    private final Map<String, PaymentProvider> providers;
    private final String defaultProvider;
    private final MeterRegistry metrics;
    private final RiskService risk;

    public PaymentService(JdbcClient jdbc, LedgerService ledger, Notifier notifier, ObjectMapper mapper, List<PaymentProvider> providers,
                          @Value("${jolay.payments.provider}") String defaultProvider, MeterRegistry metrics, RiskService risk) {
        this.risk = risk;
        this.jdbc = jdbc; this.ledger = ledger; this.notifier = notifier; this.mapper = mapper; this.defaultProvider = defaultProvider; this.metrics = metrics;
        this.providers = providers.stream().collect(java.util.stream.Collectors.toMap(PaymentProvider::name, p -> p));
    }

    public PaymentProvider provider(String name) {
        PaymentProvider p = providers.get(name);
        if (p == null) throw ApiException.notFound("unknown_provider", "Unknown payment provider");
        return p;
    }

    public record PaymentView(UUID id, String status, String purpose, BigDecimal amount, String provider, String checkoutUrl, UUID rideId) {}

    // ---------------- ride settlement (called on ride completion) ----------------

    /** Settles what can be settled without the customer: CASH (commission owed by driver) and WALLET. CARD stays PENDING. */
    @Transactional
    public void settleRideOnCompletion(UUID rideId) {
        var r = jdbc.sql("""
                SELECT r.id, r.customer_id, r.driver_id, r.payment_method, r.payment_status, f.total, f.commission, f.driver_earnings
                FROM rides r JOIN ride_fares f ON f.ride_id=r.id WHERE r.id=:id FOR UPDATE OF r""")
                .param("id", rideId).query().listOfRows().get(0);
        if ("PAID".equals(r.get("payment_status"))) return;
        String method = (String) r.get("payment_method");
        switch (method) {
            case "CASH" -> {
                // Driver collected the full fare in cash. The platform's cut is debited from the driver's wallet.
                UUID driverAcc = ledger.userAccount((UUID) r.get("driver_id"), "DRIVER_WALLET");
                BigDecimal commission = (BigDecimal) r.get("commission");
                if (commission.signum() > 0)
                    ledger.post("CASH_COMMISSION", "RIDE", rideId, "ride-cash-" + rideId, "Commission on cash ride",
                            List.of(new Leg(driverAcc, commission.negate()), new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission)));
                markRidePaid(rideId);
            }
            case "WALLET" -> {
                try { payRideFromWallet(rideId); }
                catch (ApiException e) {
                    if (!"insufficient_funds".equals(e.code())) throw e;
                    jdbc.sql("UPDATE rides SET payment_status='FAILED', updated_at=now() WHERE id=:id").param("id", rideId).update();
                    notifier.notify((UUID) r.get("customer_id"), "PAYMENT_STATUS_UPDATED", "pay-failed-" + rideId,
                            Map.of("rideId", rideId.toString(), "paymentStatus", "FAILED", "reason", "insufficient_funds"));
                }
            }
            default -> jdbc.sql("UPDATE rides SET payment_status='PENDING', updated_at=now() WHERE id=:id").param("id", rideId).update();
        }
    }

    private void payRideFromWallet(UUID rideId) {
        var r = jdbc.sql("SELECT r.customer_id, r.driver_id, f.total, f.commission, f.driver_earnings FROM rides r JOIN ride_fares f ON f.ride_id=r.id WHERE r.id=:id")
                .param("id", rideId).query().listOfRows().get(0);
        UUID cust = ledger.userAccount((UUID) r.get("customer_id"), "CUSTOMER_WALLET");
        UUID drv = ledger.userAccount((UUID) r.get("driver_id"), "DRIVER_WALLET");
        BigDecimal total = (BigDecimal) r.get("total"), commission = (BigDecimal) r.get("commission"), earnings = (BigDecimal) r.get("driver_earnings");
        List<Leg> legs = new java.util.ArrayList<>(List.of(new Leg(cust, total.negate()), new Leg(drv, earnings)));
        if (commission.signum() > 0) legs.add(new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission));
        ledger.post("RIDE_PAYMENT", "RIDE", rideId, "ride-pay-" + rideId, "Ride payment (wallet)", legs);
        markRidePaid(rideId);
    }

    private void markRidePaid(UUID rideId) {
        jdbc.sql("UPDATE rides SET payment_status='PAID', updated_at=now() WHERE id=:id").param("id", rideId).update();
        UUID customer = jdbc.sql("SELECT customer_id FROM rides WHERE id=:id").param("id", rideId).query(UUID.class).single();
        notifier.notify(customer, "PAYMENT_STATUS_UPDATED", "pay-ok-" + rideId, Map.of("rideId", rideId.toString(), "paymentStatus", "PAID"));
    }

    // ---------------- customer-initiated payments ----------------

    /** "Pay now" for a completed ride that is not paid yet (card or wallet). Fare is always read from the server. */
    @Transactional
    public PaymentView payRide(UUID userId, UUID rideId, String method, String idempotencyKey) {
        var r = jdbc.sql("SELECT r.customer_id, r.status, r.payment_status, f.total FROM rides r LEFT JOIN ride_fares f ON f.ride_id=r.id WHERE r.id=:id FOR UPDATE OF r")
                .param("id", rideId).query().listOfRows().stream().findFirst().orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
        if (!userId.equals(r.get("customer_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        if (!"COMPLETED".equals(r.get("status"))) throw ApiException.conflict("ride_not_completed", "Ride is not completed");
        if ("PAID".equals(r.get("payment_status"))) throw ApiException.conflict("already_paid", "Ride is already paid");
        BigDecimal total = (BigDecimal) r.get("total");

        if ("WALLET".equals(method)) {
            payRideFromWallet(rideId);
            jdbc.sql("UPDATE rides SET payment_method='WALLET' WHERE id=:id").param("id", rideId).update();
            return new PaymentView(null, "SUCCEEDED", "RIDE", total, "wallet", null, rideId);
        }
        if (!"CARD".equals(method)) throw ApiException.badRequest("invalid_method", "Unsupported payment method for this ride");
        var existing = jdbc.sql("SELECT id, status, provider_ref, provider FROM payment_transactions WHERE ride_id=:r AND status IN ('PENDING','SUCCEEDED')").param("r", rideId).query().listOfRows();
        if (!existing.isEmpty()) {
            var e = existing.get(0);
            return new PaymentView((UUID) e.get("id"), (String) e.get("status"), "RIDE", total, (String) e.get("provider"), checkoutUrl((UUID) e.get("id")), rideId);
        }
        return createCardPayment(userId, "RIDE", rideId, total, idempotencyKey, "JOLAY ride");
    }

    @Transactional
    public PaymentView topUp(UUID userId, BigDecimal amount, String idempotencyKey) {
        BigDecimal a = Money.scale(amount);
        if (a.compareTo(new BigDecimal("100")) < 0 || a.compareTo(new BigDecimal("500000")) > 0)
            throw ApiException.badRequest("invalid_amount", "Top-up amount must be between 100 and 500000 KZT");
        if (idempotencyKey != null) {
            var existing = jdbc.sql("SELECT id, status, amount, provider FROM payment_transactions WHERE user_id=:u AND idempotency_key=:k").param("u", userId).param("k", idempotencyKey).query().listOfRows();
            if (!existing.isEmpty()) { var e = existing.get(0);
                return new PaymentView((UUID) e.get("id"), (String) e.get("status"), "TOPUP", (BigDecimal) e.get("amount"), (String) e.get("provider"), checkoutUrl((UUID) e.get("id")), null); }
        }
        return createCardPayment(userId, "TOPUP", null, a, idempotencyKey, "JOLAY wallet top-up");
    }

    private PaymentView createCardPayment(UUID userId, String purpose, UUID rideId, BigDecimal amount, String idemKey, String desc) {
        PaymentProvider p = provider(defaultProvider);
        UUID id = UUID.randomUUID();
        PaymentProvider.Initiation init = p.initiate(id, amount, "KZT", desc);
        jdbc.sql("INSERT INTO payment_transactions(id,user_id,purpose,ride_id,provider,amount,status,provider_ref,idempotency_key) VALUES (:id,:u,:pu,:r,:p,:a,'PENDING',:ref,:k)")
                .param("id", id).param("u", userId).param("pu", purpose).param("r", rideId).param("p", p.name()).param("a", amount)
                .param("ref", init.providerRef()).param("k", idemKey).update();
        metrics.counter("jolay.payments.initiated", "provider", p.name()).increment();
        return new PaymentView(id, "PENDING", purpose, amount, p.name(), init.checkoutUrl(), rideId);
    }

    private String checkoutUrl(UUID paymentId) { return provider(defaultProvider).checkoutUrl(paymentId); }

    public PaymentView get(UUID userId, UUID paymentId, boolean admin) {
        var e = jdbc.sql("SELECT id,user_id,status,purpose,amount,provider,ride_id FROM payment_transactions WHERE id=:id").param("id", paymentId).query().listOfRows()
                .stream().findFirst().orElseThrow(() -> ApiException.notFound("payment_not_found", "Payment not found"));
        if (!admin && !userId.equals(e.get("user_id"))) throw ApiException.notFound("payment_not_found", "Payment not found");
        return new PaymentView(paymentId, (String) e.get("status"), (String) e.get("purpose"), (BigDecimal) e.get("amount"), (String) e.get("provider"), null, (UUID) e.get("ride_id"));
    }

    // ---------------- gateway callbacks ----------------

    /**
     * Processes a gateway callback. Authenticity is established ONLY by the HMAC signature over the raw body; the client
     * response is never trusted. Replays are ignored (event id dedupe + status guard + ledger idempotency key).
     */
    @Transactional
    public String handleWebhook(String providerName, String rawBody, String signature) {
        PaymentProvider p = provider(providerName);
        if (!p.verifySignature(rawBody, signature)) {
            metrics.counter("jolay.payments.webhook_rejected").increment();
            throw ApiException.unauthorized("invalid_signature", "Invalid signature");
        }
        JsonNode n;
        try { n = mapper.readTree(rawBody); } catch (Exception e) { throw ApiException.badRequest("malformed_request", "Malformed body"); }
        String eventId = n.path("eventId").asText(null), ref = n.path("providerRef").asText(null), status = n.path("status").asText(null);
        if (eventId == null || ref == null || status == null) throw ApiException.badRequest("malformed_request", "Missing fields");

        int fresh = jdbc.sql("INSERT INTO payment_webhook_events(provider,event_id) VALUES (:p,:e) ON CONFLICT DO NOTHING").param("p", providerName).param("e", eventId).update();
        if (fresh == 0) { risk.onDuplicateCallback(providerName, ref); return "duplicate"; }

        var pay = jdbc.sql("SELECT id,user_id,purpose,ride_id,amount,status FROM payment_transactions WHERE provider=:p AND provider_ref=:r FOR UPDATE")
                .param("p", providerName).param("r", ref).query().listOfRows().stream().findFirst().orElse(null);
        if (pay == null) { log.warn("webhook for unknown payment ref"); return "unknown_payment"; }
        if (!"PENDING".equals(pay.get("status"))) return "ignored";

        UUID id = (UUID) pay.get("id");
        BigDecimal amount = (BigDecimal) pay.get("amount");
        if ("SUCCEEDED".equalsIgnoreCase(status)) {
            BigDecimal paid = new BigDecimal(n.path("amount").asText("-1"));
            if (paid.compareTo(amount) != 0) {          // never accept a different amount than the one we asked for
                fail(id, pay, "amount_mismatch");
                return "amount_mismatch";
            }
            applySuccess(id, pay);
            return "succeeded";
        }
        fail(id, pay, n.path("reason").asText("declined"));
        return "failed";
    }

    private void applySuccess(UUID id, Map<String, Object> pay) {
        UUID user = (UUID) pay.get("user_id");
        BigDecimal amount = (BigDecimal) pay.get("amount");
        UUID external = ledger.systemAccount("EXTERNAL_CARD");
        if ("TOPUP".equals(pay.get("purpose"))) {
            UUID wallet = ledger.userAccount(user, "CUSTOMER_WALLET");
            ledger.post("TOPUP", "PAYMENT", id, "pay-" + id, "Wallet top-up", List.of(new Leg(external, amount.negate()), new Leg(wallet, amount)));
        } else {
            UUID rideId = (UUID) pay.get("ride_id");
            var f = jdbc.sql("SELECT r.driver_id, f.commission, f.driver_earnings FROM rides r JOIN ride_fares f ON f.ride_id=r.id WHERE r.id=:id").param("id", rideId).query().listOfRows().get(0);
            UUID drv = ledger.userAccount((UUID) f.get("driver_id"), "DRIVER_WALLET");
            BigDecimal commission = (BigDecimal) f.get("commission");
            List<Leg> legs = new java.util.ArrayList<>(List.of(new Leg(external, amount.negate()), new Leg(drv, (BigDecimal) f.get("driver_earnings"))));
            if (commission.signum() > 0) legs.add(new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission));
            ledger.post("RIDE_PAYMENT", "PAYMENT", id, "pay-" + id, "Ride payment (card)", legs);
            markRidePaid(rideId);
        }
        jdbc.sql("UPDATE payment_transactions SET status='SUCCEEDED', updated_at=now() WHERE id=:id").param("id", id).update();
        notifier.notify(user, "PAYMENT_STATUS_UPDATED", "payment-" + id + "-ok", Map.of("paymentId", id.toString(), "paymentStatus", "SUCCEEDED"));
        metrics.counter("jolay.payments.succeeded").increment();
    }

    private void fail(UUID id, Map<String, Object> pay, String reason) {
        jdbc.sql("UPDATE payment_transactions SET status='FAILED', failure_reason=:r, updated_at=now() WHERE id=:id").param("id", id).param("r", reason).update();
        if (pay.get("ride_id") != null) jdbc.sql("UPDATE rides SET payment_status='FAILED' WHERE id=:r AND payment_status<>'PAID'").param("r", pay.get("ride_id")).update();
        notifier.notify((UUID) pay.get("user_id"), "PAYMENT_STATUS_UPDATED", "payment-" + id + "-failed", Map.of("paymentId", id.toString(), "paymentStatus", "FAILED", "reason", reason));
        metrics.counter("jolay.payments.failed").increment();
    }

    // ---------------- refunds ----------------

    @Transactional
    public UUID refund(UUID adminId, UUID paymentId, String reason) {
        var pay = jdbc.sql("SELECT id,user_id,purpose,ride_id,amount,status,provider,provider_ref FROM payment_transactions WHERE id=:id FOR UPDATE").param("id", paymentId)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> ApiException.notFound("payment_not_found", "Payment not found"));
        if (!"SUCCEEDED".equals(pay.get("status"))) throw ApiException.conflict("not_refundable", "Only succeeded payments can be refunded");
        BigDecimal amount = (BigDecimal) pay.get("amount");
        UUID external = ledger.systemAccount("EXTERNAL_CARD");
        List<Leg> legs;
        if ("TOPUP".equals(pay.get("purpose"))) {
            UUID wallet = ledger.userAccount((UUID) pay.get("user_id"), "CUSTOMER_WALLET");
            legs = List.of(new Leg(wallet, amount.negate()), new Leg(external, amount));      // fails with insufficient_funds if already spent
        } else {
            var f = jdbc.sql("SELECT r.driver_id, f.commission, f.driver_earnings FROM rides r JOIN ride_fares f ON f.ride_id=r.id WHERE r.id=:id").param("id", pay.get("ride_id")).query().listOfRows().get(0);
            UUID drv = ledger.userAccount((UUID) f.get("driver_id"), "DRIVER_WALLET");
            legs = new java.util.ArrayList<>(List.of(new Leg(external, amount), new Leg(drv, ((BigDecimal) f.get("driver_earnings")).negate())));
            BigDecimal commission = (BigDecimal) f.get("commission");
            if (commission.signum() > 0) legs.add(new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission.negate()));
        }
        provider((String) pay.get("provider")).refund((String) pay.get("provider_ref"), amount);
        UUID txId = ledger.post("REFUND", "PAYMENT", paymentId, "refund-" + paymentId, "Refund: " + reason, legs);
        UUID refundId = jdbc.sql("INSERT INTO payment_refunds(payment_id,amount,reason,requested_by,ledger_transaction_id) VALUES (:p,:a,:r,:u,:t) RETURNING id")
                .param("p", paymentId).param("a", amount).param("r", reason).param("u", adminId).param("t", txId).query(UUID.class).single();
        jdbc.sql("UPDATE payment_transactions SET status='REFUNDED', updated_at=now() WHERE id=:id").param("id", paymentId).update();
        risk.onRefund((UUID) pay.get("user_id"));
        notifier.notify((UUID) pay.get("user_id"), "PAYMENT_STATUS_UPDATED", "payment-" + paymentId + "-refund", Map.of("paymentId", paymentId.toString(), "paymentStatus", "REFUNDED"));
        return refundId;
    }

    /** Sandbox-only helper: completes a pending payment as the gateway would (signed callback through the real handler). */
    @Transactional
    public String sandboxComplete(UUID userId, UUID paymentId, boolean success) {
        if (!(provider("sandbox") instanceof SandboxPaymentProvider sb)) throw ApiException.notFound("not_found", "Not available");
        if (!"sandbox".equals(defaultProvider)) throw ApiException.notFound("not_found", "Not available");
        var pay = jdbc.sql("SELECT user_id, provider_ref, amount, provider FROM payment_transactions WHERE id=:id").param("id", paymentId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("payment_not_found", "Payment not found"));
        if (!userId.equals(pay.get("user_id")) || !"sandbox".equals(pay.get("provider"))) throw ApiException.notFound("payment_not_found", "Payment not found");
        String body = "{\"eventId\":\"" + UUID.randomUUID() + "\",\"providerRef\":\"" + pay.get("provider_ref") + "\",\"status\":\"" + (success ? "SUCCEEDED" : "FAILED")
                + "\",\"amount\":\"" + ((BigDecimal) pay.get("amount")).toPlainString() + "\"}";
        return handleWebhook("sandbox", body, sb.sign(body));
    }
}
