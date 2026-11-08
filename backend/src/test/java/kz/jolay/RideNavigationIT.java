package kz.jolay;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** In-app navigation: both people on a ride see the current leg, strangers do not, and the rider's position reaches only the assigned driver's session. */
class RideNavigationIT extends IntegrationTestBase {

    private String assignedRide(Session c, Session d) {
        jdbc.sql("UPDATE driver_locations SET location = ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, updated_at = now() WHERE driver_id=:d").param("lng", PICKUP[1] + 0.003).param("lat", PICKUP[0] + 0.003).param("d", d.id()).update();
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        String offer = currentOfferId(d);
        assertNotNull(offer, "driver has no offer");
        assertEquals(200, post("/api/v1/drivers/offers/" + offer + "/accept", d.token(), null).status());
        return rideId;
    }

    @Test
    void bothParticipantsGetTheSameRouteLegAndStrangersGetNothing() {
        Session c = customer(); Session d = driver("ECONOMY", PICKUP[0] + 0.003, PICKUP[1] + 0.003);
        String rideId = assignedRide(c, d);

        Resp asCustomer = get("/api/v1/rides/" + rideId + "/navigation", c.token());
        assertEquals(200, asCustomer.status(), asCustomer.body().toString());
        assertEquals("PICKUP", asCustomer.s("leg"), "the driver is on the way to the rider");
        assertTrue(asCustomer.body().path("durationS").asInt() > 0 && asCustomer.body().path("distanceM").asInt() > 0);
        assertTrue(asCustomer.body().path("polyline").size() >= 2);
        assertEquals(2, asCustomer.body().path("polyline").get(0).size(), "points are [lat, lng]");
        assertTrue(asCustomer.body().path("steps").isArray());

        Resp asDriver = get("/api/v1/rides/" + rideId + "/navigation", d.token());
        assertEquals(200, asDriver.status(), asDriver.body().toString());
        assertEquals("PICKUP", asDriver.s("leg"));
        assertEquals(asCustomer.body().path("distanceM").asInt(), asDriver.body().path("distanceM").asInt(), "the cached leg is shared");

        assertEquals(404, get("/api/v1/rides/" + rideId + "/navigation", customer().token()).status(), "another customer must not see this ride's route");
        assertEquals(404, get("/api/v1/rides/" + rideId + "/navigation", driver("ECONOMY", PICKUP[0], PICKUP[1]).token()).status(), "another driver must not either");
        assertEquals(401, get("/api/v1/rides/" + rideId + "/navigation", null).status());
    }

    @Test
    void theRiderCanShareAPositionOnlyWhileTheDriverIsComing() {
        Session c = customer(); Session d = driver("ECONOMY", PICKUP[0] + 0.003, PICKUP[1] + 0.003);
        String rideId = assignedRide(c, d);
        Map<String, Object> here = Map.of("lat", PICKUP[0], "lng", PICKUP[1]);
        assertEquals(204, post("/api/v1/rides/" + rideId + "/customer-location", c.token(), here).status());
        assertEquals(404, post("/api/v1/rides/" + rideId + "/customer-location", customer().token(), here).status(), "not your ride");
        assertEquals(403, post("/api/v1/rides/" + rideId + "/customer-location", d.token(), here).status(), "only the rider shares their position");
        assertEquals(400, post("/api/v1/rides/" + rideId + "/customer-location", c.token(), Map.of("lat", 123, "lng", 0)).status(), "invalid coordinates");
    }

    @Test
    void noNavigationBeforeADriverIsAssigned() {
        Session c = customer();
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        assertEquals(409, get("/api/v1/rides/" + rideId + "/navigation", c.token()).status());
        assertEquals(409, post("/api/v1/rides/" + rideId + "/customer-location", c.token(), Map.of("lat", PICKUP[0], "lng", PICKUP[1])).status());
    }
}
