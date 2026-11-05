package kz.jolay.delivery;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/** Failed handover-code attempts are counted in their own transaction so the count survives when the request itself fails. */
@Component
public class CodeAttempts {
    private final JdbcClient jdbc;
    public CodeAttempts(JdbcClient jdbc) { this.jdbc = jdbc; }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFailure(UUID deliveryId) {
        jdbc.sql("INSERT INTO delivery_code_attempts(delivery_id, attempts) VALUES (:id, 1) ON CONFLICT (delivery_id) DO UPDATE SET attempts = delivery_code_attempts.attempts + 1").param("id", deliveryId).update();
    }

    public int count(UUID deliveryId) { return jdbc.sql("SELECT COALESCE(max(attempts),0) FROM delivery_code_attempts WHERE delivery_id=:id").param("id", deliveryId).query(Integer.class).single(); }
}
