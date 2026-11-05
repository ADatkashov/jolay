package kz.jolay.delivery;

import kz.jolay.common.ApiException;
import kz.jolay.common.AppSettings;
import kz.jolay.marketplace.StoreSettlement;
import kz.jolay.notifications.Notifier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Courier matching for parcel deliveries. Same safety model as ride dispatch: KNN pool, SKIP LOCKED, one live offer per order and per courier (DB unique indexes). */
@Service
public class DeliveryDispatchService {
    private static final Logger log = LoggerFactory.getLogger(DeliveryDispatchService.class);
    private final JdbcClient jdbc;
    private final AppSettings settings;
    private final Notifier notifier;
    private final DeliveryStateMachine sm;
    private final TransactionTemplate tx;
    private final StoreSettlement storeSettlement;

    public DeliveryDispatchService(JdbcClient jdbc, AppSettings settings, Notifier notifier, DeliveryStateMachine sm, TransactionTemplate tx, StoreSettlement storeSettlement) {
        this.jdbc = jdbc; this.settings = settings; this.notifier = notifier; this.sm = sm; this.tx = tx; this.storeSettlement = storeSettlement;
    }

    private record Candidate(UUID courierId, double distanceM) {}

    @Transactional
    public void dispatchRound(UUID id) {
        var d = jdbc.sql("SELECT id, customer_id, status, courier_earnings, EXTRACT(EPOCH FROM (now()-search_started_at)) AS elapsed FROM delivery_orders WHERE id=:id FOR UPDATE").param("id", id)
                .query().listOfRows().stream().findFirst().orElse(null);
        if (d == null || !"SEARCHING_COURIER".equals(d.get("status"))) return;
        if (jdbc.sql("SELECT count(*) FROM delivery_offers WHERE delivery_id=:d AND status='OFFERED'").param("d", id).query(Integer.class).single() > 0) return;

        double elapsed = ((Number) d.get("elapsed")).doubleValue();
        if (elapsed > settings.getInt("delivery.search_timeout_seconds")) {
            sm.move(id, DeliveryStatus.SEARCHING_COURIER, DeliveryStatus.EXPIRED, "SYSTEM", ", cancelled_at=now(), cancelled_by='SYSTEM', cancel_reason='no_courier_found'", null);
            notifier.notify((UUID) d.get("customer_id"), "DELIVERY_STATUS", "delivery-" + id + "-expired", Map.of("deliveryId", id.toString(), "status", "EXPIRED"));
            // a store order whose delivery found no courier is refunded in full
            jdbc.sql("SELECT store_order_id FROM delivery_orders WHERE id=:id AND store_order_id IS NOT NULL").param("id", id).query(UUID.class).optional().ifPresent(so -> storeSettlement.refundAndClose(so, "FAILED", "no_courier_found"));
            return;
        }
        int radius = Math.min(settings.getInt("dispatch.max_radius_m"), settings.getInt("dispatch.initial_radius_m")
                + settings.getInt("dispatch.radius_step_m") * (int) (elapsed / Math.max(1, settings.getInt("dispatch.offer_timeout_seconds"))));

        List<Candidate> cands = jdbc.sql("""
                SELECT d.user_id, near.dist
                FROM delivery_orders o
                JOIN LATERAL (
                    SELECT dl.driver_id, ST_Distance(dl.location, o.pickup) AS dist
                    FROM driver_locations dl
                    JOIN drivers d2 ON d2.user_id = dl.driver_id
                    JOIN users u ON u.id = d2.user_id AND u.status='ACTIVE' AND u.deleted_at IS NULL
                    LEFT JOIN accounts a ON a.owner_id = d2.user_id AND a.type='DRIVER_WALLET'
                    WHERE d2.city_id = o.city_id AND d2.verification='APPROVED' AND d2.availability='ONLINE' AND d2.accepts_delivery
                      AND EXISTS (SELECT 1 FROM vehicles v WHERE v.driver_id=d2.user_id AND v.active AND v.approved)
                      AND dl.updated_at > now() - make_interval(secs => :age)
                      AND ST_DWithin(dl.location, o.pickup, :radius)
                      AND COALESCE(a.balance, 0) >= :floor
                      AND NOT EXISTS (SELECT 1 FROM delivery_offers x WHERE x.delivery_id=o.id AND x.courier_id=d2.user_id)
                    ORDER BY dl.location <-> o.pickup
                    LIMIT :pool
                ) near ON true
                JOIN drivers d ON d.user_id = near.driver_id
                WHERE o.id = :id
                ORDER BY near.dist * (1 + 0.5 * (1 - CASE WHEN d.offers_total = 0 THEN 1.0 ELSE d.offers_accepted::numeric / d.offers_total END)), d.user_id
                LIMIT 1
                FOR UPDATE OF d SKIP LOCKED""")
                .param("id", id).param("age", settings.getInt("dispatch.location_max_age_seconds")).param("radius", radius)
                .param("floor", settings.getDecimal("wallet.driver_min_balance")).param("pool", settings.getInt("dispatch.candidate_pool"))
                .query((rs, i) -> new Candidate(rs.getObject("user_id", UUID.class), rs.getDouble("dist"))).list();
        if (cands.isEmpty()) return;

        Candidate c = cands.get(0);
        if (jdbc.sql("UPDATE drivers SET availability='OFFERED', offers_total=offers_total+1, updated_at=now() WHERE user_id=:d AND availability='ONLINE'").param("d", c.courierId()).update() != 1) return;
        jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'ONLINE','OFFERED')").param("d", c.courierId()).update();
        UUID offerId = jdbc.sql("INSERT INTO delivery_offers(delivery_id,courier_id,status,pickup_distance_m,expected_earnings,expires_at) VALUES (:d,:c,'OFFERED',:dist,:e, now() + make_interval(secs => :t)) RETURNING id")
                .param("d", id).param("c", c.courierId()).param("dist", (int) Math.round(c.distanceM())).param("e", d.get("courier_earnings")).param("t", settings.getInt("dispatch.offer_timeout_seconds")).query(UUID.class).single();
        notifier.notify(c.courierId(), "DELIVERY_OFFER", "delivery-offer-" + offerId, Map.of("offerId", offerId.toString(), "deliveryId", id.toString(), "pickupDistanceM", (int) Math.round(c.distanceM()), "expectedEarnings", d.get("courier_earnings")));
    }

    @Transactional
    public UUID accept(UUID courierId, UUID offerId) {
        var o = jdbc.sql("SELECT delivery_id, courier_id, status, expires_at < now() AS expired FROM delivery_offers WHERE id=:id FOR UPDATE").param("id", offerId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("offer_not_found", "Offer not found"));
        if (!courierId.equals(o.get("courier_id"))) throw ApiException.notFound("offer_not_found", "Offer not found");
        UUID deliveryId = (UUID) o.get("delivery_id");
        if (!"OFFERED".equals(o.get("status"))) throw ApiException.conflict("offer_closed", "Offer is no longer available");
        if ((Boolean) o.get("expired")) throw ApiException.conflict("offer_expired", "Offer has expired");
        if (sm.current(deliveryId, true) != DeliveryStatus.SEARCHING_COURIER) throw ApiException.conflict("offer_closed", "Order is no longer available");
        jdbc.sql("UPDATE delivery_offers SET status='ACCEPTED', responded_at=now() WHERE id=:id").param("id", offerId).update();
        sm.move(deliveryId, DeliveryStatus.SEARCHING_COURIER, DeliveryStatus.COURIER_ASSIGNED, "COURIER:" + courierId, ", courier_id=:c, assigned_at=now()", Map.of("c", courierId));
        if (jdbc.sql("UPDATE drivers SET availability='BUSY', offers_accepted=offers_accepted+1, updated_at=now() WHERE user_id=:d AND availability='OFFERED' AND verification='APPROVED'").param("d", courierId).update() != 1)
            throw ApiException.conflict("driver_unavailable", "Courier is not available");
        jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'OFFERED','BUSY')").param("d", courierId).update();
        UUID customer = jdbc.sql("SELECT customer_id FROM delivery_orders WHERE id=:id").param("id", deliveryId).query(UUID.class).single();
        notifier.notify(customer, "DELIVERY_STATUS", "delivery-" + deliveryId + "-assigned-" + courierId, Map.of("deliveryId", deliveryId.toString(), "status", "COURIER_ASSIGNED"));
        return deliveryId;
    }

    @Transactional
    public void decline(UUID courierId, UUID offerId) {
        var o = jdbc.sql("SELECT delivery_id, courier_id, status FROM delivery_offers WHERE id=:id FOR UPDATE").param("id", offerId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("offer_not_found", "Offer not found"));
        if (!courierId.equals(o.get("courier_id"))) throw ApiException.notFound("offer_not_found", "Offer not found");
        if (!"OFFERED".equals(o.get("status"))) throw ApiException.conflict("offer_closed", "Offer is no longer available");
        jdbc.sql("UPDATE delivery_offers SET status='DECLINED', responded_at=now() WHERE id=:id").param("id", offerId).update();
        release(courierId);
        dispatchRound((UUID) o.get("delivery_id"));
    }

    private void release(UUID courierId) {
        if (jdbc.sql("UPDATE drivers SET availability='ONLINE', updated_at=now() WHERE user_id=:d AND availability='OFFERED'").param("d", courierId).update() == 1)
            jdbc.sql("INSERT INTO driver_status_history(driver_id,from_status,to_status) VALUES (:d,'OFFERED','ONLINE')").param("d", courierId).update();
    }

    @Transactional
    public void cancelOffers(UUID deliveryId) {
        for (UUID c : jdbc.sql("UPDATE delivery_offers SET status='CANCELLED', responded_at=now() WHERE delivery_id=:d AND status='OFFERED' RETURNING courier_id").param("d", deliveryId).query(UUID.class).list()) {
            release(c);
            notifier.event(c, "OFFER_CANCELLED", Map.of("deliveryId", deliveryId.toString()));
        }
    }

    @Scheduled(fixedDelayString = "${jolay.dispatch.scheduler-delay-ms:2000}")
    public void tick() {
        try { expireOffers(); } catch (Exception e) { log.error("delivery expireOffers failed", e); }
        for (UUID id : jdbc.sql("SELECT o.id FROM delivery_orders o WHERE o.status='SEARCHING_COURIER' AND NOT EXISTS (SELECT 1 FROM delivery_offers x WHERE x.delivery_id=o.id AND x.status='OFFERED') ORDER BY o.created_at LIMIT 100").query(UUID.class).list()) {
            try { tx.executeWithoutResult(s -> dispatchRound(id)); } catch (Exception e) { log.warn("delivery dispatch failed for {}: {}", id, e.toString()); }
        }
    }

    public void expireOffers() {
        tx.executeWithoutResult(s -> {
            for (UUID c : jdbc.sql("UPDATE delivery_offers SET status='EXPIRED', responded_at=now() WHERE status='OFFERED' AND expires_at < now() RETURNING courier_id").query(UUID.class).list()) {
                release(c);
                notifier.event(c, "OFFER_EXPIRED", Map.of());
            }
        });
    }
}
