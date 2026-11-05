package kz.jolay;

import kz.jolay.delivery.DeliveryDispatchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class MarketplaceIT extends IntegrationTestBase {
    @Autowired DeliveryDispatchService dispatch;

    static final double[] STORE = {43.2335, 76.9567};
    static final double[] HOME = {43.2200, 76.9400};     // ~2 km from the store

    private Session partner(boolean approve) {
        Session p = register("PARTNER");
        Resp r = post("/api/v1/partner/register", p.token(), Map.of("businessName", "Nan Bistro", "legalId", "123456789012"));
        assertEquals(201, r.status(), r.body().toString());
        if (approve) assertEquals(200, put("/api/v1/admin/partners/" + r.s("id") + "/status", admin("OPERATIONS_ADMIN").token(), Map.of("status", "APPROVED")).status());
        return p;
    }
    private String store(Session p) {
        Resp s = post("/api/v1/partner/stores", p.token(), Map.of("name", "Nan Bistro Dostyk", "category", "FOOD", "address", "Dostyk Ave 100", "point", Map.of("lat", STORE[0], "lng", STORE[1]), "phone", "+77015550000", "prepMinutes", 15, "acceptingOrders", true));
        assertEquals(201, s.status(), s.body().toString());
        return s.s("id");
    }
    private String product(Session p, String store, String name, int price) {
        Resp r = post("/api/v1/partner/stores/" + store + "/products", p.token(), Map.of("name", name, "section", "Main", "price", price, "available", true));
        assertEquals(201, r.status(), r.body().toString());
        return r.s("id");
    }
    private Map<String, Object> order(String store, String... productQty) {
        var items = new java.util.ArrayList<Map<String, Object>>();
        for (int i = 0; i < productQty.length; i += 2) items.add(Map.of("productId", productQty[i], "quantity", Integer.parseInt(productQty[i + 1])));
        return Map.of("storeId", store, "items", items, "dropoff", Map.of("lat", HOME[0], "lng", HOME[1]), "address", "Home", "recipientName", "Aidar Bekov", "recipientPhone", "+77011110001", "note", "No onions");
    }
    private Session courier() {
        Session c = driver("ECONOMY", 43.2336, 76.9568);
        assertEquals(200, put("/api/v1/drivers/delivery", c.token(), Map.of("enabled", true)).status());
        return c;
    }
    private void at(Session d, double lat, double lng) {
        jdbc.sql("UPDATE driver_locations SET location = ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, updated_at = now() WHERE driver_id=:d").param("lng", lng).param("lat", lat).param("d", d.id()).update();
    }
    private BigDecimal escrow() { return jdbc.sql("SELECT balance FROM accounts WHERE type='ORDER_ESCROW'").query(BigDecimal.class).single(); }
    private void assertRecon() { assertEquals("OK", get("/api/v1/admin/finance/reconciliation", admin("FINANCE_ADMIN").token()).s("status")); }

    @Test
    void partnerOnboardingNeedsApprovalAndOwnsOnlyItsData() {
        Session p = partner(false);
        assertEquals("PENDING", get("/api/v1/partner/me", p.token()).s("status"));
        assertEquals("partner_not_approved", post("/api/v1/partner/stores", p.token(), Map.of("name", "X Store", "category", "FOOD", "address", "a", "point", Map.of("lat", STORE[0], "lng", STORE[1]), "prepMinutes", 10, "acceptingOrders", true)).s("code"));
        assertEquals(400, post("/api/v1/partner/register", register("PARTNER").token(), Map.of("businessName", "Bad", "legalId", "123")).status());
        assertEquals(409, post("/api/v1/partner/register", p.token(), Map.of("businessName", "Again", "legalId", "123456789012")).status());
        // approval requires a reason when not approving, and the right role
        String pid = get("/api/v1/partner/me", p.token()).s("id");
        assertEquals(400, put("/api/v1/admin/partners/" + pid + "/status", admin("OPERATIONS_ADMIN").token(), Map.of("status", "REJECTED")).status());
        assertEquals(403, put("/api/v1/admin/partners/" + pid + "/status", admin("SUPPORT_AGENT").token(), Map.of("status", "APPROVED")).status());
        assertEquals(403, get("/api/v1/partner/me", customer().token()).status());
        assertEquals(403, get("/api/v1/admin/partners", p.token()).status());
        assertEquals(200, put("/api/v1/admin/partners/" + pid + "/status", admin("OPERATIONS_ADMIN").token(), Map.of("status", "APPROVED", "commissionRate", "0.10")).status());

        String s1 = store(p); product(p, s1, "Lagman", 2500);
        Session other = partner(true);
        String s2 = store(other);
        assertEquals(404, get("/api/v1/partner/stores/" + s1 + "/products", other.token()).status(), "a partner cannot read another partner's menu");
        assertEquals(404, post("/api/v1/partner/stores/" + s1 + "/products", other.token(), Map.of("name", "Hack", "price", 1, "available", true)).status());
        assertEquals(1, get("/api/v1/partner/stores", p.token()).body().size());
        assertEquals(0, get("/api/v1/partner/stores/" + s2 + "/products", other.token()).body().size());
        assertTrue(jdbc.sql("SELECT count(*) FROM audit_logs WHERE action LIKE 'PARTNER_%'").query(Integer.class).single() >= 2);
    }

    @Test
    void customersBrowseNearbyStoresAndMenus() {
        Session p = partner(true); String s = store(p); product(p, s, "Lagman", 2500);
        Resp hidden = post("/api/v1/partner/stores/" + s + "/products", p.token(), Map.of("name", "Sold out dish", "price", 1800, "available", false));
        Session c = customer();
        Resp near = get("/api/v1/stores?lat=" + HOME[0] + "&lng=" + HOME[1], c.token());
        assertEquals(1, near.body().size());
        assertTrue(near.body().get(0).path("distance_m").asInt() < 4000);
        assertEquals(0, get("/api/v1/stores?lat=43.38&lng=77.10", c.token()).body().size(), "too far from everything");
        assertEquals(0, get("/api/v1/stores?lat=" + HOME[0] + "&lng=" + HOME[1] + "&category=PHARMACY", c.token()).body().size());
        Resp menu = get("/api/v1/stores/" + s + "/menu", c.token());
        assertEquals(1, menu.body().path("products").size(), "unavailable dishes are hidden: " + hidden.status());
        put("/api/v1/partner/stores/" + s, p.token(), Map.of("name", "Nan Bistro Dostyk", "category", "FOOD", "address", "Dostyk Ave 100", "point", Map.of("lat", STORE[0], "lng", STORE[1]), "prepMinutes", 15, "acceptingOrders", false));
        assertEquals(0, get("/api/v1/stores?lat=" + HOME[0] + "&lng=" + HOME[1], c.token()).body().size(), "closed stores are not listed");
    }

    @Test
    void orderPlacementValidationAndEscrow() {
        Session p = partner(true); String s = store(p); String lagman = product(p, s, "Lagman", 2500), tea = product(p, s, "Tea", 500);
        Session otherPartner = partner(true);
        String foreign = product(otherPartner, store(otherPartner), "Other", 100);
        Session c = customer();
        assertEquals("insufficient_funds", post("/api/v1/store-orders", c.token(), order(s, lagman, "2")).s("code"));
        topUp(c, 20000);
        assertEquals("product_not_found", post("/api/v1/store-orders", c.token(), order(s, foreign, "1")).s("code"), "a product of another store cannot be ordered here");
        assertEquals(400, post("/api/v1/store-orders", c.token(), order(s, lagman, "0")).status());
        assertEquals(400, post("/api/v1/store-orders", c.token(), merge(order(s, lagman, "1"), Map.of("items", List.of()))).status());
        Map<String, Object> far = merge(order(s, lagman, "1"), Map.of("dropoff", Map.of("lat", 43.30, "lng", 77.05)));
        assertEquals("too_far", post("/api/v1/store-orders", c.token(), far).s("code"));

        Resp preview = post("/api/v1/store-orders/estimate", c.token(), order(s, lagman, "2", tea, "1"));
        assertEquals(200, preview.status(), preview.body().toString());
        assertEquals(0, balance(c).compareTo(new BigDecimal("20000")), "a preview holds nothing");
        assertEquals(0, jdbc.sql("SELECT count(*) FROM store_orders").query(Integer.class).single());
        Resp placed = post("/api/v1/store-orders", c.token(), order(s, lagman, "2", tea, "1"));
        assertEquals(201, placed.status(), placed.body().toString());
        assertEquals(0, new BigDecimal(preview.s("total")).compareTo(new BigDecimal(placed.s("total"))), "the preview shows exactly what will be charged");
        assertEquals("PLACED", placed.s("status"));
        BigDecimal items = new BigDecimal(placed.s("itemsTotal")), fee = new BigDecimal(placed.s("deliveryFee")), total = new BigDecimal(placed.s("total"));
        assertEquals(0, items.compareTo(new BigDecimal("5500")), "2 x 2500 + 500, computed by the server");
        assertEquals(0, total.compareTo(items.add(fee)));
        assertEquals(0, balance(c).compareTo(new BigDecimal("20000").subtract(total)), "total is held immediately");
        assertEquals(0, escrow().compareTo(total));
        assertRecon();

        // menu edits never change an order that was already placed
        String id = placed.s("id");
        String lagmanId = lagman;
        put("/api/v1/partner/products/" + lagmanId, p.token(), Map.of("name", "Lagman XL", "section", "Main", "price", 9999, "available", true));
        Resp again = get("/api/v1/store-orders/" + id, c.token());
        assertEquals(0, new BigDecimal(again.s("itemsTotal")).compareTo(items));
        assertEquals("Lagman", again.body().path("items").get(0).path("name").asText());
        // idempotency
        Resp k1 = call(org.springframework.http.HttpMethod.POST, "/api/v1/store-orders", c.token(), order(s, tea, "1"), Map.of("Idempotency-Key", "o1"));
        Resp k2 = call(org.springframework.http.HttpMethod.POST, "/api/v1/store-orders", c.token(), order(s, tea, "1"), Map.of("Idempotency-Key", "o1"));
        assertEquals(k1.s("id"), k2.s("id"));
        assertEquals(2, jdbc.sql("SELECT count(*) FROM store_orders").query(Integer.class).single());
        assertLedgerBalanced(); assertRecon();
    }

    private Map<String, Object> merge(Map<String, Object> a, Map<String, Object> b) { var m = new java.util.HashMap<>(a); m.putAll(b); return m; }

    @Test
    void rejectionAndCustomerCancellationRefundInFull() {
        Session p = partner(true); String s = store(p); String dish = product(p, s, "Lagman", 2500);
        Session c = customer(); topUp(c, 10000);
        String o1 = post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("id");
        assertEquals("REJECTED", post("/api/v1/partner/orders/" + o1 + "/reject", p.token(), Map.of("reason", "Out of ingredients")).s("status"));
        assertEquals(0, balance(c).compareTo(new BigDecimal("10000")));
        assertEquals(0, escrow().signum());
        assertEquals("Out of ingredients", get("/api/v1/store-orders/" + o1, c.token()).s("rejectReason"));
        assertEquals(409, post("/api/v1/partner/orders/" + o1 + "/accept", p.token(), null).status(), "closed orders cannot be reopened");

        String o2 = post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("id");
        assertEquals("CANCELLED", post("/api/v1/store-orders/" + o2 + "/cancel", c.token(), null).s("status"));
        assertEquals(0, balance(c).compareTo(new BigDecimal("10000")));

        String o3 = post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("id");
        post("/api/v1/partner/orders/" + o3 + "/accept", p.token(), null);
        assertEquals(409, post("/api/v1/store-orders/" + o3 + "/cancel", c.token(), null).status(), "after acceptance the customer must go through support");
        assertEquals(409, post("/api/v1/partner/orders/" + o3 + "/reject", p.token(), Map.of("reason", "late")).status());
        assertEquals(1, get("/api/v1/store-orders?tab=closed", c.token()).body().size() - 1);
        assertEquals(2, get("/api/v1/store-orders?tab=closed", c.token()).body().size());
        assertLedgerBalanced(); assertRecon();
    }

    @Test
    void fullOrderFlowWithCourierDeliverySettlesEscrowToPartnerCourierAndPlatform() {
        Session p = partner(true); String s = store(p); String dish = product(p, s, "Lagman", 2500);
        Session c = customer(); topUp(c, 10000); Session k = courier();
        Resp placed = post("/api/v1/store-orders", c.token(), order(s, dish, "2"));
        String id = placed.s("id");
        BigDecimal total = new BigDecimal(placed.s("total"));
        assertEquals(1, get("/api/v1/partner/orders?tab=open", p.token()).body().size());
        assertTrue(jdbc.sql("SELECT count(*) FROM notifications WHERE type='STORE_ORDER_NEW'").query(Integer.class).single() > 0);

        assertEquals(409, post("/api/v1/partner/orders/" + id + "/ready", p.token(), null).status(), "must be accepted before it can be ready");
        assertEquals("ACCEPTED", post("/api/v1/partner/orders/" + id + "/accept", p.token(), null).s("status"));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM delivery_orders").query(Integer.class).single(), "no courier is called before the kitchen is done");
        Resp ready = post("/api/v1/partner/orders/" + id + "/ready", p.token(), null);
        assertEquals("READY", ready.s("status"));

        Resp view = get("/api/v1/store-orders/" + id, c.token());
        String deliveryId = view.body().path("delivery").path("id").asText();
        String code = view.body().path("delivery").path("handoverCode").asText();
        assertTrue(code.matches("\\d{4}"));
        assertEquals("PREPAID", jdbc.sql("SELECT payment_method FROM delivery_orders WHERE id=:i::uuid").param("i", deliveryId).query(String.class).single());
        assertEquals("cancel_via_store_order", post("/api/v1/deliveries/" + deliveryId + "/cancel", c.token(), null).s("code"));

        String offer = get("/api/v1/drivers/delivery-offers", k.token()).s("offer_id");
        assertNotNull(offer);
        Resp acc = post("/api/v1/drivers/delivery-offers/" + offer + "/accept", k.token(), null);
        assertEquals("Nan Bistro Dostyk", acc.s("senderName"), "the courier collects at the store");
        at(k, STORE[0], STORE[1]);
        assertEquals("PICKED_UP", post("/api/v1/drivers/deliveries/" + deliveryId + "/picked-up", k.token(), null).s("status"));
        assertEquals(0, escrow().compareTo(total), "money is still held while the food is on its way");
        at(k, HOME[0], HOME[1]);
        assertEquals(200, post("/api/v1/drivers/deliveries/" + deliveryId + "/deliver", k.token(), Map.of("code", code)).status());

        assertEquals("COMPLETED", get("/api/v1/store-orders/" + id, c.token()).s("status"));
        BigDecimal commission = jdbc.sql("SELECT partner_commission FROM store_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        BigDecimal courierEarn = jdbc.sql("SELECT delivery_courier_earnings FROM store_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        BigDecimal cut = jdbc.sql("SELECT delivery_platform_cut FROM store_orders WHERE id=:i::uuid").param("i", id).query(BigDecimal.class).single();
        assertEquals(0, escrow().signum());
        assertEquals(0, balance(p).compareTo(new BigDecimal("5000").subtract(commission)), "partner gets items minus commission");
        assertEquals(0, balance(k).compareTo(courierEarn));
        assertEquals(0, jdbc.sql("SELECT balance FROM accounts WHERE type='PLATFORM_REVENUE'").query(BigDecimal.class).single().compareTo(commission.add(cut)));
        assertEquals(0, balance(c).compareTo(new BigDecimal("10000").subtract(total)));
        assertLedgerBalanced(); assertRecon();

        Resp sales = get("/api/v1/partner/reports/sales?days=30", p.token());
        assertEquals(1, sales.body().path("orders").asInt());
        assertEquals(0, new BigDecimal(sales.s("gross")).compareTo(new BigDecimal("5000")));
        assertEquals(0, new BigDecimal(sales.s("net")).compareTo(new BigDecimal("5000").subtract(commission)));
        assertEquals("Lagman", sales.body().path("topProducts").get(0).path("name").asText());
        assertEquals(1, get("/api/v1/store-orders?tab=done", c.token()).body().size());
        assertEquals(1, get("/api/v1/admin/store-orders?status=COMPLETED", admin("SUPPORT_AGENT").token()).body().size());
    }

    @Test
    void noCourierFoundRefundsTheCustomerAndFailsTheOrder() {
        Session p = partner(true); String s = store(p); String dish = product(p, s, "Lagman", 2500);
        Session c = customer(); topUp(c, 10000);
        String id = post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("id");
        post("/api/v1/partner/orders/" + id + "/accept", p.token(), null);
        post("/api/v1/partner/orders/" + id + "/ready", p.token(), null);
        jdbc.sql("UPDATE delivery_orders SET search_started_at = now() - interval '10 minutes'").update();
        dispatch.tick();
        Resp o = get("/api/v1/store-orders/" + id, c.token());
        assertEquals("FAILED", o.s("status"));
        assertEquals(0, balance(c).compareTo(new BigDecimal("10000")), "full refund");
        assertEquals(0, escrow().signum());
        assertEquals(0, balance(p).signum(), "the partner is not paid for an undelivered order");
        assertLedgerBalanced(); assertRecon();
    }

    @Test
    void ordersAreVisibleOnlyToTheirPartiesAndStaff() {
        Session p = partner(true); String s = store(p); String dish = product(p, s, "Lagman", 2500);
        Session other = partner(true), c = customer(), c2 = customer(); topUp(c, 10000);
        String id = post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("id");
        assertEquals(404, get("/api/v1/store-orders/" + id, c2.token()).status());
        assertEquals(404, get("/api/v1/partner/orders/" + id, other.token()).status());
        assertEquals(404, post("/api/v1/partner/orders/" + id + "/accept", other.token(), null).status());
        assertEquals(404, post("/api/v1/store-orders/" + id + "/cancel", c2.token(), null).status());
        assertEquals(403, post("/api/v1/partner/orders/" + id + "/accept", c.token(), null).status());
        assertEquals(403, post("/api/v1/store-orders", p.token(), order(s, dish, "1")).status(), "partners are not customers");
        assertEquals(200, get("/api/v1/admin/store-orders/" + id, admin("SUPPORT_AGENT").token()).status());
        assertEquals(403, get("/api/v1/admin/store-orders", admin("PARTNER_ADMIN").token()).status());
        // partner view exposes its commission, the customer's does not
        assertNotNull(get("/api/v1/partner/orders/" + id, p.token()).body().get("partnerNet"));
        assertNull(get("/api/v1/store-orders/" + id, c.token()).body().get("partnerNet"));
        // a suspended partner can no longer receive orders
        String pid = get("/api/v1/partner/me", p.token()).s("id");
        assertEquals(200, put("/api/v1/admin/partners/" + pid + "/status", admin("OPERATIONS_ADMIN").token(), Map.of("status", "SUSPENDED", "note", "complaints")).status());
        assertEquals("store_not_found", post("/api/v1/store-orders", c.token(), order(s, dish, "1")).s("code"));
        assertEquals(0, get("/api/v1/stores?lat=" + HOME[0] + "&lng=" + HOME[1], c.token()).body().size());
    }
}
