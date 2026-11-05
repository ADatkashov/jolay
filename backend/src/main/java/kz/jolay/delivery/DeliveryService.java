package kz.jolay.delivery;

import kz.jolay.common.*;
import kz.jolay.geography.EstimatedRouteProvider;
import kz.jolay.geography.GeoService;
import kz.jolay.geography.RouteProvider;
import kz.jolay.identity.AuthService;
import kz.jolay.marketplace.StoreSettlement;
import kz.jolay.notifications.Notifier;
import kz.jolay.wallet.LedgerService;
import kz.jolay.wallet.LedgerService.Leg;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.SecureRandom;
import java.util.*;

@Service
public class DeliveryService {
    private static final SecureRandom RNG = new SecureRandom();
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private final JdbcClient jdbc;
    private final GeoService geo;
    private final RouteProvider routes;
    private final DeliveryStateMachine sm;
    private final DeliveryDispatchService dispatch;
    private final LedgerService ledger;
    private final Notifier notifier;
    private final AppSettings settings;
    private final CodeAttempts attempts;
    private final StoreSettlement storeSettlement;
    static final int MAX_CODE_ATTEMPTS = 5;

    public DeliveryService(JdbcClient jdbc, GeoService geo, RouteProvider routes, DeliveryStateMachine sm, DeliveryDispatchService dispatch, LedgerService ledger, Notifier notifier, AppSettings settings, CodeAttempts attempts, StoreSettlement storeSettlement) {
        this.attempts = attempts; this.storeSettlement = storeSettlement;
        this.jdbc = jdbc; this.geo = geo; this.routes = routes; this.sm = sm; this.dispatch = dispatch; this.ledger = ledger; this.notifier = notifier; this.settings = settings;
    }

    public record Quote(UUID cityId, int distanceM, int durationS, String routeSource, BigDecimal base, BigDecimal distanceFare, BigDecimal weightFare, BigDecimal fee,
                        BigDecimal commission, BigDecimal courierEarnings, String sizeClass) {}

