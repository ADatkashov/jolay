package kz.jolay.rides;

import kz.jolay.common.*;
import kz.jolay.dispatch.DispatchService;
import kz.jolay.geography.GeoService;
import kz.jolay.geography.RouteProvider;
import kz.jolay.notifications.Notifier;
import kz.jolay.payments.PaymentService;
import kz.jolay.pricing.PricingService;
import kz.jolay.risk.RiskService;
import kz.jolay.rides.RideDtos.*;
import kz.jolay.wallet.LedgerService;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

@Service
public class RideService {
    private final JdbcClient jdbc;
    private final GeoService geo;
    private final RouteProvider routes;
    private final PricingService pricing;
    private final RideStateMachine sm;
    private final DispatchService dispatch;
    private final PaymentService payments;
    private final LedgerService ledger;
    private final Notifier notifier;
    private final AppSettings settings;
    private final MeterRegistry metrics;
    private final RiskService risk;

    public RideService(JdbcClient jdbc, GeoService geo, RouteProvider routes, PricingService pricing, RideStateMachine sm, DispatchService dispatch,
                       PaymentService payments, LedgerService ledger, Notifier notifier, AppSettings settings, MeterRegistry metrics, RiskService risk) {
        this.risk = risk;
        this.jdbc = jdbc; this.geo = geo; this.routes = routes; this.pricing = pricing; this.sm = sm; this.dispatch = dispatch;
        this.payments = payments; this.ledger = ledger; this.notifier = notifier; this.settings = settings; this.metrics = metrics;
    }

    private static FareView view(PricingService.Fare f) {
        return new FareView(f.baseFare(), f.distanceFare(), f.timeFare(), f.fees(), f.discount(), f.multiplier(), f.total(), "KZT");
    }

    // ---------------- estimate ----------------
    public EstimateResponse estimate(EstimateRequest r, String lang) {
        UUID city = geo.cityFor(r.pickup(), "pickup_out_of_zone");
        if (!city.equals(geo.cityFor(r.dropoff(), "dropoff_out_of_zone"))) throw ApiException.badRequest("intercity_unsupported", "Pickup and destination must be in the same city");
        var route = routes.route(r.pickup(), r.dropoff());
        String l = switch (lang == null ? "en" : lang) { case "kk" -> "kk"; case "ru" -> "ru"; default -> "en"; };
        List<CategoryEstimate> out = new ArrayList<>();
        for (var rule : pricing.rules(city)) {
            var cat = jdbc.sql("SELECT name_" + l + " n, desc_" + l + " d, capacity FROM vehicle_categories WHERE code=:c").param("c", rule.category()).query().listOfRows().get(0);
            Integer eta = nearestEta(city, r.pickup(), rule.category());
            out.add(new CategoryEstimate(rule.category(), (String) cat.get("n"), (String) cat.get("d"), (Integer) cat.get("capacity"),
                    view(pricing.compute(rule, route.distanceM(), route.durationS(), null)), eta, eta != null));
        }
        return new EstimateResponse(route.distanceM(), route.durationS(), route.source(), out);
    }

    private Integer nearestEta(UUID city, GeoPoint p, String category) {
        int radius = settings.getInt("dispatch.max_radius_m"), age = settings.getInt("dispatch.location_max_age_seconds");
        // Nearest 100 fresh positions via the GiST index first, then eligibility. EXPLAIN ANALYZE on 100k drivers: 19 ms (the former min() join took 89 ms).
        Double dist = jdbc.sql("""
                WITH q AS (SELECT ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography AS p),
                near AS MATERIALIZED (
                    SELECT dl.driver_id, dl.location <-> q.p AS dist FROM driver_locations dl, q
                    WHERE dl.updated_at > now() - make_interval(secs => :age) AND ST_DWithin(dl.location, q.p, :radius)
                    ORDER BY dl.location <-> q.p LIMIT 100)
                SELECT min(near.dist) FROM near
                JOIN drivers d ON d.user_id=near.driver_id AND d.verification='APPROVED' AND d.availability='ONLINE' AND d.city_id=:city
                JOIN vehicles v ON v.driver_id=d.user_id AND v.active AND v.approved
                JOIN vehicle_categories vc ON vc.code=v.category_code JOIN vehicle_categories rc ON rc.code=:cat
                WHERE ((rc.code='XL' AND vc.code='XL') OR (rc.code<>'XL' AND vc.code<>'XL' AND vc.rank >= rc.rank))""")
                .param("lng", p.lng()).param("lat", p.lat()).param("cat", category).param("city", city).param("age", age).param("radius", radius)
                .query((rs, i) -> rs.getObject(1) == null ? Double.NaN : rs.getDouble(1)).optional().orElse(null);
        if (dist == null || dist.isNaN()) return null;
        double speed = settings.getDecimal("rides.avg_speed_kmh").doubleValue() / 3.6;
        return (int) Math.round(dist * settings.getDecimal("rides.detour_factor").doubleValue() / speed);
    }

