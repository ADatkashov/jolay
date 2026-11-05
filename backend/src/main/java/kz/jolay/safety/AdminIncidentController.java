package kz.jolay.safety;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import kz.jolay.common.ApiException;
import kz.jolay.common.Audit;
import kz.jolay.common.Auth;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Operations centre: triage and resolve incidents. Every step is an immutable row in incident_events and in audit_logs. */
@RestController
@RequestMapping("/api/v1/admin/incidents")
@PreAuthorize("hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','SUPPORT_AGENT')")
public class AdminIncidentController {
    private final JdbcClient jdbc;
    private final Audit audit;
    public AdminIncidentController(JdbcClient jdbc, Audit audit) { this.jdbc = jdbc; this.audit = audit; }

    public record Note(@NotBlank @Size(max = 500) String note) {}

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false) String status) {
        return jdbc.sql("""
                SELECT i.id, i.type, i.severity, i.status, i.description, i.created_at, i.ride_id, r.full_name AS reporter, r.phone AS reporter_phone, s.full_name AS subject,
                       ST_Y(i.location::geometry) AS lat, ST_X(i.location::geometry) AS lng
                FROM incidents i JOIN users r ON r.id=i.reporter_id LEFT JOIN users s ON s.id=i.subject_user_id
                WHERE (:s::text IS NULL OR i.status=:s)
                ORDER BY (i.status='RESOLVED'), CASE i.severity WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 ELSE 2 END, i.created_at DESC LIMIT 200""").param("s", status).query().listOfRows();
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable UUID id) {
        var i = jdbc.sql("""
                SELECT i.*, ST_Y(i.location::geometry) AS lat, ST_X(i.location::geometry) AS lng, r.full_name AS reporter, r.phone AS reporter_phone,
                       s.full_name AS subject, s.phone AS subject_phone, a.full_name AS assignee
                FROM incidents i JOIN users r ON r.id=i.reporter_id LEFT JOIN users s ON s.id=i.subject_user_id LEFT JOIN users a ON a.id=i.assigned_to WHERE i.id=:id""")
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> ApiException.notFound("incident_not_found", "Incident not found"));
        Map<String, Object> m = new LinkedHashMap<>(i);
        m.remove("location");
        m.put("events", jdbc.sql("SELECT e.id, e.action, e.note, e.created_at, u.full_name AS actor FROM incident_events e LEFT JOIN users u ON u.id=e.actor_id WHERE e.incident_id=:id ORDER BY e.id").param("id", id).query().listOfRows());
        if (i.get("ride_id") != null)
            m.put("ride", jdbc.sql("SELECT id, status, pickup_address, dropoff_address, created_at FROM rides WHERE id=:r").param("r", i.get("ride_id")).query().listOfRows().get(0));
        audit.log(Auth.id(), role(), "INCIDENT_VIEWED", "incident", id, null);
        return m;
    }

    @PostMapping("/{id}/ack") @Transactional
    public Map<String, Object> ack(@PathVariable UUID id) {
        int n = jdbc.sql("UPDATE incidents SET status='ACKNOWLEDGED', assigned_to=:u, acknowledged_at=now() WHERE id=:id AND status='OPEN'").param("u", Auth.id()).param("id", id).update();
        if (n == 0) throw ApiException.conflict("incident_not_open", "Incident is not open");
        event(id, "ACKNOWLEDGED", null);
        return Map.of("id", id, "status", "ACKNOWLEDGED");
    }

    @PostMapping("/{id}/note") @Transactional
    public Map<String, Object> note(@PathVariable UUID id, @Valid @RequestBody Note n) {
        exists(id);
        event(id, "NOTE", n.note());
        return Map.of("id", id);
    }

    @PostMapping("/{id}/resolve") @Transactional
    public Map<String, Object> resolve(@PathVariable UUID id, @Valid @RequestBody Note n) {
        int c = jdbc.sql("UPDATE incidents SET status='RESOLVED', resolution=:r, resolved_at=now(), assigned_to=COALESCE(assigned_to,:u) WHERE id=:id AND status<>'RESOLVED'").param("r", n.note()).param("u", Auth.id()).param("id", id).update();
        if (c == 0) { exists(id); throw ApiException.conflict("incident_resolved", "Incident is already resolved"); }
        event(id, "RESOLVED", n.note());
        return Map.of("id", id, "status", "RESOLVED");
    }

    private void exists(UUID id) {
        if (jdbc.sql("SELECT count(*) FROM incidents WHERE id=:id").param("id", id).query(Integer.class).single() == 0) throw ApiException.notFound("incident_not_found", "Incident not found");
    }
    private void event(UUID id, String action, String note) {
        jdbc.sql("INSERT INTO incident_events(incident_id,actor_id,action,note) VALUES (:i,:a,:ac,:n)").param("i", id).param("a", Auth.id()).param("ac", action).param("n", note).update();
        audit.log(Auth.id(), role(), "INCIDENT_" + action, "incident", id, note == null ? null : Map.of("note", note));
    }
    private String role() { return Auth.user().roles().stream().findFirst().orElse("?"); }
}
