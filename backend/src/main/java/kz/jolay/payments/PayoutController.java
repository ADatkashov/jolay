package kz.jolay.payments;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.Audit;
import kz.jolay.common.Auth;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class PayoutController {
    private final PayoutService payouts;
    private final JdbcClient jdbc;
    private final Audit audit;
    public PayoutController(PayoutService payouts, JdbcClient jdbc, Audit audit) { this.payouts = payouts; this.jdbc = jdbc; this.audit = audit; }

    public record PayoutRequest(@NotNull @DecimalMin("1") @DecimalMax("10000000") BigDecimal amount, @NotBlank @Size(max = 60) String destination) {}
    public record PayRequest(@NotBlank @Size(max = 100) String reference) {}
    public record RejectRequest(@NotBlank @Size(max = 300) String reason) {}

    @PostMapping("/drivers/payouts") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize("hasRole('DRIVER')")
    public Map<String, Object> request(@Valid @RequestBody PayoutRequest r) { return Map.of("id", payouts.request(Auth.id(), r.amount(), r.destination()), "status", "REQUESTED"); }

    @GetMapping("/drivers/payouts") @PreAuthorize("hasRole('DRIVER')")
    public List<Map<String, Object>> mine() {
        return jdbc.sql("SELECT id, amount, status, reference, note, created_at, reviewed_at, '****' || right(destination, 4) AS destination FROM payouts WHERE driver_id=:d ORDER BY created_at DESC LIMIT 50").param("d", Auth.id()).query().listOfRows();
    }

    @GetMapping("/admin/payouts") @PreAuthorize("hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')")
    public List<Map<String, Object>> list(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT p.id, p.amount, p.status, p.destination, p.reference, p.note, p.created_at, p.reviewed_at, u.full_name AS driver, u.phone FROM payouts p JOIN users u ON u.id=p.driver_id WHERE (:s::text IS NULL OR p.status=:s) ORDER BY (p.status='REQUESTED') DESC, p.created_at DESC LIMIT 200")
                .param("s", status).query().listOfRows();
    }

    @PostMapping("/admin/payouts/{id}/pay") @PreAuthorize("hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')")
    public Map<String, Object> pay(@PathVariable UUID id, @Valid @RequestBody PayRequest r) {
        payouts.pay(Auth.id(), id, r.reference());
        audit.log(Auth.id(), "FINANCE", "PAYOUT_PAID", "payout", id, Map.of("reference", r.reference()));
        return Map.of("id", id, "status", "PAID");
    }

    @PostMapping("/admin/payouts/{id}/reject") @PreAuthorize("hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')")
    public Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody RejectRequest r) {
        payouts.reject(Auth.id(), id, r.reason());
        audit.log(Auth.id(), "FINANCE", "PAYOUT_REJECTED", "payout", id, Map.of("reason", r.reason()));
        return Map.of("id", id, "status", "REJECTED");
    }
}
