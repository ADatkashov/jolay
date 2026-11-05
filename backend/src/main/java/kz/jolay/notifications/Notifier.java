package kz.jolay.notifications;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import kz.jolay.push.PushService;
import kz.jolay.realtime.RealtimeService;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.UUID;

/**
 * Persists in-app notifications and pushes them over WebSocket. (userId, dedupeKey) is unique, so the same event can
 * never notify the same user twice. FCM push delivery plugs in here (see docs/ARCHITECTURE.md) once credentials exist.
 */
@Service
public class Notifier {
    private final JdbcClient jdbc;
    private final RealtimeService realtime;
    private final ObjectMapper mapper;
    private final PushService push;

    public Notifier(JdbcClient jdbc, RealtimeService realtime, ObjectMapper mapper, PushService push) { this.jdbc = jdbc; this.realtime = realtime; this.mapper = mapper; this.push = push; }

    /** Notification + realtime event. */
    public void notify(UUID userId, String type, String dedupeKey, Map<String, Object> payload) {
        String json;
        try { json = mapper.writeValueAsString(payload); } catch (JsonProcessingException e) { json = "{}"; }
        int inserted = jdbc.sql("INSERT INTO notifications(user_id,type,dedupe_key,payload) VALUES (:u,:t,:d,:p::jsonb) ON CONFLICT (user_id, dedupe_key) DO NOTHING")
                .param("u", userId).param("t", type).param("d", dedupeKey).param("p", json).update();
        if (inserted == 1) { realtime.publish(userId, type, payload); push.push(userId, type, payload); }   // push mirrors the in-app notification, once per dedupe key
    }

    /** Realtime-only event (no persisted notification), e.g. driver location ticks. */
    public void event(UUID userId, String type, Map<String, Object> payload) { realtime.publish(userId, type, payload); }
}
