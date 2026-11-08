package kz.jolay;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import kz.jolay.common.SimpleBreaker;
import kz.jolay.geography.TwoGisGeocoder;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** The 2GIS adapter against a local stub that speaks the documented /3.0/suggests envelope. Nothing is sent to 2GIS. */
class TwoGisGeocoderTest {
    private HttpServer server;
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicReference<String> lastUri = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String body = "{}";

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", ex -> {
            hits.incrementAndGet(); lastUri.set(ex.getRequestURI().toString());
            byte[] out = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out); ex.close();
        });
        server.start();
    }
    @AfterEach void stop() { server.stop(0); }

    private TwoGisGeocoder geocoder(int failuresToOpen, String regionId) {
        return new TwoGisGeocoder("http://127.0.0.1:" + server.getAddress().getPort() + "/", "SECRET", regionId, Duration.ofSeconds(2), new ObjectMapper(), null,
                new SimpleBreaker(failuresToOpen, Duration.ofSeconds(30)));
    }

    private static final String SUGGEST = """
            {"meta":{"api_version":"3.0","code":200},"result":{"total":3,"items":[
              {"id":"70000001","name":"Достык Плаза","address_name":"проспект Достык, 111","full_address_name":"Алматы, проспект Достык, 111","type":"branch","point":{"lat":43.2335,"lon":76.9567}},
              {"id":"70000002","name":"проспект Абая, 10","address_name":"проспект Абая, 10","type":"building","point":{"lat":43.2400,"lon":76.9400}},
              {"id":"70000003","name":"No point","address_name":"x","type":"building"}]}}""";

    @Test
    void searchMapsItemsSkipsOnesWithoutAPointAndBuildsAStableId() {
        body = SUGGEST;
        var g = geocoder(3, "");
        var places = g.search("Достык", 43.25, 76.95, 5, "ru");
        assertEquals(2, places.size());
        assertEquals("Достык Плаза", places.get(0).name());
        assertEquals("Достык Плаза, Алматы, проспект Достык, 111", places.get(0).address());
        assertEquals(43.2335, places.get(0).lat(), 1e-9);
        assertEquals(76.9567, places.get(0).lng(), 1e-9);
        assertEquals("проспект Абая, 10", places.get(1).address(), "name equal to the address is not repeated");
        assertEquals(places.get(0).id(), g.search("Достык", 43.25, 76.95, 5, "ru").get(0).id());

        String uri = lastUri.get();
        assertTrue(uri.startsWith("/3.0/suggests?key=SECRET&q=%D0%94"), uri);
        assertTrue(uri.contains("fields=items.point") && uri.contains("locale=ru_KZ") && uri.contains("page_size=5"), uri);
        assertTrue(uri.contains("location=76.950000,43.250000"), "location is lng,lat: " + uri);
        assertFalse(uri.contains("region_id"));
    }

    @Test
    void kazakhAndEnglishLocalesAndRegionIdAreForwarded() {
        body = SUGGEST;
        geocoder(3, "67").search("a", null, null, 50, "kk");
        assertTrue(lastUri.get().contains("locale=kk_KZ") && lastUri.get().contains("region_id=67") && lastUri.get().contains("page_size=20"), lastUri.get());
        assertFalse(lastUri.get().contains("location="));
        geocoder(3, "").search("a", null, null, 5, "en");
        assertTrue(lastUri.get().contains("locale=ru_KZ"), "2GIS has no en_KZ: " + lastUri.get());
    }

    @Test
    void noResultsIsANormalEmptyAnswerAndDoesNotOpenTheBreaker() {
        body = "{\"meta\":{\"code\":404,\"error\":{\"message\":\"Results not found\",\"type\":\"itemNotFound\"}}}";
        var g = geocoder(2, "");
        for (int i = 0; i < 5; i++) assertTrue(g.search("zzz", null, null, 5, null).isEmpty());
        assertEquals(5, hits.get(), "404 is not a failure, so every call still reaches the server");
    }

    @Test
    void errorsDegradeToEmptyAndTheBreakerStopsHammering() {
        body = "{\"meta\":{\"code\":403,\"error\":{\"message\":\"Access denied\"}}}";
        var g = geocoder(3, "");
        for (int i = 0; i < 3; i++) assertTrue(g.search("x", null, null, 5, null).isEmpty());
        for (int i = 0; i < 3; i++) assertTrue(g.search("x", null, null, 5, null).isEmpty());
        assertTrue(g.reverse(1, 1, null).isEmpty());
        assertEquals(3, hits.get());
        status = 200; body = "<html>nope</html>";
        assertTrue(geocoder(3, "").search("x", null, null, 5, null).isEmpty());
    }

    @Test
    void reverseUsesTheFirstItemText() {
        body = "{\"meta\":{\"code\":200},\"result\":{\"items\":[{\"id\":\"1\",\"full_name\":\"Алматы, проспект Достык, 5\",\"address_name\":\"проспект Достык, 5\"}]}}";
        var g = geocoder(3, "");
        assertEquals("Алматы, проспект Достык, 5", g.reverse(43.2335, 76.9567, "ru").orElseThrow());
        assertTrue(lastUri.get().startsWith("/3.0/items/geocode?key=SECRET&lon=76.956700&lat=43.233500"), lastUri.get());
    }
}
