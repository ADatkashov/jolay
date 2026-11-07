package kz.jolay;

import kz.jolay.common.GeoPoint;
import kz.jolay.pricing.PricingService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** Flat zone surcharges: matching by pickup / destination, summing, quote = final fee, admin API. */
class TariffZoneIT extends IntegrationTestBase {
    @Autowired PricingService pricing;

    @BeforeEach
    void clean() { jdbc.sql("DELETE FROM tariff_zones").update(); jdbc.sql("DELETE FROM peak_windows").update(); jdbc.sql("DELETE FROM promo_redemptions").update(); jdbc.sql("DELETE FROM promo_codes").update(); jdbc.sql("UPDATE pricing_rules SET demand_multiplier=1.00").update(); }

    private UUID city() { return jdbc.sql("SELECT id FROM cities WHERE code='ALA'").query(UUID.class).single(); }
    private void zone(String name, double[] at, int radius, String surcharge, String appliesTo, boolean active) {
        jdbc.sql("INSERT INTO tariff_zones(city_id,name,center,radius_m,surcharge,applies_to,active) VALUES (:c,:n,ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography,:r,:s,:a,:act)")
                .param("c", city()).param("n", name).param("lng", at[1]).param("lat", at[0]).param("r", radius).param("s", new BigDecimal(surcharge)).param("a", appliesTo).param("act", active).update();
    }
    private GeoPoint p(double[] a) { return new GeoPoint(a[0], a[1]); }
    private BigDecimal bd(String s) { return new BigDecimal(s); }
    private Map<String, Object> estimateBody() { return Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1])); }

    @Test
    void surchargeFollowsPickupDropoffAndEitherSemanticsAndNeverCountsAZoneTwice() {
        zone("Pickup only", PICKUP, 300, "500", "PICKUP", true);
        zone("Dropoff only", PICKUP, 300, "900", "DROPOFF", true);            // the destination is ~7 km away: must not apply
        assertEquals(0, bd("500").compareTo(pricing.zoneSurcharge(city(), p(PICKUP), p(DROPOFF))));
        assertEquals(0, bd("900").compareTo(pricing.zoneSurcharge(city(), p(DROPOFF), p(PICKUP))), "reversed trip: now the destination is inside");

        zone("Airport", DROPOFF, 400, "700", "EITHER", true);
        assertEquals(0, bd("1200").compareTo(pricing.zoneSurcharge(city(), p(PICKUP), p(DROPOFF))), "pickup zone + EITHER zone around the destination");
        // both ends inside the same EITHER zone: counted once
        assertEquals(0, bd("700").compareTo(pricing.zoneSurcharge(city(), p(DROPOFF), new GeoPoint(DROPOFF[0] + 0.0005, DROPOFF[1]))));
        zone("Off", DROPOFF, 400, "10000", "EITHER", false);
        assertEquals(0, bd("1200").compareTo(pricing.zoneSurcharge(city(), p(PICKUP), p(DROPOFF))), "inactive zones are ignored");
        // outside every zone
        assertEquals(0, BigDecimal.ZERO.compareTo(pricing.zoneSurcharge(city(), new GeoPoint(43.30, 77.10), new GeoPoint(43.31, 77.11))));
    }

    @Test
    void estimateAddsTheSurchargeToTheFeesAndTheRideKeepsTheQuotedAmount() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        var plain = post("/api/v1/rides/estimate", c.token(), estimateBody()).body().path("categories").get(0).path("fare");
        BigDecimal base = bd(plain.path("total").asText()), bookingFee = bd(plain.path("fees").asText());

        zone("Station", PICKUP, 300, "700", "EITHER", true);
        var quoted = post("/api/v1/rides/estimate", c.token(), estimateBody()).body().path("categories").get(0).path("fare");
        assertEquals(0, bookingFee.add(bd("700")).compareTo(bd(quoted.path("fees").asText())), "the surcharge is shown in the fee line");
        BigDecimal diff = bd(quoted.path("total").asText()).subtract(base);
        assertTrue(diff.compareTo(bd("700")) >= 0 && diff.compareTo(bd("800")) <= 0, "total rises by the surcharge (plus rounding): " + diff);

        Resp ride = requestRide(c, "ECONOMY", "CASH");
        assertEquals(201, ride.status(), ride.body().toString());
        assertEquals(0, bd("700").compareTo(jdbc.sql("SELECT zone_surcharge FROM rides WHERE id=:r::uuid").param("r", ride.s("id")).query(BigDecimal.class).single()));
        assertEquals(0, bd(quoted.path("total").asText()).compareTo(bd(ride.s("estimatedFare"))));

        jdbc.sql("DELETE FROM tariff_zones").update();                          // the zone disappears mid-ride: the rider keeps the quoted surcharge
        String rideId = ride.s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, 43.2200, 76.9300); moveDriver(d, DROPOFF[0], DROPOFF[1]);
        assertEquals(200, post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null).status());
        assertEquals(0, bookingFee.add(bd("700")).compareTo(jdbc.sql("SELECT fees FROM ride_fares WHERE ride_id=:r::uuid").param("r", rideId).query(BigDecimal.class).single()), "final fee line = quoted");
        assertLedgerBalanced();
    }

    @Test
    void adminManagesZonesWithRolesValidationAndAudit() {
        Session fin = admin("FINANCE_ADMIN"); Session support = admin("SUPPORT_AGENT");
        Map<String, Object> z = new java.util.HashMap<>(Map.of("city", "ALA", "name", "Airport", "lat", 43.3521, "lng", 77.0405, "radiusM", 2000, "surcharge", 800, "appliesTo", "EITHER", "active", true));
        assertEquals(403, post("/api/v1/admin/pricing/zones", support.token(), z).status());
        Resp created = post("/api/v1/admin/pricing/zones", fin.token(), z);
        assertEquals(201, created.status(), created.body().toString());

        for (var bad : java.util.List.<Map<String, Object>>of(
                Map.of("radiusM", 50), Map.of("radiusM", 90000), Map.of("surcharge", 0), Map.of("appliesTo", "BOTH"), Map.of("lat", 123), Map.of("city", "NOWHERE"))) {
            Map<String, Object> m = new java.util.HashMap<>(z); m.putAll(bad);
            assertEquals(400, post("/api/v1/admin/pricing/zones", fin.token(), m).status(), "should be rejected: " + bad);
        }
        Resp list = get("/api/v1/admin/pricing/zones", support.token());
        assertEquals(1, list.body().size());
        assertEquals(43.3521, list.body().get(0).path("lat").asDouble(), 1e-6);
        assertEquals("EITHER", list.body().get(0).path("applies_to").asText());

        z.put("surcharge", 1000); z.put("active", false);
        assertEquals(200, put("/api/v1/admin/pricing/zones/" + created.s("id"), fin.token(), z).status());
        assertFalse(get("/api/v1/admin/pricing/zones", fin.token()).body().get(0).path("active").asBoolean());
        assertEquals(204, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/admin/pricing/zones/" + created.s("id"), fin.token(), null, null).status());
        assertEquals(404, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/admin/pricing/zones/" + created.s("id"), fin.token(), null, null).status());
        assertEquals(3, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action LIKE 'TARIFF_ZONE_%'").query(Integer.class).single());
    }
}
