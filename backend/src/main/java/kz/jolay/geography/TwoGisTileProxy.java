package kz.jolay.geography;

import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.SimpleBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Fetches 2GIS raster tiles ({@code https://tile{n}.maps.2gis.com/v2/tiles/{tileset}/{z}/{x}/{y}.png?key=...}) on behalf of the apps, so the 2GIS key stays
 * on the server and never ships inside an APK or a web bundle. A small in-memory LRU absorbs repeated tiles (panning, several riders in one city).
 * Never throws: an unavailable upstream yields {@link Optional#empty()} and the circuit breaker stops hammering a dead service.
 */
public class TwoGisTileProxy {
    private static final Logger log = LoggerFactory.getLogger(TwoGisTileProxy.class);
    public static final int MAX_ZOOM = 19;

    private final String hostPattern, tileset, key;
    private final Duration timeout;
    private final HttpClient http;
    private final MeterRegistry metrics;
    private final SimpleBreaker breaker;
    private final Map<String, byte[]> cache;
    private final AtomicInteger host = new AtomicInteger();

    /** @param hostPattern upstream base with {@code {n}} replaced by 0..4, e.g. {@code https://tile{n}.maps.2gis.com} */
    public TwoGisTileProxy(String hostPattern, String tileset, String key, Duration timeout, int cacheTiles, MeterRegistry metrics, SimpleBreaker breaker) {
        this.hostPattern = hostPattern.endsWith("/") ? hostPattern.substring(0, hostPattern.length() - 1) : hostPattern;
        this.tileset = tileset; this.key = key; this.timeout = timeout; this.metrics = metrics; this.breaker = breaker;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
        this.cache = java.util.Collections.synchronizedMap(new LinkedHashMap<>(256, 0.75f, true) {
            @Override protected boolean removeEldestEntry(Map.Entry<String, byte[]> e) { return size() > Math.max(1, cacheTiles); }
        });
    }

    /** True when {@code z/x/y} is a valid slippy-map tile coordinate that this proxy is willing to fetch. */
    public static boolean valid(int z, int x, int y) {
        if (z < 0 || z > MAX_ZOOM) return false;
        long n = 1L << z;
        return x >= 0 && x < n && y >= 0 && y < n;
    }

    /** PNG bytes of the tile, or empty when it cannot be provided. Callers must check {@link #valid} first. */
    public Optional<byte[]> tile(int z, int x, int y) {
        String id = z + "/" + x + "/" + y;
        byte[] hit = cache.get(id);
        if (hit != null) { count("cache_hit"); return Optional.of(hit); }
        if (breaker.isOpen()) { count("skipped"); return Optional.empty(); }
        try {
            String base = hostPattern.replace("{n}", String.valueOf(Math.floorMod(host.getAndIncrement(), 5)));
            URI uri = URI.create(base + "/v2/tiles/" + tileset + "/" + id + ".png?key=" + URLEncoder.encode(key, StandardCharsets.UTF_8));
            HttpResponse<byte[]> res = http.send(HttpRequest.newBuilder(uri).timeout(timeout).header("Accept", "image/png").GET().build(), HttpResponse.BodyHandlers.ofByteArray());
            if (res.statusCode() == 200 && res.body().length > 0) { breaker.success(); count("ok"); cache.put(id, res.body()); return Optional.of(res.body()); }
            if (res.statusCode() == 404) { breaker.success(); count("not_found"); return Optional.empty(); }   // an empty (e.g. open-sea) tile is not an outage
            failed("http_" + res.statusCode());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); failed("interrupted");
        } catch (Exception e) {
            failed(e.getClass().getSimpleName());     // never e.getMessage(): it can contain the URL and therefore the key
        }
        return Optional.empty();
    }

    private void failed(String why) {
        count("error");
        if (breaker.failure()) log.warn("2GIS tiles failed repeatedly (last: {}); pausing tile requests for a while", why);
        else log.warn("2GIS tile request failed ({})", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.maps.tiles", "outcome", outcome).increment(); }
}
