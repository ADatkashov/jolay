package kz.jolay.drivers;

import kz.jolay.common.ApiException;
import kz.jolay.common.AppSettings;
import kz.jolay.common.GeoPoint;
import kz.jolay.drivers.DriverDtos.*;
import kz.jolay.geography.EstimatedRouteProvider;
import kz.jolay.geography.GeoService;
import kz.jolay.notifications.Notifier;
import kz.jolay.rides.RideDtos.LocationRequest;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class DriverService {
    private final JdbcClient jdbc;
    private final GeoService geo;
    private final Notifier notifier;
    private final AppSettings settings;

    public DriverService(JdbcClient jdbc, GeoService geo, Notifier notifier, AppSettings settings) { this.jdbc = jdbc; this.geo = geo; this.notifier = notifier; this.settings = settings; }

    @Transactional
    public void register(UUID userId, DriverRegisterRequest r) {
        if (jdbc.sql("SELECT count(*) FROM drivers WHERE user_id=:u").param("u", userId).query(Integer.class).single() > 0)
            throw ApiException.conflict("already_registered", "Driver profile already exists");
        UUID city = jdbc.sql("SELECT id FROM cities WHERE code=:c AND active").param("c", r.cityCode() == null ? "ALA" : r.cityCode()).query(UUID.class).optional()
                .orElseThrow(() -> ApiException.badRequest("unknown_city", "Unknown city"));
        if (jdbc.sql("SELECT count(*) FROM vehicle_categories WHERE code=:c AND active").param("c", r.vehicle().category()).query(Integer.class).single() == 0)
            throw ApiException.badRequest("unknown_category", "Unknown vehicle category");
        jdbc.sql("INSERT INTO drivers(user_id, city_id) VALUES (:u,:c)").param("u", userId).param("c", city).update();
        try {
            var v = r.vehicle();
            jdbc.sql("INSERT INTO vehicles(driver_id,brand,model,year,color,plate,category_code) VALUES (:d,:b,:m,:y,:c,:p,:k)")
                    .param("d", userId).param("b", v.brand()).param("m", v.model()).param("y", v.year()).param("c", v.color())
                    .param("p", v.plate().toUpperCase().replace(" ", "")).param("k", v.category()).update();
        } catch (DuplicateKeyException e) { throw ApiException.conflict("plate_taken", "This plate is already registered"); }
    }

    public Map<String, Object> me(UUID userId) {
        var d = jdbc.sql("""
                SELECT d.verification, d.availability, d.rating_avg, d.rating_count, d.rejection_reason, d.offers_total, d.offers_accepted, u.full_name, u.phone
                FROM drivers d JOIN users u ON u.id=d.user_id WHERE d.user_id=:u""").param("u", userId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("driver_not_registered", "Driver profile not found"));
        var veh = jdbc.sql("SELECT id, brand, model, year, color, plate, category_code, approved FROM vehicles WHERE driver_id=:u AND active ORDER BY created_at LIMIT 1").param("u", userId).query().listOfRows();
        var today = jdbc.sql("""
                SELECT count(*) AS trips, COALESCE(sum(f.driver_earnings),0) AS net
                FROM rides r JOIN ride_fares f ON f.ride_id=r.id
                WHERE r.driver_id=:u AND r.status='COMPLETED' AND r.completed_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'""").param("u", userId).query().listOfRows().get(0);
        var m = new java.util.LinkedHashMap<String, Object>(d);
        m.put("vehicle", veh.isEmpty() ? null : veh.get(0));
        m.put("todayTrips", today.get("trips")); m.put("todayEarnings", today.get("net"));
        return m;
    }

    @Transactional
    public void setAvailability(UUID userId, boolean online) {
        var d = jdbc.sql("SELECT verification, availability FROM drivers WHERE user_id=:u FOR UPDATE").param("u", userId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("driver_not_registered", "Driver profile not found"));
        String cur = (String) d.get("availability");
        if (!"APPROVED".equals(d.get("verification"))) throw ApiException.forbidden("driver_not_approved", "Driver account is not approved");
        String next = online ? "ONLINE" : "OFFLINE";
        if (cur.equals(next)) return;
        if (online && !(cur.equals("OFFLINE") || cur.equals("PAUSED"))) return;
        if (!online && (cur.equals("BUSY") || cur.equals("OFFERED"))) throw ApiException.conflict("driver_busy", "Finish or resolve your current order first");
        if ("SUSPENDED".equals(cur)) throw ApiException.forbidden("account_suspended", "Account is suspended");
        if (online && jdbc.sql("SELECT count(*) FROM vehicles WHERE driver_id=:u AND active AND approved").param("u", userId).query(Integer.class).single() == 0)
            throw ApiException.forbidden("vehicle_not_approved", "No approved vehicle");
        jdbc.sql("UPDATE drivers SET availability=:a, updated_at=now() WHERE user_id=:u").param("a", next).param("u", userId).update();
        jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:u,:f,:t)").param("u", userId).param("f", cur).param("t", next).update();
        if (!online) jdbc.sql("DELETE FROM driver_locations WHERE driver_id=:u").param("u", userId).update();
    }

    /** Validates and stores a location. Rejects impossible jumps (>220 km/h) so spoofed/glitched fixes can't win dispatch. */
    @Transactional
    public void updateLocation(UUID userId, LocationRequest r) {
        var d = jdbc.sql("SELECT availability, verification FROM drivers WHERE user_id=:u").param("u", userId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("driver_not_registered", "Driver profile not found"));
        if (!"APPROVED".equals(d.get("verification")) || "SUSPENDED".equals(d.get("availability")) || "OFFLINE".equals(d.get("availability")))
            throw ApiException.conflict("driver_offline", "Go online to share your location");
        GeoPoint p = r.point();
        var prev = jdbc.sql("SELECT ST_Y(location::geometry) lat, ST_X(location::geometry) lng, EXTRACT(EPOCH FROM (now()-updated_at)) age FROM driver_locations WHERE driver_id=:u").param("u", userId).query().listOfRows().stream().findFirst();
        if (prev.isPresent()) {
            double dist = EstimatedRouteProvider.haversineM((Double) prev.get().get("lat"), (Double) prev.get().get("lng"), p.lat(), p.lng());
            double secs = Math.max(1.0, ((Number) prev.get().get("age")).doubleValue());
            if (dist / secs * 3.6 > 220 && dist > 500) throw ApiException.badRequest("implausible_location", "Location jump rejected");
        }
        jdbc.sql("""
                INSERT INTO driver_locations(driver_id, location, heading, speed_kmh, updated_at)
                VALUES (:u, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, :h, :s, now())
                ON CONFLICT (driver_id) DO UPDATE SET location=EXCLUDED.location, heading=EXCLUDED.heading, speed_kmh=EXCLUDED.speed_kmh, updated_at=now()""")
                .param("u", userId).param("lng", p.lng()).param("lat", p.lat()).param("h", r.heading()).param("s", r.speedKmh()).update();
        // Active ride: record the track while the trip is running and stream the position to the customer.
        var ride = jdbc.sql("SELECT id, customer_id, status FROM rides WHERE driver_id=:u AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')").param("u", userId).query().listOfRows().stream().findFirst();
        if (ride.isPresent()) {
            if ("IN_PROGRESS".equals(ride.get().get("status")))
                jdbc.sql("INSERT INTO ride_locations(ride_id, location) VALUES (:r, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography)").param("r", ride.get().get("id")).param("lng", p.lng()).param("lat", p.lat()).update();
            notifier.event((UUID) ride.get().get("customer_id"), "DRIVER_LOCATION_UPDATED",
                    Map.of("rideId", ride.get().get("id").toString(), "lat", p.lat(), "lng", p.lng(), "heading", r.heading() == null ? 0 : r.heading()));
        }
    }

    public Map<String, Object> currentOffer(UUID userId) {
        var o = jdbc.sql("""
                SELECT o.id AS offer_id, o.ride_id, o.pickup_distance_m, o.eta_s, o.expected_earnings, o.expires_at,
                       EXTRACT(EPOCH FROM (o.expires_at - now()))::int AS seconds_left,
                       r.pickup_address, r.dropoff_address, r.est_distance_m, r.est_duration_s, r.payment_method, r.category_code,
                       ST_Y(r.pickup::geometry) plat, ST_X(r.pickup::geometry) plng, ST_Y(r.dropoff::geometry) dlat, ST_X(r.dropoff::geometry) dlng
                FROM ride_offers o JOIN rides r ON r.id=o.ride_id WHERE o.driver_id=:u AND o.status='OFFERED' AND o.expires_at > now()""")
                .param("u", userId).query().listOfRows();
        return o.isEmpty() ? null : o.get(0);
    }

    public Map<String, Object> earnings(UUID userId, String period) {
        String since = switch (period == null ? "today" : period) {
            case "week" -> "date_trunc('week', now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'";
            case "month" -> "date_trunc('month', now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'";
            default -> "date_trunc('day', now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'";
        };
        var row = jdbc.sql("SELECT count(*) trips, COALESCE(sum(f.total),0) gross, COALESCE(sum(f.commission),0) commission, COALESCE(sum(f.driver_earnings),0) net " +
                "FROM rides r JOIN ride_fares f ON f.ride_id=r.id WHERE r.driver_id=:u AND r.status='COMPLETED' AND r.completed_at >= " + since)
                .param("u", userId).query().listOfRows().get(0);
        var m = new java.util.LinkedHashMap<String, Object>(row);
        m.put("period", period == null ? "today" : period);
        m.put("currency", "KZT");
        return m;
    }
}
