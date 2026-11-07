package kz.jolay.geography;

import kz.jolay.common.GeoPoint;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/geo")
public class GeoController {
    private final GeoService geo;
    public GeoController(GeoService geo) { this.geo = geo; }

    @GetMapping("/places")
    public List<GeoService.Place> places(@RequestParam String q, @RequestParam(required = false) Double lat,
                                         @RequestParam(required = false) Double lng, @RequestParam(defaultValue = "10") int limit,
                                         @RequestHeader(value = "Accept-Language", required = false) String lang) {
        return geo.search(q, lat, lng, limit, language(lang));
    }

    @GetMapping("/reverse")
    public Map<String, String> reverse(@RequestParam double lat, @RequestParam double lng, @RequestHeader(value = "Accept-Language", required = false) String lang) {
        return Map.of("address", geo.reverse(new GeoPoint(lat, lng), language(lang)));
    }

    /** Only the three supported UI languages are forwarded to the geocoder. */
    private static String language(String header) {
        if (header == null || header.length() < 2) return null;
        String l = header.substring(0, 2).toLowerCase();
        return l.equals("kk") || l.equals("ru") || l.equals("en") ? l : null;
    }
}
