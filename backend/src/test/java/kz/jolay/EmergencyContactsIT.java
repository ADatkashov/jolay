package kz.jolay;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Emergency contacts and the SMS they receive when the customer presses SOS. */
class EmergencyContactsIT extends IntegrationTestBase {

    @Test
    void contactsAreManagedPerCustomerWithLimitsAndValidation() {
        Session c = customer(); Session other = customer();
        Resp a = post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Mom", "phone", "+7 701 111 22 33"));
        assertEquals(201, a.status(), a.body().toString());
        assertEquals("+77011112233", a.s("phone"));
        assertEquals(409, post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Mom again", "phone", "+77011112233")).status());
        assertEquals(400, post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Bad", "phone", "12345")).status());
        assertEquals(201, post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Dad", "phone", "+77011112244")).status());
        assertEquals(201, post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Sis", "phone", "+77011112255")).status());
        Resp fourth = post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Extra", "phone", "+77011112266"));
        assertEquals(400, fourth.status());
        assertEquals("too_many_contacts", fourth.s("code"));

        assertEquals(3, get("/api/v1/customers/me/emergency-contacts", c.token()).body().size());
        assertEquals(0, get("/api/v1/customers/me/emergency-contacts", other.token()).body().size());   // not visible to others
        // another customer cannot delete it
        call(org.springframework.http.HttpMethod.DELETE, "/api/v1/customers/me/emergency-contacts/" + a.s("id"), other.token(), null, null);
        assertEquals(3, get("/api/v1/customers/me/emergency-contacts", c.token()).body().size());
        assertEquals(204, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/customers/me/emergency-contacts/" + a.s("id"), c.token(), null, null).status());
        assertEquals(2, get("/api/v1/customers/me/emergency-contacts", c.token()).body().size());
    }

    @Test
    void sosTextsEveryContactWithALiveTripLinkAndRepeatedPressesDoNotResend() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Mom", "phone", "+77011112233"));
        post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Dad", "phone", "+77011112244"));
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);

        assertEquals(201, post("/api/v1/incidents", c.token(), Map.of("type", "SOS", "point", Map.of("lat", 43.2301, "lng", 76.9501))).status());
        var sos = TestConfig.SENT.stream().filter(s -> s[1].contains("SOS")).toList();
        assertEquals(2, sos.size());
        assertEquals(java.util.Set.of("+77011112233", "+77011112244"), sos.stream().map(s -> s[0]).collect(java.util.stream.Collectors.toSet()));
        String token = jdbc.sql("SELECT token FROM ride_shares WHERE ride_id=:r::uuid AND revoked_at IS NULL").param("r", rideId).query(String.class).single();
        assertTrue(sos.get(0)[1].contains("/api/v1/catalog/trip/" + token), sos.get(0)[1]);
        assertEquals(200, get("/api/v1/catalog/ride-share/" + token, null).status());      // the link in the SMS works

        post("/api/v1/incidents", c.token(), Map.of("type", "SOS"));                         // pressed again: no second SMS burst
        assertEquals(2, TestConfig.SENT.stream().filter(s -> s[1].contains("SOS")).count());
    }

    @Test
    void sosWithoutContactsStillWorksAndComplaintsSendNoSms() {
        Session c = customer();
        assertEquals(201, post("/api/v1/incidents", c.token(), Map.of("type", "SOS")).status());
        post("/api/v1/customers/me/emergency-contacts", c.token(), Map.of("name", "Mom", "phone", "+77011112233"));
        assertEquals(201, post("/api/v1/incidents", c.token(), Map.of("type", "COMPLAINT", "description", "Rude driver")).status());
        assertEquals(0, TestConfig.SENT.stream().filter(s -> s[1].contains("SOS")).count());
    }
}
