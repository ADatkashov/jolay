package kz.jolay.marketplace;

import kz.jolay.notifications.Notifier;
import kz.jolay.wallet.LedgerService;
import kz.jolay.wallet.LedgerService.Leg;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Money movements of a store order. Funds are held in ORDER_ESCROW from placement until hand-over.
 *  delivered:  ESCROW -> partner wallet (items - commission) + courier wallet (delivery share) + platform revenue (commission + delivery cut)
 *  otherwise:  ESCROW -> customer wallet (full refund)
 * Every posting has an idempotency key, so retries and concurrent callers can never pay twice.
 */
@Component
public class StoreSettlement {
    private final JdbcClient jdbc;
    private final LedgerService ledger;
    private final Notifier notifier;
    public StoreSettlement(JdbcClient jdbc, LedgerService ledger, Notifier notifier) { this.jdbc = jdbc; this.ledger = ledger; this.notifier = notifier; }

    @Transactional(propagation = Propagation.MANDATORY)
    public void hold(UUID orderId, UUID customerId, BigDecimal total) {
        UUID tx = ledger.post("ORDER_ESCROW", "STORE_ORDER", orderId, "order-escrow-" + orderId, "Store order payment held",
                List.of(new Leg(ledger.userAccount(customerId, "CUSTOMER_WALLET"), total.negate()), new Leg(ledger.systemAccount("ORDER_ESCROW"), total)));
        jdbc.sql("UPDATE store_orders SET escrow_tx=:t WHERE id=:id").param("t", tx).param("id", orderId).update();
    }

    /** Called when the delivery leg is handed over. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void settleDelivered(UUID orderId, UUID courierId) {
        var o = jdbc.sql("SELECT customer_id, partner_id, items_total, delivery_fee, partner_commission, delivery_courier_earnings, delivery_platform_cut, status FROM store_orders WHERE id=:id FOR UPDATE").param("id", orderId).query().listOfRows().get(0);
        if ("COMPLETED".equals(o.get("status"))) return;
        BigDecimal total = ((BigDecimal) o.get("items_total")).add((BigDecimal) o.get("delivery_fee"));
        BigDecimal toPartner = ((BigDecimal) o.get("items_total")).subtract((BigDecimal) o.get("partner_commission"));
        BigDecimal toPlatform = ((BigDecimal) o.get("partner_commission")).add((BigDecimal) o.get("delivery_platform_cut"));
        UUID partnerUser = jdbc.sql("SELECT owner_id FROM partners WHERE id=:p").param("p", o.get("partner_id")).query(UUID.class).single();
        List<Leg> legs = new ArrayList<>();
        legs.add(new Leg(ledger.systemAccount("ORDER_ESCROW"), total.negate()));
        if (toPartner.signum() > 0) legs.add(new Leg(ledger.userAccount(partnerUser, "PARTNER_WALLET"), toPartner));
        if (((BigDecimal) o.get("delivery_courier_earnings")).signum() > 0) legs.add(new Leg(ledger.userAccount(courierId, "DRIVER_WALLET"), (BigDecimal) o.get("delivery_courier_earnings")));
        if (toPlatform.signum() > 0) legs.add(new Leg(ledger.systemAccount("PLATFORM_REVENUE"), toPlatform));
        ledger.post("ORDER_SETTLEMENT", "STORE_ORDER", orderId, "order-settle-" + orderId, "Store order settled", legs);
        jdbc.sql("UPDATE store_orders SET status='COMPLETED', completed_at=now(), updated_at=now() WHERE id=:id").param("id", orderId).update();
        notifier.notify((UUID) o.get("customer_id"), "STORE_ORDER_STATUS", "store-order-" + orderId + "-completed", Map.of("orderId", orderId.toString(), "status", "COMPLETED"));
        notifier.notify(partnerUser, "STORE_ORDER_STATUS", "store-order-" + orderId + "-completed-p", Map.of("orderId", orderId.toString(), "status", "COMPLETED"));
    }

    /** Refunds the customer in full and closes the order as REJECTED / CANCELLED / FAILED. No-op if it is already closed. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void refundAndClose(UUID orderId, String finalStatus, String reason) {
        var o = jdbc.sql("SELECT customer_id, partner_id, items_total, delivery_fee, status FROM store_orders WHERE id=:id FOR UPDATE").param("id", orderId).query().listOfRows().get(0);
        String st = (String) o.get("status");
        if (st.equals("COMPLETED") || st.equals("REJECTED") || st.equals("CANCELLED") || st.equals("FAILED")) return;
        BigDecimal total = ((BigDecimal) o.get("items_total")).add((BigDecimal) o.get("delivery_fee"));
        ledger.post("ORDER_REFUND", "STORE_ORDER", orderId, "order-refund-" + orderId, "Store order refunded: " + finalStatus,
                List.of(new Leg(ledger.systemAccount("ORDER_ESCROW"), total.negate()), new Leg(ledger.userAccount((UUID) o.get("customer_id"), "CUSTOMER_WALLET"), total)));
        jdbc.sql("UPDATE store_orders SET status=:s, reject_reason=:r, updated_at=now() WHERE id=:id").param("s", finalStatus).param("r", reason).param("id", orderId).update();
        UUID partnerUser = jdbc.sql("SELECT owner_id FROM partners WHERE id=:p").param("p", o.get("partner_id")).query(UUID.class).single();
        notifier.notify((UUID) o.get("customer_id"), "STORE_ORDER_STATUS", "store-order-" + orderId + "-" + finalStatus.toLowerCase(), Map.of("orderId", orderId.toString(), "status", finalStatus));
        if (!"REJECTED".equals(finalStatus)) notifier.notify(partnerUser, "STORE_ORDER_STATUS", "store-order-" + orderId + "-" + finalStatus.toLowerCase() + "-p", Map.of("orderId", orderId.toString(), "status", finalStatus));
    }
}
