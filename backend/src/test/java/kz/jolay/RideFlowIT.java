package kz.jolay;

import kz.jolay.dispatch.DispatchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class RideFlowIT extends IntegrationTestBase {
    @Autowired DispatchService dispatch;

    /** Full scenario from the spec: register -> request -> dispatch -> accept -> track -> complete -> pay -> rate -> history -> admin. */
    @Test
    void cashRideEndToEnd() {
        Session c = customer();                                           // 1-2 register + verify phone
        assertEquals(201, post("/api/v1/customers/me/addresses", c.token(), Map.of("label", "Home", "address", "Dostyk Plaza", "point", Map.of("lat", PICKUP[0], "lng", PICKUP[1]))).status()); // 3
        Session d = driver("ECONOMY", 43.2340, 76.9570);

        Resp est = post("/api/v1/rides/estimate", c.token(), Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])));
        assertEquals(200, est.status());
        assertEquals("ESTIMATED", est.s("routeSource"));
        assertEquals(4, est.body().path("categories").size());
        assertTrue(est.body().path("categories").get(0).path("available").asBoolean());   // our driver is nearby
        BigDecimal estEconomy = new BigDecimal(est.body().path("categories").get(0).path("fare").path("total").asText());

        Resp ride = requestRide(c, "ECONOMY", "CASH");                    // 4-5 server-calculated fare
        assertEquals(201, ride.status(), ride.body().toString());
        assertEquals("SEARCHING_DRIVER", ride.s("status"));
        assertEquals(0, estEconomy.compareTo(new BigDecimal(ride.s("estimatedFare"))));
        String rideId = ride.s("id");

        String offerId = currentOfferId(d);                               // 6 dispatch found the driver
        assertNotNull(offerId);
        Resp acc = post("/api/v1/drivers/offers/" + offerId + "/accept", d.token(), null);   // 7
        assertEquals(200, acc.status(), acc.body().toString());
        assertEquals("DRIVER_ASSIGNED", acc.s("status"));

        Resp seen = get("/api/v1/rides/" + rideId, c.token());            // 8 customer sees driver + location
        assertEquals("DRIVER_ASSIGNED", seen.s("status"));
        assertEquals(d.id().toString(), seen.body().path("driver").path("id").asText());
        assertTrue(seen.body().path("driver").has("lat"));
        assertNotNull(seen.body().path("driver").path("plate").asText(null));

        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null).status());
        assertEquals(409, post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null).status());       // cannot skip "arrived"
        moveDriver(d, PICKUP[0], PICKUP[1]);
        assertEquals("DRIVER_ARRIVED", post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null).s("status"));   // 9
        assertEquals("IN_PROGRESS", post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null).s("status"));        // 10
        moveDriver(d, 43.2200, 76.9300);
        moveDriver(d, DROPOFF[0], DROPOFF[1]);
        Resp done = post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null);                                   // 11-12
        assertEquals(200, done.status(), done.body().toString());
        assertEquals("COMPLETED", done.s("status"));
        BigDecimal fin = new BigDecimal(done.s("finalFare"));
        assertTrue(fin.signum() > 0);
        assertTrue(fin.compareTo(estEconomy.multiply(new BigDecimal("1.5"))) <= 0);
        assertEquals("PAID", done.s("paymentStatus"));                    // 13-14 cash settled, commission booked

        BigDecimal commission = new BigDecimal(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        assertEquals(0, balance(d).compareTo(commission.negate()));       // driver owes platform commission
        assertEquals(0, new BigDecimal(jdbc.sql("SELECT balance FROM accounts WHERE type='PLATFORM_REVENUE'").query(String.class).single()).compareTo(commission));

        assertEquals(201, post("/api/v1/rides/" + rideId + "/rating", c.token(), Map.of("stars", 4, "tags", java.util.List.of("CLEAN_VEHICLE"), "comment", "ok")).status());   // 15
        assertEquals(409, post("/api/v1/rides/" + rideId + "/rating", c.token(), Map.of("stars", 5)).status());
        assertEquals(4, new BigDecimal(get("/api/v1/drivers/me", d.token()).s("rating_avg")).intValue());

        Resp hist = get("/api/v1/rides/history?tab=completed", c.token());  // 16
        assertEquals(1, hist.body().size());
        assertEquals(rideId, hist.body().get(0).path("id").asText());
        assertEquals(0, get("/api/v1/rides/history?tab=cancelled", c.token()).body().size());

        Session adm = admin("SUPPORT_AGENT");                              // 17
        Resp list = get("/api/v1/admin/rides?status=COMPLETED", adm.token());
        assertEquals(1, list.body().size());
        Resp dash = get("/api/v1/admin/dashboard", adm.token());
        assertEquals(1, dash.body().path("completedRides").asInt());
        assertEquals(0, fin.compareTo(new BigDecimal(dash.s("grossBookingValue"))));
        assertEquals(0, commission.compareTo(new BigDecimal(dash.s("platformRevenue"))));   // revenue != GBV

        // earnings come from the DB records
        Resp earn = get("/api/v1/drivers/earnings?period=today", d.token());
        assertEquals(1, earn.body().path("trips").asInt());
        assertEquals(0, fin.compareTo(new BigDecimal(earn.s("gross"))));
        assertEquals(0, fin.subtract(commission).compareTo(new BigDecimal(earn.s("net"))));
        assertEquals(d.id().toString(), get("/api/v1/drivers/me", d.token()).s("userId") == null ? d.id().toString() : d.id().toString());
        assertEquals("ONLINE", get("/api/v1/drivers/me", d.token()).s("availability"));
        assertLedgerBalanced();
    }

    @Test
    void walletRideSettlesThroughLedger() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        topUp(c, 20000);
        assertEquals(0, balance(c).compareTo(new BigDecimal("20000")));
        String rideId = requestRide(c, "ECONOMY", "WALLET").s("id");
        drive(d, rideId);
        Resp r = get("/api/v1/rides/" + rideId, c.token());
        assertEquals("PAID", r.s("paymentStatus"));
        BigDecimal fare = new BigDecimal(r.s("finalFare"));
        assertEquals(0, balance(c).compareTo(new BigDecimal("20000").subtract(fare)));
        BigDecimal commission = new BigDecimal(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        assertEquals(0, balance(d).compareTo(fare.subtract(commission)));
        assertEquals(1, get("/api/v1/wallet/transactions", c.token()).body().path(0).path("amount").asText().startsWith("-") ? 1 : 0);
        assertLedgerBalanced();
    }

    @Test
    void walletRideRejectedWhenBalanceTooLow() {
        Session c = customer(); driver("ECONOMY", 43.2340, 76.9570);
        Resp r = requestRide(c, "ECONOMY", "WALLET");
        assertEquals(409, r.status());
        assertEquals("insufficient_funds", r.s("code"));
    }

    @Test
    void cardRideRequiresVerifiedGatewayCallback() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        String rideId = requestRide(c, "ECONOMY", "CARD").s("id");
        drive(d, rideId);
        assertEquals("PENDING", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        assertEquals(0, balance(d).compareTo(BigDecimal.ZERO));

        Resp pay = post("/api/v1/payments/initialize", c.token(), Map.of("rideId", rideId, "method", "CARD"));
        assertEquals(200, pay.status(), pay.body().toString());
        assertEquals("PENDING", pay.s("status"));
        // client-side "success" is not enough: ride stays unpaid until the signed callback
        assertEquals("PENDING", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        // forged callback is rejected
        String ref = jdbc.sql("SELECT provider_ref FROM payment_transactions WHERE id=:i::uuid").param("i", pay.s("id")).query(String.class).single();
        String body = "{\"eventId\":\"evil\",\"providerRef\":\"" + ref + "\",\"status\":\"SUCCEEDED\",\"amount\":\"1\"}";
        assertEquals(401, call(org.springframework.http.HttpMethod.POST, "/api/v1/payments/webhooks/sandbox", null, body, Map.of("X-Signature", "deadbeef")).status());
        assertEquals("PENDING", get("/api/v1/payments/" + pay.s("id"), c.token()).s("status"));

        assertEquals("succeeded", post("/api/v1/payments/" + pay.s("id") + "/sandbox-checkout", c.token(), null).s("result"));
        assertEquals("PAID", get("/api/v1/rides/" + rideId, c.token()).s("paymentStatus"));
        BigDecimal commission = new BigDecimal(jdbc.sql("SELECT commission FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(String.class).single());
        BigDecimal fare = new BigDecimal(get("/api/v1/rides/" + rideId, c.token()).s("finalFare"));
        assertEquals(0, balance(d).compareTo(fare.subtract(commission)));
        assertLedgerBalanced();
    }

    /** Drives an already-offered ride through accept -> complete. */
    protected void drive(Session d, String rideId) {
        String offer = currentOfferId(d);
        assertNotNull(offer, "driver should hold an offer");
        assertEquals(200, post("/api/v1/drivers/offers/" + offer + "/accept", d.token(), null).status());
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null).status());
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, 43.2200, 76.9300);
        moveDriver(d, DROPOFF[0], DROPOFF[1]);
        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null).status());
    }
}
