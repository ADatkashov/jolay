package kz.jolay;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import kz.jolay.common.GeoPoint;
import kz.jolay.common.SimpleBreaker;
import kz.jolay.geography.RouteProvider;
import kz.jolay.geography.TwoGisRouteProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** The 2GIS routing adapter against a local stub speaking the documented /routing/7.0.0/global format. Nothing is sent to 2GIS. */
class TwoGisRouteProviderTest {
    private HttpServer server;
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicReference<String> lastUri = new AtomicReference<>(), lastBody = new AtomicReference<>(), lastMethod = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String body = "{}";

    private final RouteProvider estimate = (a, b) -> new RouteProvider.RouteInfo(1234, 321, "ESTIMATED");
    private static final GeoPoint A = new GeoPoint(43.2335, 76.9567), B = new GeoPoint(43.2025, 76.9066);

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", ex -> {
            hits.incrementAndGet(); lastUri.set(ex.getRequestURI().toString()); lastMethod.set(ex.getRequestMethod());
            lastBody.set(new String(ex.getRequestBody().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
            byte[] out = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out); ex.close();
        });
        server.start();
    }
    @AfterEach void stop() { server.stop(0); }

    private TwoGisRouteProvider provider(int failuresToOpen) {
        return new TwoGisRouteProvider("http://127.0.0.1:" + server.getAddress().getPort() + "/", "SECRET", Duration.ofSeconds(2), new ObjectMapper(), estimate, null,
                new SimpleBreaker(failuresToOpen, Duration.ofSeconds(30)));
    }

    @Test
    void usesTheFirstRouteAndSendsLonLatStops() throws Exception {
        body = "{\"status\":\"OK\",\"type\":\"result\",\"result\":[{\"total_distance\":5904,\"total_duration\":1099.4},{\"total_distance\":9999,\"total_duration\":9999}]}";
        var r = provider(3).route(A, B);
        assertEquals(5904, r.distanceM());
        assertEquals(1099, r.durationS());
        assertEquals("2GIS", r.source());
        assertEquals("POST", lastMethod.get());
        assertEquals("/routing/7.0.0/global?key=SECRET", lastUri.get());
        var json = new ObjectMapper().readTree(lastBody.get());
        assertEquals("driving", json.path("transport").asText());
        assertEquals(76.9567, json.path("points").path(0).path("lon").asDouble(), 1e-9);
        assertEquals(43.2335, json.path("points").path(0).path("lat").asDouble(), 1e-9);
        assertEquals("stop", json.path("points").path(1).path("type").asText());
    }

    @Test
    void aNoRouteAnswerFallsBackToTheEstimateWithoutOpeningTheBreaker() {
        status = 400; body = "{\"status\":\"FAIL\"}";
        var p = provider(2);
        for (int i = 0; i < 4; i++) assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals(4, hits.get(), "a 4xx 'no route' is not an outage, every call still reaches the server");
    }

    @Test
    void outagesFallBackAndTheBreakerStopsHammering() {
        status = 500; body = "oops";
        var p = provider(3);
        for (int i = 0; i < 3; i++) assertEquals(1234, p.route(A, B).distanceM());
        for (int i = 0; i < 3; i++) assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals(3, hits.get(), "the breaker is open: no more calls");
        status = 200; body = "<html>nope</html>";
        assertEquals("ESTIMATED", provider(3).route(A, B).source());
        assertEquals("ESTIMATED", new TwoGisRouteProvider("http://127.0.0.1:1", "k", Duration.ofMillis(300), new ObjectMapper(), estimate, null, new SimpleBreaker(3, Duration.ofSeconds(30))).route(A, B).source());
    }
}
