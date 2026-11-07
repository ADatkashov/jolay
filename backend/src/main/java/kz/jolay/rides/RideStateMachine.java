package kz.jolay.rides;

import kz.jolay.common.ApiException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/** The only place that changes rides.status. Rejects invalid transitions and guards against concurrent updates. */
@Component
public class RideStateMachine {
    private final JdbcClient jdbc;
    public RideStateMachine(JdbcClient jdbc) { this.jdbc = jdbc; }

    /** @param extraSet additional trusted SQL assignments, e.g. ", assigned_at = now()" (never user input) */
    @Transactional(propagation = Propagation.MANDATORY)
    public void move(UUID rideId, RideStatus from, RideStatus to, String actor, String extraSet, java.util.Map<String, Object> params) {
        if (!from.canMoveTo(to)) throw ApiException.conflict("invalid_transition", "Cannot change ride from " + from + " to " + to);
        var q = jdbc.sql("UPDATE rides SET status=:to, updated_at=now()" + (extraSet == null ? "" : extraSet) + " WHERE id=:id AND status=:from")
                .param("to", to.name()).param("from", from.name()).param("id", rideId);
        if (params != null) for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        if (q.update() != 1) throw ApiException.conflict("invalid_transition", "Ride state changed concurrently");
        jdbc.sql("INSERT INTO ride_status_history(ride_id,from_status,to_status,actor) VALUES (:r,:f,:t,:a)")
                .param("r", rideId).param("f", from.name()).param("t", to.name()).param("a", actor).update();
        if (to.isTerminal() && to != RideStatus.COMPLETED)      // the rider gets the promo use back
            jdbc.sql("UPDATE promo_redemptions SET status='RELEASED' WHERE ride_id=:r AND status='RESERVED'").param("r", rideId).update();
    }

    public RideStatus current(UUID rideId, boolean lock) {
        return jdbc.sql("SELECT status FROM rides WHERE id=:id" + (lock ? " FOR UPDATE" : "")).param("id", rideId)
                .query(String.class).optional().map(RideStatus::valueOf)
                .orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
    }
}