    // ---------------- create ----------------
    @Transactional
    public RideView create(UUID customerId, CreateRideRequest r, String idempotencyKey) {
        if (idempotencyKey != null) {
            var existing = jdbc.sql("SELECT id FROM rides WHERE customer_id=:c AND idempotency_key=:k").param("c", customerId).param("k", idempotencyKey).query(UUID.class).optional();
            if (existing.isPresent()) return get(existing.get(), customerId, Set.of("CUSTOMER"));
        }
        UUID city = geo.cityFor(r.pickup().point(), "pickup_out_of_zone");
        if (!city.equals(geo.cityFor(r.dropoff().point(), "dropoff_out_of_zone"))) throw ApiException.badRequest("intercity_unsupported", "Pickup and destination must be in the same city");
        var rule = pricing.rule(city, r.category());
        var route = routes.route(r.pickup().point(), r.dropoff().point());
        if (route.distanceM() < 100) throw ApiException.badRequest("trip_too_short", "Pickup and destination are too close");
        var fare = pricing.compute(rule, route.distanceM(), route.durationS(), null);

        if ("WALLET".equals(r.paymentMethod())) {
            BigDecimal bal = ledger.balance(ledger.userAccount(customerId, "CUSTOMER_WALLET"));
            if (bal.compareTo(fare.total()) < 0) throw ApiException.conflict("insufficient_funds", "Wallet balance is lower than the estimated fare");
        }
        String pAddr = blank(r.pickup().address()) ? geo.reverse(r.pickup().point()) : r.pickup().address().trim();
        String dAddr = blank(r.dropoff().address()) ? geo.reverse(r.dropoff().point()) : r.dropoff().address().trim();

        UUID id;
        try {
            id = jdbc.sql("""
                    INSERT INTO rides(customer_id,city_id,category_code,status,pickup_address,pickup,dropoff_address,dropoff,est_distance_m,est_duration_s,est_fare,
                                      payment_method,pricing_rule_id,idempotency_key,search_started_at)
                    VALUES (:c,:city,:cat,'CREATED',:pa,ST_SetSRID(ST_MakePoint(:plng,:plat),4326)::geography,:da,ST_SetSRID(ST_MakePoint(:dlng,:dlat),4326)::geography,
                            :dist,:dur,:fare,:pm,:rule,:idem,now()) RETURNING id""")
                    .param("c", customerId).param("city", city).param("cat", r.category()).param("pa", pAddr).param("plng", r.pickup().point().lng()).param("plat", r.pickup().point().lat())
                    .param("da", dAddr).param("dlng", r.dropoff().point().lng()).param("dlat", r.dropoff().point().lat())
                    .param("dist", route.distanceM()).param("dur", route.durationS()).param("fare", fare.total()).param("pm", r.paymentMethod())
                    .param("rule", rule.id()).param("idem", idempotencyKey).query(UUID.class).single();
        } catch (DuplicateKeyException e) {
            throw ApiException.conflict("active_ride_exists", "You already have an active ride");
        }
        jdbc.sql("INSERT INTO ride_status_history(ride_id,from_status,to_status,actor) VALUES (:r,NULL,'CREATED',:a)").param("r", id).param("a", "CUSTOMER:" + customerId).update();
        sm.move(id, RideStatus.CREATED, RideStatus.SEARCHING_DRIVER, "SYSTEM", null, null);
        metrics.counter("jolay.rides.created").increment();
        dispatch.dispatchRound(id);        // first round immediately; the scheduler continues until assigned / expired
        return get(id, customerId, Set.of("CUSTOMER"));
    }

    private static boolean blank(String s) { return s == null || s.isBlank(); }

