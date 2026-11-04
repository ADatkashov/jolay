package kz.jolay.geography;

import kz.jolay.common.ApiException;
import kz.jolay.common.GeoPoint;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.UUID;

@Service
public class GeoService {
    private final JdbcClient jdbc;
    public GeoService(JdbcClient jdbc) { this.jdbc = jdbc; }

    public record Place(UUID id, String name, String address, double lat, double lng) {}

    /** Returns the city whose active service zone covers the point, or fails if the point is unserved. */
    public UUID cityFor(GeoPoint p, String errorCode) {
        return jdbc.sql("""
                SELECT z.city_id FROM service_zones z JOIN cities c ON c.id=z.city_id
                WHERE z.active AND c.active AND ST_Intersects(z.boundary, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography) LIMIT 1""")
                .param("lng", p.lng()).param("lat", p.lat()).query(UUID.class).optional()
                .orElseThrow(() -> ApiException.badRequest(errorCode, "Location is outside the JOLAY service area"));
    }

    public List<Place> search(String q, Double lat, Double lng, int limit) {
        String like = "%" + q.trim().replace("%", "").replace("_", "") + "%";
        String order = lat != null && lng != null ? "ST_Distance(location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography)" : "name";
        var s = jdbc.sql("SELECT id,name,address,ST_Y(location::geometry) lat,ST_X(location::geometry) lng FROM places WHERE name ILIKE :q OR address ILIKE :q ORDER BY " + order + " LIMIT :l")
                .param("q", like).param("l", Math.min(limit, 20));
        if (lat != null && lng != null) s = s.param("lat", lat).param("lng", lng);
        return s.query((rs, i) -> new Place(rs.getObject("id", UUID.class), rs.getString("name"), rs.getString("address"), rs.getDouble("lat"), rs.getDouble("lng"))).list();
    }

    /** Nearest known place within 250 m, else a coordinate label. A real geocoder replaces this behind the same call. */
    public String reverse(GeoPoint p) {
        return jdbc.sql("SELECT name FROM places WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, 250) ORDER BY ST_Distance(location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography) LIMIT 1")
                .param("lng", p.lng()).param("lat", p.lat()).query(String.class).optional()
                .orElse(String.format("%.5f, %.5f", p.lat(), p.lng()));
    }
}
