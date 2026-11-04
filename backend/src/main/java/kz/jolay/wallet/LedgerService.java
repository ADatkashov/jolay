package kz.jolay.wallet;

import kz.jolay.common.ApiException;
import kz.jolay.common.Money;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * Double-entry, append-only ledger. Every balance change is a ledger transaction whose entries sum to zero.
 * Account balances are a cached projection updated in the same DB transaction, with row locks, ordered by account id
 * to avoid deadlocks. Idempotency keys make every posting safe to retry.
 */
@Service
public class LedgerService {
    private final JdbcClient jdbc;
    public LedgerService(JdbcClient jdbc) { this.jdbc = jdbc; }

    public record Leg(UUID accountId, BigDecimal amount) {}

    public UUID systemAccount(String type) {
        return jdbc.sql("SELECT id FROM accounts WHERE type=:t AND owner_id IS NULL").param("t", type).query(UUID.class).single();
    }

    @Transactional
    public UUID userAccount(UUID userId, String type) {
        return jdbc.sql("""
                INSERT INTO accounts(type, owner_id) VALUES (:t,:u)
                ON CONFLICT (owner_id, type) WHERE owner_id IS NOT NULL DO UPDATE SET type=EXCLUDED.type RETURNING id""")
                .param("t", type).param("u", userId).query(UUID.class).single();
    }

    public BigDecimal balance(UUID accountId) {
        return jdbc.sql("SELECT balance FROM accounts WHERE id=:id").param("id", accountId).query(BigDecimal.class).single();
    }

    /** Posts a balanced transaction. Returns the ledger transaction id (existing id if the idempotency key was already used). */
    @Transactional(propagation = Propagation.MANDATORY)
    public UUID post(String txType, String refType, UUID refId, String idempotencyKey, String description, List<Leg> legs) {
        BigDecimal sum = legs.stream().map(Leg::amount).reduce(BigDecimal.ZERO, BigDecimal::add);
        if (sum.compareTo(BigDecimal.ZERO) != 0) throw new IllegalStateException("Unbalanced ledger transaction: " + sum);
        if (legs.stream().anyMatch(l -> l.amount().signum() == 0)) throw new IllegalArgumentException("Zero-amount leg");

        if (idempotencyKey != null) {
            var existing = jdbc.sql("SELECT id FROM ledger_transactions WHERE idempotency_key=:k").param("k", idempotencyKey).query(UUID.class).optional();
            if (existing.isPresent()) return existing.get();
        }
        UUID txId = jdbc.sql("INSERT INTO ledger_transactions(tx_type,ref_type,ref_id,idempotency_key,description) VALUES (:t,:rt,:ri,:k,:d) RETURNING id")
                .param("t", txType).param("rt", refType).param("ri", refId).param("k", idempotencyKey).param("d", description)
                .query(UUID.class).single();

        // lock accounts in a stable order
        List<Leg> ordered = legs.stream().sorted((a, b) -> a.accountId().compareTo(b.accountId())).toList();
        for (Leg leg : ordered) {
            BigDecimal amount = Money.scale(leg.amount());
            BigDecimal after;
            try {
                after = jdbc.sql("UPDATE accounts SET balance = balance + :a WHERE id=:id RETURNING balance")
                        .param("a", amount).param("id", leg.accountId()).query(BigDecimal.class).single();
            } catch (org.springframework.dao.DataIntegrityViolationException e) {
                throw ApiException.conflict("insufficient_funds", "Insufficient wallet balance");
            }
            jdbc.sql("INSERT INTO ledger_entries(transaction_id,account_id,amount,balance_after) VALUES (:t,:a,:amt,:b)")
                    .param("t", txId).param("a", leg.accountId()).param("amt", amount).param("b", after).update();
        }
        return txId;
    }

    public List<java.util.Map<String, Object>> history(UUID accountId, int limit, int offset) {
        return jdbc.sql("""
                SELECT e.id, t.tx_type AS type, e.amount, e.balance_after, t.description, t.ref_type, t.ref_id, e.created_at
                FROM ledger_entries e JOIN ledger_transactions t ON t.id=e.transaction_id
                WHERE e.account_id=:a ORDER BY e.id DESC LIMIT :l OFFSET :o""")
                .param("a", accountId).param("l", Math.min(limit, 100)).param("o", offset).query().listOfRows();
    }
}
