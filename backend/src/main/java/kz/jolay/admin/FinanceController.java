package kz.jolay.admin;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

/** Read-only financial consistency checks. Every number here must be 0 (or an explainable backlog) on a healthy system. */
@RestController
@RequestMapping("/api/v1/admin/finance")
public class FinanceController {
    private final JdbcClient jdbc;
    public FinanceController(JdbcClient jdbc) { this.jdbc = jdbc; }

    @GetMapping("/reconciliation") @PreAuthorize("hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')")
    public Map<String, Object> reconciliation() {
        Map<String, Object> m = new LinkedHashMap<>();
        BigDecimal sum = jdbc.sql("SELECT COALESCE(sum(balance),0) FROM accounts").query(BigDecimal.class).single();
        long unbalanced = jdbc.sql("SELECT count(*) FROM (SELECT transaction_id FROM ledger_entries GROUP BY 1 HAVING sum(amount) <> 0) x").query(Long.class).single();
        long drift = jdbc.sql("SELECT count(*) FROM accounts a WHERE a.balance <> COALESCE((SELECT sum(amount) FROM ledger_entries e WHERE e.account_id=a.id),0)").query(Long.class).single();
        long succeededWithoutLedger = jdbc.sql("SELECT count(*) FROM payment_transactions p WHERE p.status IN ('SUCCEEDED','REFUNDED') AND NOT EXISTS (SELECT 1 FROM ledger_transactions t WHERE t.idempotency_key = 'pay-' || p.id::text)").query(Long.class).single();
        long paidRidesWithoutLedger = jdbc.sql("""
                SELECT count(*) FROM rides r JOIN ride_fares f ON f.ride_id=r.id
                WHERE r.payment_status='PAID' AND f.commission > 0
                  AND NOT EXISTS (SELECT 1 FROM ledger_transactions t WHERE t.ref_id = r.id)
                  AND NOT EXISTS (SELECT 1 FROM ledger_transactions t JOIN payment_transactions p ON p.id=t.ref_id WHERE p.ride_id=r.id)""").query(Long.class).single();
        long completedWithoutFare = jdbc.sql("SELECT count(*) FROM rides r WHERE r.status='COMPLETED' AND NOT EXISTS (SELECT 1 FROM ride_fares f WHERE f.ride_id=r.id)").query(Long.class).single();
        long stalePending = jdbc.sql("SELECT count(*) FROM payment_transactions WHERE status='PENDING' AND created_at < now() - interval '30 minutes'").query(Long.class).single();
        long unpaidCompleted = jdbc.sql("SELECT count(*) FROM rides WHERE status='COMPLETED' AND payment_status IN ('PENDING','FAILED','NONE') AND completed_at < now() - interval '1 hour'").query(Long.class).single();
        m.put("ledgerBalanceSum", sum);
        m.put("unbalancedLedgerTransactions", unbalanced);
        m.put("accountsWithBalanceDrift", drift);
        m.put("succeededPaymentsWithoutLedger", succeededWithoutLedger);
        m.put("paidRidesWithoutLedger", paidRidesWithoutLedger);
        m.put("completedRidesWithoutFare", completedWithoutFare);
        m.put("pendingPaymentsOlderThan30Min", stalePending);
        m.put("completedRidesUnpaidOverOneHour", unpaidCompleted);
        boolean critical = sum.signum() != 0 || unbalanced + drift + succeededWithoutLedger + paidRidesWithoutLedger + completedWithoutFare > 0;
        m.put("status", critical ? "CRITICAL" : (stalePending + unpaidCompleted > 0 ? "ATTENTION" : "OK"));
        return m;
    }
}
