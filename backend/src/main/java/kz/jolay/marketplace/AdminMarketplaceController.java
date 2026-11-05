package kz.jolay.marketplace;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.ApiException;
import kz.jolay.common.Audit;
import kz.jolay.common.Auth;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/admin")
public class AdminMarketplaceController {
    private final JdbcClient jdbc;
    private final Audit audit;
    private final StoreOrderService orders;
    public AdminMarketplaceController(JdbcClient jdbc, Audit audit, StoreOrderService orders) { this.jdbc = jdbc; this.audit = audit; this.orders = orders; }

    public record PartnerDecision(@NotBlank @Pattern(regexp = "APPROVED|REJECTED|SUSPENDED") String status, @Size(max = 300) String note,
                                  @DecimalMin("0") @DecimalMax("0.5") BigDecimal commissionRate) {}

    @GetMapping("/partners") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','SUPPORT_AGENT')")
    public List<Map<String, Object>> partners(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT p.id, p.business_name, p.legal_id, p.status, p.commission_rate, p.review_note, p.created_at, u.full_name AS owner, u.phone, (SELECT count(*) FROM stores s WHERE s.partner_id=p.id) AS stores FROM partners p JOIN users u ON u.id=p.owner_id WHERE (:s::text IS NULL OR p.status=:s) ORDER BY p.created_at DESC LIMIT 200")
                .param("s", status).query().listOfRows();
    }

    @PutMapping("/partners/{id}/status") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN')") @Transactional
    public Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody PartnerDecision d) {
        if (!"APPROVED".equals(d.status()) && (d.note() == null || d.note().isBlank())) throw ApiException.badRequest("reason_required", "A reason is required");
        int n = jdbc.sql("UPDATE partners SET status=:s, review_note=:n, commission_rate=COALESCE(:c, commission_rate) WHERE id=:id").param("s", d.status()).param("n", d.note()).param("c", d.commissionRate()).param("id", id).update();
        if (n == 0) throw ApiException.notFound("partner_not_found", "Partner not found");
        if (!"APPROVED".equals(d.status())) jdbc.sql("UPDATE stores SET accepting_orders=false WHERE partner_id=:p").param("p", id).update();
        audit.log(Auth.id(), "OPS", "PARTNER_" + d.status(), "partner", id, Map.of("note", d.note() == null ? "" : d.note()));
        return Map.of("id", id, "status", d.status());
    }

    @GetMapping("/store-orders") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT')")
    public List<Map<String, Object>> storeOrders(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT o.id, o.number, o.status, o.items_total, o.delivery_fee, o.created_at, s.name AS store, c.full_name AS customer FROM store_orders o JOIN stores s ON s.id=o.store_id JOIN users c ON c.id=o.customer_id WHERE (:s::text IS NULL OR o.status=:s) ORDER BY o.created_at DESC LIMIT 200")
                .param("s", status).query().listOfRows();
    }

    @GetMapping("/store-orders/{id}") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT')")
    public Map<String, Object> storeOrder(@PathVariable UUID id) { return orders.view(id, Auth.id(), Auth.user().roles()); }
}
