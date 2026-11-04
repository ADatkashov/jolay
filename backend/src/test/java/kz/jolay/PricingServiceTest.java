package kz.jolay;

import kz.jolay.pricing.PricingService;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class PricingServiceTest {
    private final PricingService svc = new PricingService(null);

    private PricingService.Rule rule(String mult, String min) {
        return new PricingService.Rule(UUID.randomUUID(), UUID.randomUUID(), "ECONOMY", new BigDecimal("300"), new BigDecimal("110"), new BigDecimal("18"),
                new BigDecimal(min), new BigDecimal("0"), new BigDecimal("300"), 120, new BigDecimal("0.15"), new BigDecimal(mult), new BigDecimal("10"), true);
    }

    @Test void computesComponentsAndRoundsUpToStep() {
        var f = svc.compute(rule("1.00", "600"), 7000, 900, null);       // 300 + 7km*110 + 15min*18 = 300+770+270 = 1340
        assertEquals(0, new BigDecimal("770.00").compareTo(f.distanceFare()));
        assertEquals(0, new BigDecimal("270.00").compareTo(f.timeFare()));
        assertEquals(0, new BigDecimal("1340.00").compareTo(f.total()));
        assertEquals(0, new BigDecimal("201.00").compareTo(f.commission()));
        assertEquals(f.total(), f.commission().add(f.driverEarnings()));
    }
    @Test void minimumFareApplies() {
        assertEquals(0, new BigDecimal("600.00").compareTo(svc.compute(rule("1.00", "600"), 300, 60, null).total()));
    }
    @Test void demandMultiplierAndDiscountAreApplied() {
        var f = svc.compute(rule("1.50", "600"), 7000, 900, new BigDecimal("100"));
        assertEquals(0, new BigDecimal("1910.00").compareTo(f.total()));   // 1340*1.5 = 2010 - 100
    }
    @Test void totalIsAlwaysAMultipleOfRoundingStep() {
        for (int d = 150; d < 30000; d += 733) {
            var t = svc.compute(rule("1.00", "600"), d, d / 10, null).total();
            assertEquals(0, t.remainder(new BigDecimal("10")).compareTo(BigDecimal.ZERO), "total " + t);
        }
    }
}
