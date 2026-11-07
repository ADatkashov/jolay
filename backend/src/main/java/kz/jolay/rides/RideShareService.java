package kz.jolay.rides;

import kz.jolay.common.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.UUID;

/** Creates and revokes the public trip-sharing links (see {@link RideShareController}). */
@Service
public class RideShareService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcClient jdbc;
    private final String publicBase;

    public RideShareService(JdbcClient jdbc, @Value("${jolay.payments.public-base-url}") String publicBase) { this.jdbc = jdbc; this.publicBase = publicBase; }

    /** Returns the token of the ride's active share link, creating it first if needed. Only the ride's customer may share, and only while the ride is active. */
    @Transactional
    public String ensureToken(UUID rideId, UUID customerId) {
        String status = jdbc.sql("SELECT status FROM rides WHERE id=:r AND customer_id=:u FOR UPDATE").param("r", rideId).param("u", customerId).query(String.class).optional()
                .orElseThrow(() -> ApiException.notFound("ride_not_found", "Ride not found"));
        if (!status.matches("SEARCHING_DRIVER|DRIVER_ASSIGNED|DRIVER_ARRIVING|DRIVER_ARRIVED|IN_PROGRESS"))
            throw ApiException.conflict("ride_not_active", "Only an active ride can be shared");
        return jdbc.sql("SELECT token FROM ride_shares WHERE ride_id=:r AND revoked_at IS NULL").param("r", rideId).query(String.class).optional().orElseGet(() -> {
            byte[] b = new byte[24]; RANDOM.nextBytes(b);
            String t = Base64.getUrlEncoder().withoutPadding().encodeToString(b);
            jdbc.sql("INSERT INTO ride_shares(token, ride_id, created_by) VALUES (:t,:r,:u)").param("t", t).param("r", rideId).param("u", customerId).update();
            return t;
        });
    }

    public String urlFor(String token) { return publicBase + "/api/v1/catalog/trip/" + token; }
}
