package kz.jolay.common;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;

@Component
public class Audit {
    private final JdbcClient jdbc;
    private final ObjectMapper mapper;
    public Audit(JdbcClient jdbc, ObjectMapper mapper) { this.jdbc = jdbc; this.mapper = mapper; }

    public void log(UUID actor, String role, String action, String entityType, Object entityId, Map<String, ?> details) {
        String json;
        try { json = mapper.writeValueAsString(details == null ? Map.of() : details); }
        catch (JsonProcessingException e) { json = "{}"; }
        jdbc.sql("INSERT INTO audit_logs(actor_id,actor_role,action,entity_type,entity_id,details) VALUES (:a,:r,:ac,:et,:ei,:d::jsonb)")
                .param("a", actor).param("r", role).param("ac", action).param("et", entityType)
                .param("ei", entityId == null ? null : entityId.toString()).param("d", json).update();
    }
}
