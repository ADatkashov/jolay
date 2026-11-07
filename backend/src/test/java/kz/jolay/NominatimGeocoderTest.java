package kz.jolay;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import kz.jolay.common.SimpleBreaker;
import kz.jolay.geography.NominatimGeocoder;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** The Nominatim adapter against a local stub that speaks the documented /search and /reverse format (jsonv2). Nothing is sent to a real server. */
class NominatimGeocoderTest {
    private HttpServer server;
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicReference<String> lastUri = new AtomicReference<>();
    private final AtomicReference<String> lastUserAgent = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String body = "[]";
    private volatile long delayMs = 0;

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", ex -> {
            hits.incrementAndGet(); lastUri.set(ex.getRequestURI().toString()); lastUserAgent.set(ex.getRequestHeaders().getFirst("User-Agent"));
            try { Thread.sleep(delayMs); } catch (InterruptedException ignored) {}
            byte[] out = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out); ex.close();
        });
        server.start();
    }
    @AfterEach void stop() { server.stop(0); }

    private NominatimGeocoder geocoder(String url, Duration timeout, int failuresToOpen) {
        return new NominatimGeocoder(url, "kz", "JOLAY-test", timeout, new ObjectMapper(), null, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(30)));
    }
    private String url() { return "http://127.0.0.1:" + server.getAddress().getPort(); }

    private static final String HITS = """
            [{"place_id":101,"osm_type":"node","osm_id":555,"lat":"43.2335","lon":"76.9567","display_name":"Dostyk Plaza, проспект Достык, Алматы, Казахстан","name":"Dostyk Plaza"},
             {"place_id":102,"osm_type":"way","osm_id":777,"lat":"43.2025","lon":"76.9066","display_name":"Мега Алма-Ата, улица Розыбакиева, Алматы","name":""},
             {"place_id":103,"osm_type":"node","osm_id":888,"lat":"bad","lon":"76.9","display_name":"Broken","name":"Broken"}]""";

    @Test
    void searchMapsHitsSkipsBrokenOnesAndBuildsAStableId() {
        body = HITS;
        var g = geocoder(url() + "/", Duration.ofSeconds(2), 3);
        var places = g.search("Достык плаза", 43.25, 76.95, 5, "ru");
        assertEquals(2, places.size(), "the hit with unparseable coordinates is dropped");
        assertEquals("Dostyk Plaza", places.get(0).name());
        assertEquals("Dostyk Plaza, проспект Достык, Алматы, Казахстан", places.get(0).address());
        assertEquals(43.2335, places.get(0).lat(), 1e-9);
        assertEquals(76.9567, places.get(0).lng(), 1e-9);
        assertEquals("Мега Алма-Ата", places.get(1).name(), "an empty name falls back to the first part of display_name");
        assertEquals(places.get(0).id(), g.search("Достык плаза", 43.25, 76.95, 5, "ru").get(0).id(), "the same OSM object always gets the same id");
        assertNotEquals(places.get(0).id(), places.get(1).id());

        String uri = lastUri.get();
        assertTrue(uri.startsWith("/search?format=jsonv2"), uri);
        assertTrue(uri.contains("q=%D0%94%D0%BE%D1%81%D1%82%D1%8B%D0%BA"), "query is URL-encoded UTF-8: " + uri);
        assertTrue(uri.contains("countrycodes=kz") && uri.contains("accept-language=ru") && uri.contains("limit=5"), uri);
        assertTrue(uri.contains("viewbox=76.55000,43.55000,77.35000,42.95000") && uri.contains("bounded=0"), "ranking is biased towards the rider, not restricted: " + uri);
        assertEquals("JOLAY-test", lastUserAgent.get(), "Nominatim requires an identifying User-Agent");
    }

    @Test
    void searchWithoutAPositionHasNoViewbox() {
        body = "[]";
        geocoder(url(), Duration.ofSeconds(2), 3).search("abc", null, null, 50, null);
        assertFalse(lastUri.get().contains("viewbox"));
        assertTrue(lastUri.get().contains("limit=20"), "the limit is capped");
        assertFalse(lastUri.get().contains("accept-language"));
    }

    @Test
    void reverseReturnsTheDisplayNameAndTreatsAnErrorAnswerAsNothing() {
        body = "{\"place_id\":1,\"display_name\":\"проспект Достык 5, Алматы\"}";
        var g = geocoder(url(), Duration.ofSeconds(2), 3);
        assertEquals("проспект Достык 5, Алматы", g.reverse(43.2335, 76.9567, "ru").orElseThrow());
        assertTrue(lastUri.get().startsWith("/reverse?format=jsonv2&zoom=18&lat=43.233500&lon=76.956700"), lastUri.get());
        body = "{\"error\":\"Unable to geocode\"}";
        assertTrue(g.reverse(0, 0, null).isEmpty());
    }

    @Test
    void failuresDegradeToEmptyResultsAndTheBreakerStopsHammeringADeadServer() {
        status = 500; body = "oops";
        var g = geocoder(url(), Duration.ofSeconds(2), 3);
        for (int i = 0; i < 3; i++) assertTrue(g.search("x", null, null, 5, null).isEmpty());
        assertEquals(3, hits.get());
        for (int i = 0; i < 4; i++) assertTrue(g.search("x", null, null, 5, null).isEmpty());
        assertTrue(g.reverse(1, 1, null).isEmpty());
        assertEquals(3, hits.get(), "the breaker is open: no more calls while it stays open");
    }

    @Test
    void slowUnreachableAndMalformedServersAllGiveNothingQuickly() {
        delayMs = 1500;
        long t0 = System.nanoTime();
        assertTrue(geocoder(url(), Duration.ofMillis(200), 3).search("x", null, null, 5, null).isEmpty());
        assertTrue(Duration.ofNanos(System.nanoTime() - t0).toMillis() < 1200, "a slow geocoder must not stall the app");
        delayMs = 0;
        assertTrue(geocoder("http://127.0.0.1:1", Duration.ofMillis(300), 3).search("x", null, null, 5, null).isEmpty());
        body = "<html>nope</html>"; status = 200;
        assertTrue(geocoder(url(), Duration.ofSeconds(2), 3).search("x", null, null, 5, null).isEmpty());
    }
}
