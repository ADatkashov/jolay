package kz.jolay;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import kz.jolay.common.AppSettings;
import kz.jolay.common.GeoPoint;
import kz.jolay.geography.EstimatedRouteProvider;
import kz.jolay.geography.OsrmRouteProvider;
import kz.jolay.geography.RouteProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.math.BigDecimal;
import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** The OSRM adapter against a local stub that speaks the documented Route-service format; nothing is sent to a real OSRM server. */
class OsrmRouteProviderTest {
    private static final GeoPoint A = new GeoPoint(43.2335, 76.9567), B = new GeoPoint(43.2025, 76.9066);
    private HttpServer server;
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String body = "{\"code\":\"Ok\",\"routes\":[{\"distance\":8123.4,\"duration\":912.6,\"legs\":[]}],\"waypoints\":[]}";
    private volatile long delayMs = 0;

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", ex -> {
            hits.incrementAndGet(); lastPath.set(ex.getRequestURI().toString());
            try { Thread.sleep(delayMs); } catch (InterruptedException ignored) {}
            byte[] out = body.getBytes();
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out); ex.close();
        });
        server.start();
    }

    @AfterEach
    void stop() { server.stop(0); }

    private RouteProvider estimate() {
        AppSettings s = Mockito.mock(AppSettings.class);
        Mockito.when(s.getDecimal("rides.detour_factor")).thenReturn(new BigDecimal("1.35"));
        Mockito.when(s.getDecimal("rides.avg_speed_kmh")).thenReturn(new BigDecimal("30"));
        return new EstimatedRouteProvider(s);
    }
    private OsrmRouteProvider osrm(String url, Duration timeout, int failuresToOpen) {
        return new OsrmRouteProvider(url, timeout, new ObjectMapper(), estimate(), null, failuresToOpen, Duration.ofSeconds(30));
    }
    private String url() { return "http://127.0.0.1:" + server.getAddress().getPort(); }

    @Test
    void usesTheRoadDistanceAndDurationAndSendsLongitudeFirst() {
        var r = osrm(url() + "/", Duration.ofSeconds(2), 3).route(A, B);
        assertEquals("OSRM", r.source());
        assertEquals(8123, r.distanceM());
        assertEquals(913, r.durationS());
        assertTrue(lastPath.get().startsWith("/route/v1/driving/76.956700,43.233500;76.906600,43.202500"), lastPath.get());   // lng,lat order
        assertTrue(lastPath.get().contains("overview=false"));
    }

    @Test
    void anUnroutablePairFallsBackToTheEstimateWithoutOpeningTheBreaker() {
        body = "{\"code\":\"NoRoute\",\"message\":\"Impossible route between points\"}";
        var p = osrm(url(), Duration.ofSeconds(2), 1);
        assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals(2, hits.get(), "NoRoute is an answer, not an outage: OSRM is still asked every time");
    }

    @Test
    void serverErrorsFallBackAndTheBreakerStopsHammeringADeadServer() {
        status = 500; body = "{}";
        var p = osrm(url(), Duration.ofSeconds(2), 3);
        for (int i = 0; i < 3; i++) assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals(3, hits.get());
        for (int i = 0; i < 5; i++) assertEquals("ESTIMATED", p.route(A, B).source());
        assertEquals(3, hits.get(), "the breaker is open: no more calls while it stays open");
    }

    @Test
    void aSlowServerIsCutOffAtTheTimeout() {
        delayMs = 1500;
        var p = osrm(url(), Duration.ofMillis(200), 3);
        long t0 = System.nanoTime();
        assertEquals("ESTIMATED", p.route(A, B).source());
        assertTrue(Duration.ofNanos(System.nanoTime() - t0).toMillis() < 1200, "a slow routing server must not stall ride requests");
    }

    @Test
    void anUnreachableServerAndAMalformedBodyBothFallBack() {
        assertEquals("ESTIMATED", osrm("http://127.0.0.1:1", Duration.ofMillis(300), 3).route(A, B).source());
        body = "<html>not json</html>";
        assertEquals("ESTIMATED", osrm(url(), Duration.ofSeconds(2), 3).route(A, B).source());
    }

    @Test
    void theBreakerCountsOnlyConsecutiveFailures() {
        var p = osrm(url(), Duration.ofSeconds(2), 3);
        status = 500; body = "{}";
        p.route(A, B); p.route(A, B);
        status = 200; body = "{\"code\":\"Ok\",\"routes\":[{\"distance\":1000,\"duration\":100}]}";
        assertEquals("OSRM", p.route(A, B).source());                  // success resets the counter
        status = 500; body = "{}";
        p.route(A, B); p.route(A, B);
        status = 200; body = "{\"code\":\"Ok\",\"routes\":[{\"distance\":1000,\"duration\":100}]}";
        assertEquals("OSRM", p.route(A, B).source(), "two failures after a success must not open the breaker");
    }
}
