package kz.jolay.safety;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import kz.jolay.common.*;
import kz.jolay.notifications.Notifier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Safety reporting from the apps (customers and drivers). An SOS creates a CRITICAL incident, links the active ride and counterpart,
 * records the location and immediately notifies all on-duty staff roles in real time. Staff handle it in the admin console.
 * The apps still dial 112: this service does not replace emergency services.
 */
@RestController
@RequestMapping("/api/v1/incidents")
@PreAuthorize("hasAnyRole('CUSTOMER','DRIVER')")
public class IncidentController {
    private static final String ACTIVE = "('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')";
    private final JdbcClient jdbc;
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(IncidentController.class);
    private final Notifier notifier;
    private final kz.jolay.identity.SmsSender sms;
    private final kz.jolay.rides.RideShareService shares;

    public IncidentController(JdbcClient jdbc, Notifier notifier, kz.jolay.identity.SmsSender sms, kz.jolay.rides.RideShareService shares) {
        this.jdbc = jdbc; this.notifier = notifier; this.sms = sms; this.shares = shares;
    }

    /** Tells the customer's emergency contacts about an SOS, with a live trip link. Best effort: a failing SMS gateway must never block the SOS itself. */
    private void alertContacts(UUID me, UUID rideId) {
        try {
            var contacts = jdbc.sql("SELECT name, phone FROM emergency_contacts WHERE user_id=:u").param("u", me).query().listOfRows();
            if (contacts.isEmpty()) return;
            String who = jdbc.sql("SELECT full_name FROM users WHERE id=:u").param("u", me).query(String.class).single().trim().split("\\s+")[0];
            String link = null;
            if (rideId != null) { try { link = shares.urlFor(shares.ensureToken(rideId, me)); } catch (ApiException ignored) { /* not the rider, or ride no longer active */ } }
            String text = "JOLAY: " + who + " pressed the SOS button during a trip." + (link == null ? "" : " Live trip: " + link) + " If you cannot reach them, call 112.";
            for (var c : contacts) { try { sms.send((String) c.get("phone"), text); } catch (RuntimeException e) { log.warn("SOS SMS to a contact failed: {}", e.toString()); } }
        } catch (RuntimeException e) { log.warn("SOS contact alert failed: {}", e.toString()); }
    }

    public record IncidentRequest(@NotBlank @Pattern(regexp = "SOS|COMPLAINT|ACCIDENT|OTHER") String type, UUID rideId,
                                  @Size(max = 1000) String description, GeoPoint point) {}

    @PostMapping @ResponseStatus(HttpStatus.CREATED) @Transactional
    public Map<String, Object> create(@Valid @RequestBody IncidentRequest r) {
        UUID me = Auth.id();
        if (!"SOS".equals(r.type()) && (r.description() == null || r.description().isBlank()))
            throw ApiException.badRequest("description_required", "Please describe the problem");

        UUID rideId = r.rideId(), subject = null;
        if (rideId != null) {
            var ride = jdbc.sql("SELECT customer_id, driver_id FROM rides WHERE id=:r AND (customer_id=:u OR driver_id=:u)").param("r", rideId).param("u", me).query().listOfRows().stream().findFirst()
                    .orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
            subject = me.equals(ride.get("customer_id")) ? (UUID) ride.get("driver_id") : (UUID) ride.get("customer_id");
        } else if ("SOS".equals(r.type()) || "ACCIDENT".equals(r.type())) {
            var ride = jdbc.sql("SELECT id, customer_id, driver_id FROM rides WHERE (customer_id=:u OR driver_id=:u) AND status IN " + ACTIVE + " LIMIT 1").param("u", me).query().listOfRows().stream().findFirst();
            if (ride.isPresent()) { rideId = (UUID) ride.get().get("id"); subject = me.equals(ride.get().get("customer_id")) ? (UUID) ride.get().get("driver_id") : (UUID) ride.get().get("customer_id"); }
        }

        // Repeated SOS presses must not flood staff: reuse an unresolved SOS from the last 30 minutes.
        if ("SOS".equals(r.type())) {
            var existing = jdbc.sql("SELECT id FROM incidents WHERE reporter_id=:u AND type='SOS' AND status<>'RESOLVED' AND created_at > now() - interval '30 minutes' ORDER BY created_at DESC LIMIT 1")
                    .param("u", me).query(UUID.class).optional();
            if (existing.isPresent()) {
                event(existing.get(), me, "REPEATED", r.point() == null ? null : String.format("%.5f,%.5f", r.point().lat(), r.point().lng()));
                return Map.of("id", existing.get(), "status", "OPEN", "duplicate", true);
            }
        }

        String severity = switch (r.type()) { case "SOS" -> "CRITICAL"; case "ACCIDENT" -> "HIGH"; default -> "LOW"; };
        var q = jdbc.sql("""
                INSERT INTO incidents(type,severity,reporter_id,subject_user_id,ride_id,description,location)
                VALUES (:t,:s,:u,:sub,:r,:d, CASE WHEN :lng::float8 IS NULL THEN NULL ELSE ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography END) RETURNING id""")
                .param("t", r.type()).param("s", severity).param("u", me).param("sub", subject).param("r", rideId).param("d", r.description())
                .param("lng", r.point() == null ? null : r.point().lng()).param("lat", r.point() == null ? null : r.point().lat());
        UUID id = q.query(UUID.class).single();
        event(id, me, "CREATED", null);

        for (UUID staff : jdbc.sql("SELECT DISTINCT user_id FROM user_roles WHERE role IN ('SUPPORT_AGENT','OPERATIONS_ADMIN','SUPER_ADMIN')").query(UUID.class).list())
            notifier.notify(staff, "INCIDENT_CREATED", "incident-" + id + "-" + staff, Map.of("incidentId", id.toString(), "type", r.type(), "severity", severity));
        if ("SOS".equals(r.type())) alertContacts(me, rideId);
        return Map.of("id", id, "status", "OPEN", "duplicate", false);
    }

    @GetMapping
    public List<Map<String, Object>> mine() {
        return jdbc.sql("SELECT id, type, severity, status, description, created_at, resolved_at FROM incidents WHERE reporter_id=:u ORDER BY created_at DESC LIMIT 50").param("u", Auth.id()).query().listOfRows();
    }

    private void event(UUID incident, UUID actor, String action, String note) {
        jdbc.sql("INSERT INTO incident_events(incident_id,actor_id,action,note) VALUES (:i,:a,:ac,:n)").param("i", incident).param("a", actor).param("ac", action).param("n", note).update();
    }
}
