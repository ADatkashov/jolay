package kz.jolay.risk;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import kz.jolay.common.ApiException;
import kz.jolay.common.Audit;
import kz.jolay.common.Auth;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Risk review queue. Decisions are recorded with the reviewer and audited; no account is ever changed automatically. */
@RestController
@RequestMapping("/api/v1/admin/risk-flags")
public class RiskController {
    private final JdbcClient jdbc;
    private final Audit audit;
    public RiskController(JdbcClient jdbc, Audit audit) { this.jdbc = jdbc; this.audit = audit; }

    public record Review(@NotBlank @Pattern(regexp = "DISMISSED|CONFIRMED") String status, @NotBlank @Size(max = 300) String note) {}

    @GetMapping @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN')")
    public List<Map<String, Object>> list(@RequestParam(defaultValue = "OPEN") String status) {
        return jdbc.sql("""
                SELECT f.id, f.rule, f.severity, f.status, f.details, f.ride_id, f.created_at, f.reviewed_at, f.review_note, u.id AS user_id, u.full_name AS user_name, u.phone
                FROM risk_flags f JOIN users u ON u.id=f.user_id WHERE f.status=:s
                ORDER BY CASE f.severity WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END, f.created_at DESC LIMIT 200""").param("s", status).query().listOfRows();
    }

    @PostMapping("/{id}/review") @PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN')") @Transactional
    public Map<String, Object> review(@PathVariable UUID id, @Valid @RequestBody Review r) {
        int n = jdbc.sql("UPDATE risk_flags SET status=:s, reviewed_by=:u, reviewed_at=now(), review_note=:n WHERE id=:id AND status='OPEN'")
                .param("s", r.status()).param("u", Auth.id()).param("n", r.note()).param("id", id).update();
        if (n == 0) throw ApiException.conflict("flag_not_open", "Flag not found or already reviewed");
        audit.log(Auth.id(), Auth.user().roles().stream().findFirst().orElse("?"), "RISK_FLAG_REVIEWED", "risk_flag", id, Map.of("status", r.status(), "note", r.note()));
        return Map.of("id", id, "status", r.status());
    }
}
