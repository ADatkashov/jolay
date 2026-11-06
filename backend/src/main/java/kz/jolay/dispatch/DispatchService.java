package kz.jolay.dispatch;

import kz.jolay.common.ApiException;
import kz.jolay.common.AppSettings;
import kz.jolay.common.Money;
import kz.jolay.notifications.Notifier;
import kz.jolay.pricing.PricingService;
import kz.jolay.rides.RideStateMachine;
import kz.jolay.rides.RideStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Driver matching. One offer at a time per ride; a driver holds at most one OFFERED offer (DB unique indexes) and
 * candidate rows are locked with FOR UPDATE SKIP LOCKED so concurrent dispatchers never pick the same driver.
 * See docs/DISPATCH_ALGORITHM.md.
 */
@Service
public class DispatchService {
    private static final Logger log = LoggerFactory.getLogger(DispatchService.class);
    private final JdbcClient jdbc;
    private final AppSettings settings;
    private final RideStateMachine sm;
    private final Notifier notifier;
    private final PricingService pricing;
    private final TransactionTemplate tx;
    private final MeterRegistry metrics;

    public DispatchService(JdbcClient jdbc, AppSettings settings, RideStateMachine sm, Notifier notifier, PricingService pricing,
                           TransactionTemplate tx, MeterRegistry metrics) {
        this.jdbc = jdbc; this.settings = settings; this.sm = sm; this.notifier = notifier; this.pricing = pricing; this.tx = tx; this.metrics = metrics;
    }

    private record Candidate(UUID driverId, UUID vehicleId, double distanceM) {}

