package kz.jolay.marketplace;

import kz.jolay.common.*;
import kz.jolay.delivery.DeliveryDispatchService;
import kz.jolay.delivery.DeliveryService;
import kz.jolay.identity.AuthService;
import kz.jolay.notifications.Notifier;
import kz.jolay.wallet.LedgerService;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.util.*;

@Service
public class StoreOrderService {
    private static final SecureRandom RNG = new SecureRandom();
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private final JdbcClient jdbc;
    private final DeliveryService deliveries;
    private final DeliveryDispatchService dispatch;
    private final StoreSettlement settlement;
    private final LedgerService ledger;
    private final Notifier notifier;
    private final AppSettings settings;

    public StoreOrderService(JdbcClient jdbc, DeliveryService deliveries, DeliveryDispatchService dispatch, StoreSettlement settlement, LedgerService ledger, Notifier notifier, AppSettings settings) {
        this.jdbc = jdbc; this.deliveries = deliveries; this.dispatch = dispatch; this.settlement = settlement; this.ledger = ledger; this.notifier = notifier; this.settings = settings;
    }

    public record Line(UUID productId, int quantity) {}

    @Transactional
    public Map<String, Object> place(UUID customerId, UUID storeId, List<Line> lines, GeoPoint dropoff, String dropAddr, String recipientName, String recipientPhone, String note, String idemKey) {
        if (idemKey != null) {
            var ex = jdbc.sql("SELECT id FROM store_orders WHERE customer_id=:c AND idempotency_key=:k").param("c", customerId).param("k", idemKey).query(UUID.class).optional();
            if (ex.isPresent()) return view(ex.get(), customerId, Set.of("CUSTOMER"));
        }
        var store = jdbc.sql("""
                SELECT s.id, s.name, s.accepting_orders, s.active, s.partner_id, p.status AS pstatus, p.commission_rate, s.address, ST_X(s.location::geometry) lng, ST_Y(s.location::geometry) lat
                FROM stores s JOIN partners p ON p.id=s.partner_id WHERE s.id=:id""").param("id", storeId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("store_not_found", "Store not found"));
        if (!(Boolean) store.get("active") || !"APPROVED".equals(store.get("pstatus"))) throw ApiException.notFound("store_not_found", "Store not found");
        if (!(Boolean) store.get("accepting_orders")) throw ApiException.conflict("store_closed", "The store is not accepting orders right now");
        if (lines == null || lines.isEmpty() || lines.size() > settings.getInt("marketplace.max_items")) throw ApiException.badRequest("invalid_items", "Invalid items");

        Map<UUID, Integer> qty = new LinkedHashMap<>();
        for (Line l : lines) qty.merge(l.productId(), l.quantity(), Integer::sum);
        BigDecimal itemsTotal = BigDecimal.ZERO;
        List<Map<String, Object>> snap = new ArrayList<>();
        for (var e : qty.entrySet()) {
            if (e.getValue() < 1 || e.getValue() > 50) throw ApiException.badRequest("invalid_items", "Invalid quantity");
            var p = jdbc.sql("SELECT id, name, price, available FROM products WHERE id=:id AND store_id=:s AND deleted_at IS NULL").param("id", e.getKey()).param("s", storeId).query().listOfRows().stream().findFirst()
                    .orElseThrow(() -> ApiException.badRequest("product_not_found", "A product is not part of this store"));
            if (!(Boolean) p.get("available")) throw ApiException.conflict("product_unavailable", "\"" + p.get("name") + "\" is not available");
            itemsTotal = itemsTotal.add(((BigDecimal) p.get("price")).multiply(BigDecimal.valueOf(e.getValue())));
            snap.add(Map.of("id", p.get("id"), "name", p.get("name"), "price", p.get("price"), "qty", e.getValue()));
        }
        itemsTotal = Money.scale(itemsTotal);

        GeoPoint from = new GeoPoint((Double) store.get("lat"), (Double) store.get("lng"));
        var quote = deliveries.quote(from, dropoff, "MEDIUM", new BigDecimal("3.0"));
        if (quote.distanceM() > settings.getInt("marketplace.max_distance_m")) throw ApiException.badRequest("too_far", "The store does not deliver to this address");
        BigDecimal courierEarnings = Money.scale(quote.fee().multiply(settings.getDecimal("marketplace.delivery_courier_share")));
        BigDecimal platformCut = quote.fee().subtract(courierEarnings);
        BigDecimal partnerCommission = Money.scale(itemsTotal.multiply((BigDecimal) store.get("commission_rate")));
        BigDecimal total = itemsTotal.add(quote.fee());
        if (ledger.balance(ledger.userAccount(customerId, "CUSTOMER_WALLET")).compareTo(total) < 0) throw ApiException.conflict("insufficient_funds", "Wallet balance is lower than the order total");

        String number = "S" + randomDigits(6);
        UUID id;
        try {
            id = jdbc.sql("""
                    INSERT INTO store_orders(number,customer_id,store_id,partner_id,status,items_total,delivery_fee,partner_commission,delivery_courier_earnings,delivery_platform_cut,
                        dropoff_address,dropoff,recipient_name,recipient_phone,note,idempotency_key)
                    VALUES (:n,:c,:s,:p,'PLACED',:it,:df,:pc,:ce,:pl,:da,ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography,:rn,:rp,:note,:idem) RETURNING id""")
                    .param("n", number).param("c", customerId).param("s", storeId).param("p", store.get("partner_id")).param("it", itemsTotal).param("df", quote.fee()).param("pc", partnerCommission)
                    .param("ce", courierEarnings).param("pl", platformCut).param("da", dropAddr == null || dropAddr.isBlank() ? "—" : dropAddr.trim()).param("lng", dropoff.lng()).param("lat", dropoff.lat())
                    .param("rn", recipientName.trim()).param("rp", AuthService.normalizePhone(recipientPhone)).param("note", note).param("idem", idemKey).query(UUID.class).single();
        } catch (DuplicateKeyException e) { throw ApiException.conflict("conflict", "Please retry"); }
        for (var s : snap)
            jdbc.sql("INSERT INTO store_order_items(order_id,product_id,name,unit_price,quantity) VALUES (:o,:p,:n,:u,:q)").param("o", id).param("p", s.get("id")).param("n", s.get("name")).param("u", s.get("price")).param("q", s.get("qty")).update();
        settlement.hold(id, customerId, total);
        UUID partnerUser = jdbc.sql("SELECT owner_id FROM partners WHERE id=:p").param("p", store.get("partner_id")).query(UUID.class).single();
        notifier.notify(partnerUser, "STORE_ORDER_NEW", "store-order-" + id + "-new", Map.of("orderId", id.toString(), "number", number));
        return view(id, customerId, Set.of("CUSTOMER"));
    }

