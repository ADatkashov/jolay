package kz.jolay.delivery;

import kz.jolay.common.ApiException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;
import java.util.UUID;

/** The only place that changes delivery_orders.status. */
@Component
public class DeliveryStateMachine {
    private final JdbcClient jdbc;
    public DeliveryStateMachine(JdbcClient jdbc) { this.jdbc = jdbc; }

    @Transactional(propagation = Propagation.MANDATORY)
    public void move(UUID id, DeliveryStatus from, DeliveryStatus to, String actor, String extraSet, Map<String, Object> params) {
        if (!from.canMoveTo(to)) throw ApiException.conflict("invalid_transition", "Cannot change delivery from " + from + " to " + to);
        var q = jdbc.sql("UPDATE delivery_orders SET status=:to, updated_at=now()" + (extraSet == null ? "" : extraSet) + " WHERE id=:id AND status=:from").param("to", to.name()).param("from", from.name()).param("id", id);
        if (params != null) for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        if (q.update() != 1) throw ApiException.conflict("invalid_transition", "Delivery state changed concurrently");
        jdbc.sql("INSERT INTO delivery_status_history(delivery_id,from_status,to_status,actor) VALUES (:d,:f,:t,:a)").param("d", id).param("f", from.name()).param("t", to.name()).param("a", actor).update();
    }

    public DeliveryStatus current(UUID id, boolean lock) {
        return jdbc.sql("SELECT status FROM delivery_orders WHERE id=:id" + (lock ? " FOR UPDATE" : "")).param("id", id).query(String.class).optional().map(DeliveryStatus::valueOf)
                .orElseThrow(() -> ApiException.notFound("delivery_not_found", "Delivery not found"));
    }
}