    /** Runs one dispatch round for the ride (idempotent: does nothing if an offer is already pending). */
    @Transactional
    public void dispatchRound(UUID rideId) {
        var ride = jdbc.sql("""
                SELECT id, customer_id, city_id, category_code, status, est_fare, pricing_rule_id,
                       ST_X(pickup::geometry) plng, ST_Y(pickup::geometry) plat, EXTRACT(EPOCH FROM (now()-search_started_at)) AS elapsed
                FROM rides WHERE id=:id FOR UPDATE""").param("id", rideId).query().listOfRows().stream().findFirst().orElse(null);
        if (ride == null || !"SEARCHING_DRIVER".equals(ride.get("status"))) return;

        if (jdbc.sql("SELECT count(*) FROM ride_offers WHERE ride_id=:r AND status='OFFERED'").param("r", rideId).query(Integer.class).single() > 0) return;

        double elapsed = ((Number) ride.get("elapsed")).doubleValue();
        if (elapsed > settings.getInt("dispatch.search_timeout_seconds")) {
            sm.move(rideId, RideStatus.SEARCHING_DRIVER, RideStatus.EXPIRED, "SYSTEM", ", cancelled_at=now(), cancelled_by='SYSTEM', cancel_reason='no_driver_found'", null);
            UUID customer = (UUID) ride.get("customer_id");
            notifier.notify(customer, "RIDE_EXPIRED", "ride-expired-" + rideId, Map.of("rideId", rideId.toString(), "status", "EXPIRED"));
            metrics.counter("jolay.dispatch.expired").increment();
            return;
        }

        int step = settings.getInt("dispatch.radius_step_m");
        int roundIdx = (int) (elapsed / Math.max(1, settings.getInt("dispatch.offer_timeout_seconds")));
        int radius = Math.min(settings.getInt("dispatch.max_radius_m"), settings.getInt("dispatch.initial_radius_m") + step * roundIdx);
        int maxAgeSec = settings.getInt("dispatch.location_max_age_seconds");
        BigDecimal floor = settings.getDecimal("wallet.driver_min_balance");

        List<Candidate> cands = jdbc.sql("""
                SELECT d.user_id, near.vehicle_id, near.dist
                FROM rides r
                JOIN LATERAL (
                    -- KNN over the GiST index: stops after :pool eligible drivers, so cost does not grow with driver density
                    SELECT dl.driver_id, v.id AS vehicle_id, ST_Distance(dl.location, r.pickup) AS dist
                    FROM driver_locations dl
                    JOIN drivers d2 ON d2.user_id = dl.driver_id
                    JOIN vehicles v ON v.driver_id = d2.user_id AND v.active AND v.approved
                    JOIN vehicle_categories vc ON vc.code = v.category_code
                    JOIN vehicle_categories rc ON rc.code = r.category_code
                    JOIN users u ON u.id = d2.user_id AND u.status='ACTIVE' AND u.deleted_at IS NULL
                    LEFT JOIN accounts a ON a.owner_id = d2.user_id AND a.type='DRIVER_WALLET'
                    WHERE d2.city_id = r.city_id AND d2.verification='APPROVED' AND d2.availability='ONLINE'
                      AND dl.updated_at > now() - make_interval(secs => :age)
                      AND ST_DWithin(dl.location, r.pickup, :radius)
                      AND ((rc.code='XL' AND vc.code='XL') OR (rc.code<>'XL' AND vc.code<>'XL' AND vc.rank >= rc.rank))
                      AND COALESCE(a.balance, 0) >= :floor
                      AND ((SELECT count(*) FROM ride_status_history h WHERE h.actor = 'DRIVER:' || d2.user_id AND h.to_status = 'SEARCHING_DRIVER' AND h.created_at > now() - make_interval(hours => :cwin))
                         + (SELECT count(*) FROM delivery_status_history h2 WHERE h2.actor = 'COURIER:' || d2.user_id AND h2.to_status = 'SEARCHING_COURIER' AND h2.created_at > now() - make_interval(hours => :cwin))) < :cmax
                      AND NOT EXISTS (SELECT 1 FROM ride_offers o WHERE o.ride_id=r.id AND o.driver_id=d2.user_id)
                    ORDER BY dl.location <-> r.pickup
                    LIMIT :pool
                ) near ON true
                JOIN drivers d ON d.user_id = near.driver_id
                WHERE r.id = :rid
                ORDER BY near.dist * (1 + 0.5 * (1 - CASE WHEN d.offers_total = 0 THEN 1.0 ELSE d.offers_accepted::numeric / d.offers_total END)), d.user_id
                LIMIT :n
                FOR UPDATE OF d SKIP LOCKED""")
                .param("cwin", settings.getInt("dispatch.cancel_cooldown_hours")).param("cmax", settings.getInt("dispatch.cancel_cooldown_count")).param("rid", rideId).param("age", maxAgeSec).param("radius", radius).param("floor", floor)
                .param("pool", settings.getInt("dispatch.candidate_pool")).param("n", settings.getInt("dispatch.max_candidates_per_round"))
                .query((rs, i) -> new Candidate(rs.getObject("user_id", UUID.class), rs.getObject("vehicle_id", UUID.class), rs.getDouble("dist"))).list();

        if (cands.isEmpty()) return;         // the scheduler retries with a wider radius as time passes
        Candidate best = cands.get(0);

        int moved = jdbc.sql("UPDATE drivers SET availability='OFFERED', offers_total=offers_total+1, updated_at=now() WHERE user_id=:d AND availability='ONLINE'")
                .param("d", best.driverId()).update();
        if (moved != 1) return;
        recordDriverStatus(best.driverId(), "ONLINE", "OFFERED");

        double speed = settings.getDecimal("rides.avg_speed_kmh").doubleValue() / 3.6;
        int etaS = (int) Math.round(best.distanceM() * settings.getDecimal("rides.detour_factor").doubleValue() / speed);
        var rule = pricing.ruleById((UUID) ride.get("pricing_rule_id"));
        BigDecimal estFare = (BigDecimal) ride.get("est_fare");
        BigDecimal earnings = estFare.subtract(Money.scale(estFare.multiply(rule.commissionRate())));

        UUID offerId = jdbc.sql("""
                INSERT INTO ride_offers(ride_id, driver_id, status, pickup_distance_m, eta_s, expected_earnings, expires_at)
                VALUES (:r,:d,'OFFERED',:dist,:eta,:earn, now() + make_interval(secs => :t)) RETURNING id""")
                .param("r", rideId).param("d", best.driverId()).param("dist", (int) Math.round(best.distanceM())).param("eta", etaS)
                .param("earn", earnings).param("t", settings.getInt("dispatch.offer_timeout_seconds")).query(UUID.class).single();
        metrics.counter("jolay.dispatch.offers").increment();
        notifier.notify(best.driverId(), "RIDE_OFFER", "offer-" + offerId,
                Map.of("offerId", offerId.toString(), "rideId", rideId.toString(), "pickupDistanceM", (int) Math.round(best.distanceM()),
                        "etaSeconds", etaS, "expectedEarnings", earnings));
    }

