package kz.jolay.geography;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.GeoPoint;
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

/**
 * Road routing through the 2GIS Routing API ({@code POST {base}/routing/7.0.0/global?key=...}, JSON body with two {@code stop} points, car transport).
 * The distance (m) and duration (s) are read from {@code result[0].total_distance / total_duration}.
 * A routing outage must never stop riders from ordering: on any error, "no route" answer or while the breaker is open, the great-circle estimate is
 * returned, flagged {@code ESTIMATED}. The key is in the URL, so URLs are never logged.
 */
public class TwoGisRouteProvider implements RouteProvider {
    private static final Logger log = LoggerFactory.getLogger(TwoGisRouteProvider.class);

    private final String baseUrl, key;
    private final Duration timeout;
    private final HttpClient http;
    private final ObjectMapper mapper;
    private final RouteProvider fallback;
    private final MeterRegistry metrics;
    private final SimpleBreaker breaker;

    public TwoGisRouteProvider(String baseUrl, String key, Duration timeout, ObjectMapper mapper, RouteProvider fallback, MeterRegistry metrics, SimpleBreaker breaker) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.key = key; this.timeout = timeout; this.mapper = mapper; this.fallback = fallback; this.metrics = metrics; this.breaker = breaker;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    @Override
    public RouteInfo route(GeoPoint from, GeoPoint to) {
        if (breaker.isOpen()) { count("skipped"); return fallback.route(from, to); }
        try {
            ObjectNode body = mapper.createObjectNode();
            var points = body.putArray("points");
            points.addObject().put("type", "stop").put("lon", from.lng()).put("lat", from.lat());
            points.addObject().put("type", "stop").put("lon", to.lng()).put("lat", to.lat());
            body.put("transport", "driving").put("route_mode", "fastest").put("traffic_mode", "jam").put("locale", "ru");
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(baseUrl + "/routing/7.0.0/global?key=" + URLEncoder.encode(key, StandardCharsets.UTF_8)))
                    .timeout(timeout).header("Content-Type", "application/json").header("Accept", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
            JsonNode json = res.body() == null || res.body().isBlank() ? null : mapper.readTree(res.body());
            if (res.statusCode() == 200 && json != null && "OK".equalsIgnoreCase(json.path("status").asText())) {
                JsonNode route = json.path("result").path(0);
                if (route.has("total_distance") && route.has("total_duration")) {
                    breaker.success(); count("ok");
                    return new RouteInfo((int) Math.round(route.path("total_distance").asDouble()), (int) Math.round(route.path("total_duration").asDouble()), "2GIS");
                }
            }
            // 2GIS answered but has no route for these points (or this demo key's limit): not an outage, the breaker is left alone
            if (res.statusCode() < 500 && res.statusCode() != 429 && res.statusCode() != 403 && res.statusCode() != 401) {
                log.info("2GIS routing returned no route (HTTP {}); using the estimate", res.statusCode());
                count("no_route");
                return fallback.route(from, to);
            }
            failed("http_" + res.statusCode());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); failed("interrupted");
        } catch (Exception e) {
            failed(e.getClass().getSimpleName());
        }
        return fallback.route(from, to);
    }

    private void failed(String why) {
        count("error");
        if (breaker.failure()) log.warn("2GIS routing failed repeatedly (last: {}); using estimated routes for a while", why);
        else log.warn("2GIS routing request failed ({}); using the estimate for this request", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.routing.twogis", "outcome", outcome).increment(); }
}
