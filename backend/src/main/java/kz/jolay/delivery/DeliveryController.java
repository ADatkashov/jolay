package kz.jolay.delivery;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.Auth;
import kz.jolay.common.GeoPoint;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** JOLAY Express (parcel delivery) — customer side. */
@RestController
@RequestMapping("/api/v1")
public class DeliveryController {
    private final DeliveryService deliveries;
    private final DeliveryDispatchService dispatch;
    private final JdbcClient jdbc;

    public DeliveryController(DeliveryService deliveries, DeliveryDispatchService dispatch, JdbcClient jdbc) { this.deliveries = deliveries; this.dispatch = dispatch; this.jdbc = jdbc; }

    public record EstimateRequest(@NotNull @Valid GeoPoint pickup, @NotNull @Valid GeoPoint dropoff, @NotBlank @Pattern(regexp = "SMALL|MEDIUM|LARGE") String sizeClass,
                                  @NotNull @DecimalMin("0.1") @DecimalMax("100") BigDecimal weightKg) {}
    public record PartyDto(@NotBlank @Size(min = 2, max = 120) String name, @NotBlank String phone) {}
    public record Stop(@NotNull @Valid GeoPoint point, @Size(max = 300) String address) {}
    public record CreateRequest(@NotNull @Valid Stop pickup, @NotNull @Valid Stop dropoff, @NotBlank @Pattern(regexp = "SMALL|MEDIUM|LARGE") String sizeClass,
                                @NotNull @DecimalMin("0.1") @DecimalMax("100") BigDecimal weightKg, @NotBlank @Size(max = 300) String description,
                                @NotNull @Valid PartyDto sender, @NotNull @Valid PartyDto recipient, @NotBlank @Pattern(regexp = "CASH|WALLET") String paymentMethod) {}
    public record CancelRequest(@Size(max = 200) String reason) {}
    public record RatingRequest(@Min(1) @Max(5) int stars, @Size(max = 500) String comment) {}

    @PostMapping("/deliveries/estimate") @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> estimate(@Valid @RequestBody EstimateRequest r) { return deliveries.estimate(r.pickup(), r.dropoff(), r.sizeClass(), r.weightKg()); }

    @PostMapping("/deliveries") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> create(@Valid @RequestBody CreateRequest r, @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        return deliveries.create(Auth.id(), r.pickup().point(), r.pickup().address(), r.dropoff().point(), r.dropoff().address(), r.sizeClass(), r.weightKg(), r.description(),
                new DeliveryService.Party(r.sender().name(), r.sender().phone()), new DeliveryService.Party(r.recipient().name(), r.recipient().phone()), r.paymentMethod(), key);
    }

    @GetMapping("/deliveries/history") @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> history(@RequestParam(defaultValue = "completed") String tab, @RequestParam(defaultValue = "20") int limit, @RequestParam(defaultValue = "0") int offset) {
        return deliveries.history(Auth.id(), false, tab, limit, offset);
    }

    @GetMapping("/deliveries/{id}") @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> get(@PathVariable UUID id) { return deliveries.view(id, Auth.id(), Auth.user().roles()); }

    @PostMapping("/deliveries/{id}/cancel") @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody(required = false) CancelRequest r) { return deliveries.cancelByCustomer(id, Auth.id(), r == null ? null : r.reason()); }

    @PostMapping("/deliveries/{id}/rating") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize("hasRole('CUSTOMER')")
    public void rate(@PathVariable UUID id, @Valid @RequestBody RatingRequest r) { deliveries.rate(id, Auth.id(), r.stars(), r.comment()); }

    /** Public tracking page data for recipients: status and timestamps only. */
    @GetMapping("/catalog/track/{number}")
    public Map<String, Object> track(@PathVariable String number) { return deliveries.publicTrack(number); }

    // ---------------- courier side ----------------
    public record DeliverRequest(@NotBlank @Pattern(regexp = "\\d{4}") String code) {}
    public record EnableRequest(boolean enabled) {}

    @PutMapping("/drivers/delivery") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> enable(@RequestBody EnableRequest r) {
        jdbc.sql("UPDATE drivers SET accepts_delivery=:e, updated_at=now() WHERE user_id=:u").param("e", r.enabled()).param("u", Auth.id()).update();
        return Map.of("acceptsDelivery", r.enabled());
    }

    @GetMapping("/drivers/delivery-offers") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> offer() { return deliveries.currentOffer(Auth.id()); }

    @PostMapping("/drivers/delivery-offers/{id}/accept") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> accept(@PathVariable UUID id) { UUID d = dispatch.accept(Auth.id(), id); return deliveries.view(d, Auth.id(), Auth.user().roles()); }

    @PostMapping("/drivers/delivery-offers/{id}/decline") @ResponseStatus(HttpStatus.NO_CONTENT) @PreAuthorize("hasRole('DRIVER')")
    public void decline(@PathVariable UUID id) { dispatch.decline(Auth.id(), id); }

    @GetMapping("/drivers/deliveries/active") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> activeDelivery() { return deliveries.activeForCourier(Auth.id()).orElse(null); }

    @GetMapping("/drivers/deliveries/history") @PreAuthorize("hasRole('DRIVER')")
    public List<Map<String, Object>> courierHistory(@RequestParam(defaultValue = "completed") String tab) { return deliveries.history(Auth.id(), true, tab, 20, 0); }

    @PostMapping("/drivers/deliveries/{id}/picked-up") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> pickedUp(@PathVariable UUID id) { return deliveries.pickedUp(id, Auth.id()); }

    @PostMapping("/drivers/deliveries/{id}/deliver") @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> deliver(@PathVariable UUID id, @Valid @RequestBody DeliverRequest r) { return deliveries.deliver(id, Auth.id(), r.code()); }

    @PostMapping("/drivers/deliveries/{id}/cancel") @ResponseStatus(HttpStatus.NO_CONTENT) @PreAuthorize("hasRole('DRIVER')")
    public void courierCancel(@PathVariable UUID id, @RequestBody(required = false) CancelRequest r) { deliveries.cancelByCourier(id, Auth.id(), r == null ? null : r.reason()); }

    // ---------------- staff ----------------
    @GetMapping("/admin/deliveries") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT')")
    public List<Map<String, Object>> adminList(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT o.id, o.tracking_number, o.status, o.size_class, o.fee, o.payment_method, o.payment_status, o.pickup_address, o.dropoff_address, o.created_at, c.full_name AS customer, k.full_name AS courier FROM delivery_orders o JOIN users c ON c.id=o.customer_id LEFT JOIN users k ON k.id=o.courier_id WHERE (:s::text IS NULL OR o.status=:s) ORDER BY o.created_at DESC LIMIT 200")
                .param("s", status).query().listOfRows();
    }

    @GetMapping("/admin/deliveries/{id}") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT')")
    public Map<String, Object> adminGet(@PathVariable UUID id) { return deliveries.view(id, Auth.id(), Auth.user().roles()); }
}
