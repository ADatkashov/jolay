package kz.jolay;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Promo codes: eligibility rules, platform-funded discount through the ledger for cash / wallet / card, release on cancel, admin API. */
class PromoCodeIT extends IntegrationTestBase {

    @BeforeEach
    void clean() { jdbc.sql("DELETE FROM promo_redemptions").update(); jdbc.sql("DELETE FROM promo_codes").update(); jdbc.sql("DELETE FROM peak_windows").update(); jdbc.sql("UPDATE pricing_rules SET demand_multiplier=1.00").update(); }

    private void promo(String code, String kind, String value, String maxDiscount, String minFare, Integer maxRedemptions, int perUser, boolean firstRideOnly, boolean active, String endsAt) {
        jdbc.sql("INSERT INTO promo_codes(code,kind,value,max_discount,min_fare,max_redemptions,per_user_limit,first_ride_only,active,ends_at) VALUES (:c,:k,:v,:md,:mf,:mr,:pu,:fr,:a,:e::timestamptz)")
                .param("c", code).param("k", kind).param("v", new BigDecimal(value)).param("md", maxDiscount == null ? null : new BigDecimal(maxDiscount)).param("mf", new BigDecimal(minFare))
                .param("mr", maxRedemptions).param("pu", perUser).param("fr", firstRideOnly).param("a", active).param("e", endsAt).update();
    }
    private Resp ride(Session c, String payment, String code) {
        Map<String, Object> body = new java.util.HashMap<>(rideRequest("ECONOMY", payment));
        if (code != null) body.put("promoCode", code);
        return post("/api/v1/rides", c.token(), body);
    }
    private BigDecimal bd(String s) { return new BigDecimal(s); }
    private BigDecimal promoBalance() { return jdbc.sql("SELECT balance FROM accounts WHERE type='PROMO'").query(BigDecimal.class).single(); }
    private void drive(Session d, String rideId) {
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, 43.2200, 76.9300); moveDriver(d, DROPOFF[0], DROPOFF[1]);
        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null).status());
    }
    private Map<String, Object> estimateBody(String code) {
        Map<String, Object> m = new java.util.HashMap<>(Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])));
        if (code != null) m.put("promoCode", code);
        return m;
    }

    @Test
    void estimateShowsDiscountAndPayableAndRejectsBadCodes() {
        Session c = customer(); driver("ECONOMY", 43.2340, 76.9570);
        promo("WELCOME", "PERCENT", "20", "300", "0", null, 1, false, true, null);
        promo("OLD", "FIXED", "500", null, "0", null, 1, false, true, "2020-01-01T00:00:00Z");
        promo("OFF", "FIXED", "500", null, "0", null, 1, false, false, null);
        promo("BIGSPEND", "FIXED", "500", null, "999999", null, 1, false, true, null);

        BigDecimal plain = bd(post("/api/v1/rides/estimate", c.token(), estimateBody(null)).body().path("categories").get(0).path("fare").path("total").asText());
        Resp est = post("/api/v1/rides/estimate", c.token(), estimateBody("welcome"));          // case-insensitive
        var fare = est.body().path("categories").get(0).path("fare");
        assertEquals(0, plain.compareTo(bd(fare.path("total").asText())), "total stays the gross fare");
        BigDecimal expectedDiscount = plain.multiply(bd("0.20")).min(bd("300")).setScale(2, java.math.RoundingMode.DOWN);
        assertEquals(0, expectedDiscount.compareTo(bd(fare.path("discount").asText())));
        assertEquals(0, plain.subtract(expectedDiscount).compareTo(bd(fare.path("payable").asText())));

        assertEquals("promo_not_found", post("/api/v1/rides/estimate", c.token(), estimateBody("NOPE")).s("code"));
        assertEquals("promo_expired", post("/api/v1/rides/estimate", c.token(), estimateBody("OLD")).s("code"));
        assertEquals("promo_inactive", post("/api/v1/rides/estimate", c.token(), estimateBody("OFF")).s("code"));
        // a fare below the code's minimum: the estimate simply shows no discount, but ordering the ride is refused
        assertEquals(0, bd("0").compareTo(bd(post("/api/v1/rides/estimate", c.token(), estimateBody("BIGSPEND")).body().path("categories").get(0).path("fare").path("discount").asText())));
        Resp refused = ride(c, "CASH", "BIGSPEND");
        assertEquals(400, refused.status());
        assertEquals("promo_min_fare", refused.s("code"));
    }

    @Test
    void cashRideWithPromoDriverKeepsEarningsAndPlatformPaysTheDiscount() {
        promo("CASH100", "FIXED", "100", null, "0", null, 1, false, true, null);
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        Resp r = ride(c, "CASH", "cash100");
        assertEquals(201, r.status(), r.body().toString());
        assertEquals("CASH100", r.s("promoCode"));
        assertEquals(0, bd("100").compareTo(bd(r.s("promoDiscount"))));
        assertEquals(0, bd(r.s("estimatedFare")).subtract(bd("100")).compareTo(bd(r.s("payable"))));
        String rideId = r.s("id");
        drive(d, rideId);

        Resp done = get("/api/v1/rides/" + rideId, c.token());
        BigDecimal fare = bd(done.s("finalFare"));
        assertEquals(0, bd("100").compareTo(bd(done.s("promoDiscount"))));
        assertEquals(0, fare.subtract(bd("100")).compareTo(bd(done.s("payable"))));
        BigDecimal commission = bd(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        assertEquals(0, bd("100").subtract(commission).compareTo(balance(d)), "driver: -commission (cash rides) + promo compensation");
        assertEquals(0, bd("-100").compareTo(promoBalance()));
        assertEquals("APPLIED", jdbc.sql("SELECT status FROM promo_redemptions").query(String.class).single());
        assertLedgerBalanced();
    }

    @Test
    void walletRidePaysFareMinusDiscountAndDriverEarningsAreUnchanged() {
        promo("W20", "PERCENT", "20", null, "0", null, 1, false, true, null);
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        topUp(c, 20000);
        Resp r = ride(c, "WALLET", "W20");
        assertEquals(201, r.status(), r.body().toString());
        String rideId = r.s("id");
        drive(d, rideId);
        Resp done = get("/api/v1/rides/" + rideId, c.token());
        assertEquals("PAID", done.s("paymentStatus"));
        BigDecimal fare = bd(done.s("finalFare")), discount = fare.multiply(bd("0.20")).setScale(2, java.math.RoundingMode.DOWN);
        assertEquals(0, bd("20000").subtract(fare.subtract(discount)).compareTo(balance(c)));
        BigDecimal commission = bd(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        assertEquals(0, fare.subtract(commission).compareTo(balance(d)), "driver earns on the full fare");
        assertEquals(0, discount.negate().compareTo(promoBalance()));
        assertLedgerBalanced();
    }

    @Test
    void cardRideAsksTheGatewayForTheDiscountedAmount() {
        promo("C50", "FIXED", "50", null, "0", null, 1, false, true, null);
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        Resp r = ride(c, "CARD", "C50");
        assertEquals(201, r.status(), r.body().toString());
        String rideId = r.s("id");
        drive(d, rideId);
        Resp pay = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        assertEquals(200, pay.status(), pay.body().toString());
        BigDecimal fare = bd(get("/api/v1/rides/" + rideId, c.token()).s("finalFare"));
        assertEquals(0, fare.subtract(bd("50")).compareTo(bd(pay.s("amount"))), "gateway amount = fare - discount");

        assertEquals("succeeded", post("/api/v1/payments/" + pay.s("id") + "/sandbox-checkout", c.token(), null).s("result"));
        assertEquals("PAID", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        BigDecimal commission = bd(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        assertEquals(0, fare.subtract(commission).compareTo(balance(d)), "driver earns on the full fare");
        assertEquals(0, bd("-50").compareTo(promoBalance()));
        assertLedgerBalanced();
    }

    @Test
    void limitsFirstRideOnlyAndReleaseOnCancel() {
        promo("ONCE", "FIXED", "100", null, "0", null, 1, false, true, null);
        promo("TWO", "FIXED", "100", null, "0", 1, 5, false, true, null);          // one use in total
        promo("FIRST", "FIXED", "100", null, "0", null, 1, true, true, null);
        Session c = customer(); Session other = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);

        Resp first = ride(c, "CASH", "ONCE");
        assertEquals(201, first.status());
        // the reserved use already counts: a second ride with the same code is refused while the first is open (and the active-ride rule would also refuse it)
        assertEquals("promo_already_used", post("/api/v1/rides/estimate", c.token(), estimateBody("ONCE")).s("code"));
        // cancelling releases the use
        assertEquals(200, post("/api/v1/rides/" + first.s("id") + "/cancel", c.token(), Map.of("reason", "changed my mind")).status());
        assertEquals("RELEASED", jdbc.sql("SELECT status FROM promo_redemptions").query(String.class).single());
        assertEquals(200, post("/api/v1/rides/estimate", c.token(), estimateBody("ONCE")).status());
        assertEquals(0, jdbc.sql("SELECT count(*) FROM accounts WHERE type='PROMO' AND balance<>0").query(Integer.class).single());

        // global limit
        Resp a = ride(c, "CASH", "TWO"); assertEquals(201, a.status(), a.body().toString());
        post("/api/v1/rides/" + a.s("id") + "/cancel", c.token(), null);          // released -> available again
        Resp b = ride(other, "CASH", "TWO"); assertEquals(201, b.status(), b.body().toString());
        assertEquals("promo_exhausted", post("/api/v1/rides/estimate", c.token(), estimateBody("TWO")).s("code"));

        // first-ride-only: refused once the customer has a completed ride
        post("/api/v1/rides/" + b.s("id") + "/cancel", other.token(), null);
        String done = completeRide(c, d, "CASH");
        assertNotNull(done);
        assertEquals("promo_first_ride_only", post("/api/v1/rides/estimate", c.token(), estimateBody("FIRST")).s("code"));
        assertEquals(200, post("/api/v1/rides/estimate", other.token(), estimateBody("FIRST")).status());
        assertLedgerBalanced();
    }

    @Test
    void adminManagesPromosWithRolesValidationAndAudit() {
        Session fin = admin("FINANCE_ADMIN"); Session support = admin("SUPPORT_AGENT");
        Map<String, Object> p = new java.util.HashMap<>(Map.of("code", "summer25", "kind", "PERCENT", "value", 25, "maxDiscount", 400, "minFare", 800, "perUserLimit", 1, "firstRideOnly", false, "active", true));
        assertEquals(403, post("/api/v1/admin/promos", support.token(), p).status());
        Resp created = post("/api/v1/admin/promos", fin.token(), p);
        assertEquals(201, created.status(), created.body().toString());
        assertEquals(409, post("/api/v1/admin/promos", fin.token(), p).status());                             // duplicate code
        Map<String, Object> over = new java.util.HashMap<>(p); over.put("code", "TOOMUCH"); over.put("value", 150);
        assertEquals(400, post("/api/v1/admin/promos", fin.token(), over).status());                          // > 100 %
        Map<String, Object> badDate = new java.util.HashMap<>(p); badDate.put("code", "BADDATE"); badDate.put("startsAt", "2026-12-01T00:00:00+05:00"); badDate.put("endsAt", "2026-11-01T00:00:00+05:00");
        assertEquals(400, post("/api/v1/admin/promos", fin.token(), badDate).status());

        Resp list = get("/api/v1/admin/promos", support.token());
        assertEquals(1, list.body().size());
        assertEquals("SUMMER25", list.body().get(0).path("code").asText());                                  // stored upper-case
        Map<String, Object> upd = new java.util.HashMap<>(p); upd.put("active", false);
        assertEquals(200, put("/api/v1/admin/promos/" + created.s("id"), fin.token(), upd).status());
        upd.put("code", "RENAMED");
        assertEquals(404, put("/api/v1/admin/promos/" + created.s("id"), fin.token(), upd).status());         // codes cannot be renamed
        assertFalse(get("/api/v1/admin/promos", fin.token()).body().get(0).path("active").asBoolean());
        assertEquals(2, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action LIKE 'PROMO_%'").query(Integer.class).single());
    }
}
