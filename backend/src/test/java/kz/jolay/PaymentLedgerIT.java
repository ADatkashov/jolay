package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class PaymentLedgerIT extends IntegrationTestBase {
    private String body(String event, String ref, String status, String amount) {
        return "{\"eventId\":\"" + event + "\",\"providerRef\":\"" + ref + "\",\"status\":\"" + status + "\",\"amount\":\"" + amount + "\"}";
    }
    private String sign(String b) { return new kz.jolay.payments.SandboxPaymentProvider("test-secret", "http://x").sign(b); }
    private Resp webhook(String b, String sig) { return call(HttpMethod.POST, "/api/v1/payments/webhooks/sandbox", null, b, Map.of("X-Signature", sig)); }

    @Test
    void duplicateWebhookCreditsOnlyOnce() {
        Session c = customer();
        Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000));
        String ref = jdbc.sql("SELECT provider_ref FROM payment_transactions WHERE id=:i::uuid").param("i", t.s("id")).query(String.class).single();
        String b = body("evt-1", ref, "SUCCEEDED", "3000.00");
        assertEquals("succeeded", webhook(b, sign(b)).s("result"));
        assertEquals("duplicate", webhook(b, sign(b)).s("result"));
        String b2 = body("evt-2", ref, "SUCCEEDED", "3000.00");          // same payment, different event id
        assertEquals("ignored", webhook(b2, sign(b2)).s("result"));
        assertEquals(0, balance(c).compareTo(new BigDecimal("3000")));
        assertEquals(1, jdbc.sql("SELECT count(*) FROM ledger_transactions WHERE tx_type='TOPUP'").query(Integer.class).single());
        assertLedgerBalanced();
    }

    @Test
    void tamperedAmountOrSignatureNeverCredits() {
        Session c = customer();
        Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000));
        String ref = jdbc.sql("SELECT provider_ref FROM payment_transactions WHERE id=:i::uuid").param("i", t.s("id")).query(String.class).single();
        String signed = body("evt-a", ref, "SUCCEEDED", "3000.00");
        assertEquals(401, webhook(signed.replace("3000.00", "9000.00"), sign(signed)).status());       // body changed after signing
        assertEquals(401, webhook(signed, "").status());
        String lowball = body("evt-b", ref, "SUCCEEDED", "10.00");
        assertEquals("amount_mismatch", webhook(lowball, sign(lowball)).s("result"));
        assertEquals(0, balance(c).compareTo(BigDecimal.ZERO));
        assertEquals("FAILED", get("/api/v1/payments/" + t.s("id"), c.token()).s("status"));
    }

    @Test
    void malformedOrMissingAmountIsRejectedWithoutCrediting() {
        Session c = customer();
        Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000));
        String ref = jdbc.sql("SELECT provider_ref FROM payment_transactions WHERE id=:i::uuid").param("i", t.s("id")).query(String.class).single();
        String garbage = body("evt-g", ref, "SUCCEEDED", "not-a-number");
        assertEquals("amount_mismatch", webhook(garbage, sign(garbage)).s("result"));
        assertEquals(0, balance(c).compareTo(BigDecimal.ZERO));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM ledger_transactions WHERE tx_type='TOPUP'").query(Integer.class).single());
        assertLedgerBalanced();
    }

    @Test
    void failedPaymentLeavesRideUnpaidAndCanBeRetriedWithAnotherMethod() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CARD").s("id");
        new RideFlowIT().getClass();                                       // (type reference only)
        String offer = currentOfferId(d);
        post("/api/v1/drivers/offers/" + offer + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, DROPOFF[0], DROPOFF[1]);
        post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null);

        Resp pay = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        assertEquals("failed", post("/api/v1/payments/" + pay.s("id") + "/sandbox-checkout?success=false", c.token(), null).s("result"));
        assertEquals("FAILED", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        assertEquals(0, balance(d).compareTo(BigDecimal.ZERO));
        // retry succeeds via a fresh payment
        Resp retry = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        assertNotEquals(pay.s("id"), retry.s("id"));
        assertEquals("succeeded", post("/api/v1/payments/" + retry.s("id") + "/sandbox-checkout", c.token(), null).s("result"));
        assertEquals("PAID", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        assertEquals(409, post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD")).status(), "cannot pay twice");
        assertLedgerBalanced();

        // admin refund reverses every leg and is itself audited in the ledger
        Session fin = admin("FINANCE_ADMIN");
        assertEquals(201, post("/api/v1/admin/payments/" + retry.s("id") + "/refund", fin.token(), Map.of("reason", "customer complaint")).status());
        assertEquals(0, balance(d).compareTo(BigDecimal.ZERO));
        assertEquals(0, jdbc.sql("SELECT balance FROM accounts WHERE type='PLATFORM_REVENUE'").query(BigDecimal.class).single().compareTo(BigDecimal.ZERO));
        assertEquals(409, post("/api/v1/admin/payments/" + retry.s("id") + "/refund", fin.token(), Map.of("reason", "again")).status(), "no double refund");
        assertEquals(1, jdbc.sql("SELECT count(*) FROM payment_refunds").query(Integer.class).single());
        assertLedgerBalanced();
    }

    @Test
    void topUpIdempotencyKeyAndAmountLimits() {
        Session c = customer();
        Resp a = call(HttpMethod.POST, "/api/v1/wallet/top-ups", c.token(), Map.of("amount", 1000), Map.of("Idempotency-Key", "abc"));
        Resp b = call(HttpMethod.POST, "/api/v1/wallet/top-ups", c.token(), Map.of("amount", 1000), Map.of("Idempotency-Key", "abc"));
        assertEquals(a.s("id"), b.s("id"));
        assertEquals(400, post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 5)).status());
        assertEquals(400, post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 99999999)).status());
    }

    @Test
    void ledgerIsImmutableAndRefundOfSpentTopUpFails() {
        Session c = customer();
        topUp(c, 2000);
        assertThrows(Exception.class, () -> jdbc.sql("UPDATE ledger_entries SET amount = 1").update());
        assertThrows(Exception.class, () -> jdbc.sql("DELETE FROM ledger_transactions").update());
        assertThrows(Exception.class, () -> jdbc.sql("UPDATE accounts SET balance = -5 WHERE type='CUSTOMER_WALLET'").update(), "customer wallet can never go negative");
        // spend the money, then try to refund the top-up
        jdbc.sql("UPDATE accounts SET balance = 0 WHERE type='CUSTOMER_WALLET'").update();
        String payId = jdbc.sql("SELECT id FROM payment_transactions LIMIT 1").query(String.class).single();
        Resp r = post("/api/v1/admin/payments/" + payId + "/refund", admin("FINANCE_ADMIN").token(), Map.of("reason", "test"));
        assertEquals(409, r.status());
        assertEquals("insufficient_funds", r.s("code"));
    }

    @Test
    void pricingChangesAreValidatedAndAudited() {
        Session fin = admin("FINANCE_ADMIN");
        String id = get("/api/v1/admin/pricing", fin.token()).body().get(0).path("id").asText();
        Map<String, Object> bad = Map.of("baseFare", -1, "perKm", 100, "perMinute", 10, "minFare", 500, "bookingFee", 0, "cancellationFee", 0, "freeCancelSeconds", 60, "commissionRate", "0.15", "demandMultiplier", "1.0", "active", true);
        assertEquals(400, put("/api/v1/admin/pricing/" + id, fin.token(), bad).status());
        Map<String, Object> highCommission = Map.of("baseFare", 100, "perKm", 100, "perMinute", 10, "minFare", 500, "bookingFee", 0, "cancellationFee", 0, "freeCancelSeconds", 60, "commissionRate", "0.9", "demandMultiplier", "1.0", "active", true);
        assertEquals(400, put("/api/v1/admin/pricing/" + id, fin.token(), highCommission).status());
        Map<String, Object> ok = Map.of("baseFare", 500, "perKm", 120, "perMinute", 20, "minFare", 700, "bookingFee", 50, "cancellationFee", 300, "freeCancelSeconds", 120, "commissionRate", "0.2", "demandMultiplier", "1.0", "active", true);
        assertEquals(200, put("/api/v1/admin/pricing/" + id, fin.token(), ok).status());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action='PRICING_UPDATED'").query(Integer.class).single());
        Session c = customer();
        Resp est = post("/api/v1/rides/estimate", c.token(), Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])));
        assertEquals(200, est.status());   // estimate immediately reflects configured tariffs (no hardcoded prices)
    }

    @Test
    void outsideServiceAreaIsRejected() {
        Session c = customer();
        Resp r = post("/api/v1/rides/estimate", c.token(), Map.of("pickup", Map.of("lat", 51.1694, "lng", 71.4491), "dropoff", Map.of("lat", 51.12, "lng", 71.43)));
        assertEquals(400, r.status());
        assertEquals("pickup_out_of_zone", r.s("code"));
    }
}
