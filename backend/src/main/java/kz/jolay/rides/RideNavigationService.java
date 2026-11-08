package kz.jolay.rides;

import kz.jolay.common.ApiException;
import kz.jolay.common.GeoPoint;
import kz.jolay.geography.RouteProvider;
import kz.jolay.notifications.Notifier;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * In-app navigation for the two people on a ride: the road route of the current leg (driver to pickup, then the trip itself) with ETA and manoeuvres,
 * and the rider's position streamed to the driver while the driver is on the way. A route is computed at most once per {@link #TTL_MS} per ride and leg and
 * shared by both participants, which keeps the 2GIS routing quota in check.
 */
@Service
public class RideNavigationService {
    static final long TTL_MS = 12_000;

    public record Navigation(String leg, int distanceM, int durationS, String source, List<double[]> polyline, List<RouteProvider.Step> steps, double[] from, double[] to) {}
    private record Cached(long at, Navigation nav) {}

    private final JdbcClient jdbc;
    private final RouteProvider routes;
    private final Notifier notifier;
    private final Map<String, Cached> cache = new ConcurrentHashMap<>();

    public RideNavigationService(JdbcClient jdbc, RouteProvider routes, Notifier notifier) { this.jdbc = jdbc; this.routes = routes; this.notifier = notifier; }

    private Map<String, Object> ride(UUID rideId, UUID viewer) {
        var m = jdbc.sql("""
                SELECT r.status, r.customer_id, r.driver_id, ST_Y(r.pickup::geometry) plat, ST_X(r.pickup::geometry) plng, ST_Y(r.dropoff::geometry) dlat, ST_X(r.dropoff::geometry) dlng,
                       ST_Y(dl.location::geometry) alat, ST_X(dl.location::geometry) alng
                FROM rides r LEFT JOIN driver_locations dl ON dl.driver_id=r.driver_id WHERE r.id=:id""")
                .param("id", rideId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
        if (!viewer.equals(m.get("customer_id")) && !viewer.equals(m.get("driver_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        return m;
    }

    public Navigation navigation(UUID rideId, UUID viewer) {
        var m = ride(rideId, viewer);
        String status = (String) m.get("status");
        GeoPoint pickup = new GeoPoint(((Number) m.get("plat")).doubleValue(), ((Number) m.get("plng")).doubleValue());
        GeoPoint drop = new GeoPoint(((Number) m.get("dlat")).doubleValue(), ((Number) m.get("dlng")).doubleValue());
        GeoPoint driver = m.get("alat") == null ? null : new GeoPoint(((Number) m.get("alat")).doubleValue(), ((Number) m.get("alng")).doubleValue());
        String leg; GeoPoint from, to;
        switch (status) {
            case "DRIVER_ASSIGNED", "DRIVER_ARRIVING" -> {
                if (driver != null) { leg = "PICKUP"; from = driver; to = pickup; } else { leg = "TRIP"; from = pickup; to = drop; }
            }
            case "DRIVER_ARRIVED" -> { leg = "TRIP"; from = pickup; to = drop; }
            case "IN_PROGRESS" -> { leg = "TRIP"; from = driver != null ? driver : pickup; to = drop; }
            default -> throw ApiException.conflict("navigation_unavailable", "Navigation is available while a driver is assigned or the trip is running");
        }
        String key = rideId + ":" + leg;
        long now = System.currentTimeMillis();
        Cached c = cache.get(key);
        if (c != null && now - c.at() < TTL_MS) return c.nav();
        if (cache.size() > 2000) cache.entrySet().removeIf(e -> now - e.getValue().at() > TTL_MS);
        RouteProvider.RouteDetail d = routes.detail(from, to);
        Navigation nav = new Navigation(leg, d.distanceM(), d.durationS(), d.source(), d.polyline(), d.steps(), new double[]{from.lat(), from.lng()}, new double[]{to.lat(), to.lng()});
        cache.put(key, new Cached(now, nav));
        return nav;
    }

    /** The rider shares their position with the driver only while the driver is on the way to or waiting at the pickup. */
    public void shareCustomerLocation(UUID rideId, UUID customerId, GeoPoint p) {
        var m = ride(rideId, customerId);
        if (!customerId.equals(m.get("customer_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        String status = (String) m.get("status");
        if (!List.of("DRIVER_ASSIGNED", "DRIVER_ARRIVING", "DRIVER_ARRIVED").contains(status) || m.get("driver_id") == null)
            throw ApiException.conflict("location_sharing_unavailable", "The rider's position is shared only while the driver is coming to the pickup");
        notifier.event((UUID) m.get("driver_id"), "CUSTOMER_LOCATION_UPDATED", Map.of("rideId", rideId.toString(), "lat", p.lat(), "lng", p.lng()));
    }
}
