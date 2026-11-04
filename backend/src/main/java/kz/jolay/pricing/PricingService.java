package kz.jolay.pricing;

import kz.jolay.common.ApiException;
import kz.jolay.common.Money;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.UUID;

/** Server-side fare engine. Clients can never submit a fare; they only receive what is computed here. */
@Service
public class PricingService {
    private final JdbcClient jdbc;
    public PricingService(JdbcClient jdbc) { this.jdbc = jdbc; }

    public record Rule(UUID id, UUID cityId, String category, BigDecimal baseFare, BigDecimal perKm, BigDecimal perMinute,
                       BigDecimal minFare, BigDecimal bookingFee, BigDecimal cancellationFee, int freeCancelSeconds,
                       BigDecimal commissionRate, BigDecimal demandMultiplier, BigDecimal roundingStep, boolean active) {}

    public record Fare(BigDecimal baseFare, BigDecimal distanceFare, BigDecimal timeFare, BigDecimal fees, BigDecimal discount,
                       BigDecimal multiplier, BigDecimal total, BigDecimal commissionRate, BigDecimal commission, BigDecimal driverEarnings) {}

    public Rule rule(UUID cityId, String category) {
        return jdbc.sql("SELECT * FROM pricing_rules WHERE city_id=:c AND category_code=:k AND active")
                .param("c", cityId).param("k", category).query((rs, i) -> map(rs)).optional()
                .orElseThrow(() -> ApiException.badRequest("category_unavailable", "This ride category is not available in your city"));
    }

    public Rule ruleById(UUID id) {
        return jdbc.sql("SELECT * FROM pricing_rules WHERE id=:id").param("id", id).query((rs, i) -> map(rs)).single();
    }

    public List<Rule> rules(UUID cityId) {
        return jdbc.sql("SELECT r.* FROM pricing_rules r JOIN vehicle_categories v ON v.code=r.category_code WHERE r.city_id=:c AND r.active AND v.active ORDER BY v.rank")
                .param("c", cityId).query((rs, i) -> map(rs)).list();
    }

    private static Rule map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Rule(rs.getObject("id", UUID.class), rs.getObject("city_id", UUID.class), rs.getString("category_code"),
                rs.getBigDecimal("base_fare"), rs.getBigDecimal("per_km"), rs.getBigDecimal("per_minute"), rs.getBigDecimal("min_fare"),
                rs.getBigDecimal("booking_fee"), rs.getBigDecimal("cancellation_fee"), rs.getInt("free_cancel_seconds"),
                rs.getBigDecimal("commission_rate"), rs.getBigDecimal("demand_multiplier"), rs.getBigDecimal("rounding_step"), rs.getBoolean("active"));
    }

    /**
     * total = max(minFare, (base + km*dist + min*dur) * demandMultiplier + fees - discount), rounded up to the rounding step.
     * commission = total * commissionRate; driver earnings = total - commission.
     */
    public Fare compute(Rule r, int distanceM, int durationS, BigDecimal discount) {
        BigDecimal km = BigDecimal.valueOf(distanceM).divide(BigDecimal.valueOf(1000), 4, RoundingMode.HALF_UP);
        BigDecimal minutes = BigDecimal.valueOf(durationS).divide(BigDecimal.valueOf(60), 4, RoundingMode.HALF_UP);
        BigDecimal distanceFare = Money.scale(r.perKm().multiply(km));
        BigDecimal timeFare = Money.scale(r.perMinute().multiply(minutes));
        BigDecimal variable = Money.scale(r.baseFare().add(distanceFare).add(timeFare).multiply(r.demandMultiplier()));
        BigDecimal disc = discount == null ? Money.ZERO : Money.scale(discount);
        BigDecimal raw = variable.add(r.bookingFee()).subtract(disc);
        BigDecimal total = Money.roundUp(raw.max(r.minFare()), r.roundingStep());
        BigDecimal commission = Money.scale(total.multiply(r.commissionRate()));
        return new Fare(Money.scale(r.baseFare()), distanceFare, timeFare, Money.scale(r.bookingFee()), disc,
                r.demandMultiplier(), total, r.commissionRate(), commission, total.subtract(commission));
    }
}
