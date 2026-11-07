package kz.jolay.geography;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.GeoPoint;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Road routing through an OSRM server (the open-source router; it can be self-hosted on OpenStreetMap data, so no map licence is needed for routing).
 * <p>
 * Requests use the documented Route service: {@code GET {base}/route/v1/driving/{lng},{lat};{lng},{lat}?overview=false}.
 * The fallback is deliberate: a routing outage must never stop riders from ordering, so on any error (timeout, HTTP error, {@code code != Ok}, no route)
 * the great-circle estimate is returned, flagged {@code ESTIMATED}. After {@code failuresToOpen} consecutive failures the provider stops calling OSRM for
 * {@code openFor} (a circuit breaker) so that every request does not wait for the timeout.
 */
public class OsrmRouteProvider implements RouteProvider {
    private static final Logger log = LoggerFactory.getLogger(OsrmRouteProvider.class);

    private final String baseUrl;
    private final HttpClient http;
    private final Duration timeout;
    private final ObjectMapper mapper;
    private final RouteProvider fallback;
    private final MeterRegistry metrics;
    private final int failuresToOpen;
    private final Duration openFor;
    private final AtomicInteger consecutiveFailures = new AtomicInteger();
    private final AtomicLong openUntilMillis = new AtomicLong();

    public OsrmRouteProvider(String baseUrl, Duration timeout, ObjectMapper mapper, RouteProvider fallback, MeterRegistry metrics, int failuresToOpen, Duration openFor) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.timeout = timeout; this.mapper = mapper; this.fallback = fallback; this.metrics = metrics; this.failuresToOpen = failuresToOpen; this.openFor = openFor;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    @Override
    public RouteInfo route(GeoPoint from, GeoPoint to) {
        if (System.currentTimeMillis() < openUntilMillis.get()) { count("skipped"); return fallback.route(from, to); }
        try {
            String url = String.format(Locale.ROOT, "%s/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=false&alternatives=false&steps=false", baseUrl, from.lng(), from.lat(), to.lng(), to.lat());
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(url)).timeout(timeout).GET().build(), HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 200) {
                JsonNode body = mapper.readTree(res.body());
                JsonNode route = body.path("routes").path(0);
                if ("Ok".equals(body.path("code").asText()) && route.has("distance") && route.has("duration")) {
                    consecutiveFailures.set(0);
                    count("ok");
                    return new RouteInfo((int) Math.round(route.path("distance").asDouble()), (int) Math.round(route.path("duration").asDouble()), "OSRM");
                }
                // OSRM answered but found no route (e.g. NoRoute): not an outage, so the breaker is left alone
                log.info("OSRM returned code={} for a route request; using the estimate", body.path("code").asText());
                count("no_route");
                return fallback.route(from, to);
            }
            failed("http_" + res.statusCode());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            failed("interrupted");
        } catch (Exception e) {
            failed(e.getClass().getSimpleName());
        }
        return fallback.route(from, to);
    }

    private void failed(String why) {
        count("error");
        int n = consecutiveFailures.incrementAndGet();
        if (n >= failuresToOpen) {
            openUntilMillis.set(System.currentTimeMillis() + openFor.toMillis());
            consecutiveFailures.set(0);
            log.warn("OSRM failed {} times in a row (last: {}); using estimated routes for {}", n, why, openFor);
        } else log.warn("OSRM request failed ({}); using the estimate for this request", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.routing.osrm", "outcome", outcome).increment(); }
}
