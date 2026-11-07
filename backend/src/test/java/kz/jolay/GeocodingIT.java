package kz.jolay;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.net.InetSocketAddress;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** End to end with JOLAY_NOMINATIM_URL pointing at a local stub: search, reverse geocoding of a pickup, and the fallback to the seeded places. */
class GeocodingIT extends IntegrationTestBase {
    private static HttpServer stub;
    private static final AtomicReference<String> searchBody = new AtomicReference<>("[]");
    private static final AtomicReference<String> reverseBody = new AtomicReference<>("{\"error\":\"none\"}");
    private static final AtomicReference<String> lastAcceptLanguage = new AtomicReference<>();
    private static volatile int status = 200;

    static {
        try {
            stub = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            stub.createContext("/", ex -> {
                String q = ex.getRequestURI().getQuery();
                lastAcceptLanguage.set(q == null || !q.contains("accept-language=") ? null : q.replaceAll(".*accept-language=([a-z]+).*", "$1"));
                byte[] out = (ex.getRequestURI().getPath().equals("/search") ? searchBody.get() : reverseBody.get()).getBytes(java.nio.charset.StandardCharsets.UTF_8);
                ex.sendResponseHeaders(status, out.length);
                ex.getResponseBody().write(out); ex.close();
            });
            stub.start();
        } catch (Exception e) { throw new ExceptionInInitializerError(e); }
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) { r.add("jolay.geocoding.nominatim-url", () -> "http://127.0.0.1:" + stub.getAddress().getPort()); }

    @AfterAll static void stopStub() { stub.stop(0); }

    @BeforeEach
    void reset() { status = 200; searchBody.set("[]"); reverseBody.set("{\"error\":\"none\"}"); lastAcceptLanguage.set(null); }

    @Test
    void searchUsesNominatimAndForwardsTheUiLanguage() {
        searchBody.set("[{\"place_id\":1,\"osm_type\":\"node\",\"osm_id\":42,\"lat\":\"43.3521\",\"lon\":\"77.0405\",\"display_name\":\"Аэропорт Алматы, Алматы\",\"name\":\"Аэропорт Алматы\"}]");
        Session c = customer();
        Resp r = call(org.springframework.http.HttpMethod.GET, "/api/v1/geo/places?q=airport&lat=43.25&lng=76.95", c.token(), null, Map.of("Accept-Language", "ru-RU,ru;q=0.9"));
        assertEquals(200, r.status(), r.body().toString());
        assertEquals(1, r.body().size());
        assertEquals("Аэропорт Алматы", r.body().get(0).path("name").asText());
        assertEquals("ru", lastAcceptLanguage.get());
    }

    @Test
    void anEmptyAnswerOrAnOutageFallsBackToTheSeededPlaces() {
        Session c = customer();
        Resp empty = get("/api/v1/geo/places?q=Dostyk", c.token());                    // Nominatim knows nothing -> seeded landmarks
        assertEquals(200, empty.status());
        assertTrue(empty.body().size() >= 1, "seeded place expected");
        status = 500;
        Resp down = get("/api/v1/geo/places?q=Dostyk", c.token());
        assertEquals(200, down.status());
        assertTrue(down.body().size() >= 1, "an outage must not break search");
    }

    @Test
    void aPickupWithoutAnAddressGetsTheReverseGeocodedOne() {
        reverseBody.set("{\"place_id\":9,\"display_name\":\"проспект Достык 5, Алматы, Казахстан\"}");
        Session c = customer(); driver("ECONOMY", 43.2340, 76.9570);
        Map<String, Object> body = new java.util.HashMap<>(rideRequest("ECONOMY", "CASH"));
        body.put("pickup", Map.of("point", Map.of("lat", PICKUP[0], "lng", PICKUP[1])));           // no address given
        Resp ride = post("/api/v1/rides", c.token(), body);
        assertEquals(201, ride.status(), ride.body().toString());
        assertEquals("проспект Достык 5, Алматы, Казахстан", ride.s("pickupAddress"));
    }
}
