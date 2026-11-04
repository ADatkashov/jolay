package kz.jolay.notifications;

import kz.jolay.common.Auth;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {
    private final JdbcClient jdbc;
    public NotificationController(JdbcClient jdbc) { this.jdbc = jdbc; }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(defaultValue = "50") int limit) {
        return jdbc.sql("SELECT id, type, payload, read_at, created_at FROM notifications WHERE user_id=:u ORDER BY created_at DESC LIMIT :l")
                .param("u", Auth.id()).param("l", Math.min(limit, 100)).query().listOfRows();
    }

    @PostMapping("/{id}/read")
    public void read(@PathVariable UUID id) {
        jdbc.sql("UPDATE notifications SET read_at=now() WHERE id=:i AND user_id=:u AND read_at IS NULL").param("i", id).param("u", Auth.id()).update();
    }

    @PostMapping("/devices")
    public void registerDevice(@RequestBody Map<String, String> body) {
        String token = body.get("pushToken"), platform = body.getOrDefault("platform", "unknown");
        if (token == null || token.isBlank() || token.length() > 300) return;
        jdbc.sql("INSERT INTO user_devices(user_id,push_token,platform) VALUES (:u,:t,:p) ON CONFLICT (user_id,push_token) DO UPDATE SET updated_at=now()")
                .param("u", Auth.id()).param("t", token).param("p", platform).update();
    }
}
