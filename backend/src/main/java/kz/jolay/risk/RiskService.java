package kz.jolay.risk;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import kz.jolay.common.AppSettings;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.UUID;

/**
 * Rule-based risk flags for HUMAN review. A flag never suspends, blocks or charges anyone: it only appears in the admin risk queue,
 * and every review decision is audited. Each rule creates at most one flag per user per day (dedupe key) so a bad actor cannot flood the queue.
 * All methods are plain SQL and run inside the caller's transaction.
 */
@Service
public class RiskService {
    private final JdbcClient jdbc;
    private final AppSettings settings;
    private final ObjectMapper mapper;

    public RiskService(JdbcClient jdbc, AppSettings settings, ObjectMapper mapper) { this.jdbc = jdbc; this.settings = settings; this.mapper = mapper; }

    public void flag(UUID userId, UUID rideId, String rule, String severity, String dedupeKey, Map<String, ?> details) {
        String json;
        try { json = mapper.writeValueAsString(details); } catch (JsonProcessingException e) { json = "{}"; }
        jdbc.sql("INSERT INTO risk_flags(user_id,ride_id,rule,severity,dedupe_key,details) VALUES (:u,:r,:rule,:s,:k,:d::jsonb) ON CONFLICT (user_id,rule,dedupe_key) DO NOTHING")
                .param("u", userId).param("r", rideId).param("rule", rule).param("s", severity).param("k", dedupeKey).param("d", json).update();
    }

    private String today() { return jdbc.sql("SELECT to_char((now() AT TIME ZONE 'Asia/Almaty')::date,'YYYY-MM-DD')").query(String.class).single(); }

    public void event(UUID userId, String kind) { jdbc.sql("INSERT INTO risk_events(user_id,kind) VALUES (:u,:k)").param("u", userId).param("k", kind).update(); }

    /** REPEATED_CANCELLATIONS (customer). */
    public void onCustomerCancel(UUID customerId) {
        int n = jdbc.sql("SELECT count(*) FROM rides WHERE customer_id=:u AND cancelled_by='CUSTOMER' AND cancelled_at > now() - interval '24 hours'").param("u", customerId).query(Integer.class).single();
        if (n >= settings.getInt("risk.customer_cancels_24h")) flag(customerId, null, "REPEATED_CANCELLATIONS", "MEDIUM", today(), Map.of("cancellations24h", n, "role", "CUSTOMER"));
    }

    /** REPEATED_CANCELLATIONS (driver, after accepting). */
    public void onDriverCancel(UUID driverId) {
        int n = jdbc.sql("SELECT count(*) FROM ride_status_history WHERE actor=:a AND to_status='SEARCHING_DRIVER' AND created_at > now() - interval '24 hours'").param("a", "DRIVER:" + driverId).query(Integer.class).single();
        if (n >= settings.getInt("risk.driver_cancels_24h")) flag(driverId, null, "REPEATED_CANCELLATIONS", "MEDIUM", today(), Map.of("cancellations24h", n, "role", "DRIVER"));
    }

    /** GPS_SPOOFING_INDICATOR: impossible position jumps rejected by the location endpoint. */
    public void onGpsJump(UUID driverId) {
        event(driverId, "GPS_JUMP");
        int n = jdbc.sql("SELECT count(*) FROM risk_events WHERE user_id=:u AND kind='GPS_JUMP' AND created_at > now() - interval '1 hour'").param("u", driverId).query(Integer.class).single();
        if (n >= settings.getInt("risk.gps_jumps_1h")) flag(driverId, null, "GPS_SPOOFING_INDICATOR", "HIGH", today(), Map.of("rejectedJumps1h", n));
    }

    /** COLLUSION_INDICATOR: the same customer-driver pair completing many rides in a day. */
    public void onRideCompleted(UUID rideId) {
        var r = jdbc.sql("SELECT customer_id, driver_id FROM rides WHERE id=:id").param("id", rideId).query().listOfRows().get(0);
        UUID c = (UUID) r.get("customer_id"), d = (UUID) r.get("driver_id");
        int n = jdbc.sql("SELECT count(*) FROM rides WHERE customer_id=:c AND driver_id=:d AND status='COMPLETED' AND completed_at > now() - interval '24 hours'").param("c", c).param("d", d).query(Integer.class).single();
        if (n >= settings.getInt("risk.pair_rides_24h")) {
            Map<String, Object> det = Map.of("pairRides24h", n, "customerId", c.toString(), "driverId", d.toString());
            flag(d, rideId, "COLLUSION_INDICATOR", "HIGH", c + "|" + today(), det);
            flag(c, rideId, "COLLUSION_INDICATOR", "HIGH", d + "|" + today(), det);
        }
    }

    /** DUPLICATE_IDENTITY_INDICATOR: one push device registered by many accounts. */
    public void onDeviceRegistered(UUID userId, String pushToken) {
        int n = jdbc.sql("SELECT count(DISTINCT user_id) FROM user_devices WHERE push_token=:t").param("t", pushToken).query(Integer.class).single();
        if (n >= settings.getInt("risk.device_accounts")) {
            for (UUID u : jdbc.sql("SELECT DISTINCT user_id FROM user_devices WHERE push_token=:t").param("t", pushToken).query(UUID.class).list())
                flag(u, null, "DUPLICATE_IDENTITY_INDICATOR", "MEDIUM", "device|" + Integer.toHexString(pushToken.hashCode()), Map.of("accountsOnDevice", n));
        }
    }

    /** ABNORMAL_REFUNDS. */
    public void onRefund(UUID customerId) {
        int n = jdbc.sql("SELECT count(*) FROM payment_refunds r JOIN payment_transactions p ON p.id=r.payment_id WHERE p.user_id=:u AND r.created_at > now() - interval '30 days'").param("u", customerId).query(Integer.class).single();
        if (n >= settings.getInt("risk.refunds_30d")) flag(customerId, null, "ABNORMAL_REFUNDS", "MEDIUM", today(), Map.of("refunds30d", n));
    }

    /** SUSPICIOUS_PAYMENT_CALLBACKS: the same gateway event replayed many times. */
    public void onDuplicateCallback(String provider, String providerRef) {
        jdbc.sql("SELECT user_id FROM payment_transactions WHERE provider=:p AND provider_ref=:r").param("p", provider).param("r", providerRef).query(UUID.class).optional().ifPresent(u -> {
            event(u, "DUPLICATE_CALLBACK");
            int n = jdbc.sql("SELECT count(*) FROM risk_events WHERE user_id=:u AND kind='DUPLICATE_CALLBACK' AND created_at > now() - interval '24 hours'").param("u", u).query(Integer.class).single();
            if (n >= settings.getInt("risk.duplicate_callbacks_24h")) flag(u, null, "SUSPICIOUS_PAYMENT_CALLBACKS", "MEDIUM", today(), Map.of("replays24h", n));
        });
    }
}
