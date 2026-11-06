package kz.jolay;

import kz.jolay.delivery.DeliveryDispatchService;
import kz.jolay.delivery.DeliveryStatus;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class DeliveryIT extends IntegrationTestBase {
    @Autowired DeliveryDispatchService dispatch;

    private Session courier(double lat, double lng) {
        Session c = driver("ECONOMY", lat, lng);
        assertEquals(200, put("/api/v1/drivers/delivery", c.token(), Map.of("enabled", true)).status());
        return c;
    }
    private Map<String, Object> body(String size, double kg, String payment) {
        return Map.of("pickup", Map.of("point", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "address", "Dostyk Plaza"),
                "dropoff", Map.of("point", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1]), "address", "Mega Alma-Ata"),
                "sizeClass", size, "weightKg", kg, "description", "Documents in an envelope", "paymentMethod", payment,
                "sender", Map.of("name", "Aidar Bekov", "phone", "+77011110001"), "recipient", Map.of("name", "Dana Sadykova", "phone", "8 701 222 33 44"));
    }
    private void at(Session d, double lat, double lng) {
        jdbc.sql("UPDATE driver_locations SET location = ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, updated_at = now() WHERE driver_id=:d").param("lng", lng).param("lat", lat).param("d", d.id()).update();
    }
    private String offerId(Session d) { Resp o = get("/api/v1/drivers/delivery-offers", d.token()); return o.status() == 200 && o.body().has("offer_id") ? o.s("offer_id") : null; }
    private Resp create(Session c, Map<String, Object> b) { return post("/api/v1/deliveries", c.token(), b); }

    @Test
    void estimateUsesTariffsAndValidatesParcelAndZone() {
        Session c = customer();
        Map<String, Object> pts = Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1]));
        Resp small = post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "SMALL", "weightKg", 1.0)));
        assertEquals(200, small.status(), small.body().toString());
        assertEquals("ESTIMATED", small.s("routeSource"));
        assertFalse(small.body().path("courierAvailable").asBoolean());
        BigDecimal fee = small.body().path("fee").path("total").decimalValue();
        assertEquals(0, fee.remainder(new BigDecimal("10")).signum(), "rounded to the tariff step");
        BigDecimal heavy = post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "MEDIUM", "weightKg", 9.0))).body().path("fee").path("total").decimalValue();
        BigDecimal light = post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "MEDIUM", "weightKg", 2.0))).body().path("fee").path("total").decimalValue();
        assertTrue(heavy.compareTo(light) > 0, "weight above the free allowance costs more");
        assertEquals("parcel_too_heavy", post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "SMALL", "weightKg", 3.0))).s("code"));
        assertEquals(400, post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "HUGE", "weightKg", 1.0))).status());
        assertEquals("pickup_out_of_zone", post("/api/v1/deliveries/estimate", c.token(), Map.of("pickup", Map.of("lat", 51.17, "lng", 71.45), "dropoff", Map.of("lat", 51.12, "lng", 71.43), "sizeClass", "SMALL", "weightKg", 1.0)).s("code"));
        courier(43.2336, 76.9568);
        assertTrue(post("/api/v1/deliveries/estimate", c.token(), merge(pts, Map.of("sizeClass", "SMALL", "weightKg", 1.0))).body().path("courierAvailable").asBoolean());
    }

    private Map<String, Object> merge(Map<String, Object> a, Map<String, Object> b) { var m = new java.util.HashMap<>(a); m.putAll(b); return m; }

    @Test
    void cashDeliveryEndToEndWithHandoverCode() {
        Session c = customer(); Session k = courier(43.2336, 76.9568);
        Resp created = create(c, body("SMALL", 1.0, "CASH"));
        assertEquals(201, created.status(), created.body().toString());
        String id = created.s("id");
        assertEquals("SEARCHING_COURIER", created.s("status"));
        assertTrue(created.s("trackingNumber").startsWith("JL"));
        String code = created.s("handoverCode");
        assertTrue(code.matches("\\d{4}"));
        assertEquals("+77012223344", created.s("recipientPhone"), "phone normalised");

        String offer = offerId(k);
        assertNotNull(offer);
        Resp acc = post("/api/v1/drivers/delivery-offers/" + offer + "/accept", k.token(), null);
        assertEquals("COURIER_ASSIGNED", acc.s("status"));
        assertNull(acc.body().get("handoverCode"), "the courier never sees the code");
        assertEquals(k.id().toString(), get("/api/v1/drivers/deliveries/active", k.token()).s("id") == null ? "" : k.id().toString());

        // cannot confirm pickup from far away, nor skip steps
        at(k, 43.30, 76.95);
        assertEquals("not_at_pickup", post("/api/v1/drivers/deliveries/" + id + "/picked-up", k.token(), null).s("code"));
        assertEquals(409, post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", code)).status());
        at(k, PICKUP[0], PICKUP[1]);
        assertEquals("PICKED_UP", post("/api/v1/drivers/deliveries/" + id + "/picked-up", k.token(), null).s("status"));
        assertEquals(409, post("/api/v1/deliveries/" + id + "/cancel", c.token(), null).status(), "no customer cancel once picked up");

        at(k, 43.2300, 76.9400);
        assertEquals("not_at_dropoff", post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", code)).s("code"));
        at(k, DROPOFF[0], DROPOFF[1]);
        String wrong = code.equals("0000") ? "1111" : "0000";
        assertEquals("invalid_handover_code", post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", wrong)).s("code"));
        assertEquals("PICKED_UP", get("/api/v1/deliveries/" + id, c.token()).s("status"));
        Resp done = post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", code));
        assertEquals(200, done.status(), done.body().toString());
        assertEquals("DELIVERED", done.s("status"));
        assertEquals("PAID", done.s("paymentStatus"));

        BigDecimal commission = jdbc.sql("SELECT commission FROM delivery_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        assertEquals(0, balance(k).compareTo(commission.negate()), "courier owes the platform commission on cash");
        assertEquals("ONLINE", get("/api/v1/drivers/me", k.token()).s("availability"));
        assertNull(get("/api/v1/deliveries/" + id, c.token()).body().get("handoverCode"), "code is hidden once the order is finished");
        assertEquals(201, post("/api/v1/deliveries/" + id + "/rating", c.token(), Map.of("stars", 5, "comment", "Fast")).status());
        assertEquals(409, post("/api/v1/deliveries/" + id + "/rating", c.token(), Map.of("stars", 4)).status());
        assertEquals(1, get("/api/v1/deliveries/history?tab=completed", c.token()).body().size());
        assertEquals(1, get("/api/v1/drivers/deliveries/history", k.token()).body().size());
        assertEquals(1, get("/api/v1/admin/deliveries?status=DELIVERED", admin("SUPPORT_AGENT").token()).body().size());
        assertLedgerBalanced();
        assertEquals("OK", get("/api/v1/admin/finance/reconciliation", admin("FINANCE_ADMIN").token()).s("status"));
    }

    @Test
    void walletDeliverySettlesThroughTheLedger() {
        Session c = customer(); Session k = courier(43.2336, 76.9568);
        assertEquals("insufficient_funds", create(c, body("SMALL", 1.0, "WALLET")).s("code"));
        topUp(c, 10000);
        String id = create(c, body("SMALL", 1.0, "WALLET")).s("id");
        String code = get("/api/v1/deliveries/" + id, c.token()).s("handoverCode");
        post("/api/v1/drivers/delivery-offers/" + offerId(k) + "/accept", k.token(), null);
        at(k, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/deliveries/" + id + "/picked-up", k.token(), null);
        at(k, DROPOFF[0], DROPOFF[1]);
        assertEquals(200, post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", code)).status());
        BigDecimal fee = jdbc.sql("SELECT fee FROM delivery_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        BigDecimal earnings = jdbc.sql("SELECT courier_earnings FROM delivery_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        assertEquals(0, balance(c).compareTo(new BigDecimal("10000").subtract(fee)));
        assertEquals(0, balance(k).compareTo(earnings));
        assertLedgerBalanced();
    }

    @Test
    void handoverCodeIsProtectedAgainstGuessing() {
        Session c = customer(); Session k = courier(43.2336, 76.9568);
        String id = create(c, body("SMALL", 1.0, "CASH")).s("id");
        String code = get("/api/v1/deliveries/" + id, c.token()).s("handoverCode");
        post("/api/v1/drivers/delivery-offers/" + offerId(k) + "/accept", k.token(), null);
        at(k, PICKUP[0], PICKUP[1]); post("/api/v1/drivers/deliveries/" + id + "/picked-up", k.token(), null);
        at(k, DROPOFF[0], DROPOFF[1]);
        String wrong = code.equals("0000") ? "1111" : "0000";
        for (int i = 0; i < 5; i++) assertEquals("invalid_handover_code", post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", wrong)).s("code"));
        Resp locked = post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", code));   // even the right code is refused now
        assertEquals(403, locked.status());
        assertEquals("handover_locked", locked.s("code"));
        assertEquals("PICKED_UP", get("/api/v1/deliveries/" + id, c.token()).s("status"));
        assertEquals(400, post("/api/v1/drivers/deliveries/" + id + "/deliver", k.token(), Map.of("code", "12ab")).status());
    }

    @Test
    void dispatchOnlyOffersToCouriersWhoOptedInAndRespectsDeclineExpiryAndTimeout() {
        Session c = customer();
        Session rideOnly = driver("ECONOMY", 43.2336, 76.9568);                 // did not opt in to deliveries
        String id = create(c, body("SMALL", 1.0, "CASH")).s("id");
        assertNull(offerId(rideOnly));
        Session near = courier(43.2337, 76.9569); Session far = courier(43.2400, 76.9700);
        dispatch.tick();
        assertNotNull(offerId(near));
        assertNull(offerId(far), "one offer at a time");
        assertEquals(204, post("/api/v1/drivers/delivery-offers/" + offerId(near) + "/decline", near.token(), null).status());
        String farOffer = offerId(far);
        assertNotNull(farOffer);
        jdbc.sql("UPDATE delivery_offers SET expires_at = now() - interval '1 second'").update();
        Resp late = post("/api/v1/drivers/delivery-offers/" + farOffer + "/accept", far.token(), null);
        assertEquals(409, late.status(), "late accept is refused");
        assertEquals("offer_expired", late.s("code"));
        dispatch.expireOffers();
        assertEquals("ONLINE", get("/api/v1/drivers/me", far.token()).s("availability"));
        // nobody left (near declined, far expired) -> the order expires after the search window
        jdbc.sql("UPDATE delivery_orders SET search_started_at = now() - interval '10 minutes'").update();
        dispatch.tick();
        assertEquals("EXPIRED", get("/api/v1/deliveries/" + id, c.token()).s("status"));
        assertEquals(1, get("/api/v1/deliveries/history?tab=cancelled", c.token()).body().size());
    }

    @Test
    void cancellationsAndCourierHandBack() {
        Session c = customer(); Session k1 = courier(43.2336, 76.9568);
        String id = create(c, body("SMALL", 1.0, "CASH")).s("id");
        post("/api/v1/drivers/delivery-offers/" + offerId(k1) + "/accept", k1.token(), null);
        Session k2 = courier(43.2340, 76.9570);
        assertEquals(204, post("/api/v1/drivers/deliveries/" + id + "/cancel", k1.token(), Map.of("reason", "flat tyre")).status());
        assertEquals("SEARCHING_COURIER", get("/api/v1/deliveries/" + id, c.token()).s("status"));
        assertNotNull(offerId(k2));
        assertNull(offerId(k1), "the courier who handed it back is not re-offered");
        post("/api/v1/drivers/delivery-offers/" + offerId(k2) + "/accept", k2.token(), null);
        Resp cancelled = post("/api/v1/deliveries/" + id + "/cancel", c.token(), Map.of("reason", "changed my mind"));
        assertEquals("CANCELLED", cancelled.s("status"));
        assertEquals("ONLINE", get("/api/v1/drivers/me", k2.token()).s("availability"));
        assertEquals(409, post("/api/v1/deliveries/" + id + "/cancel", c.token(), null).status());
        // cancelling while searching withdraws the pending offer
        Session c2 = customer();
        String id2 = create(c2, body("SMALL", 1.0, "CASH")).s("id");
        Session offered = offerId(k1) != null ? k1 : k2;              // the nearest free courier gets it
        assertNotNull(offerId(offered));
        assertEquals("OFFERED", get("/api/v1/drivers/me", offered.token()).s("availability"));
        assertEquals("CANCELLED", post("/api/v1/deliveries/" + id2 + "/cancel", c2.token(), null).s("status"));
        assertNull(offerId(offered));
        assertEquals("ONLINE", get("/api/v1/drivers/me", offered.token()).s("availability"));
    }

    @Test
    void accessControlPrivacyTrackingAndIdempotency() {
        Session c = customer(), other = customer(); Session k = courier(43.2336, 76.9568); Session ride = register("DRIVER");
        Resp a = call(org.springframework.http.HttpMethod.POST, "/api/v1/deliveries", c.token(), body("SMALL", 1.0, "CASH"), Map.of("Idempotency-Key", "d1"));
        Resp b = call(org.springframework.http.HttpMethod.POST, "/api/v1/deliveries", c.token(), body("SMALL", 1.0, "CASH"), Map.of("Idempotency-Key", "d1"));
        assertEquals(a.s("id"), b.s("id"));
        assertEquals(1, jdbc.sql("SELECT count(*) FROM delivery_orders").query(Integer.class).single());
        String id = a.s("id"), tracking = a.s("trackingNumber");

        assertEquals(404, get("/api/v1/deliveries/" + id, other.token()).status());
        assertEquals(404, post("/api/v1/deliveries/" + id + "/cancel", other.token(), null).status());
        assertEquals(403, post("/api/v1/deliveries", k.token(), body("SMALL", 1.0, "CASH")).status(), "couriers are not customers");
        assertEquals(403, get("/api/v1/drivers/delivery-offers", c.token()).status());
        assertEquals(404, post("/api/v1/drivers/deliveries/" + id + "/picked-up", k.token(), null).status(), "not this courier's order");
        assertEquals(403, get("/api/v1/admin/deliveries", c.token()).status());
        assertEquals(403, get("/api/v1/admin/deliveries", admin("PARTNER_ADMIN").token()).status());
        assertEquals(400, post("/api/v1/deliveries", c.token(), merge(body("SMALL", 1.0, "CASH"), Map.of("recipient", Map.of("name", "X Y", "phone", "123")))).status());
        assertEquals(400, post("/api/v1/deliveries", c.token(), merge(body("SMALL", 1.0, "CARD"), Map.of())).status(), "card delivery is not supported yet");

        // the courier sees phone numbers only once assigned; before that nothing personal leaks
        post("/api/v1/drivers/delivery-offers/" + offerId(k) + "/accept", k.token(), null);
        Resp courierView = get("/api/v1/admin/deliveries/" + id, admin("SUPPORT_AGENT").token());
        assertEquals("COURIER_ASSIGNED", courierView.s("status"));
        // public tracking: status and timestamps only
        Resp pub = get("/api/v1/catalog/track/" + tracking.toLowerCase(), null);
        assertEquals(200, pub.status());
        assertEquals("COURIER_ASSIGNED", pub.s("status"));
        String json = pub.body().toString();
        assertFalse(json.contains("Aidar") || json.contains("Dana") || json.contains("+7701") || json.contains("Dostyk"), "no personal data in public tracking: " + json);
        assertEquals(404, get("/api/v1/catalog/track/NOPE", null).status());
        // courier location is streamed to the customer through the delivery view
        at(k, 43.2338, 76.9570);
        assertEquals(43.2338, get("/api/v1/deliveries/" + id, c.token()).body().path("courier").path("lat").asDouble(), 0.0001);
    }

    @Test
    void stateMachineRules() {
        assertTrue(DeliveryStatus.SEARCHING_COURIER.canMoveTo(DeliveryStatus.COURIER_ASSIGNED));
        assertTrue(DeliveryStatus.COURIER_ASSIGNED.canMoveTo(DeliveryStatus.SEARCHING_COURIER));
        assertFalse(DeliveryStatus.SEARCHING_COURIER.canMoveTo(DeliveryStatus.PICKED_UP));
        assertFalse(DeliveryStatus.PICKED_UP.canMoveTo(DeliveryStatus.CANCELLED));
        for (DeliveryStatus t : new DeliveryStatus[]{DeliveryStatus.DELIVERED, DeliveryStatus.CANCELLED, DeliveryStatus.EXPIRED, DeliveryStatus.FAILED})
            for (DeliveryStatus n : DeliveryStatus.values()) assertFalse(t.canMoveTo(n));
    }

    @Test
    void aCourierWhoCancelsRepeatedlyIsFlaggedAndStopsReceivingOffers() {
        assertEquals(200, put("/api/v1/admin/settings/dispatch.cancel_cooldown_count", admin("SUPER_ADMIN").token(), Map.of("value", "2")).status());
        assertEquals(200, put("/api/v1/admin/settings/risk.courier_cancels_24h", admin("SUPER_ADMIN").token(), Map.of("value", "2")).status());
        try {
            Session k = courier(43.2336, 76.9568);
            for (int i = 0; i < 2; i++) {
                Session c = customer();
                assertEquals(201, create(c, body("SMALL", 1.0, "CASH")).status());
                String offer = offerId(k);
                assertNotNull(offer, "cancellation " + i + ": still eligible");
                String id = post("/api/v1/drivers/delivery-offers/" + offer + "/accept", k.token(), null).s("id");
                assertEquals(204, post("/api/v1/drivers/deliveries/" + id + "/cancel", k.token(), Map.of("reason", "changed my mind")).status());
                put("/api/v1/drivers/availability", k.token(), Map.of("online", true));
                moveDriver(k, 43.2336, 76.9568);
            }
            assertEquals(1, jdbc.sql("SELECT count(*) FROM risk_flags WHERE user_id=:u AND rule='REPEATED_CANCELLATIONS'").param("u", k.id()).query(Integer.class).single(), "advisory flag raised");
            assertEquals("ACTIVE", jdbc.sql("SELECT status FROM users WHERE id=:i").param("i", k.id()).query(String.class).single(), "never suspended automatically");
            Session c3 = customer();
            assertEquals(201, create(c3, body("SMALL", 1.0, "CASH")).status());
            assertNull(offerId(k), "no new offers while the cancellations count");
        } finally {
            put("/api/v1/admin/settings/dispatch.cancel_cooldown_count", admin("SUPER_ADMIN").token(), Map.of("value", "3"));
            put("/api/v1/admin/settings/risk.courier_cancels_24h", admin("SUPER_ADMIN").token(), Map.of("value", "3"));
        }
    }
}
