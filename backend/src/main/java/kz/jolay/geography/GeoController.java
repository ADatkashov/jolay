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
                                         @RequestParam(required = false) Double lng, @RequestParam(defaultValue = "10") int limit) {
        return geo.search(q, lat, lng, limit);
    }

    @GetMapping("/reverse")
    public Map<String, String> reverse(@RequestParam double lat, @RequestParam double lng) {
        return Map.of("address", geo.reverse(new GeoPoint(lat, lng)));
    }
}
