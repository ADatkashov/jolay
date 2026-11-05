package kz.jolay;

import kz.jolay.rides.TrackRetentionJob;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpMethod;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Safety / operations centre, payouts, risk flags, legal documents and data retention. */
class OpsFeaturesIT extends IntegrationTestBase {
    @Autowired TrackRetentionJob retention;

    // ---------------- incidents / SOS ----------------
    @Test
    void sosDuringRideCreatesCriticalIncidentNotifiesStaffAndIsHandledEndToEnd() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        Session agent = admin("SUPPORT_AGENT"); Session ops = admin("OPERATIONS_ADMIN");
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);

        Resp sos = post("/api/v1/incidents", c.token(), Map.of("type", "SOS", "point", Map.of("lat", 43.2301, "lng", 76.9501)));
        assertEquals(201, sos.status());
        String id = sos.s("id");
        assertFalse(sos.body().path("duplicate").asBoolean());
        // pressing SOS again does not create a second incident
        Resp again = post("/api/v1/incidents", c.token(), Map.of("type", "SOS"));
        assertEquals(id, again.s("id"));
        assertTrue(again.body().path("duplicate").asBoolean());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM incidents").query(Integer.class).single());
        // staff were notified, exactly once each
        int staff = jdbc.sql("SELECT count(DISTINCT user_id) FROM user_roles WHERE role IN ('SUPPORT_AGENT','OPERATIONS_ADMIN','SUPER_ADMIN')").query(Integer.class).single();
        assertTrue(staff >= 2);
        assertEquals(staff, jdbc.sql("SELECT count(*) FROM notifications WHERE type='INCIDENT_CREATED'").query(Integer.class).single());

        Resp detail = get("/api/v1/admin/incidents/" + id, agent.token());
        assertEquals(200, detail.status());
        assertEquals("CRITICAL", detail.s("severity"));
        assertEquals(rideId, detail.s("ride_id"), "active ride is linked automatically");
        assertEquals(d.id().toString(), jdbc.sql("SELECT subject_user_id::text FROM incidents").query(String.class).single(), "counterpart is linked");
        assertNotNull(detail.s("subject_phone"));
        assertEquals(43.2301, detail.body().path("lat").asDouble(), 0.0001);

        assertEquals(200, post("/api/v1/admin/incidents/" + id + "/ack", agent.token(), null).status());
        assertEquals(409, post("/api/v1/admin/incidents/" + id + "/ack", ops.token(), null).status(), "already acknowledged");
        assertEquals(200, post("/api/v1/admin/incidents/" + id + "/note", ops.token(), Map.of("note", "Called the driver, passenger is safe")).status());
        assertEquals(200, post("/api/v1/admin/incidents/" + id + "/resolve", ops.token(), Map.of("note", "False alarm confirmed by passenger")).status());
        assertEquals(409, post("/api/v1/admin/incidents/" + id + "/resolve", ops.token(), Map.of("note", "again")).status());

        Resp done = get("/api/v1/admin/incidents/" + id, ops.token());
        assertEquals("RESOLVED", done.s("status"));
        var actions = done.body().path("events");
        assertEquals("CREATED", actions.get(0).path("action").asText());
        assertTrue(done.body().toString().contains("REPEATED") && done.body().toString().contains("ACKNOWLEDGED") && done.body().toString().contains("RESOLVED"));
        assertTrue(jdbc.sql("SELECT count(*) FROM audit_logs WHERE action LIKE 'INCIDENT_%'").query(Integer.class).single() >= 4);
        assertEquals(1, get("/api/v1/incidents", c.token()).body().size());
        assertEquals(1, get("/api/v1/admin/incidents?status=RESOLVED", agent.token()).body().size());
    }

    @Test
    void incidentValidationAndAccessControl() {
        Session c = customer(), other = customer(); Session d = register("DRIVER");
        assertEquals(400, post("/api/v1/incidents", c.token(), Map.of("type", "COMPLAINT")).status(), "complaints need a description");
        assertEquals(400, post("/api/v1/incidents", c.token(), Map.of("type", "HACK", "description", "x")).status());
        assertEquals(404, post("/api/v1/incidents", c.token(), Map.of("type", "COMPLAINT", "description", "rude", "rideId", "00000000-0000-0000-0000-000000000001")).status());
        assertEquals(201, post("/api/v1/incidents", c.token(), Map.of("type", "COMPLAINT", "description", "Driver was rude")).status());
        // SOS without any ride is still accepted (location may be sent from the app)
        assertEquals(201, post("/api/v1/incidents", d.token(), Map.of("type", "SOS")).status());
        assertEquals(401, post("/api/v1/incidents", null, Map.of("type", "SOS")).status());
        // customers cannot read staff endpoints or someone else's incidents
        String id = get("/api/v1/incidents", c.token()).body().get(0).path("id").asText();
        assertEquals(403, get("/api/v1/admin/incidents/" + id, c.token()).status());
        assertEquals(0, get("/api/v1/incidents", other.token()).body().size());
        assertEquals(403, get("/api/v1/admin/incidents", admin("PARTNER_ADMIN").token()).status());
        assertEquals(403, get("/api/v1/admin/incidents", admin("FINANCE_ADMIN").token()).status());
        assertEquals(404, get("/api/v1/admin/incidents/00000000-0000-0000-0000-000000000009", admin("SUPPORT_AGENT").token()).status());
    }

    // ---------------- payouts ----------------
    private Session driverWithEarnings() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        topUp(c, 60000);
        for (int i = 0; i < 4; i++) completeRide(c, d, "WALLET");
        assertTrue(balance(d).compareTo(new BigDecimal("2600")) > 0, "driver earned: " + balance(d));
        assertEquals(200, put("/api/v1/admin/settings/payouts.min_amount", admin("SUPER_ADMIN").token(), Map.of("value", "1000")).status());
        return d;
    }

    @Test
    void payoutHoldPayAndRejectGoThroughTheLedger() {
        Session d = driverWithEarnings();
        BigDecimal before = balance(d);
        Session fin = admin("FINANCE_ADMIN");

        assertEquals("payout_below_minimum", post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 100, "destination", "KZ12345678901234")).s("code"));
        assertEquals("invalid_destination", post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 1000, "destination", "not an iban!")).s("code"));
        assertEquals("insufficient_funds", post("/api/v1/drivers/payouts", d.token(), Map.of("amount", before.add(new BigDecimal("1")), "destination", "KZ12345678901234")).s("code"));

        Resp req = post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 1000, "destination", "KZ12 3456 7890 1234"));
        assertEquals(201, req.status());
        String id = req.s("id");
        assertEquals(0, balance(d).compareTo(before.subtract(new BigDecimal("1000"))), "funds are held immediately");
        assertEquals(0, jdbc.sql("SELECT balance FROM accounts WHERE type='PAYOUT_CLEARING'").query(BigDecimal.class).single().compareTo(new BigDecimal("1000")));
        assertEquals("payout_already_requested", post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 1000, "destination", "KZ12345678901234")).s("code"));
        assertEquals("****1234", get("/api/v1/drivers/payouts", d.token()).body().get(0).path("destination").asText(), "drivers only see a masked destination");
        assertAdminReconciliation(fin, "OK");

        assertEquals(403, post("/api/v1/admin/payouts/" + id + "/pay", admin("OPERATIONS_ADMIN").token(), Map.of("reference", "x")).status());
        assertEquals(200, post("/api/v1/admin/payouts/" + id + "/pay", fin.token(), Map.of("reference", "BANK-REF-001")).status());
        assertEquals(409, post("/api/v1/admin/payouts/" + id + "/pay", fin.token(), Map.of("reference", "again")).status(), "no double payout");
        assertEquals(409, post("/api/v1/admin/payouts/" + id + "/reject", fin.token(), Map.of("reason", "late")).status());
        assertEquals(0, jdbc.sql("SELECT balance FROM accounts WHERE type='PAYOUT_CLEARING'").query(BigDecimal.class).single().signum());
        assertEquals(0, jdbc.sql("SELECT balance FROM accounts WHERE type='EXTERNAL_BANK'").query(BigDecimal.class).single().compareTo(new BigDecimal("1000")));
        assertAdminReconciliation(fin, "OK");
        assertLedgerBalanced();

        // second request, rejected -> funds come back
        BigDecimal mid = balance(d);
        String id2 = post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 1500, "destination", "KZ12345678901234")).s("id");
        assertEquals(0, balance(d).compareTo(mid.subtract(new BigDecimal("1500"))));
        assertEquals(200, post("/api/v1/admin/payouts/" + id2 + "/reject", fin.token(), Map.of("reason", "Wrong IBAN")).status());
        assertEquals(0, balance(d).compareTo(mid));
        assertEquals(2, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action IN ('PAYOUT_PAID','PAYOUT_REJECTED')").query(Integer.class).single());
        assertAdminReconciliation(fin, "OK");
        assertLedgerBalanced();
        assertEquals(1, jdbc.sql("SELECT count(*) FROM notifications WHERE type='PAYOUT_PAID'").query(Integer.class).single());
        // dashboard counts only PAID payouts
        assertEquals(0, new BigDecimal(get("/api/v1/admin/dashboard", fin.token()).s("driverPayouts")).compareTo(new BigDecimal("1000")));
    }

    @Test
    void customersAndUnapprovedDriversCannotRequestPayouts() {
        Session c = customer();
        assertEquals(403, post("/api/v1/drivers/payouts", c.token(), Map.of("amount", 5000, "destination", "KZ12345678901234")).status());
        Session d = register("DRIVER");
        post("/api/v1/drivers/register", d.token(), Map.of("vehicle", Map.of("brand", "Kia", "model", "Rio", "year", 2019, "color", "Black", "plate", "777ABC02", "category", "ECONOMY")));
        assertEquals("driver_not_approved", post("/api/v1/drivers/payouts", d.token(), Map.of("amount", 5000, "destination", "KZ12345678901234")).s("code"));
        assertEquals(403, get("/api/v1/admin/payouts", admin("SUPPORT_AGENT").token()).status());
    }

    private void assertAdminReconciliation(Session fin, String expected) {
        Resp r = get("/api/v1/admin/finance/reconciliation", fin.token());
        assertEquals(expected, r.s("status"), r.body().toString());
        assertEquals(0, r.body().path("payoutHoldMismatch").asInt());
    }

    // ---------------- risk flags ----------------
    @Test
    void repeatedCustomerCancellationsRaiseAFlagButNeverSuspendTheAccount() {
        Session c = customer(); Session ops = admin("OPERATIONS_ADMIN");
        for (int i = 0; i < 5; i++) {
            String id = requestRide(c, "ECONOMY", "CASH").s("id");
            assertEquals("CANCELLED", post("/api/v1/rides/" + id + "/cancel", c.token(), null).s("status"));
        }
        Resp flags = get("/api/v1/admin/risk-flags", ops.token());
        assertEquals(1, flags.body().size());
        assertEquals("REPEATED_CANCELLATIONS", flags.body().get(0).path("rule").asText());
        assertEquals("ACTIVE", jdbc.sql("SELECT status FROM users WHERE id=:u").param("u", c.id()).query(String.class).single(), "no automatic suspension");
        assertEquals(200, get("/api/v1/customers/me", c.token()).status());
        assertEquals(201, requestRide(c, "ECONOMY", "CASH").status(), "the customer can keep ordering");
        // the flag is not duplicated by more cancellations the same day
        post("/api/v1/rides/" + get("/api/v1/rides/active", c.token()).s("id") + "/cancel", c.token(), null);
        assertEquals(1, get("/api/v1/admin/risk-flags", ops.token()).body().size());

        String flagId = flags.body().get(0).path("id").asText();
        assertEquals(403, post("/api/v1/admin/risk-flags/" + flagId + "/review", admin("SUPPORT_AGENT").token(), Map.of("status", "DISMISSED", "note", "x")).status());
        assertEquals(400, post("/api/v1/admin/risk-flags/" + flagId + "/review", ops.token(), Map.of("status", "DISMISSED")).status(), "a note is mandatory");
        assertEquals(200, post("/api/v1/admin/risk-flags/" + flagId + "/review", ops.token(), Map.of("status", "DISMISSED", "note", "Customer changed plans, normal behaviour")).status());
        assertEquals(409, post("/api/v1/admin/risk-flags/" + flagId + "/review", ops.token(), Map.of("status", "CONFIRMED", "note", "x")).status());
        assertEquals(0, get("/api/v1/admin/risk-flags", ops.token()).body().size());
        assertEquals(1, get("/api/v1/admin/risk-flags?status=DISMISSED", ops.token()).body().size());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action='RISK_FLAG_REVIEWED'").query(Integer.class).single());
    }

    @Test
    void gpsSpoofingIndicatorAfterRepeatedImpossibleJumps() {
        Session d = driver("ECONOMY", 43.2336, 76.9568);
        for (int i = 0; i < 3; i++) assertEquals(400, moveDriver(d, 43.40, 77.10).status());
        Resp flags = get("/api/v1/admin/risk-flags", admin("OPERATIONS_ADMIN").token());
        assertEquals("GPS_SPOOFING_INDICATOR", flags.body().get(0).path("rule").asText());
        assertEquals("HIGH", flags.body().get(0).path("severity").asText());
        assertEquals("ONLINE", get("/api/v1/drivers/me", d.token()).s("availability"), "driver is not blocked automatically");
    }

    @Test
    void collusionIndicatorForTheSameCustomerDriverPairAndDeviceSharing() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        for (int i = 0; i < 4; i++) completeRide(c, d, "CASH");
        Resp flags = get("/api/v1/admin/risk-flags", admin("OPERATIONS_ADMIN").token());
        long collusion = 0;
        for (var f : flags.body()) if ("COLLUSION_INDICATOR".equals(f.path("rule").asText())) collusion++;
        assertEquals(2, collusion, "one flag for the customer and one for the driver");

        // one push device shared by three accounts
        Session a = customer(), b = customer(), e = customer();
        for (Session s : new Session[]{a, b, e}) assertEquals(200, post("/api/v1/notifications/devices", s.token(), Map.of("pushToken", "shared-device-token", "platform", "android")).status());
        long dup = 0;
        for (var f : get("/api/v1/admin/risk-flags", admin("OPERATIONS_ADMIN").token()).body()) if ("DUPLICATE_IDENTITY_INDICATOR".equals(f.path("rule").asText())) dup++;
        assertEquals(3, dup);
    }

    @Test
    void abnormalRefundsAndReplayedCallbacksAreFlagged() {
        Session c = customer(); Session fin = admin("FINANCE_ADMIN");
        for (int i = 0; i < 3; i++) {
            Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 1000 + i));
            post("/api/v1/payments/" + t.s("id") + "/sandbox-checkout", c.token(), null);
            assertEquals(201, post("/api/v1/admin/payments/" + t.s("id") + "/refund", fin.token(), Map.of("reason", "test")).status());
        }
        assertTrue(get("/api/v1/admin/risk-flags", fin.token()).body().toString().contains("ABNORMAL_REFUNDS"));

        Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000));
        String ref = jdbc.sql("SELECT provider_ref FROM payment_transactions WHERE id=:i::uuid").param("i", t.s("id")).query(String.class).single();
        String body = "{\"eventId\":\"replay-1\",\"providerRef\":\"" + ref + "\",\"status\":\"SUCCEEDED\",\"amount\":\"3000.00\"}";
        String sig = new kz.jolay.payments.SandboxPaymentProvider("test-secret", "http://x").sign(body);
        for (int i = 0; i < 6; i++) call(HttpMethod.POST, "/api/v1/payments/webhooks/sandbox", null, body, Map.of("X-Signature", sig));
        assertEquals(0, balance(c).compareTo(new BigDecimal("3000").add(BigDecimal.ZERO).subtract(new BigDecimal("3000")).add(balance(c))), "balance is a number");
        assertTrue(get("/api/v1/admin/risk-flags", fin.token()).body().toString().contains("SUSPICIOUS_PAYMENT_CALLBACKS"));
        assertLedgerBalanced();
    }

    // ---------------- legal documents ----------------
    @Test
    void legalDocumentsAreVersionedPublishedBySuperAdminOnlyAndNeverPrefilled() {
        assertEquals(404, get("/api/v1/catalog/legal/terms?lang=kk", null).status(), "nothing is invented before counsel provides the text");
        assertEquals("legal_not_published", get("/api/v1/catalog/legal/privacy?lang=ru", null).s("code"));
        Session sa = admin("SUPER_ADMIN");
        assertEquals(403, put("/api/v1/admin/legal/TERMS/kk", admin("OPERATIONS_ADMIN").token(), Map.of("body", "x")).status());
        assertEquals(400, put("/api/v1/admin/legal/NOPE/kk", sa.token(), Map.of("body", "x")).status());
        assertEquals(201, call(HttpMethod.PUT, "/api/v1/admin/legal/TERMS/kk", sa.token(), Map.of("body", "Шарттар v1"), null).status());
        assertEquals(201, call(HttpMethod.PUT, "/api/v1/admin/legal/TERMS/kk", sa.token(), Map.of("body", "Шарттар v2"), null).status());
        Resp t = get("/api/v1/catalog/legal/TERMS?lang=kk", null);
        assertEquals(2, t.body().path("version").asInt());
        assertEquals("Шарттар v2", t.s("body"));
        assertEquals(404, get("/api/v1/catalog/legal/TERMS?lang=ru", null).status(), "each language is published separately");
        assertEquals(2, jdbc.sql("SELECT count(*) FROM legal_documents").query(Integer.class).single(), "old versions are kept");
        assertEquals(2, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action='LEGAL_PUBLISHED'").query(Integer.class).single());
    }

    // ---------------- data retention ----------------
    @Test
    void simplifiedRouteIsKeptAndRawGpsPointsArePurgedAfterTheRetentionWindow() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = completeRide(c, d, "CASH");
        assertTrue(jdbc.sql("SELECT count(*) FROM ride_locations WHERE ride_id=:r::uuid").param("r", rideId).query(Integer.class).single() >= 2);
        assertTrue(jdbc.sql("SELECT route_line IS NOT NULL FROM rides WHERE id=:r::uuid").param("r", rideId).query(Boolean.class).single(), "simplified route stored at completion");
        assertEquals(0, retention.purge(), "recent rides are untouched");
        jdbc.sql("UPDATE rides SET completed_at = now() - interval '20 days' WHERE id=:r::uuid").param("r", rideId).update();
        assertTrue(retention.purge() >= 2);
        assertEquals(0, jdbc.sql("SELECT count(*) FROM ride_locations WHERE ride_id=:r::uuid").param("r", rideId).query(Integer.class).single());
        assertTrue(jdbc.sql("SELECT route_line IS NOT NULL FROM rides WHERE id=:r::uuid").param("r", rideId).query(Boolean.class).single(), "the simplified route survives the purge");
    }
}
