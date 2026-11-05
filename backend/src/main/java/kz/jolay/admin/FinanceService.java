package kz.jolay.admin;

import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Financial consistency checks. Every number must be 0 (or an explainable backlog). Runs hourly and on demand from the admin API. */
@Service
public class FinanceService {
    private static final Logger log = LoggerFactory.getLogger(FinanceService.class);
    private final JdbcClient jdbc;
    private final AtomicInteger critical = new AtomicInteger();

    public FinanceService(JdbcClient jdbc, MeterRegistry metrics) { this.jdbc = jdbc; metrics.gauge("jolay.reconciliation.critical", critical); }

    private long count(String sql) { return jdbc.sql(sql).query(Long.class).single(); }

    public Map<String, Object> reconciliation() {
        Map<String, Object> m = new LinkedHashMap<>();
        BigDecimal sum = jdbc.sql("SELECT COALESCE(sum(balance),0) FROM accounts").query(BigDecimal.class).single();
        long unbalanced = count("SELECT count(*) FROM (SELECT transaction_id FROM ledger_entries GROUP BY 1 HAVING sum(amount) <> 0) x");
        long drift = count("SELECT count(*) FROM accounts a WHERE a.balance <> COALESCE((SELECT sum(amount) FROM ledger_entries e WHERE e.account_id=a.id),0)");
        long succeededWithoutLedger = count("SELECT count(*) FROM payment_transactions p WHERE p.status IN ('SUCCEEDED','REFUNDED') AND NOT EXISTS (SELECT 1 FROM ledger_transactions t WHERE t.idempotency_key = 'pay-' || p.id::text)");
        long paidRidesWithoutLedger = count("""
                SELECT count(*) FROM rides r JOIN ride_fares f ON f.ride_id=r.id
                WHERE r.payment_status='PAID' AND f.commission > 0
                  AND NOT EXISTS (SELECT 1 FROM ledger_transactions t WHERE t.ref_id = r.id)
                  AND NOT EXISTS (SELECT 1 FROM ledger_transactions t JOIN payment_transactions p ON p.id=t.ref_id WHERE p.ride_id=r.id)""");
        long completedWithoutFare = count("SELECT count(*) FROM rides r WHERE r.status='COMPLETED' AND NOT EXISTS (SELECT 1 FROM ride_fares f WHERE f.ride_id=r.id)");
        long paidPayoutsWithoutLedger = count("SELECT count(*) FROM payouts p WHERE p.status IN ('PAID','REJECTED') AND p.final_tx IS NULL");
        BigDecimal held = jdbc.sql("SELECT COALESCE(sum(amount),0) FROM payouts WHERE status='REQUESTED'").query(BigDecimal.class).single();
        BigDecimal clearing = jdbc.sql("SELECT balance FROM accounts WHERE type='PAYOUT_CLEARING'").query(BigDecimal.class).single();
        long clearingMismatch = held.compareTo(clearing) == 0 ? 0 : 1;
        BigDecimal openOrders = jdbc.sql("SELECT COALESCE(sum(items_total + delivery_fee),0) FROM store_orders WHERE status IN ('PLACED','ACCEPTED','READY')").query(BigDecimal.class).single();
        BigDecimal escrow = jdbc.sql("SELECT balance FROM accounts WHERE type='ORDER_ESCROW'").query(BigDecimal.class).single();
        long escrowMismatch = openOrders.compareTo(escrow) == 0 ? 0 : 1;
        long stalePending = count("SELECT count(*) FROM payment_transactions WHERE status='PENDING' AND created_at < now() - interval '30 minutes'");
        long unpaidCompleted = count("SELECT count(*) FROM rides WHERE status='COMPLETED' AND payment_status IN ('PENDING','FAILED','NONE') AND completed_at < now() - interval '1 hour'");
        long oldPayouts = count("SELECT count(*) FROM payouts WHERE status='REQUESTED' AND created_at < now() - interval '3 days'");
        m.put("ledgerBalanceSum", sum);
        m.put("unbalancedLedgerTransactions", unbalanced);
        m.put("accountsWithBalanceDrift", drift);
        m.put("succeededPaymentsWithoutLedger", succeededWithoutLedger);
        m.put("paidRidesWithoutLedger", paidRidesWithoutLedger);
        m.put("completedRidesWithoutFare", completedWithoutFare);
        m.put("processedPayoutsWithoutLedger", paidPayoutsWithoutLedger);
        m.put("payoutHoldMismatch", clearingMismatch);
        m.put("orderEscrowMismatch", escrowMismatch);
        m.put("pendingPaymentsOlderThan30Min", stalePending);
        m.put("completedRidesUnpaidOverOneHour", unpaidCompleted);
        m.put("payoutRequestsOlderThan3Days", oldPayouts);
        boolean crit = sum.signum() != 0 || unbalanced + drift + succeededWithoutLedger + paidRidesWithoutLedger + completedWithoutFare + paidPayoutsWithoutLedger + clearingMismatch + escrowMismatch > 0;
        m.put("status", crit ? "CRITICAL" : (stalePending + unpaidCompleted + oldPayouts > 0 ? "ATTENTION" : "OK"));
        return m;
    }

    @Scheduled(initialDelayString = "PT5M", fixedDelayString = "PT1H")
    public void scheduledCheck() {
        try {
            Map<String, Object> r = reconciliation();
            critical.set("CRITICAL".equals(r.get("status")) ? 1 : 0);
            if ("CRITICAL".equals(r.get("status"))) log.error("FINANCIAL RECONCILIATION CRITICAL: {}", r);
            else if ("ATTENTION".equals(r.get("status"))) log.warn("financial reconciliation needs attention: {}", r);
        } catch (Exception e) { log.error("reconciliation job failed", e); }
    }
}
