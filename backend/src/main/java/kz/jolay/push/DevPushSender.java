package kz.jolay.push;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;

/**
 * DEVELOPMENT MOCK. Nothing is delivered to any phone: messages are only written to push_outbox so flows can be exercised and inspected.
 * Replaced automatically by {@link FcmPushSender} when jolay.push.fcm.service-account-file is configured.
 */
@Component
public class DevPushSender implements PushSender {
    private final JdbcClient jdbc;
    private final ObjectMapper mapper;
    public DevPushSender(JdbcClient jdbc, ObjectMapper mapper) { this.jdbc = jdbc; this.mapper = mapper; }

    @Override
    public boolean send(UUID userId, String token, String type, String title, String body, Map<String, String> data) {
        String json;
        try { json = mapper.writeValueAsString(data); } catch (JsonProcessingException e) { json = "{}"; }
        jdbc.sql("INSERT INTO push_outbox(user_id,push_token,type,title,body,data) VALUES (:u,:t,:ty,:ti,:b,:d::jsonb)")
                .param("u", userId).param("t", token).param("ty", type).param("ti", title).param("b", body).param("d", json).update();
        return true;
    }
}