    private void recordDriverStatus(UUID driverId, String from, String to) {
        jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,:f,:t)").param("d", driverId).param("f", from).param("t", to).update();
    }

    // ---------------- driver responses ----------------
    @Transactional
    public UUID accept(UUID driverId, UUID offerId) {
        var offer = jdbc.sql("SELECT id, ride_id, driver_id, status, expires_at < now() AS expired FROM ride_offers WHERE id=:id FOR UPDATE")
                .param("id", offerId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("offer_not_found", "Offer not found"));
        if (!driverId.equals(offer.get("driver_id"))) throw ApiException.notFound("offer_not_found", "Offer not found");
        UUID rideId = (UUID) offer.get("ride_id");
        if (!"OFFERED".equals(offer.get("status"))) throw ApiException.conflict("offer_closed", "Offer is no longer available");
        if ((Boolean) offer.get("expired")) throw ApiException.conflict("offer_expired", "Offer has expired");

        RideStatus st = sm.current(rideId, true);
        if (st != RideStatus.SEARCHING_DRIVER) throw ApiException.conflict("offer_closed", "Ride is no longer available");

        UUID vehicleId = jdbc.sql("SELECT id FROM vehicles WHERE driver_id=:d AND active AND approved LIMIT 1").param("d", driverId).query(UUID.class).optional()
                .orElseThrow(() -> ApiException.conflict("no_vehicle", "No approved vehicle"));
        jdbc.sql("UPDATE ride_offers SET status='ACCEPTED', responded_at=now() WHERE id=:id").param("id", offerId).update();
        sm.move(rideId, RideStatus.SEARCHING_DRIVER, RideStatus.DRIVER_ASSIGNED, "DRIVER:" + driverId,
                ", driver_id=:d, vehicle_id=:v, assigned_at=now()", Map.of("d", driverId, "v", vehicleId));
        int upd = jdbc.sql("UPDATE drivers SET availability='BUSY', offers_accepted=offers_accepted+1, updated_at=now() WHERE user_id=:d AND availability='OFFERED' AND verification='APPROVED'")
                .param("d", driverId).update();
        if (upd != 1) throw ApiException.conflict("driver_unavailable", "Driver is not available");
        recordDriverStatus(driverId, "OFFERED", "BUSY");

        UUID customer = jdbc.sql("SELECT customer_id FROM rides WHERE id=:id").param("id", rideId).query(UUID.class).single();
        metrics.counter("jolay.dispatch.accepted").increment();
        notifier.notify(customer, "DRIVER_ACCEPTED", "ride-" + rideId + "-assigned-" + driverId,
                Map.of("rideId", rideId.toString(), "status", "DRIVER_ASSIGNED"));
        return rideId;
    }

    @Transactional
    public void decline(UUID driverId, UUID offerId) {
        var offer = jdbc.sql("SELECT ride_id, driver_id, status FROM ride_offers WHERE id=:id FOR UPDATE").param("id", offerId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("offer_not_found", "Offer not found"));
        if (!driverId.equals(offer.get("driver_id"))) throw ApiException.notFound("offer_not_found", "Offer not found");
        if (!"OFFERED".equals(offer.get("status"))) throw ApiException.conflict("offer_closed", "Offer is no longer available");
        jdbc.sql("UPDATE ride_offers SET status='DECLINED', responded_at=now() WHERE id=:id").param("id", offerId).update();
        releaseDriver(driverId);
        dispatchRound((UUID) offer.get("ride_id"));
    }

    private void releaseDriver(UUID driverId) {
        if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='OFFERED'").param("d", driverId).update() == 1)
            recordDriverStatus(driverId, "OFFERED", "ONLINE");
    }

    /** Cancels any pending offer for the ride and frees the offered driver (used on cancellation). */
    @Transactional
    public void cancelOffers(UUID rideId) {
        List<UUID> drivers = jdbc.sql("UPDATE ride_offers SET status='CANCELLED', responded_at=now() WHERE ride_id=:r AND status='OFFERED' RETURNING driver_id")
                .param("r", rideId).query(UUID.class).list();
        for (UUID d : drivers) {
            releaseDriver(d);
            notifier.event(d, "OFFER_CANCELLED", Map.of("rideId", rideId.toString()));
        }
    }

    // ---------------- scheduler ----------------
    @Scheduled(fixedDelayString = "${jolay.dispatch.scheduler-delay-ms:2000}")
    public void tick() {
        try { expireOffers(); } catch (Exception e) { log.error("expireOffers failed", e); }
        List<UUID> rides = jdbc.sql("""
                SELECT r.id FROM rides r WHERE r.status='SEARCHING_DRIVER'
                  AND NOT EXISTS (SELECT 1 FROM ride_offers o WHERE o.ride_id=r.id AND o.status='OFFERED')
                ORDER BY r.created_at LIMIT 100""").query(UUID.class).list();
        for (UUID id : rides) {
            try { tx.executeWithoutResult(s -> dispatchRound(id)); }
            catch (Exception e) { log.warn("dispatch round failed for ride {}: {}", id, e.toString()); }
        }
    }

    /** Public for tests: expires timed-out offers and frees the drivers. */
    public void expireOffers() {
        tx.executeWithoutResult(s -> {
            List<UUID> drivers = jdbc.sql("UPDATE ride_offers SET status='EXPIRED', responded_at=now() WHERE status='OFFERED' AND expires_at < now() RETURNING driver_id")
                    .query(UUID.class).list();
            for (UUID d : drivers) {
                releaseDriver(d);
                notifier.event(d, "OFFER_EXPIRED", Map.of());
                metrics.counter("jolay.dispatch.offer_timeouts").increment();
            }
        });
    }
}
