package kz.jolay.push;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Fans a persisted notification out to the user's registered devices, after the surrounding transaction commits. A push failure never affects the business transaction. */
@Service
public class PushService {
    private static final Logger log = LoggerFactory.getLogger(PushService.class);
    private final JdbcClient jdbc;
    private final PushSender sender;

    public PushService(JdbcClient jdbc, PushSender sender) { this.jdbc = jdbc; this.sender = sender; }

    public void push(UUID userId, String type, Map<String, Object> payload) {
        Runnable job = () -> {
            try {
                String locale = jdbc.sql("SELECT locale FROM users WHERE id=:u").param("u", userId).query(String.class).optional().orElse("kk");
                var text = PushTexts.of(type, locale);
                Map<String, String> data = new HashMap<>();
                payload.forEach((k, v) -> data.put(k, String.valueOf(v)));
                data.put("type", type);
                List<String> tokens = jdbc.sql("SELECT push_token FROM user_devices WHERE user_id=:u").param("u", userId).query(String.class).list();
                for (String t : tokens) {
                    boolean ok;
                    try { ok = sender.send(userId, t, type, text.title(), text.body(), data); }
                    catch (Exception e) { log.warn("push send failed for user {}: {}", userId, e.toString()); continue; }
                    if (!ok) jdbc.sql("DELETE FROM user_devices WHERE user_id=:u AND push_token=:t").param("u", userId).param("t", t).update();   // token is dead
                }
            } catch (Exception e) { log.warn("push fan-out failed: {}", e.toString()); }
        };
        if (TransactionSynchronizationManager.isSynchronizationActive())
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() { @Override public void afterCommit() { job.run(); } });
        else job.run();
    }
}
