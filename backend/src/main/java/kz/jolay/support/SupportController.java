package kz.jolay.support;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.ApiException;
import kz.jolay.common.Auth;
import kz.jolay.notifications.Notifier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/support")
public class SupportController {
    private final JdbcClient jdbc;
    private final Notifier notifier;
    public SupportController(JdbcClient jdbc, Notifier notifier) { this.jdbc = jdbc; this.notifier = notifier; }

    public record TicketRequest(@NotBlank @Pattern(regexp = "PAYMENT|RIDE|DELIVERY|SAFETY|OTHER") String category, @NotBlank @Size(max = 160) String subject,
                                UUID rideId, @NotBlank @Size(max = 2000) String message) {}
    public record MessageRequest(@NotBlank @Size(max = 2000) String body) {}

    @PostMapping("/tickets") @ResponseStatus(HttpStatus.CREATED) @Transactional
    public Map<String, Object> create(@Valid @RequestBody TicketRequest r) {
        UUID me = Auth.id();
        if (r.rideId() != null && jdbc.sql("SELECT count(*) FROM rides WHERE id=:r AND (customer_id=:u OR driver_id=:u)").param("r", r.rideId()).param("u", me).query(Integer.class).single() == 0)
            throw ApiException.notFound("ride_not_found", "Ride not found");
        UUID id = jdbc.sql("INSERT INTO support_tickets(user_id,category,subject,ride_id) VALUES (:u,:c,:s,:r) RETURNING id")
                .param("u", me).param("c", r.category()).param("s", r.subject()).param("r", r.rideId()).query(UUID.class).single();
        jdbc.sql("INSERT INTO support_messages(ticket_id,sender_id,body) VALUES (:t,:u,:b)").param("t", id).param("u", me).param("b", r.message()).update();
        return Map.of("id", id, "status", "OPEN");
    }

    @GetMapping("/tickets")
    public List<Map<String, Object>> list() {
        return jdbc.sql("""
                SELECT t.id, t.category, t.subject, t.status, t.updated_at,
                  (SELECT body FROM support_messages m WHERE m.ticket_id=t.id ORDER BY created_at DESC LIMIT 1) AS last_message,
                  (SELECT count(*) FROM support_messages m WHERE m.ticket_id=t.id AND m.from_agent AND m.read_at IS NULL) AS unread
                FROM support_tickets t WHERE t.user_id=:u ORDER BY t.updated_at DESC LIMIT 100""").param("u", Auth.id()).query().listOfRows();
    }

    @GetMapping("/tickets/{id}/messages") @Transactional
    public List<Map<String, Object>> messages(@PathVariable UUID id) {
        own(id);
        jdbc.sql("UPDATE support_messages SET read_at=now() WHERE ticket_id=:t AND from_agent AND read_at IS NULL").param("t", id).update();
        return jdbc.sql("SELECT id, body, from_agent, read_at, created_at FROM support_messages WHERE ticket_id=:t ORDER BY created_at").param("t", id).query().listOfRows();
    }

    @PostMapping("/tickets/{id}/messages") @ResponseStatus(HttpStatus.CREATED) @Transactional
    public Map<String, Object> post(@PathVariable UUID id, @Valid @RequestBody MessageRequest r) {
        own(id);
        if (jdbc.sql("SELECT status='CLOSED' FROM support_tickets WHERE id=:i").param("i", id).query(Boolean.class).single())
            throw ApiException.conflict("ticket_closed", "Ticket is closed");
        UUID mid = jdbc.sql("INSERT INTO support_messages(ticket_id,sender_id,body) VALUES (:t,:u,:b) RETURNING id").param("t", id).param("u", Auth.id()).param("b", r.body()).query(UUID.class).single();
        jdbc.sql("UPDATE support_tickets SET updated_at=now(), status='OPEN' WHERE id=:t").param("t", id).update();
        return Map.of("id", mid);
    }

    private void own(UUID ticket) {
        if (jdbc.sql("SELECT count(*) FROM support_tickets WHERE id=:t AND user_id=:u").param("t", ticket).param("u", Auth.id()).query(Integer.class).single() == 0)
            throw ApiException.notFound("ticket_not_found", "Ticket not found");
    }
}
