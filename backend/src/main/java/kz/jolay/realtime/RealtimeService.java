package kz.jolay.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.time.Instant;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Pushes events to connected users. Events are hints only: they are sent AFTER the surrounding transaction commits,
 * and clients must treat REST as the source of truth (especially for money) and re-fetch state on reconnect.
 */
@Service
public class RealtimeService {
    private static final Logger log = LoggerFactory.getLogger(RealtimeService.class);
    private final Map<UUID, Set<WebSocketSession>> sessions = new ConcurrentHashMap<>();
    private final ObjectMapper mapper;

    public RealtimeService(ObjectMapper mapper) { this.mapper = mapper; }

    void register(UUID userId, WebSocketSession s) { sessions.computeIfAbsent(userId, k -> ConcurrentHashMap.newKeySet()).add(s); }
    void unregister(UUID userId, WebSocketSession s) {
        sessions.computeIfPresent(userId, (k, v) -> { v.remove(s); return v.isEmpty() ? null : v; });
    }
    public int connectedUsers() { return sessions.size(); }

    public void publish(UUID userId, String type, Map<String, ?> data) {
        Runnable send = () -> deliver(userId, type, data);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { send.run(); }
            });
        } else send.run();
    }

    private void deliver(UUID userId, String type, Map<String, ?> data) {
        Set<WebSocketSession> set = sessions.get(userId);
        if (set == null) return;
        String json;
        try { json = mapper.writeValueAsString(Map.of("type", type, "data", data, "ts", Instant.now().toString())); }
        catch (Exception e) { log.error("ws serialize failed", e); return; }
        for (WebSocketSession s : set) {
            try { synchronized (s) { if (s.isOpen()) s.sendMessage(new TextMessage(json)); } }
            catch (Exception e) { log.debug("ws send failed, closing", e); try { s.close(CloseStatus.SERVER_ERROR); } catch (Exception ignored) {} }
        }
    }
}
