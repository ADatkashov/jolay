package kz.jolay;

import kz.jolay.pricing.PricingService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.time.*;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** Peak-hour windows: matching in city-local time (incl. overnight windows), estimate/ride/final-fare consistency, admin API. */
class PeakPricingIT extends IntegrationTestBase {
    @Autowired PricingService pricing;
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @BeforeEach
    void clean() { jdbc.sql("DELETE FROM peak_windows").update(); jdbc.sql("UPDATE pricing_rules SET demand_multiplier=1.00").update(); }

    private UUID city() { return jdbc.sql("SELECT id FROM cities WHERE code='ALA'").query(UUID.class).single(); }
    private Instant at(DayOfWeek d, int h, int m) {
        LocalDate date = LocalDate.of(2026, 11, 2).with(java.time.temporal.TemporalAdjusters.nextOrSame(d));   // 2026-11-02 is a Monday
        return ZonedDateTime.of(date, LocalTime.of(h, m), ALMATY).toInstant();
    }
    private void window(String days, String start, String end, String mult, boolean active) {
        jdbc.sql("INSERT INTO peak_windows(city_id,label,days,start_time,end_time,multiplier,active) VALUES (:c,'w',:d::smallint[],:s::time,:e::time,:m,:a)")
                .param("c", city()).param("d", days).param("s", start).param("e", end).param("m", new BigDecimal(mult)).param("a", active).update();
    }
    private void assertMult(String expected, Instant when) { assertEquals(0, new BigDecimal(expected).compareTo(pricing.peakMultiplier(city(), when)), "at " + when); }

    @Test
    void windowsMatchByLocalWeekdayAndTimeIncludingOvernightAndInactive() {
        window("{1,2,3,4,5}", "07:30", "09:30", "1.30", true);     // weekday morning rush
        window("{5,6}", "22:00", "02:00", "1.50", true);           // Fri/Sat night, crosses midnight
        window("{7}", "00:00", "23:59", "2.00", false);            // inactive

        assertMult("1.00", at(DayOfWeek.MONDAY, 7, 29));
        assertMult("1.30", at(DayOfWeek.MONDAY, 7, 30));            // start inclusive
        assertMult("1.30", at(DayOfWeek.FRIDAY, 9, 29));
        assertMult("1.00", at(DayOfWeek.MONDAY, 9, 30));            // end exclusive
        assertMult("1.00", at(DayOfWeek.SATURDAY, 8, 0));           // weekend: no morning rush
        assertMult("1.50", at(DayOfWeek.FRIDAY, 23, 0));
        assertMult("1.50", at(DayOfWeek.SATURDAY, 1, 59));          // after midnight belongs to the previous day's window (Friday night)
        assertMult("1.50", at(DayOfWeek.SUNDAY, 1, 0));             // Saturday night spills into Sunday
        assertMult("1.00", at(DayOfWeek.SUNDAY, 2, 0));
        assertMult("1.00", at(DayOfWeek.MONDAY, 1, 0));             // Sunday night is not a window
        assertMult("1.00", at(DayOfWeek.SUNDAY, 12, 0));            // inactive window ignored
        // overlapping windows: the highest wins
        window("{1}", "08:00", "09:00", "1.80", true);
        assertMult("1.80", at(DayOfWeek.MONDAY, 8, 15));
        assertMult("1.30", at(DayOfWeek.MONDAY, 9, 15));
    }

