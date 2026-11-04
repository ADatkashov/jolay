package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Regression tests for defects found in the CTO audit. */
class AuditFixesIT extends IntegrationTestBase {

    @Test
    void metricsAreNotPublicOnTheMainPort() {
        assertEquals(200, get("/actuator/health", null).status());
        int prom = get("/actuator/prometheus", null).status();
        assertTrue(prom == 401 || prom == 403 || prom == 404, "prometheus must not be anonymous, got " + prom);
        assertTrue(get("/actuator/prometheus", customer().token()).status() >= 400);
    }

    @Test
    void partnerAdminHasNoAccessToStaffApis() {
        Session p = admin("PARTNER_ADMIN");
        for (String path : new String[]{"/api/v1/admin/dashboard", "/api/v1/admin/rides", "/api/v1/admin/customers", "/api/v1/admin/drivers", "/api/v1/admin/finance/reconciliation"})
            assertEquals(403, get(path, p.token()).status(), path);
    }

    @Test
    void reconciliationIsCleanAfterAllMoneyFlowsAndFlagsCorruption() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        topUp(c, 20000);
        String rideId = requestRide(c, "ECONOMY", "WALLET").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, DROPOFF[0], DROPOFF[1]);
        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null).status());

        Session fin = admin("FINANCE_ADMIN");
        Resp ok = get("/api/v1/admin/finance/reconciliation", fin.token());
        assertEquals(200, ok.status());
        assertEquals("OK", ok.s("status"), ok.body().toString());
        assertEquals(0, ok.body().path("ledgerBalanceSum").decimalValue().signum());
        assertEquals(403, get("/api/v1/admin/finance/reconciliation", admin("SUPPORT_AGENT").token()).status());

        // simulate a bug/manual tamper: a paid ride without ledger entries must be detected
        jdbc.sql("UPDATE rides SET payment_status='PAID' WHERE id=:r::uuid").param("r", rideId).update();
        jdbc.sql("ALTER TABLE ledger_transactions DISABLE TRIGGER trg_ledger_tx_immutable").update();
        jdbc.sql("ALTER TABLE ledger_entries DISABLE TRIGGER trg_ledger_entries_immutable").update();
        try {
            jdbc.sql("DELETE FROM ledger_entries").update();
            jdbc.sql("DELETE FROM ledger_transactions").update();
        } finally {
            jdbc.sql("ALTER TABLE ledger_transactions ENABLE TRIGGER trg_ledger_tx_immutable").update();
            jdbc.sql("ALTER TABLE ledger_entries ENABLE TRIGGER trg_ledger_entries_immutable").update();
        }
        Resp bad = get("/api/v1/admin/finance/reconciliation", fin.token());
        assertEquals("CRITICAL", bad.s("status"));
        assertTrue(bad.body().path("paidRidesWithoutLedger").asInt() >= 1 || bad.body().path("accountsWithBalanceDrift").asInt() >= 1);
    }

    @Test
    void pendingCardPaymentReturnsTheSameCheckoutUrlWhenRequestedAgain() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CARD").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, DROPOFF[0], DROPOFF[1]);
        post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null);
        Resp a = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        Resp b = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        assertEquals(a.s("id"), b.s("id"));
        assertEquals(a.s("checkoutUrl"), b.s("checkoutUrl"));
        assertEquals(1, jdbc.sql("SELECT count(*) FROM payment_transactions").query(Integer.class).single());
    }

    @Test
    void estimateStillReportsNearestDriverEtaAfterQueryRewrite() {
        Session c = customer();
        Resp none = post("/api/v1/rides/estimate", c.token(), Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])));
        assertFalse(none.body().path("categories").get(0).path("available").asBoolean());
        driver("COMFORT", 43.2340, 76.9570);
        Resp some = post("/api/v1/rides/estimate", c.token(), Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])));
        assertTrue(some.body().path("categories").get(0).path("available").asBoolean(), "a Comfort driver can serve Economy");
        assertTrue(some.body().path("categories").get(0).path("etaSeconds").asInt() > 0);
        assertFalse(some.body().path("categories").get(2).path("available").asBoolean(), "a Comfort driver cannot serve Business");
    }

    @Test
    void unknownRoutesAndBadRequestsAreClientErrorsNotServerErrors() {
        Session c = customer();
        assertEquals(404, get("/api/v1/does-not-exist", c.token()).status());
        assertEquals(405, call(HttpMethod.DELETE, "/api/v1/rides/estimate", c.token(), null, null).status());
        assertEquals(400, get("/api/v1/geo/places", c.token()).status(), "missing ?q");
        assertEquals(400, get("/api/v1/rides/not-a-uuid", c.token()).status());
    }
}
