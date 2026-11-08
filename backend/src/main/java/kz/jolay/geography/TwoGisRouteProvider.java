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
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Road routing through the 2GIS Routing API ({@code POST {base}/routing/7.0.0/global?key=...}, JSON body with two {@code stop} points, car transport).
 * The distance (m) and duration (s) are read from {@code result[0].total_distance / total_duration}; the road geometry from the WKT
 * {@code maneuvers[].outcoming_path.geometry[].selection} and the steps from {@code maneuvers[].comment / icon}.
 * A routing outage must never stop riders from ordering: on any error, "no route" answer or while the breaker is open, the great-circle estimate is
 * returned, flagged {@code ESTIMATED}. The key is in the URL, so URLs are never logged.
 * Geometry and step parsing is defensive (anything missing is skipped) because the field layout was written from the public docs and not yet checked against a live key.
 */
public class TwoGisRouteProvider implements RouteProvider {
    private static final Logger log = LoggerFactory.getLogger(TwoGisRouteProvider.class);
    private static final Pattern PAIR = Pattern.compile("(-?\\d+(?:\\.\\d+)?)\\s+(-?\\d+(?:\\.\\d+)?)");
    static final int MAX_POINTS = 500, MAX_STEPS = 80;

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
        JsonNode r = request(from, to);
        return r == null ? fallback.route(from, to) : info(r);
    }

    @Override
    public RouteDetail detail(GeoPoint from, GeoPoint to) {
        JsonNode r = request(from, to);
        if (r == null) return fallback.detail(from, to);
        RouteInfo i = info(r);
        List<double[]> line = new ArrayList<>();
        List<Step> steps = new ArrayList<>();
        for (JsonNode m : r.path("maneuvers")) {
            List<double[]> seg = new ArrayList<>();
            for (JsonNode g : m.path("outcoming_path").path("geometry")) seg.addAll(parseWkt(g.path("selection").asText("")));
            line.addAll(seg);
            String text = m.path("comment").asText("").trim(), icon = m.path("icon").asText("").trim();
            if ((!text.isEmpty() || !icon.isEmpty()) && steps.size() < MAX_STEPS)
                steps.add(new Step(text, icon, (int) Math.round(m.path("outcoming_path").path("distance").asDouble(0)),
                        seg.isEmpty() ? null : seg.get(0)[0], seg.isEmpty() ? null : seg.get(0)[1]));
        }
        if (line.size() < 2) { line = List.of(new double[]{from.lat(), from.lng()}, new double[]{to.lat(), to.lng()}); }
        return new RouteDetail(i.distanceM(), i.durationS(), i.source(), decimate(line, MAX_POINTS), steps);
    }

    private static RouteInfo info(JsonNode r) {
        return new RouteInfo((int) Math.round(r.path("total_distance").asDouble()), (int) Math.round(r.path("total_duration").asDouble()), "2GIS");
    }

    /** {@code [lat, lng]} pairs from a WKT string such as {@code LINESTRING(76.9 43.2, 76.91 43.21)} (WKT order is lon lat). */
    static List<double[]> parseWkt(String wkt) {
        List<double[]> out = new ArrayList<>();
        Matcher m = PAIR.matcher(wkt == null ? "" : wkt);
        while (m.find()) {
            double lon = Double.parseDouble(m.group(1)), lat = Double.parseDouble(m.group(2));
            if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) out.add(new double[]{Math.round(lat * 1e5) / 1e5, Math.round(lon * 1e5) / 1e5});
        }
        return out;
    }

    /** Keeps at most {@code max} points, always including the first and the last. */
    static List<double[]> decimate(List<double[]> in, int max) {
        if (in.size() <= max) return in;
        List<double[]> out = new ArrayList<>(max);
        double step = (in.size() - 1) / (double) (max - 1);
        for (int i = 0; i < max - 1; i++) out.add(in.get((int) Math.round(i * step)));
        out.add(in.get(in.size() - 1));
        return out;
    }

    /** One POST; returns {@code result[0]} or null when there is no usable route (the caller then falls back to the estimate). */
    private JsonNode request(GeoPoint from, GeoPoint to) {
        if (breaker.isOpen()) { count("skipped"); return null; }
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
                if (route.has("total_distance") && route.has("total_duration")) { breaker.success(); count("ok"); return route; }
            }
            // 2GIS answered but has no route for these points (or this demo key's limit): not an outage, the breaker is left alone
            if (res.statusCode() < 500 && res.statusCode() != 429 && res.statusCode() != 403 && res.statusCode() != 401) {
                log.info("2GIS routing returned no route (HTTP {}); using the estimate", res.statusCode());
                count("no_route");
                return null;
            }
            failed("http_" + res.statusCode());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); failed("interrupted");
        } catch (Exception e) {
            failed(e.getClass().getSimpleName());
        }
        return null;
    }

    private void failed(String why) {
        count("error");
        if (breaker.failure()) log.warn("2GIS routing failed repeatedly (last: {}); using estimated routes for a while", why);
        else log.warn("2GIS routing request failed ({}); using the estimate for this request", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.routing.twogis", "outcome", outcome).increment(); }
}