    @Test
    void estimateRideAndFinalFareUseTheSameMultiplierAndRuleMultiplierIsAFloor() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        Map<String, Object> body = Map.of("pickup", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "dropoff", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1]));
        BigDecimal base = new BigDecimal(post("/api/v1/rides/estimate", c.token(), body).body().path("categories").get(0).path("fare").path("total").asText());

        // an all-day, all-week window makes "now" a peak regardless of the clock
        window("{1,2,3,4,5,6,7}", "00:00", "23:59", "1.50", true);
        window("{1,2,3,4,5,6,7}", "23:59", "00:00", "1.50", true);
        Resp est = post("/api/v1/rides/estimate", c.token(), body);
        BigDecimal peak = new BigDecimal(est.body().path("categories").get(0).path("fare").path("total").asText());
        assertEquals(0, new BigDecimal("1.50").compareTo(new BigDecimal(est.body().path("categories").get(0).path("fare").path("multiplier").asText())));
        assertTrue(peak.compareTo(base) > 0, "peak fare must exceed the normal fare: " + peak + " vs " + base);

        Resp ride = requestRide(c, "ECONOMY", "CASH");
        assertEquals(0, peak.compareTo(new BigDecimal(ride.s("estimatedFare"))));
        String rideId = ride.s("id");
        assertEquals(0, new BigDecimal("1.50").compareTo(jdbc.sql("SELECT surge_multiplier FROM rides WHERE id=:r::uuid").param("r", rideId).query(BigDecimal.class).single()));

        jdbc.sql("DELETE FROM peak_windows").update();                      // the window ends mid-ride: the rider keeps the multiplier they were quoted
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        moveDriver(d, PICKUP[0], PICKUP[1]);
        post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null);
        post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null);
        moveDriver(d, 43.2200, 76.9300); moveDriver(d, DROPOFF[0], DROPOFF[1]);
        Resp done = post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null);
        assertEquals(200, done.status(), done.body().toString());
        BigDecimal fin = new BigDecimal(done.s("finalFare"));
        assertTrue(fin.compareTo(base) > 0, "final fare keeps the quoted multiplier: " + fin + " vs " + base);
        assertLedgerBalanced();

        // the rule's own demand multiplier is a floor: a lower window changes nothing
        jdbc.sql("UPDATE pricing_rules SET demand_multiplier=2.00").update();
        window("{1,2,3,4,5,6,7}", "00:00", "23:59", "1.20", true);
        Resp est2 = post("/api/v1/rides/estimate", c.token(), body);
        assertEquals(0, new BigDecimal("2.00").compareTo(new BigDecimal(est2.body().path("categories").get(0).path("fare").path("multiplier").asText())));
    }

    @Test
    void adminManagesWindowsWithRoleChecksValidationAndAudit() {
        Session fin = admin("FINANCE_ADMIN"); Session support = admin("SUPPORT_AGENT");
        Map<String, Object> w = Map.of("city", "ALA", "label", "Morning rush", "days", List.of(1, 2, 3, 4, 5), "start", "07:30", "end", "09:30", "multiplier", 1.3, "active", true);
        assertEquals(403, post("/api/v1/admin/pricing/peak-windows", support.token(), w).status());      // only finance/super may change prices
        Resp created = post("/api/v1/admin/pricing/peak-windows", fin.token(), w);
        assertEquals(201, created.status(), created.body().toString());
        String id = created.s("id");

        assertEquals(400, post("/api/v1/admin/pricing/peak-windows", fin.token(), Map.of("city", "ALA", "label", "x", "days", List.of(8), "start", "07:30", "end", "09:30", "multiplier", 1.3, "active", true)).status());
        assertEquals(400, post("/api/v1/admin/pricing/peak-windows", fin.token(), Map.of("city", "ALA", "label", "x", "days", List.of(1), "start", "7:30", "end", "09:30", "multiplier", 1.3, "active", true)).status());
        assertEquals(400, post("/api/v1/admin/pricing/peak-windows", fin.token(), Map.of("city", "ALA", "label", "x", "days", List.of(1), "start", "07:30", "end", "09:30", "multiplier", 5, "active", true)).status());
        assertEquals(400, post("/api/v1/admin/pricing/peak-windows", fin.token(), Map.of("city", "NOWHERE", "label", "x", "days", List.of(1), "start", "07:30", "end", "09:30", "multiplier", 1.3, "active", true)).status());

        Resp list = get("/api/v1/admin/pricing/peak-windows", support.token());                          // read access for all staff
        assertEquals(1, list.body().size());
        assertEquals("07:30", list.body().get(0).path("start").asText());
        assertEquals(5, list.body().get(0).path("days").size());

        Map<String, Object> changed = Map.of("city", "ALA", "label", "Morning rush", "days", List.of(1, 2, 3), "start", "07:00", "end", "10:00", "multiplier", 1.4, "active", false);
        assertEquals(200, put("/api/v1/admin/pricing/peak-windows/" + id, fin.token(), changed).status());
        assertFalse(get("/api/v1/admin/pricing/peak-windows", fin.token()).body().get(0).path("active").asBoolean());
        assertEquals(204, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/admin/pricing/peak-windows/" + id, fin.token(), null, null).status());
        assertEquals(0, get("/api/v1/admin/pricing/peak-windows", fin.token()).body().size());
        assertEquals(3, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action LIKE 'PEAK_WINDOW_%'").query(Integer.class).single());
    }
}
