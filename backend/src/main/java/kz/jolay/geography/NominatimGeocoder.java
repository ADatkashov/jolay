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
 * Address search and reverse geocoding through a Nominatim server (open source, self-hostable on OpenStreetMap data).
 * Uses the documented endpoints {@code /search} and {@code /reverse} with {@code format=jsonv2}. Run your OWN instance: the public
 * nominatim.openstreetmap.org usage policy forbids heavy use and autocomplete. Every failure degrades to "no result" (the caller then uses the seeded places),
 * and consecutive failures open a circuit breaker so a dead server does not slow down every keystroke.
 */
public class NominatimGeocoder implements ExternalGeocoder {
    private static final Logger log = LoggerFactory.getLogger(NominatimGeocoder.class);

    private final String baseUrl, countryCodes, userAgent;
    private final Duration timeout;
    private final HttpClient http;
    private final ObjectMapper mapper;
    private final MeterRegistry metrics;
    private final SimpleBreaker breaker;

    public NominatimGeocoder(String baseUrl, String countryCodes, String userAgent, Duration timeout, ObjectMapper mapper, MeterRegistry metrics, SimpleBreaker breaker) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.countryCodes = countryCodes; this.userAgent = userAgent; this.timeout = timeout; this.mapper = mapper; this.metrics = metrics; this.breaker = breaker;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    @Override
    public List<GeoService.Place> search(String query, Double lat, Double lng, int limit, String language) {
        StringBuilder url = new StringBuilder(baseUrl).append("/search?format=jsonv2&addressdetails=0&limit=").append(Math.max(1, Math.min(limit, 20)))
                .append("&q=").append(enc(query));
        if (countryCodes != null && !countryCodes.isBlank()) url.append("&countrycodes=").append(enc(countryCodes));
        if (lat != null && lng != null)   // bias (not restrict) the ranking towards the rider
            url.append(String.format(Locale.ROOT, "&viewbox=%.5f,%.5f,%.5f,%.5f&bounded=0", lng - 0.4, lat + 0.3, lng + 0.4, lat - 0.3));
        if (language != null && !language.isBlank()) url.append("&accept-language=").append(enc(language));
        JsonNode body = get(url.toString());
        List<GeoService.Place> out = new ArrayList<>();
        if (body == null || !body.isArray()) return out;
        for (JsonNode n : body) {
            if (!n.hasNonNull("lat") || !n.hasNonNull("lon")) continue;
            try {
                String display = n.path("display_name").asText("");
                String name = n.path("name").asText("");
                if (name.isBlank()) name = display.contains(",") ? display.substring(0, display.indexOf(',')).trim() : display;
                String stable = "osm:" + n.path("osm_type").asText("") + ":" + n.path("osm_id").asText(n.path("place_id").asText(""));
                out.add(new GeoService.Place(UUID.nameUUIDFromBytes(stable.getBytes(StandardCharsets.UTF_8)), name, display.isBlank() ? name : display,
                        Double.parseDouble(n.path("lat").asText()), Double.parseDouble(n.path("lon").asText())));
            } catch (NumberFormatException skip) { /* malformed coordinates: ignore this hit */ }
        }
        return out;
    }

    @Override
    public Optional<String> reverse(double lat, double lng, String language) {
        String url = String.format(Locale.ROOT, "%s/reverse?format=jsonv2&zoom=18&lat=%.6f&lon=%.6f", baseUrl, lat, lng)
                + (language == null || language.isBlank() ? "" : "&accept-language=" + enc(language));
        JsonNode body = get(url);
        if (body == null || body.has("error")) return Optional.empty();
        String display = body.path("display_name").asText("");
        return display.isBlank() ? Optional.empty() : Optional.of(display);
    }

    /** One GET; null on any failure (never throws). */
    private JsonNode get(String url) {
        if (breaker.isOpen()) { count("skipped"); return null; }
        try {
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(url)).timeout(timeout).header("User-Agent", userAgent).header("Accept", "application/json").GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 200) { breaker.success(); count("ok"); return mapper.readTree(res.body()); }
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
        if (breaker.failure()) log.warn("Nominatim failed repeatedly (last: {}); using the seeded places for a while", why);
        else log.warn("Nominatim request failed ({}); using the seeded places for this request", why);
    }

    private void count(String outcome) { if (metrics != null) metrics.counter("jolay.geocoding.nominatim", "outcome", outcome).increment(); }
    private static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
}
