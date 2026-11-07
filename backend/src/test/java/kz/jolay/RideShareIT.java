package kz.jolay;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Trip sharing: tokenised public view of an active ride. */
class RideShareIT extends IntegrationTestBase {

    @Test
    void sharedTripIsPublicMinimalAndStopsWhenRevokedOrFinished() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);

        Resp share = post("/api/v1/rides/" + rideId + "/share", c.token(), null);
        assertEquals(200, share.status(), share.body().toString());
        String token = share.s("token");
        assertTrue(token.length() >= 32);
        assertEquals(token, post("/api/v1/rides/" + rideId + "/share", c.token(), null).s("token"));   // idempotent: one active link per ride

        assertTrue(share.s("url").endsWith("/api/v1/catalog/trip/" + token));
        var page = rest.getForEntity("http://localhost:" + port + "/api/v1/catalog/trip/" + token, String.class);
        assertEquals(200, page.getStatusCode().value());
        assertTrue(page.getBody().contains("shared trip"));

        Resp pub = get("/api/v1/catalog/ride-share/" + token, null);                                   // no authentication
        assertEquals(200, pub.status(), pub.body().toString());
        assertEquals("DRIVER_ASSIGNED", pub.s("status"));
        assertTrue(pub.body().path("active").asBoolean());
        assertTrue(pub.body().path("driverLocation").has("lat"));
        assertNotNull(pub.body().path("vehicle").path("plate").asText(null));
        String json = pub.body().toString();
        assertFalse(json.contains(c.phone()), "customer phone must not leak");
        assertFalse(json.contains(d.phone()), "driver phone must not leak");
        assertFalse(pub.body().has("finalFare") || pub.body().has("estimatedFare") || pub.body().has("paymentMethod"));

        // other customers cannot create or revoke a link for this ride
        Session other = customer();
        assertEquals(404, post("/api/v1/rides/" + rideId + "/share", other.token(), null).status());
        assertEquals(404, get("/api/v1/catalog/ride-share/not-a-real-token", null).status());

        // revoke
        assertEquals(204, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/rides/" + rideId + "/share", c.token(), null, null).status());
        assertEquals(404, get("/api/v1/catalog/ride-share/" + token, null).status());
    }

    /** Found by the live contract test: a link opened while the app is still searching must stay live, otherwise the viewer page stops refreshing and never shows the driver. */
    @Test
    void aLinkSharedWhileSearchingIsLiveButHasNoPositionYet() {
        Session c = customer(); driver("ECONOMY", 43.2340, 76.9570);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        String token = post("/api/v1/rides/" + rideId + "/share", c.token(), null).s("token");
        Resp pub = get("/api/v1/catalog/ride-share/" + token, null);
        assertEquals(200, pub.status());
        assertEquals("SEARCHING_DRIVER", pub.s("status"));
        assertTrue(pub.body().path("active").asBoolean(), "the viewer must keep polling while a driver is being found");
        assertFalse(pub.body().has("driverLocation"));
        assertFalse(pub.body().has("driverName"));
    }

    @Test
    void finishedRideKeepsFinalStatusWithoutLocationThenExpires() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        String token = post("/api/v1/rides/" + rideId + "/share", c.token(), null).s("token");

        jdbc.sql("UPDATE rides SET status='COMPLETED', completed_at=now() WHERE id=:r::uuid").param("r", rideId).update();
        Resp done = get("/api/v1/catalog/ride-share/" + token, null);
        assertEquals(200, done.status());
        assertEquals("COMPLETED", done.s("status"));
        assertFalse(done.body().path("active").asBoolean());
        assertFalse(done.body().has("driverLocation"), "no live position after the ride ends");
        assertEquals(409, post("/api/v1/rides/" + rideId + "/share", c.token(), null).status());

        jdbc.sql("UPDATE rides SET completed_at = now() - interval '3 hours' WHERE id=:r::uuid").param("r", rideId).update();
        assertEquals(404, get("/api/v1/catalog/ride-share/" + token, null).status());
    }
}
