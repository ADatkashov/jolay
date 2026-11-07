package kz.jolay.geography;

import java.util.List;
import java.util.Optional;

/**
 * Optional address search / reverse geocoding backend. When present, {@link GeoService} asks it first and falls back to the seeded places table when it
 * returns nothing or fails. Implementations must never throw: an unavailable geocoder returns empty results.
 */
public interface ExternalGeocoder {
    List<GeoService.Place> search(String query, Double lat, Double lng, int limit, String language);
    Optional<String> reverse(double lat, double lng, String language);
}