    // ---------------- read ----------------
    public RideView get(UUID rideId, UUID viewer, Set<String> roles) {
        var m = jdbc.sql("""
                SELECT r.*, ST_X(r.pickup::geometry) plng, ST_Y(r.pickup::geometry) plat, ST_X(r.dropoff::geometry) dlng, ST_Y(r.dropoff::geometry) dlat,
                       cu.full_name AS cname, cu.phone AS cphone,
                       du.full_name AS dname, du.phone AS dphone, d.rating_avg, v.brand, v.model, v.color, v.plate,
                       ST_Y(dl.location::geometry) dlat_now, ST_X(dl.location::geometry) dlng_now,
                       (SELECT stars FROM ratings rt WHERE rt.ride_id=r.id AND rt.from_user_id=r.customer_id) AS stars
                FROM rides r JOIN users cu ON cu.id=r.customer_id
                LEFT JOIN users du ON du.id=r.driver_id LEFT JOIN drivers d ON d.user_id=r.driver_id
                LEFT JOIN vehicles v ON v.id=r.vehicle_id LEFT JOIN driver_locations dl ON dl.driver_id=r.driver_id
                WHERE r.id=:id""").param("id", rideId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
        boolean admin = roles.stream().anyMatch(x -> x.endsWith("_ADMIN") || x.equals("SUPPORT_AGENT"));
        boolean isCustomer = viewer.equals(m.get("customer_id")), isDriver = viewer.equals(m.get("driver_id"));
        if (!admin && !isCustomer && !isDriver) throw ApiException.notFound("ride_not_found", "Ride not found");
        return toView(m, isCustomer || admin || isDriver);
    }

    private RideView toView(Map<String, Object> m, boolean full) {
        String status = (String) m.get("status");
        DriverView dv = null;
        if (m.get("driver_id") != null) {
            boolean showLive = Set.of("DRIVER_ASSIGNED", "DRIVER_ARRIVING", "DRIVER_ARRIVED", "IN_PROGRESS").contains(status);
            dv = new DriverView((UUID) m.get("driver_id"), (String) m.get("dname"), showLive || "COMPLETED".equals(status) ? (String) m.get("dphone") : null,
                    (BigDecimal) m.get("rating_avg"), m.get("brand") + " " + m.get("model"), (String) m.get("color"), (String) m.get("plate"),
                    showLive ? (Double) m.get("dlat_now") : null, showLive ? (Double) m.get("dlng_now") : null);
        }
        Integer eta = null;
        if (dv != null && dv.lat() != null && Set.of("DRIVER_ASSIGNED", "DRIVER_ARRIVING").contains(status)) {
            double d = kz.jolay.geography.EstimatedRouteProvider.haversineM(dv.lat(), dv.lng(), (Double) m.get("plat"), (Double) m.get("plng"));
            eta = (int) Math.round(d * settings.getDecimal("rides.detour_factor").doubleValue() / (settings.getDecimal("rides.avg_speed_kmh").doubleValue() / 3.6));
        }
        return new RideView((UUID) m.get("id"), status, (String) m.get("category_code"), (String) m.get("pickup_address"),
                new GeoPoint((Double) m.get("plat"), (Double) m.get("plng")), (String) m.get("dropoff_address"),
                new GeoPoint((Double) m.get("dlat"), (Double) m.get("dlng")),
                m.get("actual_distance_m") != null ? (Integer) m.get("actual_distance_m") : (Integer) m.get("est_distance_m"),
                m.get("actual_duration_s") != null ? (Integer) m.get("actual_duration_s") : (Integer) m.get("est_duration_s"),
                (BigDecimal) m.get("est_fare"), (BigDecimal) m.get("final_fare"), (String) m.get("payment_method"), (String) m.get("payment_status"),
                (BigDecimal) m.get("cancellation_fee"), dv, (UUID) m.get("customer_id"), (String) m.get("cname"), "IN_PROGRESS".equals(status) || status.startsWith("DRIVER") ? (String) m.get("cphone") : null,
                eta, m.get("created_at"), m.get("completed_at"), (Integer) m.get("stars"));
    }

    public Optional<RideView> activeForCustomer(UUID customerId) {
        return jdbc.sql("SELECT id FROM rides WHERE customer_id=:c AND status IN ('SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS','CREATED')")
                .param("c", customerId).query(UUID.class).optional().map(id -> get(id, customerId, Set.of("CUSTOMER")));
    }

    public Optional<RideView> activeForDriver(UUID driverId) {
        return jdbc.sql("SELECT id FROM rides WHERE driver_id=:d AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')")
                .param("d", driverId).query(UUID.class).optional().map(id -> get(id, driverId, Set.of("DRIVER")));
    }

    public List<RideView> history(UUID userId, boolean driver, String tab, int limit, int offset) {
        String statuses = switch (tab == null ? "completed" : tab) {
            case "ongoing" -> "('CREATED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')";
            case "cancelled" -> "('CANCELLED','EXPIRED','FAILED')";
            default -> "('COMPLETED')";
        };
        String col = driver ? "driver_id" : "customer_id";
        List<UUID> ids = jdbc.sql("SELECT id FROM rides WHERE " + col + "=:u AND status IN " + statuses + " ORDER BY created_at DESC LIMIT :l OFFSET :o")
                .param("u", userId).param("l", Math.min(limit, 100)).param("o", offset).query(UUID.class).list();
        return ids.stream().map(id -> get(id, userId, Set.of(driver ? "DRIVER" : "CUSTOMER"))).toList();
    }

    public List<Map<String, Object>> fareBreakdown(UUID rideId, UUID viewer, Set<String> roles) {
        get(rideId, viewer, roles);   // authorization
        return jdbc.sql("SELECT base_fare, distance_fare, time_fare, fees, discount, multiplier, total FROM ride_fares WHERE ride_id=:r").param("r", rideId).query().listOfRows();
    }

    // ---------------- customer cancel ----------------
    @Transactional
    public RideView cancelByCustomer(UUID rideId, UUID customerId, String reason) {
        var r = jdbc.sql("SELECT status, customer_id, driver_id, assigned_at, pricing_rule_id, payment_method FROM rides WHERE id=:id FOR UPDATE").param("id", rideId).query().listOfRows().stream().findFirst().orElse(null);
        if (r == null || !customerId.equals(r.get("customer_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        RideStatus st = RideStatus.valueOf((String) r.get("status"));
        if (st == RideStatus.IN_PROGRESS || st.isTerminal()) throw ApiException.conflict("cannot_cancel", "Ride cannot be cancelled in its current state");
        BigDecimal fee = Money.ZERO;
        UUID driver = (UUID) r.get("driver_id");
        if (driver != null) {
            var rule = pricing.ruleById((UUID) r.get("pricing_rule_id"));
            boolean late = jdbc.sql("SELECT now() - assigned_at > make_interval(secs => :s) FROM rides WHERE id=:id").param("s", rule.freeCancelSeconds()).param("id", rideId).query(Boolean.class).single();
            if (late) fee = rule.cancellationFee();
        }
        sm.move(rideId, st, RideStatus.CANCELLED, "CUSTOMER:" + customerId,
                ", cancelled_at=now(), cancelled_by='CUSTOMER', cancel_reason=:reason, cancellation_fee=:fee", Map.of("reason", reason == null ? "customer_cancelled" : reason, "fee", fee));
        if (fee.signum() > 0 && "WALLET".equals(r.get("payment_method"))) chargeCancellationFee(rideId, customerId, driver, fee);
        dispatch.cancelOffers(rideId);
        if (driver != null) {
            if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='BUSY'").param("d", driver).update() == 1)
                jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'BUSY','ONLINE')").param("d", driver).update();
            notifier.notify(driver, "RIDE_CANCELLED", "ride-cancelled-" + rideId, Map.of("rideId", rideId.toString(), "by", "CUSTOMER"));
        }
        risk.onCustomerCancel(customerId);
        metrics.counter("jolay.rides.cancelled", "by", "customer").increment();
        return get(rideId, customerId, Set.of("CUSTOMER"));
    }

    private void chargeCancellationFee(UUID rideId, UUID customerId, UUID driver, BigDecimal fee) {
        try {
            UUID cust = ledger.userAccount(customerId, "CUSTOMER_WALLET"), drv = ledger.userAccount(driver, "DRIVER_WALLET");
            ledger.post("CANCELLATION_FEE", "RIDE", rideId, "cancel-fee-" + rideId, "Late cancellation fee",
                    List.of(new LedgerService.Leg(cust, fee.negate()), new LedgerService.Leg(drv, fee)));
        } catch (ApiException e) { /* insufficient funds: fee stays recorded on the ride as owed */ }
    }

    // ---------------- driver actions ----------------
    private Map<String, Object> lockForDriver(UUID rideId, UUID driverId) {
        var r = jdbc.sql("SELECT id, status, customer_id, driver_id, est_fare, est_duration_s, est_distance_m, pricing_rule_id, started_at, ST_Distance(pickup, (SELECT location FROM driver_locations WHERE driver_id=:d)) AS dist_pickup FROM rides WHERE id=:id FOR UPDATE")
                .param("id", rideId).param("d", driverId).query().listOfRows().stream().findFirst().orElse(null);
        if (r == null || !driverId.equals(r.get("driver_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        return r;
    }

    @Transactional
    public RideView enRoute(UUID rideId, UUID driverId) {
        var r = lockForDriver(rideId, driverId);
        sm.move(rideId, RideStatus.valueOf((String) r.get("status")), RideStatus.DRIVER_ARRIVING, "DRIVER:" + driverId, null, null);
        notifier.notify((UUID) r.get("customer_id"), "DRIVER_ARRIVING", "ride-" + rideId + "-arriving", Map.of("rideId", rideId.toString(), "status", "DRIVER_ARRIVING"));
        return get(rideId, driverId, Set.of("DRIVER"));
    }

    @Transactional
    public RideView arrived(UUID rideId, UUID driverId) {
        var r = lockForDriver(rideId, driverId);
        Double dist = (Double) r.get("dist_pickup");
        if (dist == null || dist > settings.getInt("rides.arrive_radius_m")) throw ApiException.conflict("not_at_pickup", "You are not close enough to the pickup point");
        sm.move(rideId, RideStatus.valueOf((String) r.get("status")), RideStatus.DRIVER_ARRIVED, "DRIVER:" + driverId, ", arrived_at=now()", null);
        notifier.notify((UUID) r.get("customer_id"), "DRIVER_ARRIVED", "ride-" + rideId + "-arrived", Map.of("rideId", rideId.toString(), "status", "DRIVER_ARRIVED"));
        return get(rideId, driverId, Set.of("DRIVER"));
    }

    @Transactional
    public RideView start(UUID rideId, UUID driverId) {
        var r = lockForDriver(rideId, driverId);
        sm.move(rideId, RideStatus.valueOf((String) r.get("status")), RideStatus.IN_PROGRESS, "DRIVER:" + driverId, ", started_at=now()", null);
        jdbc.sql("INSERT INTO ride_locations(ride_id, location) SELECT :r, location FROM driver_locations WHERE driver_id=:d").param("r", rideId).param("d", driverId).update();
        notifier.notify((UUID) r.get("customer_id"), "RIDE_STARTED", "ride-" + rideId + "-started", Map.of("rideId", rideId.toString(), "status", "IN_PROGRESS"));
        return get(rideId, driverId, Set.of("DRIVER"));
    }

    @Transactional
    public RideView complete(UUID rideId, UUID driverId) {
        var r = lockForDriver(rideId, driverId);
        RideStatus st = RideStatus.valueOf((String) r.get("status"));
        if (st != RideStatus.IN_PROGRESS) throw ApiException.conflict("invalid_transition", "Cannot change ride from " + st + " to COMPLETED");
        // Record the final position, then measure the real track.
        jdbc.sql("INSERT INTO ride_locations(ride_id, location) SELECT :r, location FROM driver_locations WHERE driver_id=:d").param("r", rideId).param("d", driverId).update();
        Integer trackM = jdbc.sql("""
                SELECT round(ST_Length(ST_MakeLine(location::geometry ORDER BY id)::geography))::int FROM ride_locations WHERE ride_id=:r HAVING count(*) >= 2""")
                .param("r", rideId).query(Integer.class).optional().orElse(null);
        int estDist = (Integer) r.get("est_distance_m"), estDur = (Integer) r.get("est_duration_s");
        int actualDist = trackM == null || trackM < 50 ? estDist : trackM;
        int actualDur = jdbc.sql("SELECT GREATEST(60, EXTRACT(EPOCH FROM (now() - started_at))::int) FROM rides WHERE id=:id").param("id", rideId).query(Integer.class).single();

        var rule = pricing.ruleById((UUID) r.get("pricing_rule_id"));
        var fare = pricing.compute(rule, actualDist, actualDur, null);
        BigDecimal cap = Money.roundUp(((BigDecimal) r.get("est_fare")).multiply(settings.getDecimal("rides.max_fare_over_estimate")), rule.roundingStep());
        if (fare.total().compareTo(cap) > 0) {      // protects riders from GPS drift / fraud; see docs/BUSINESS_RULES.md
            BigDecimal commission = Money.scale(cap.multiply(rule.commissionRate()));
            fare = new PricingService.Fare(fare.baseFare(), fare.distanceFare(), fare.timeFare(), fare.fees(), fare.discount(), fare.multiplier(), cap,
                    rule.commissionRate(), commission, cap.subtract(commission));
        }
        sm.move(rideId, st, RideStatus.COMPLETED, "DRIVER:" + driverId,
                ", completed_at=now(), final_fare=:ff, actual_distance_m=:ad, actual_duration_s=:adur", Map.of("ff", fare.total(), "ad", actualDist, "adur", actualDur));
        jdbc.sql("""
                INSERT INTO ride_fares(ride_id,base_fare,distance_fare,time_fare,fees,discount,multiplier,total,commission_rate,commission,driver_earnings)
                VALUES (:r,:b,:d,:t,:f,:di,:m,:tot,:cr,:c,:e)""")
                .param("r", rideId).param("b", fare.baseFare()).param("d", fare.distanceFare()).param("t", fare.timeFare()).param("f", fare.fees()).param("di", fare.discount())
                .param("m", fare.multiplier()).param("tot", fare.total()).param("cr", fare.commissionRate()).param("c", fare.commission()).param("e", fare.driverEarnings()).update();
        if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='BUSY'").param("d", driverId).update() == 1)
            jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'BUSY','ONLINE')").param("d", driverId).update();
        // Keep a simplified route (~5 m tolerance) permanently; raw points are purged after the retention window.
        jdbc.sql("UPDATE rides SET route_line = (SELECT ST_Simplify(ST_MakeLine(location::geometry ORDER BY id), 0.00005)::geography FROM ride_locations WHERE ride_id=:r HAVING count(*) >= 2) WHERE id=:r").param("r", rideId).update();
        payments.settleRideOnCompletion(rideId);
        risk.onRideCompleted(rideId);
        notifier.notify((UUID) r.get("customer_id"), "RIDE_COMPLETED", "ride-" + rideId + "-completed", Map.of("rideId", rideId.toString(), "status", "COMPLETED", "total", fare.total()));
        metrics.counter("jolay.rides.completed").increment();
        return get(rideId, driverId, Set.of("DRIVER"));
    }

    /** Driver cancels an assigned ride: the ride returns to the search queue and this driver is excluded. */
    @Transactional
    public void cancelByDriver(UUID rideId, UUID driverId, String reason) {
        var r = lockForDriver(rideId, driverId);
        RideStatus st = RideStatus.valueOf((String) r.get("status"));
        if (st == RideStatus.IN_PROGRESS || st.isTerminal()) throw ApiException.conflict("cannot_cancel", "Ride cannot be cancelled in its current state");
        sm.move(rideId, st, RideStatus.SEARCHING_DRIVER, "DRIVER:" + driverId, ", driver_id=NULL, vehicle_id=NULL, assigned_at=NULL, search_started_at=now()", null);
        if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='BUSY'").param("d", driverId).update() == 1)
            jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'BUSY','ONLINE')").param("d", driverId).update();
        notifier.notify((UUID) r.get("customer_id"), "DRIVER_CANCELLED", "ride-" + rideId + "-drvcancel-" + driverId, Map.of("rideId", rideId.toString(), "status", "SEARCHING_DRIVER"));
        risk.onDriverCancel(driverId);
        metrics.counter("jolay.rides.cancelled", "by", "driver").increment();
        dispatch.dispatchRound(rideId);
    }

    // ---------------- rating ----------------
    @Transactional
    public void rate(UUID rideId, UUID customerId, RatingRequest r) {
        var ride = jdbc.sql("SELECT customer_id, driver_id, status FROM rides WHERE id=:id").param("id", rideId).query().listOfRows().stream().findFirst().orElse(null);
        if (ride == null || !customerId.equals(ride.get("customer_id"))) throw ApiException.notFound("ride_not_found", "Ride not found");
        if (!"COMPLETED".equals(ride.get("status"))) throw ApiException.conflict("ride_not_completed", "Only completed rides can be rated");
        UUID driver = (UUID) ride.get("driver_id");
        try {
            jdbc.sql("INSERT INTO ratings(ride_id,from_user_id,to_user_id,stars,tags,comment) VALUES (:r,:f,:t,:s,:tags,:c)")
                    .param("r", rideId).param("f", customerId).param("t", driver).param("s", r.stars())
                    .param("tags", r.tags() == null ? null : String.join(",", r.tags())).param("c", r.comment()).update();
        } catch (DuplicateKeyException e) { throw ApiException.conflict("already_rated", "Ride already rated"); }
        jdbc.sql("""
                UPDATE drivers SET rating_count=rating_count+1,
                  rating_avg = round(((rating_avg*rating_count)+:s)::numeric/(rating_count+1), 2) WHERE user_id=:d""")
                .param("s", r.stars()).param("d", driver).update();
    }
}
