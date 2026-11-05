package kz.jolay.marketplace;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.ApiException;
import kz.jolay.common.Auth;
import kz.jolay.common.GeoPoint;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Customer side of the marketplace. */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('CUSTOMER')")
public class StoreController {
    private final JdbcClient jdbc;
    private final StoreOrderService orders;
    public StoreController(JdbcClient jdbc, StoreOrderService orders) { this.jdbc = jdbc; this.orders = orders; }

    public record LineDto(@NotNull UUID productId, @Min(1) @Max(50) int quantity) {}
    public record PlaceRequest(@NotNull UUID storeId, @NotEmpty @Size(max = 30) List<@Valid LineDto> items, @NotNull @Valid GeoPoint dropoff, @Size(max = 300) String address,
                               @NotBlank @Size(min = 2, max = 120) String recipientName, @NotBlank String recipientPhone, @Size(max = 300) String note,
                               @Pattern(regexp = "WALLET|CASH") String paymentMethod) {}

    @GetMapping("/stores")
    public List<Map<String, Object>> nearby(@RequestParam double lat, @RequestParam double lng, @RequestParam(required = false) String category) {
        return jdbc.sql("""
                SELECT s.id, s.name, s.category, s.description, s.address, s.prep_minutes, round(ST_Distance(s.location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography))::int AS distance_m
                FROM stores s JOIN partners p ON p.id=s.partner_id
                WHERE s.active AND s.accepting_orders AND p.status='APPROVED' AND (:cat::text IS NULL OR s.category=:cat)
                  AND ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography, (SELECT value::int FROM application_settings WHERE key='marketplace.max_distance_m'))
                ORDER BY ST_Distance(s.location, ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography) LIMIT 50""").param("lat", lat).param("lng", lng).param("cat", category).query().listOfRows();
    }

    @GetMapping("/stores/{id}/menu")
    public Map<String, Object> menu(@PathVariable UUID id) {
        var s = jdbc.sql("SELECT s.id, s.name, s.category, s.description, s.address, s.prep_minutes, s.accepting_orders FROM stores s JOIN partners p ON p.id=s.partner_id WHERE s.id=:id AND s.active AND p.status='APPROVED'").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("store_not_found", "Store not found"));
        var m = new java.util.LinkedHashMap<String, Object>(s);
        m.put("products", jdbc.sql("SELECT id, name, description, section, price FROM products WHERE store_id=:s AND deleted_at IS NULL AND available ORDER BY section NULLS LAST, name").param("s", id).query().listOfRows());
        return m;
    }

    @PostMapping("/store-orders/estimate")
    public Map<String, Object> estimate(@Valid @RequestBody PlaceRequest r) {
        return orders.estimate(r.storeId(), r.items().stream().map(l -> new StoreOrderService.Line(l.productId(), l.quantity())).toList(), r.dropoff());
    }

    @PostMapping("/store-orders") @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> place(@Valid @RequestBody PlaceRequest r, @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        return orders.place(Auth.id(), r.storeId(), r.items().stream().map(l -> new StoreOrderService.Line(l.productId(), l.quantity())).toList(), r.dropoff(), r.address(), r.recipientName(), r.recipientPhone(), r.note(), key, r.paymentMethod());
    }

    @GetMapping("/store-orders")
    public List<Map<String, Object>> history(@RequestParam(defaultValue = "ongoing") String tab) { return orders.history(Auth.id(), tab); }

    @GetMapping("/store-orders/{id}")
    public Map<String, Object> get(@PathVariable UUID id) { return orders.view(id, Auth.id(), Auth.user().roles()); }

    @PostMapping("/store-orders/{id}/cancel")
    public Map<String, Object> cancel(@PathVariable UUID id) { return orders.cancelByCustomer(id, Auth.id()); }
}