    private static String randomDigits(int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(RNG.nextInt(10)); return b.toString(); }
    private static String randomChars(int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(ALPHABET.charAt(RNG.nextInt(ALPHABET.length()))); return b.toString(); }

    // ---------------- views ----------------
    public Map<String, Object> view(UUID id, UUID viewer, Set<String> roles) {
        var o = jdbc.sql("""
                SELECT o.*, s.name AS store_name, s.address AS store_address, s.phone AS store_phone, p.owner_id AS partner_user, cu.full_name AS customer_name,
                       ST_Y(o.dropoff::geometry) dlat, ST_X(o.dropoff::geometry) dlng
                FROM store_orders o JOIN stores s ON s.id=o.store_id JOIN partners p ON p.id=o.partner_id JOIN users cu ON cu.id=o.customer_id WHERE o.id=:id""").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("order_not_found", "Order not found"));
        boolean admin = roles.stream().anyMatch(r -> r.endsWith("_ADMIN") || r.equals("SUPPORT_AGENT"));
        boolean customer = viewer.equals(o.get("customer_id")), partner = viewer.equals(o.get("partner_user"));
        if (!admin && !customer && !partner) throw ApiException.notFound("order_not_found", "Order not found");
        Map<String, Object> v = new LinkedHashMap<>();
        v.put("id", o.get("id")); v.put("number", o.get("number")); v.put("status", o.get("status"));
        v.put("storeName", o.get("store_name")); v.put("storeAddress", o.get("store_address"));
        v.put("itemsTotal", o.get("items_total")); v.put("deliveryFee", o.get("delivery_fee")); v.put("total", ((BigDecimal) o.get("items_total")).add((BigDecimal) o.get("delivery_fee")));
        v.put("dropoffAddress", o.get("dropoff_address")); v.put("dropoff", Map.of("lat", o.get("dlat"), "lng", o.get("dlng")));
        v.put("recipientName", o.get("recipient_name")); v.put("recipientPhone", o.get("recipient_phone")); v.put("note", o.get("note")); v.put("rejectReason", o.get("reject_reason"));
        v.put("createdAt", o.get("created_at"));
        v.put("items", jdbc.sql("SELECT product_id, name, unit_price, quantity FROM store_order_items WHERE order_id=:o ORDER BY id").param("o", id).query().listOfRows());
        if (partner || admin) { v.put("partnerCommission", o.get("partner_commission")); v.put("partnerNet", ((BigDecimal) o.get("items_total")).subtract((BigDecimal) o.get("partner_commission"))); v.put("customerName", o.get("customer_name")); }
        var d = jdbc.sql("SELECT id, status FROM delivery_orders WHERE store_order_id=:o").param("o", id).query().listOfRows().stream().findFirst();
        if (d.isPresent() && (customer || admin)) v.put("delivery", deliveries.view((UUID) d.get().get("id"), customer ? viewer : viewer, customer ? Set.of("CUSTOMER") : roles));
        else d.ifPresent(x -> v.put("deliveryStatus", x.get("status")));
        v.values().removeIf(Objects::isNull);
        return v;
    }

    public List<Map<String, Object>> history(UUID customerId, String tab) {
        String st = switch (tab == null ? "ongoing" : tab) { case "done" -> "('COMPLETED')"; case "closed" -> "('REJECTED','CANCELLED','FAILED')"; default -> "('PLACED','ACCEPTED','READY')"; };
        return jdbc.sql("SELECT id FROM store_orders WHERE customer_id=:c AND status IN " + st + " ORDER BY created_at DESC LIMIT 50").param("c", customerId).query(UUID.class).list().stream().map(i -> view(i, customerId, Set.of("CUSTOMER"))).toList();
    }

    // ---------------- actions ----------------
    @Transactional
    public Map<String, Object> cancelByCustomer(UUID id, UUID customerId) {
        var o = jdbc.sql("SELECT customer_id, status FROM store_orders WHERE id=:id FOR UPDATE").param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (o == null || !customerId.equals(o.get("customer_id"))) throw ApiException.notFound("order_not_found", "Order not found");
        if (!"PLACED".equals(o.get("status"))) throw ApiException.conflict("cannot_cancel", "The store has already accepted this order. Contact support to cancel it");
        settlement.refundAndClose(id, "CANCELLED", "customer_cancelled");
        return view(id, customerId, Set.of("CUSTOMER"));
    }

    private Map<String, Object> lockForPartner(UUID id, UUID partnerUser) {
        var o = jdbc.sql("SELECT o.id, o.status, o.customer_id, p.owner_id FROM store_orders o JOIN partners p ON p.id=o.partner_id WHERE o.id=:id FOR UPDATE OF o").param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (o == null || !partnerUser.equals(o.get("owner_id"))) throw ApiException.notFound("order_not_found", "Order not found");
        return o;
    }

    @Transactional
    public Map<String, Object> accept(UUID id, UUID partnerUser) {
        var o = lockForPartner(id, partnerUser);
        if (!"PLACED".equals(o.get("status"))) throw ApiException.conflict("invalid_transition", "Order is not waiting for acceptance");
        jdbc.sql("UPDATE store_orders SET status='ACCEPTED', accepted_at=now(), updated_at=now() WHERE id=:id").param("id", id).update();
        notifier.notify((UUID) o.get("customer_id"), "STORE_ORDER_STATUS", "store-order-" + id + "-accepted", Map.of("orderId", id.toString(), "status", "ACCEPTED"));
        return view(id, partnerUser, Set.of("PARTNER"));
    }

    @Transactional
    public Map<String, Object> reject(UUID id, UUID partnerUser, String reason) {
        var o = lockForPartner(id, partnerUser);
        if (!"PLACED".equals(o.get("status"))) throw ApiException.conflict("invalid_transition", "Order is not waiting for acceptance");
        settlement.refundAndClose(id, "REJECTED", reason);
        return view(id, partnerUser, Set.of("PARTNER"));
    }

    /** The kitchen/shop finished: creates the delivery leg (pickup at the store, prepaid from escrow) and starts the courier search. */
    @Transactional
    public Map<String, Object> ready(UUID id, UUID partnerUser) {
        var o = lockForPartner(id, partnerUser);
        if (!"ACCEPTED".equals(o.get("status"))) throw ApiException.conflict("invalid_transition", "Order must be accepted first");
        var d = jdbc.sql("""
                SELECT o.customer_id, o.number, o.delivery_fee, o.delivery_platform_cut, o.delivery_courier_earnings, o.dropoff_address, o.dropoff, o.recipient_name, o.recipient_phone, o.items_total,
                       s.name AS store_name, s.address AS store_address, s.location AS store_loc, s.city_id, COALESCE(s.phone,'+77000000000') AS store_phone
                FROM store_orders o JOIN stores s ON s.id=o.store_id WHERE o.id=:id""").param("id", id).query().listOfRows().get(0);
        String tracking = "JL" + randomChars(8), code = String.format("%04d", RNG.nextInt(10000));
        var from = jdbc.sql("SELECT ST_Y(s.location::geometry) lat, ST_X(s.location::geometry) lng, ST_Y(o.dropoff::geometry) dlat, ST_X(o.dropoff::geometry) dlng FROM store_orders o JOIN stores s ON s.id=o.store_id WHERE o.id=:id").param("id", id).query().listOfRows().get(0);
        var route = deliveries.quote(new GeoPoint((Double) from.get("lat"), (Double) from.get("lng")), new GeoPoint((Double) from.get("dlat"), (Double) from.get("dlng")), "MEDIUM", new BigDecimal("3.0"));
        UUID deliveryId = jdbc.sql("""
                INSERT INTO delivery_orders(tracking_number,customer_id,city_id,status,size_class,weight_kg,parcel_description,pickup_address,pickup,dropoff_address,dropoff,sender_name,sender_phone,recipient_name,recipient_phone,
                    est_distance_m,est_duration_s,fee,commission,courier_earnings,payment_method,payment_status,handover_code,store_order_id)
                VALUES (:tn,:c,:city,'SEARCHING_COURIER','MEDIUM',3.0,:desc,:pa,:ploc,:da,:dloc,:sn,:sp,:rn,:rp,:dist,:dur,:fee,:com,:earn,'PREPAID','PAID',:code,:so) RETURNING id""")
                .param("tn", tracking).param("c", d.get("customer_id")).param("city", d.get("city_id")).param("desc", "Order " + d.get("number") + " from " + d.get("store_name"))
                .param("pa", d.get("store_address")).param("ploc", d.get("store_loc")).param("da", d.get("dropoff_address")).param("dloc", d.get("dropoff"))
                .param("sn", d.get("store_name")).param("sp", d.get("store_phone")).param("rn", d.get("recipient_name")).param("rp", d.get("recipient_phone"))
                .param("dist", route.distanceM()).param("dur", route.durationS()).param("fee", d.get("delivery_fee")).param("com", d.get("delivery_platform_cut")).param("earn", d.get("delivery_courier_earnings"))
                .param("code", code).param("so", id).query(UUID.class).single();
        jdbc.sql("INSERT INTO delivery_status_history(delivery_id,from_status,to_status,actor) VALUES (:d,NULL,'SEARCHING_COURIER',:a)").param("d", deliveryId).param("a", "PARTNER:" + partnerUser).update();
        jdbc.sql("UPDATE store_orders SET status='READY', ready_at=now(), updated_at=now() WHERE id=:id").param("id", id).update();
        dispatch.dispatchRound(deliveryId);
        notifier.notify((UUID) o.get("customer_id"), "STORE_ORDER_STATUS", "store-order-" + id + "-ready", Map.of("orderId", id.toString(), "status", "READY"));
        return view(id, partnerUser, Set.of("PARTNER"));
    }
}
