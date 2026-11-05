package kz.jolay.marketplace;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.*;
import kz.jolay.geography.GeoService;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Partner (restaurant / shop) back office. Every query is scoped to the caller's own partner record. */
@RestController
@RequestMapping("/api/v1/partner")
@PreAuthorize("hasRole('PARTNER')")
public class PartnerController {
    private final JdbcClient jdbc;
    private final GeoService geo;
    private final StoreOrderService orders;

    public PartnerController(JdbcClient jdbc, GeoService geo, StoreOrderService orders) { this.jdbc = jdbc; this.geo = geo; this.orders = orders; }

    public record RegisterRequest(@NotBlank @Size(min = 2, max = 160) String businessName, @Pattern(regexp = "\\d{12}") String legalId) {}
    public record StoreRequest(@NotBlank @Size(min = 2, max = 160) String name, @NotBlank @Pattern(regexp = "FOOD|GROCERY|PHARMACY|SHOP") String category, @Size(max = 500) String description,
                               @NotBlank @Size(max = 300) String address, @NotNull @Valid GeoPoint point, @Size(max = 20) String phone, @Min(1) @Max(240) int prepMinutes, boolean acceptingOrders) {}
    public record ProductRequest(@NotBlank @Size(min = 1, max = 160) String name, @Size(max = 500) String description, @Size(max = 60) String section,
                                 @NotNull @DecimalMin("1") @DecimalMax("10000000") BigDecimal price, boolean available) {}
    public record RejectRequest(@NotBlank @Size(max = 200) String reason) {}

    private UUID partnerId() {
        return jdbc.sql("SELECT id FROM partners WHERE owner_id=:u").param("u", Auth.id()).query(UUID.class).optional()
                .orElseThrow(() -> ApiException.notFound("partner_not_registered", "Register your business first"));
    }
    private UUID approvedPartnerId() {
        var p = jdbc.sql("SELECT id, status FROM partners WHERE owner_id=:u").param("u", Auth.id()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("partner_not_registered", "Register your business first"));
        if (!"APPROVED".equals(p.get("status"))) throw ApiException.forbidden("partner_not_approved", "Your business has not been approved yet");
        return (UUID) p.get("id");
    }
    private UUID ownStore(UUID storeId) {
        if (jdbc.sql("SELECT count(*) FROM stores WHERE id=:s AND partner_id=:p").param("s", storeId).param("p", approvedPartnerId()).query(Integer.class).single() == 0)
            throw ApiException.notFound("store_not_found", "Store not found");
        return storeId;
    }

    @PostMapping("/register") @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> register(@Valid @RequestBody RegisterRequest r) {
        try { jdbc.sql("INSERT INTO partners(owner_id,business_name,legal_id) VALUES (:u,:n,:l)").param("u", Auth.id()).param("n", r.businessName().trim()).param("l", r.legalId()).update(); }
        catch (org.springframework.dao.DuplicateKeyException e) { throw ApiException.conflict("already_registered", "Business already registered"); }
        return me();
    }

    @GetMapping("/me")
    public Map<String, Object> me() {
        return jdbc.sql("SELECT id, business_name, legal_id, status, commission_rate, review_note FROM partners WHERE owner_id=:u").param("u", Auth.id()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("partner_not_registered", "Register your business first"));
    }

    // ---------------- stores ----------------
    @GetMapping("/stores")
    public List<Map<String, Object>> stores() {
        return jdbc.sql("SELECT id, name, category, description, address, phone, accepting_orders, prep_minutes, active, ST_Y(location::geometry) lat, ST_X(location::geometry) lng FROM stores WHERE partner_id=:p ORDER BY created_at").param("p", partnerId()).query().listOfRows();
    }

    @PostMapping("/stores") @ResponseStatus(HttpStatus.CREATED) @Transactional
    public Map<String, Object> createStore(@Valid @RequestBody StoreRequest r) {
        UUID p = approvedPartnerId();
        UUID city = geo.cityFor(r.point(), "store_out_of_zone");
        UUID id = jdbc.sql("INSERT INTO stores(partner_id,city_id,name,category,description,address,location,phone,prep_minutes,accepting_orders) VALUES (:p,:c,:n,:cat,:d,:a,ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography,:ph,:pm,:ac) RETURNING id")
                .param("p", p).param("c", city).param("n", r.name().trim()).param("cat", r.category()).param("d", r.description()).param("a", r.address().trim()).param("lng", r.point().lng()).param("lat", r.point().lat())
                .param("ph", r.phone() == null || r.phone().isBlank() ? null : kz.jolay.identity.AuthService.normalizePhone(r.phone())).param("pm", r.prepMinutes()).param("ac", r.acceptingOrders()).query(UUID.class).single();
        return Map.of("id", id);
    }

    @PutMapping("/stores/{id}") @Transactional
    public Map<String, Object> updateStore(@PathVariable UUID id, @Valid @RequestBody StoreRequest r) {
        ownStore(id);
        UUID city = geo.cityFor(r.point(), "store_out_of_zone");
        jdbc.sql("UPDATE stores SET city_id=:c, name=:n, category=:cat, description=:d, address=:a, location=ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, phone=:ph, prep_minutes=:pm, accepting_orders=:ac WHERE id=:id")
                .param("c", city).param("n", r.name().trim()).param("cat", r.category()).param("d", r.description()).param("a", r.address().trim()).param("lng", r.point().lng()).param("lat", r.point().lat())
                .param("ph", r.phone() == null || r.phone().isBlank() ? null : kz.jolay.identity.AuthService.normalizePhone(r.phone())).param("pm", r.prepMinutes()).param("ac", r.acceptingOrders()).param("id", id).update();
        return Map.of("id", id);
    }