    // ---------------- pricing ----------------
    public Quote quote(GeoPoint from, GeoPoint to, String sizeClass, BigDecimal weightKg) {
        UUID city = geo.cityFor(from, "pickup_out_of_zone");
        if (!city.equals(geo.cityFor(to, "dropoff_out_of_zone"))) throw ApiException.badRequest("intercity_unsupported", "Pickup and drop-off must be in the same city");
        var t = jdbc.sql("SELECT * FROM delivery_tariffs WHERE city_id=:c AND size_class=:s AND active").param("c", city).param("s", sizeClass).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.badRequest("size_unavailable", "This parcel size is not available"));
        if (weightKg.compareTo((BigDecimal) t.get("max_kg")) > 0) throw ApiException.badRequest("parcel_too_heavy", "Parcel exceeds the maximum weight for this size");
        var route = routes.route(from, to);
        if (route.distanceM() < 100) throw ApiException.badRequest("trip_too_short", "Pickup and drop-off are too close");
        if (route.distanceM() > settings.getInt("delivery.max_distance_m")) throw ApiException.badRequest("distance_too_long", "Distance exceeds the delivery limit");
        BigDecimal km = BigDecimal.valueOf(route.distanceM()).divide(BigDecimal.valueOf(1000), 4, RoundingMode.HALF_UP);
        BigDecimal base = Money.scale((BigDecimal) t.get("base_fare"));
        BigDecimal dist = Money.scale(((BigDecimal) t.get("per_km")).multiply(km));
        BigDecimal extra = weightKg.subtract((BigDecimal) t.get("free_kg")).max(BigDecimal.ZERO);
        BigDecimal weightFare = Money.scale(((BigDecimal) t.get("per_extra_kg")).multiply(extra));
        BigDecimal raw = base.add(dist).add(weightFare).max((BigDecimal) t.get("min_fare"));
        BigDecimal fee = Money.roundUp(raw, (BigDecimal) t.get("rounding_step"));
        BigDecimal commission = Money.scale(fee.multiply((BigDecimal) t.get("commission_rate")));
        return new Quote(city, route.distanceM(), route.durationS(), route.source(), base, dist, weightFare, fee, commission, fee.subtract(commission), sizeClass);
    }

    public Map<String, Object> estimate(GeoPoint from, GeoPoint to, String sizeClass, BigDecimal weight) {
        Quote q = quote(from, to, sizeClass, weight);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("distanceM", q.distanceM()); m.put("durationS", q.durationS()); m.put("routeSource", q.routeSource());
        m.put("fee", Map.of("base", q.base(), "distance", q.distanceFare(), "weight", q.weightFare(), "total", q.fee(), "currency", "KZT"));
        m.put("courierAvailable", nearestCourier(q.cityId(), from));
        return m;
    }

    private boolean nearestCourier(UUID city, GeoPoint p) {
        return jdbc.sql("""
                SELECT count(*) > 0 FROM (SELECT dl.driver_id FROM driver_locations dl JOIN drivers d ON d.user_id=dl.driver_id
                WHERE d.city_id=:c AND d.verification='APPROVED' AND d.availability='ONLINE' AND d.accepts_delivery AND dl.updated_at > now() - make_interval(secs => :age)
                  AND ST_DWithin(dl.location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, :r) LIMIT 1) x""")
                .param("c", city).param("age", settings.getInt("dispatch.location_max_age_seconds")).param("lng", p.lng()).param("lat", p.lat()).param("r", settings.getInt("dispatch.max_radius_m")).query(Boolean.class).single();
    }

    // ---------------- create ----------------
    public record Party(String name, String phone) {}

    @Transactional
    public Map<String, Object> create(UUID customerId, GeoPoint pickup, String pickupAddr, GeoPoint dropoff, String dropAddr, String sizeClass, BigDecimal weight, String description,
                                      Party sender, Party recipient, String payment, String idemKey) {
        if (idemKey != null) {
            var ex = jdbc.sql("SELECT id FROM delivery_orders WHERE customer_id=:c AND idempotency_key=:k").param("c", customerId).param("k", idemKey).query(UUID.class).optional();
            if (ex.isPresent()) return view(ex.get(), customerId, Set.of("CUSTOMER"));
        }
        Quote q = quote(pickup, dropoff, sizeClass, weight);
        if ("WALLET".equals(payment) && ledger.balance(ledger.userAccount(customerId, "CUSTOMER_WALLET")).compareTo(q.fee()) < 0)
            throw ApiException.conflict("insufficient_funds", "Wallet balance is lower than the delivery fee");
        String sp = AuthService.normalizePhone(sender.phone()), rp = AuthService.normalizePhone(recipient.phone());
        String tracking = "JL" + randomChars(8), code = String.format("%04d", RNG.nextInt(10000));
        UUID id = jdbc.sql("""
                INSERT INTO delivery_orders(tracking_number,customer_id,city_id,status,size_class,weight_kg,parcel_description,pickup_address,pickup,dropoff_address,dropoff,
                    sender_name,sender_phone,recipient_name,recipient_phone,est_distance_m,est_duration_s,fee,commission,courier_earnings,payment_method,handover_code,idempotency_key)
                VALUES (:tn,:c,:city,'SEARCHING_COURIER',:sc,:w,:d,:pa,ST_SetSRID(ST_MakePoint(:plng,:plat),4326)::geography,:da,ST_SetSRID(ST_MakePoint(:dlng,:dlat),4326)::geography,
                    :sn,:sp,:rn,:rp,:dist,:dur,:fee,:com,:earn,:pm,:code,:idem) RETURNING id""")
                .param("tn", tracking).param("c", customerId).param("city", q.cityId()).param("sc", sizeClass).param("w", weight).param("d", description)
                .param("pa", blank(pickupAddr) ? geo.reverse(pickup) : pickupAddr.trim()).param("plng", pickup.lng()).param("plat", pickup.lat())
                .param("da", blank(dropAddr) ? geo.reverse(dropoff) : dropAddr.trim()).param("dlng", dropoff.lng()).param("dlat", dropoff.lat())
                .param("sn", sender.name().trim()).param("sp", sp).param("rn", recipient.name().trim()).param("rp", rp)
                .param("dist", q.distanceM()).param("dur", q.durationS()).param("fee", q.fee()).param("com", q.commission()).param("earn", q.courierEarnings())
                .param("pm", payment).param("code", code).param("idem", idemKey).query(UUID.class).single();
        jdbc.sql("INSERT INTO delivery_status_history(delivery_id,from_status,to_status,actor) VALUES (:d,NULL,'SEARCHING_COURIER',:a)").param("d", id).param("a", "CUSTOMER:" + customerId).update();
        dispatch.dispatchRound(id);
        return view(id, customerId, Set.of("CUSTOMER"));
    }

    private static boolean blank(String s) { return s == null || s.isBlank(); }
    private static String randomChars(int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(ALPHABET.charAt(RNG.nextInt(ALPHABET.length()))); return b.toString(); }

    // ---------------- read ----------------
    public Map<String, Object> view(UUID id, UUID viewer, Set<String> roles) {
        var m = jdbc.sql("""
                SELECT o.*, ST_X(o.pickup::geometry) plng, ST_Y(o.pickup::geometry) plat, ST_X(o.dropoff::geometry) dlng, ST_Y(o.dropoff::geometry) dlat,
                       cu.full_name AS customer_name, du.full_name AS courier_name, du.phone AS courier_phone, v.brand, v.model, v.plate, d.rating_avg,
                       ST_Y(dl.location::geometry) clat, ST_X(dl.location::geometry) clng,
                       (SELECT stars FROM delivery_ratings r WHERE r.delivery_id=o.id AND r.from_user_id=o.customer_id) AS stars
                FROM delivery_orders o JOIN users cu ON cu.id=o.customer_id LEFT JOIN users du ON du.id=o.courier_id LEFT JOIN drivers d ON d.user_id=o.courier_id
                LEFT JOIN vehicles v ON v.driver_id=o.courier_id AND v.active LEFT JOIN driver_locations dl ON dl.driver_id=o.courier_id WHERE o.id=:id""")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> ApiException.notFound("delivery_not_found", "Delivery not found"));
        boolean admin = roles.stream().anyMatch(x -> x.endsWith("_ADMIN") || x.equals("SUPPORT_AGENT"));
        boolean customer = viewer.equals(m.get("customer_id")), courier = viewer.equals(m.get("courier_id"));
        if (!admin && !customer && !courier) throw ApiException.notFound("delivery_not_found", "Delivery not found");
        String status = (String) m.get("status");
        boolean live = "COURIER_ASSIGNED".equals(status) || "PICKED_UP".equals(status);
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", m.get("id")); v.put("trackingNumber", m.get("tracking_number")); v.put("status", status); v.put("sizeClass", m.get("size_class")); v.put("weightKg", m.get("weight_kg"));
        v.put("parcelDescription", m.get("parcel_description"));
        v.put("pickupAddress", m.get("pickup_address")); v.put("pickup", Map.of("lat", m.get("plat"), "lng", m.get("plng")));
        v.put("dropoffAddress", m.get("dropoff_address")); v.put("dropoff", Map.of("lat", m.get("dlat"), "lng", m.get("dlng")));
        v.put("senderName", m.get("sender_name")); v.put("recipientName", m.get("recipient_name"));
        // phone numbers and the handover code are shown only to the parties who need them
        if (customer || admin || (courier && live)) { v.put("senderPhone", m.get("sender_phone")); v.put("recipientPhone", m.get("recipient_phone")); }
        if (customer && !DeliveryStatus.valueOf(status).isTerminal()) v.put("handoverCode", m.get("handover_code"));
        v.put("distanceM", m.get("est_distance_m")); v.put("durationS", m.get("est_duration_s")); v.put("fee", m.get("fee"));
        v.put("courierEarnings", courier || admin ? m.get("courier_earnings") : null);
        v.put("paymentMethod", m.get("payment_method")); v.put("paymentStatus", m.get("payment_status"));
        if ("STORE_CASH".equals(m.get("payment_method")) && (courier || admin))   // the courier must know how much to collect
            v.put("cashToCollect", jdbc.sql("SELECT items_total + delivery_fee FROM store_orders WHERE id=:s").param("s", m.get("store_order_id")).query(BigDecimal.class).optional().orElse(null));
        v.put("customerName", m.get("customer_name")); v.put("createdAt", m.get("created_at")); v.put("deliveredAt", m.get("delivered_at"));
        v.put("rating", m.get("stars"));
        if (m.get("courier_id") != null)
            v.put("courier", Map.of("name", String.valueOf(m.get("courier_name")), "phone", live || admin ? String.valueOf(m.get("courier_phone")) : "", "rating", m.get("rating_avg"),
                    "vehicle", m.get("brand") + " " + m.get("model"), "plate", String.valueOf(m.get("plate")), "lat", live ? m.get("clat") : "", "lng", live ? m.get("clng") : ""));
        v.values().removeIf(Objects::isNull);
        return v;
    }

    public List<Map<String, Object>> history(UUID userId, boolean courier, String tab, int limit, int offset) {
        String st = switch (tab == null ? "completed" : tab) { case "ongoing" -> "('SEARCHING_COURIER','COURIER_ASSIGNED','PICKED_UP')"; case "cancelled" -> "('CANCELLED','EXPIRED','FAILED')"; default -> "('DELIVERED')"; };
        List<UUID> ids = jdbc.sql("SELECT id FROM delivery_orders WHERE " + (courier ? "courier_id" : "customer_id") + "=:u AND status IN " + st + " ORDER BY created_at DESC LIMIT :l OFFSET :o")
                .param("u", userId).param("l", Math.min(limit, 100)).param("o", offset).query(UUID.class).list();
        return ids.stream().map(i -> view(i, userId, Set.of(courier ? "DRIVER" : "CUSTOMER"))).toList();
    }

    public Optional<Map<String, Object>> activeForCourier(UUID courierId) {
        return jdbc.sql("SELECT id FROM delivery_orders WHERE courier_id=:c AND status IN ('COURIER_ASSIGNED','PICKED_UP')").param("c", courierId).query(UUID.class).optional().map(i -> view(i, courierId, Set.of("DRIVER")));
    }

    /** Public tracking by tracking number: status and timestamps only, no names, phones or addresses. */
    public Map<String, Object> publicTrack(String number) {
        return jdbc.sql("SELECT tracking_number, status, created_at, picked_up_at, delivered_at FROM delivery_orders WHERE tracking_number=:n").param("n", number.toUpperCase()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("tracking_not_found", "Tracking number not found"));
    }

    // ---------------- customer actions ----------------
    @Transactional
    public Map<String, Object> cancelByCustomer(UUID id, UUID customerId, String reason) {
        var d = jdbc.sql("SELECT status, customer_id, courier_id, store_order_id FROM delivery_orders WHERE id=:id FOR UPDATE").param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (d == null || !customerId.equals(d.get("customer_id"))) throw ApiException.notFound("delivery_not_found", "Delivery not found");
        if (d.get("store_order_id") != null) throw ApiException.conflict("cancel_via_store_order", "This delivery belongs to a store order. Cancel or contact support through the order");
        DeliveryStatus st = DeliveryStatus.valueOf((String) d.get("status"));
        if (st == DeliveryStatus.PICKED_UP || st.isTerminal()) throw ApiException.conflict("cannot_cancel", "The parcel is already on its way or the order is finished");
        sm.move(id, st, DeliveryStatus.CANCELLED, "CUSTOMER:" + customerId, ", cancelled_at=now(), cancelled_by='CUSTOMER', cancel_reason=:r", Map.of("r", reason == null ? "customer_cancelled" : reason));
        dispatch.cancelOffers(id);
        UUID courier = (UUID) d.get("courier_id");
        if (courier != null) {
            freeCourier(courier);
            notifier.notify(courier, "DELIVERY_STATUS", "delivery-" + id + "-cancelled", Map.of("deliveryId", id.toString(), "status", "CANCELLED"));
        }
        return view(id, customerId, Set.of("CUSTOMER"));
    }

    @Transactional
    public void rate(UUID id, UUID customerId, int stars, String comment) {
        var d = jdbc.sql("SELECT customer_id, courier_id, status FROM delivery_orders WHERE id=:id").param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (d == null || !customerId.equals(d.get("customer_id"))) throw ApiException.notFound("delivery_not_found", "Delivery not found");
        if (!"DELIVERED".equals(d.get("status"))) throw ApiException.conflict("delivery_not_completed", "Only delivered orders can be rated");
        try { jdbc.sql("INSERT INTO delivery_ratings(delivery_id,from_user_id,to_user_id,stars,comment) VALUES (:i,:f,:t,:s,:c)").param("i", id).param("f", customerId).param("t", d.get("courier_id")).param("s", stars).param("c", comment).update(); }
        catch (DuplicateKeyException e) { throw ApiException.conflict("already_rated", "Already rated"); }
        jdbc.sql("UPDATE drivers SET rating_count=rating_count+1, rating_avg = round(((rating_avg*rating_count)+:s)::numeric/(rating_count+1), 2) WHERE user_id=:d").param("s", stars).param("d", d.get("courier_id")).update();
    }

    // ---------------- courier actions ----------------
    private Map<String, Object> lockFor(UUID id, UUID courierId) {
        var d = jdbc.sql("""
                SELECT id, status, customer_id, courier_id, handover_code, payment_method, store_order_id, fee, commission, courier_earnings,
                       ST_Distance(pickup,  (SELECT location FROM driver_locations WHERE driver_id=:c)) AS dist_pickup,
                       ST_Distance(dropoff, (SELECT location FROM driver_locations WHERE driver_id=:c)) AS dist_drop
                FROM delivery_orders WHERE id=:id FOR NO KEY UPDATE""").param("id", id).param("c", courierId).query().listOfRows().stream().findFirst().orElse(null);
        if (d == null || !courierId.equals(d.get("courier_id"))) throw ApiException.notFound("delivery_not_found", "Delivery not found");
        return d;
    }

    @Transactional
    public Map<String, Object> pickedUp(UUID id, UUID courierId) {
        var d = lockFor(id, courierId);
        Double dist = (Double) d.get("dist_pickup");
        if (dist == null || dist > settings.getInt("delivery.arrive_radius_m")) throw ApiException.conflict("not_at_pickup", "You are not close enough to the pickup point");
        sm.move(id, DeliveryStatus.valueOf((String) d.get("status")), DeliveryStatus.PICKED_UP, "COURIER:" + courierId, ", picked_up_at=now()", null);
        notifier.notify((UUID) d.get("customer_id"), "DELIVERY_STATUS", "delivery-" + id + "-pickedup", Map.of("deliveryId", id.toString(), "status", "PICKED_UP"));
        return view(id, courierId, Set.of("DRIVER"));
    }

    /** Completes the delivery. The recipient's 4-digit code (shown only to the customer) must match: protects against false "delivered" claims. */
    @Transactional
    public Map<String, Object> deliver(UUID id, UUID courierId, String code) {
        var d = lockFor(id, courierId);
        DeliveryStatus st = DeliveryStatus.valueOf((String) d.get("status"));
        if (st != DeliveryStatus.PICKED_UP) throw ApiException.conflict("invalid_transition", "Cannot change delivery from " + st + " to DELIVERED");
        Double dist = (Double) d.get("dist_drop");
        if (dist == null || dist > settings.getInt("delivery.arrive_radius_m")) throw ApiException.conflict("not_at_dropoff", "You are not close enough to the drop-off point");
        if (attempts.count(id) >= MAX_CODE_ATTEMPTS)
            throw ApiException.forbidden("handover_locked", "Too many wrong codes. Contact JOLAY support");
        if (code == null || !MessageDigestEq.eq(code, (String) d.get("handover_code"))) {
            attempts.recordFailure(id);     // committed in its own transaction, survives the rollback of this one
            throw ApiException.badRequest("invalid_handover_code", "The handover code is incorrect");
        }
        sm.move(id, st, DeliveryStatus.DELIVERED, "COURIER:" + courierId, ", delivered_at=now()", null);
        freeCourier(courierId);
        settlePayment(id, d);
        notifier.notify((UUID) d.get("customer_id"), "DELIVERY_STATUS", "delivery-" + id + "-delivered", Map.of("deliveryId", id.toString(), "status", "DELIVERED"));
        return view(id, courierId, Set.of("DRIVER"));
    }

    private void settlePayment(UUID id, Map<String, Object> d) {
        UUID courierId = (UUID) d.get("courier_id"), customer = (UUID) d.get("customer_id");
        BigDecimal fee = (BigDecimal) d.get("fee"), commission = (BigDecimal) d.get("commission"), earnings = (BigDecimal) d.get("courier_earnings");
        if ("PREPAID".equals(d.get("payment_method"))) {      // store order: the escrow is split between partner, courier and platform
            storeSettlement.settleDelivered((UUID) d.get("store_order_id"), courierId);
            return;
        }
        if ("STORE_CASH".equals(d.get("payment_method"))) {   // store order paid in cash: the courier collected the total
            storeSettlement.settleDeliveredCash((UUID) d.get("store_order_id"), courierId);
            jdbc.sql("UPDATE delivery_orders SET payment_status='PAID' WHERE id=:id").param("id", id).update();
            return;
        }
        UUID cAcc = ledger.userAccount(courierId, "DRIVER_WALLET");
        if ("CASH".equals(d.get("payment_method"))) {
            if (commission.signum() > 0) ledger.post("CASH_COMMISSION", "DELIVERY", id, "delivery-cash-" + id, "Commission on cash delivery", List.of(new Leg(cAcc, commission.negate()), new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission)));
            jdbc.sql("UPDATE delivery_orders SET payment_status='PAID' WHERE id=:id").param("id", id).update();
            return;
        }
        try {
            List<Leg> legs = new ArrayList<>(List.of(new Leg(ledger.userAccount(customer, "CUSTOMER_WALLET"), fee.negate()), new Leg(cAcc, earnings)));
            if (commission.signum() > 0) legs.add(new Leg(ledger.systemAccount("PLATFORM_REVENUE"), commission));
            ledger.post("RIDE_PAYMENT", "DELIVERY", id, "delivery-pay-" + id, "Delivery payment (wallet)", legs);
            jdbc.sql("UPDATE delivery_orders SET payment_status='PAID' WHERE id=:id").param("id", id).update();
        } catch (ApiException e) {
            if (!"insufficient_funds".equals(e.code())) throw e;
            jdbc.sql("UPDATE delivery_orders SET payment_status='FAILED' WHERE id=:id").param("id", id).update();
            notifier.notify(customer, "PAYMENT_STATUS_UPDATED", "delivery-pay-failed-" + id, Map.of("deliveryId", id.toString(), "paymentStatus", "FAILED", "reason", "insufficient_funds"));
        }
    }

    /** Courier gives the order back: it returns to the search queue and this courier is not offered it again. */
    @Transactional
    public void cancelByCourier(UUID id, UUID courierId, String reason) {
        var d = lockFor(id, courierId);
        DeliveryStatus st = DeliveryStatus.valueOf((String) d.get("status"));
        if (st != DeliveryStatus.COURIER_ASSIGNED) throw ApiException.conflict("cannot_cancel", "The parcel is already picked up");
        sm.move(id, st, DeliveryStatus.SEARCHING_COURIER, "COURIER:" + courierId, ", courier_id=NULL, assigned_at=NULL, search_started_at=now()", null);
        freeCourier(courierId);
        notifier.notify((UUID) d.get("customer_id"), "DELIVERY_STATUS", "delivery-" + id + "-recourier-" + courierId, Map.of("deliveryId", id.toString(), "status", "SEARCHING_COURIER"));
        dispatch.dispatchRound(id);
    }

    private void freeCourier(UUID courierId) {
        if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='BUSY'").param("d", courierId).update() == 1)
            jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'BUSY','ONLINE')").param("d", courierId).update();
    }

    public Map<String, Object> currentOffer(UUID courierId) {
        var o = jdbc.sql("""
                SELECT o.id AS offer_id, o.delivery_id, o.pickup_distance_m, o.expected_earnings, EXTRACT(EPOCH FROM (o.expires_at - now()))::int AS seconds_left,
                       d.pickup_address, d.dropoff_address, d.est_distance_m, d.size_class, d.weight_kg, d.parcel_description, d.payment_method,
                       ST_Y(d.pickup::geometry) plat, ST_X(d.pickup::geometry) plng, ST_Y(d.dropoff::geometry) dlat, ST_X(d.dropoff::geometry) dlng
                FROM delivery_offers o JOIN delivery_orders d ON d.id=o.delivery_id WHERE o.courier_id=:c AND o.status='OFFERED' AND o.expires_at > now()""").param("c", courierId).query().listOfRows();
        return o.isEmpty() ? null : o.get(0);
    }

    /** Constant-time comparison for short secrets. */
    static final class MessageDigestEq {
        static boolean eq(String a, String b) { return java.security.MessageDigest.isEqual(a.getBytes(java.nio.charset.StandardCharsets.UTF_8), b.getBytes(java.nio.charset.StandardCharsets.UTF_8)); }
    }
}
