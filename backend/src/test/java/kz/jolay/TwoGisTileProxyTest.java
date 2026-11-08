package kz.jolay;

import com.sun.net.httpserver.HttpServer;
import kz.jolay.common.SimpleBreaker;
import kz.jolay.geography.TwoGisTileProxy;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** The 2GIS tile proxy against a local stub of the raster tile endpoint. Nothing is sent to 2GIS. */
class TwoGisTileProxyTest {
    private HttpServer server;
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicReference<String> lastUri = new AtomicReference<>();
    private volatile int status = 200;
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 1, 2, 3};

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", ex -> {
            hits.incrementAndGet(); lastUri.set(ex.getRequestURI().toString());
            byte[] out = status == 200 ? PNG : new byte[0];
            ex.sendResponseHeaders(status, status == 200 ? out.length : -1);
            if (status == 200) ex.getResponseBody().write(out);
            ex.close();
        });
        server.start();
    }
    @AfterEach void stop() { server.stop(0); }

    private TwoGisTileProxy proxy(int cache, int failuresToOpen) {
        return new TwoGisTileProxy("http://127.0.0.1:" + server.getAddress().getPort(), "online_hd", "SECRET", Duration.ofSeconds(2), cache, null, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(30)));
    }

    @Test
    void coordinatesAreValidated() {
        assertTrue(TwoGisTileProxy.valid(0, 0, 0));
        assertTrue(TwoGisTileProxy.valid(12, 2900, 1300));
        assertFalse(TwoGisTileProxy.valid(0, 1, 0), "only one tile at zoom 0");
        assertFalse(TwoGisTileProxy.valid(3, 8, 0));
        assertFalse(TwoGisTileProxy.valid(3, -1, 0));
        assertFalse(TwoGisTileProxy.valid(20, 0, 0), "above the maximum zoom");
        assertFalse(TwoGisTileProxy.valid(-1, 0, 0));
    }

    @Test
    void fetchesWithTheKeyAndServesRepeatsFromTheCache() {
        var p = proxy(10, 3);
        assertArrayEquals(PNG, p.tile(16, 47851, 20734).orElseThrow());
        assertEquals("/v2/tiles/online_hd/16/47851/20734.png?key=SECRET", lastUri.get());
        assertArrayEquals(PNG, p.tile(16, 47851, 20734).orElseThrow());
        assertEquals(1, hits.get(), "the second request is served from memory");
    }

    @Test
    void theCacheIsBounded() {
        var p = proxy(2, 3);
        p.tile(5, 1, 1); p.tile(5, 2, 2); p.tile(5, 3, 3);
        assertEquals(3, hits.get());
        p.tile(5, 1, 1);
        assertEquals(4, hits.get(), "the oldest tile was evicted");
    }

    @Test
    void aMissingTileIsNotAnOutageButErrorsOpenTheBreaker() {
        status = 404;
        var p = proxy(10, 2);
        for (int i = 0; i < 4; i++) assertTrue(p.tile(1, 0, i % 2).isEmpty());
        assertEquals(4, hits.get(), "404 does not open the breaker");
        status = 500;
        for (int i = 0; i < 2; i++) assertTrue(p.tile(2, 0, i).isEmpty());
        for (int i = 0; i < 3; i++) assertTrue(p.tile(3, 0, i).isEmpty());
        assertEquals(6, hits.get(), "after two failures the breaker is open");
    }
}
