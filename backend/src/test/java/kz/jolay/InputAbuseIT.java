package kz.jolay;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Hostile input must end in a clean 4xx (never a 500, never data from an injected query) and oversized bodies must be refused early. */
class InputAbuseIT extends IntegrationTestBase {

    private static final List<String> HOSTILE = List.of("' OR 1=1 --", "'; DROP TABLE users; --", "%", "_", "\\", "\" OR \"\"=\"", "${jndi:ldap://x/a}", "<script>alert(1)</script>", "\u0000", "𝒳".repeat(200), "A".repeat(5000));

    @Test
    void injectionAndOddStringsInQueryParametersNeverCauseServerErrors() {
        Session c = customer();
        for (String s : HOSTILE) {
            String q = java.net.URLEncoder.encode(s, java.nio.charset.StandardCharsets.UTF_8);
            int status = get("/api/v1/geo/places?q=" + q, c.token()).status();
            assertTrue(status == 200 || status == 400, "geo q=" + s.substring(0, Math.min(20, s.length())) + " -> " + status);
        }
        assertTrue(jdbc.sql("SELECT count(*) FROM users").query(Integer.class).single() >= 1, "the users table is still there");
        // a place whose name merely contains a quote is found literally, not interpreted
        jdbc.sql("INSERT INTO places(city_id,name,address,location) SELECT id,'O''Neil Bar','Somewhere 1',ST_SetSRID(ST_MakePoint(76.9,43.2),4326)::geography FROM cities LIMIT 1").update();
        assertEquals(1, get("/api/v1/geo/places?q=O'Neil", c.token()).body().size());
        assertEquals(0, get("/api/v1/geo/places?q=' OR 1=1 --", c.token()).body().size(), "an injection string matches nothing");
    }

    @Test
    void hostileValuesInJsonBodiesAreRejectedOrStoredLiterally() {
        Session c = customer();
        for (String s : HOSTILE) {
            Map<String, Object> promoEstimate = Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1]), "promoCode", s);
            int st = post("/api/v1/rides/estimate", c.token(), promoEstimate).status();
            assertTrue(st == 400 || st == 429, "promo '" + s.substring(0, Math.min(15, s.length())) + "' -> " + st);
            int st2 = post("/api/v1/support/tickets", c.token(), Map.of("category", "OTHER", "subject", s, "message", s)).status();
            assertTrue(st2 == 201 || st2 == 400, "ticket -> " + st2);
        }
        Resp bad = post("/api/v1/auth/login", null, Map.of("identifier", "' OR 1=1 --", "password", "x"));
        assertTrue(bad.status() == 400 || bad.status() == 401, "login injection -> " + bad.status());
    }

    @Test
    void malformedJsonWrongTypesAndBadPathVariablesAreClientErrors() {
        Session c = customer();
        assertEquals(400, call(org.springframework.http.HttpMethod.POST, "/api/v1/rides/estimate", c.token(), "{not json", null).status());
        assertEquals(400, call(org.springframework.http.HttpMethod.POST, "/api/v1/rides/estimate", c.token(), "{\"pickup\":\"x\",\"dropoff\":5}", null).status());
        assertEquals(400, call(org.springframework.http.HttpMethod.POST, "/api/v1/rides/estimate", c.token(), "{\"pickup\":{\"lat\":\"north\",\"lng\":1},\"dropoff\":{\"lat\":1,\"lng\":1}}", null).status());
        assertEquals(400, call(org.springframework.http.HttpMethod.POST, "/api/v1/rides/estimate", c.token(), "{\"pickup\":{\"lat\":999,\"lng\":1},\"dropoff\":{\"lat\":1,\"lng\":1}}", null).status(), "out-of-range coordinates");
        for (String path : List.of("/api/v1/rides/not-a-uuid", "/api/v1/deliveries/123", "/api/v1/support/tickets/x/messages", "/api/v1/stores/%27%20OR%201=1/menu")) {
            int st = get(path, c.token()).status();
            assertTrue(st == 400 || st == 401 || st == 403 || st == 404, path + " -> " + st);      // 401/403: rejected by the servlet firewall / the role rule before reaching a controller
        }
    }

    @Test
    void anOversizedJsonBodyIsRefusedBeforeItIsParsed() {
        String huge = "{\"identifier\":\"" + "a".repeat(5 * 1024 * 1024) + "\",\"password\":\"x\"}";
        Resp r = call(org.springframework.http.HttpMethod.POST, "/api/v1/auth/login", null, huge, null);
        assertEquals(413, r.status(), "a 5 MB login body must be refused with 413, got " + r.status());
        // normal-sized requests are unaffected
        assertEquals(401, post("/api/v1/auth/login", null, Map.of("identifier", "+77000000001", "password", "x")).status());
        // 300 KB is still too much for any real request, 200 KB (a long support message with a lot of headroom) is let through to normal validation
        Resp big = call(org.springframework.http.HttpMethod.POST, "/api/v1/auth/login", null, "{\"identifier\":\"" + "a".repeat(300 * 1024) + "\",\"password\":\"x\"}", null);
        assertEquals(413, big.status());
        assertEquals("payload_too_large", big.s("code"));
        Resp ok = call(org.springframework.http.HttpMethod.POST, "/api/v1/auth/login", null, "{\"identifier\":\"" + "a".repeat(200 * 1024) + "\",\"password\":\"x\"}", null);
        assertNotEquals(413, ok.status());
    }
}
