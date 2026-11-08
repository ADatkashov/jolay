package kz.jolay.geography;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

/**
 * Address search (2GIS Suggest, {@code /3.0/suggests}) and reverse geocoding ({@code /3.0/items/geocode}) through the 2GIS Places API.
 * Every failure degrades to "no result" (the caller then uses the seeded places) and consecutive failures open a circuit breaker.
 * The API key travels in the query string, so request URLs are never logged.
 * <p>
 * Verified against the public 2GIS docs: the suggests endpoint, its parameters and the {@code meta.code} envelope. NOT yet verified against a live key:
 * the reverse endpoint and the exact {@code point} shape ({@code lat}/{@code lon} is assumed; both are parsed defensively) — check on staging with a demo key.
 */
public class TwoGisGeocoder implements ExternalGeocoder {
    private static final Logger log = LoggerFactory.getLogger(TwoGisGeocoder.class);
    private static final String SUGGEST_TYPES = "building,branch,attraction,station";

    private final String baseUrl, key, regionId;
    private final Duration timeout;
    private final HttpClient http;
    private final ObjectMapper mapper;
    private final MeterRegistry metrics;
    private final SimpleBreaker breaker;

    public TwoGisGeocoder(String baseUrl, String key, String regionId, Duration timeout, ObjectMapper mapper, MeterRegistry metrics, SimpleBreaker breaker) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.key = key; this.regionId = regionId == null ? "" : regionId.trim();
        this.timeout = timeout; this.mapper = mapper; this.metrics = metrics; this.breaker = breaker;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    @Override
    public List<GeoService.Place> search(String query, Double lat, Double lng, int limit, String language) {
        StringBuilder url = new StringBuilder(baseUrl).append("/3.0/suggests?key=").append(enc(key))
                .append("&q=").append(enc(query))
                .append("&fields=").append(enc("items.point,items.address_name,items.full_address_name"))
                .append("&type=").append(enc(SUGGEST_TYPES))
                .append("&locale=").append(locale(language))
                .append("&page_size=").append(Math.max(1, Math.min(limit, 20)));
        if (!regionId.isEmpty()) url.append("&region_id=").append(enc(regionId));
        if (lat != null && lng != null) url.append(String.format(Locale.ROOT, "&location=%.6f,%.6f", lng, lat));   // ranking bias only
        JsonNode items = get(url.toString());
        List<GeoService.Place> out = new ArrayList<>();
        if (items == null) return out;
        for (JsonNode n : items) {
            double[] p = point(n.path("point"));
            if (p == null) continue;
            String name = n.path("name").asText("").trim();
            String addr = n.path("full_address_name").asText("").trim();
            if (addr.isEmpty()) addr = n.path("address_name").asText("").trim();
            if (name.isEmpty()) name = addr;
            if (name.isEmpty()) continue;
            String display = addr.isEmpty() || addr.equals(name) ? name : name.contains(addr) ? name : name + ", " + addr;
            String stable = "2gis:" + n.path("id").asText(name + p[0] + p[1]);
            out.add(new GeoService.Place(UUID.nameUUIDFromBytes(stable.getBytes(StandardCharsets.UTF_8)), name, display, p[0], p[1]));
        }
        return out;
    }

    @Override
    public Optional<String> reverse(double lat, double lng, String language) {
        String url = String.format(Locale.ROOT, "%s/3.0/items/geocode?key=%s&lon=%.6f&lat=%.6f&fields=%s&locale=%s", baseUrl, enc(key), lng, lat,
                enc("items.point,items.address_name,items.full_name"), locale(language));
        JsonNode items = get(url);
        if (items == null) return Optional.empty();
        for (JsonNode n : items) {
            String text = n.path("full_name").asText("").trim();
            if (text.isEmpty()) text = n.path("address_name").asText("").trim();
            if (text.isEmpty()) text = n.path("name").asText("").trim();
            if (!text.isEmpty()) return Optional.of(text);
        }
        return Optional.empty();
    }

    /** {@code [lat, lng]} from a 2GIS point object, or null. */
    private static double[] point(JsonNode p) {
        if (p == null || !p.hasNonNull("lat") || !p.hasNonNull("lon")) return null;
        try {
            double lat = Double.parseDouble(p.path("lat").asText()), lon = Double.parseDouble(p.path("lon").asText());
            return Double.isFinite(lat) && Double.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 ? new double[]{lat, lon} : null;
        } catch (NumberFormatException e) { return null; }
    }

    /** 2GIS has no en_KZ; English UI falls back to Russian names. */
    private static String locale(String language) { return "kk".equals(language) ? "kk_KZ" : "ru_KZ"; }

    /** One GET; returns {@code result.items} (possibly empty), or null on any failure. "No results" (meta.code 404) is a normal empty answer, not a failure. */
    private JsonNode get(String url) {
        if (breaker.isOpen()) { count("skipped"); return null; }
        try {
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(url)).timeout(timeout).header("Accept", "application/json").GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            JsonNode body = res.body() == null || res.body().isBlank() ? null : mapper.readTree(res.body());
            int code = body != null && body.path("meta").has("code") ? body.path("meta").path("code").asInt() : res.statusCode();
            if (code == 404) { breaker.success(); count("ok"); return mapper.createArrayNode(); }
            if (res.statusCode() == 200 && code == 200 && body != null && body.path("result").path("items").isArray()) {
                breaker.success(); count("ok"); return body.path("result").path("items");
            }
            failed("code_" + code);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); failed("interrupted");
        } catch (Exception e) {
            failed(e.getClass().getSimpleName());      // never e.getMessage(): it can contain the URL and therefore the key
        }
        return null;
    }

    private void failed(String why) {
        count("error");
        if (breaker.failure()) log.warn("2GIS failed repeatedly (last: {}); using the seeded places for a while", why);
        else log.warn("2GIS request failed ({}); using the seeded places for this request", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.geocoding.twogis", "outcome", outcome).increment(); }
    private static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
}
