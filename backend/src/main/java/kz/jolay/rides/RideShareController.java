package kz.jolay.rides;

import kz.jolay.common.ApiException;
import kz.jolay.common.Auth;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Trip sharing. The customer creates (or revokes) a share link for one of their active rides; anyone holding the token can read a minimal
 * public view of the ride. The view contains no phone numbers, fare or payment data, shows the driver's first name, vehicle and live position
 * only while the ride is active, and expires a configurable grace period after the ride ends.
 */
@RestController
public class RideShareController {
    private static final String ACTIVE = "('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')";
    private final JdbcClient jdbc;

    private final RideShareService shares;

    public RideShareController(JdbcClient jdbc, RideShareService shares) { this.jdbc = jdbc; this.shares = shares; }

    /** Minimal viewer page for the people the link was shared with; it reads the public JSON view below. */
    @GetMapping(value = "/api/v1/catalog/trip/{token}", produces = "text/html;charset=UTF-8")
    public org.springframework.http.ResponseEntity<byte[]> page(@PathVariable String token) throws java.io.IOException {
        try (var in = getClass().getResourceAsStream("/web/trip.html")) {
            return org.springframework.http.ResponseEntity.ok().header("Cache-Control", "no-store").header("Referrer-Policy", "no-referrer")
                    .header("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'").body(in.readAllBytes());
        }
    }

    @PostMapping("/api/v1/rides/{id}/share") @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> share(@PathVariable UUID id) {
        String token = shares.ensureToken(id, Auth.id());
        return Map.of("token", token, "url", shares.urlFor(token));
    }

    @DeleteMapping("/api/v1/rides/{id}/share") @PreAuthorize("hasRole('CUSTOMER')") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(@PathVariable UUID id) {
        jdbc.sql("UPDATE ride_shares SET revoked_at=now() WHERE ride_id=:r AND revoked_at IS NULL AND created_by=:u").param("r", id).param("u", Auth.id()).update();
    }

    /** Public, unauthenticated (permitted under /api/v1/catalog). */
    @GetMapping("/api/v1/catalog/ride-share/{token}")
    public Map<String, Object> view(@PathVariable String token) {
        var row = jdbc.sql("""
                SELECT r.status, r.pickup_address, r.dropoff_address, r.completed_at, r.cancelled_at, r.updated_at,
                       cu.full_name AS customer_name, du.full_name AS driver_name, v.brand, v.model, v.color, v.plate,
                       ST_Y(dl.location::geometry) AS lat, ST_X(dl.location::geometry) AS lng, dl.updated_at AS loc_at,
                       ST_Y(r.dropoff::geometry) AS drop_lat, ST_X(r.dropoff::geometry) AS drop_lng,
                       (s.revoked_at IS NOT NULL) AS revoked,
                       (r.status IN %s) AS active,
                       (r.status IN ('COMPLETED','CANCELLED','EXPIRED','FAILED')
                         AND COALESCE(r.completed_at, r.cancelled_at, r.updated_at) < now() - make_interval(mins => COALESCE((SELECT value::int FROM application_settings WHERE key='safety.share_grace_minutes'),60))) AS expired
                FROM ride_shares s JOIN rides r ON r.id=s.ride_id JOIN users cu ON cu.id=r.customer_id
                LEFT JOIN users du ON du.id=r.driver_id LEFT JOIN vehicles v ON v.id=r.vehicle_id LEFT JOIN driver_locations dl ON dl.driver_id=r.driver_id
                WHERE s.token=:t""".formatted(ACTIVE)).param("t", token).query().listOfRows().stream().findFirst().orElse(null);
        if (row == null || Boolean.TRUE.equals(row.get("revoked")) || Boolean.TRUE.equals(row.get("expired")))
            throw ApiException.notFound("share_not_found", "This trip link is no longer available");
        boolean active = Boolean.TRUE.equals(row.get("active"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("status", row.get("status"));
        out.put("active", active);
        out.put("sharedBy", firstName((String) row.get("customer_name")));
        out.put("pickupAddress", row.get("pickup_address"));
        out.put("dropoffAddress", row.get("dropoff_address"));
        if (row.get("driver_name") != null) {
            out.put("driverName", firstName((String) row.get("driver_name")));
            out.put("vehicle", Map.of("brand", row.get("brand"), "model", row.get("model"), "color", row.get("color"), "plate", row.get("plate")));
        }
        if (active && row.get("lat") != null) {
            out.put("driverLocation", Map.of("lat", row.get("lat"), "lng", row.get("lng"), "updatedAt", String.valueOf(row.get("loc_at"))));
            out.put("dropoff", Map.of("lat", row.get("drop_lat"), "lng", row.get("drop_lng")));
        }
        return out;
    }

    private static String firstName(String full) { return full == null ? null : full.trim().split("\\s+")[0]; }
}