    // ---------------- products ----------------
    @GetMapping("/stores/{id}/products")
    public List<Map<String, Object>> products(@PathVariable UUID id) {
        ownStore(id);
        return jdbc.sql("SELECT id, name, description, section, price, available FROM products WHERE store_id=:s AND deleted_at IS NULL ORDER BY section NULLS LAST, name").param("s", id).query().listOfRows();
    }

    @PostMapping("/stores/{id}/products") @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> addProduct(@PathVariable UUID id, @Valid @RequestBody ProductRequest r) {
        ownStore(id);
        if (jdbc.sql("SELECT count(*) FROM products WHERE store_id=:s AND deleted_at IS NULL").param("s", id).query(Integer.class).single() >= 500) throw ApiException.badRequest("too_many_products", "Product limit reached");
        UUID pid = jdbc.sql("INSERT INTO products(store_id,name,description,section,price,available) VALUES (:s,:n,:d,:sec,:p,:a) RETURNING id").param("s", id).param("n", r.name().trim()).param("d", r.description()).param("sec", r.section()).param("p", Money.scale(r.price())).param("a", r.available()).query(UUID.class).single();
        return Map.of("id", pid);
    }

    @PutMapping("/products/{pid}")
    public Map<String, Object> updateProduct(@PathVariable UUID pid, @Valid @RequestBody ProductRequest r) {
        int n = jdbc.sql("UPDATE products SET name=:n, description=:d, section=:sec, price=:p, available=:a WHERE id=:id AND deleted_at IS NULL AND store_id IN (SELECT id FROM stores WHERE partner_id=:partner)")
                .param("n", r.name().trim()).param("d", r.description()).param("sec", r.section()).param("p", Money.scale(r.price())).param("a", r.available()).param("id", pid).param("partner", approvedPartnerId()).update();
        if (n == 0) throw ApiException.notFound("product_not_found", "Product not found");
        return Map.of("id", pid);
    }

    @DeleteMapping("/products/{pid}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteProduct(@PathVariable UUID pid) {
        int n = jdbc.sql("UPDATE products SET deleted_at=now(), available=false WHERE id=:id AND deleted_at IS NULL AND store_id IN (SELECT id FROM stores WHERE partner_id=:partner)").param("id", pid).param("partner", approvedPartnerId()).update();
        if (n == 0) throw ApiException.notFound("product_not_found", "Product not found");
    }

    // ---------------- orders ----------------
    @GetMapping("/orders")
    public List<Map<String, Object>> orderList(@RequestParam(defaultValue = "open") String tab) {
        String st = switch (tab) { case "done" -> "('COMPLETED')"; case "closed" -> "('REJECTED','CANCELLED','FAILED')"; default -> "('PLACED','ACCEPTED','READY')"; };
        UUID me = Auth.id();
        return jdbc.sql("SELECT id FROM store_orders WHERE partner_id=:p AND status IN " + st + " ORDER BY created_at DESC LIMIT 100").param("p", partnerId()).query(UUID.class).list().stream().map(i -> orders.view(i, me, Set_PARTNER)).toList();
    }
    private static final java.util.Set<String> Set_PARTNER = java.util.Set.of("PARTNER");

    @GetMapping("/orders/{id}")
    public Map<String, Object> order(@PathVariable UUID id) { return orders.view(id, Auth.id(), Set_PARTNER); }
    @PostMapping("/orders/{id}/accept") public Map<String, Object> accept(@PathVariable UUID id) { return orders.accept(id, Auth.id()); }
    @PostMapping("/orders/{id}/reject") public Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody RejectRequest r) { return orders.reject(id, Auth.id(), r.reason()); }
    @PostMapping("/orders/{id}/ready") public Map<String, Object> ready(@PathVariable UUID id) { return orders.ready(id, Auth.id()); }

    /** Sales report from the order records: gross items, commission, net, count — completed orders only. */
    @GetMapping("/reports/sales")
    public Map<String, Object> sales(@RequestParam(defaultValue = "30") int days) {
        var r = jdbc.sql("""
                SELECT count(*) AS orders, COALESCE(sum(items_total),0) AS gross, COALESCE(sum(partner_commission),0) AS commission, COALESCE(sum(items_total - partner_commission),0) AS net
                FROM store_orders WHERE partner_id=:p AND status='COMPLETED' AND completed_at > now() - make_interval(days => :d)""").param("p", partnerId()).param("d", Math.max(1, Math.min(days, 366))).query().listOfRows().get(0);
        var m = new java.util.LinkedHashMap<String, Object>(r);
        m.put("days", days);
        m.put("openOrders", jdbc.sql("SELECT count(*) FROM store_orders WHERE partner_id=:p AND status IN ('PLACED','ACCEPTED','READY')").param("p", partnerId()).query(Long.class).single());
        m.put("topProducts", jdbc.sql("""
                SELECT i.name, sum(i.quantity) AS units, sum(i.quantity * i.unit_price) AS revenue FROM store_order_items i JOIN store_orders o ON o.id=i.order_id
                WHERE o.partner_id=:p AND o.status='COMPLETED' AND o.completed_at > now() - make_interval(days => :d) GROUP BY i.name ORDER BY revenue DESC LIMIT 5""").param("p", partnerId()).param("d", Math.max(1, Math.min(days, 366))).query().listOfRows());
        return m;
    }
}
