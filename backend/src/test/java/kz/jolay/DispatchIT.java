package kz.jolay;

import kz.jolay.dispatch.DispatchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.*;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;

class DispatchIT extends IntegrationTestBase {
    @Autowired DispatchService dispatch;
    @Autowired TransactionTemplate tx;

    @Test
    void declineMovesOfferToNextNearestDriver() {
        Session c = customer();
        Session near = driver("ECONOMY", 43.2336, 76.9568);
        Session far = driver("ECONOMY", 43.2400, 76.9700);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        String nearOffer = currentOfferId(near);
        assertNotNull(nearOffer, "closest driver is offered first");
        assertNull(currentOfferId(far), "only one driver is offered at a time");
        assertEquals(204, post("/api/v1/drivers/offers/" + nearOffer + "/decline", near.token(), null).status());
        assertNotNull(currentOfferId(far));
        assertEquals("ONLINE", get("/api/v1/drivers/me", near.token()).s("availability"));
        assertEquals("OFFERED", get("/api/v1/drivers/me", far.token()).s("availability"));
        assertEquals("SEARCHING_DRIVER", get("/api/v1/rides/" + rideId, c.token()).s("status"));
    }

    @Test
    void timeoutExpiresOfferAndFreesDriver() {
        Session c = customer();
        Session d1 = driver("ECONOMY", 43.2336, 76.9568);
        requestRide(c, "ECONOMY", "CASH");
        String offer = currentOfferId(d1);
        assertNotNull(offer);
        jdbc.sql("UPDATE ride_offers SET expires_at = now() - interval '1 second'").update();
        assertEquals(409, post("/api/v1/drivers/offers/" + offer + "/accept", d1.token(), null).status());   // late accept refused
        dispatch.expireOffers();
        assertEquals("ONLINE", get("/api/v1/drivers/me", d1.token()).s("availability"));
        Session d2 = driver("ECONOMY", 43.2340, 76.9570);
        dispatch.tick();                                                  // scheduler round: d1 already tried, so d2 gets it
        assertNotNull(currentOfferId(d2));
        assertNull(currentOfferId(d1));
    }

    @Test
    void noDriversAvailableExpiresRide() {
        Session c = customer();
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        assertEquals("SEARCHING_DRIVER", get("/api/v1/rides/" + rideId, c.token()).s("status"));
        jdbc.sql("UPDATE rides SET search_started_at = now() - interval '10 minutes'").update();
        dispatch.tick();
        assertEquals("EXPIRED", get("/api/v1/rides/" + rideId, c.token()).s("status"));
        assertEquals(1, get("/api/v1/rides/history?tab=cancelled", c.token()).body().size());
        // the customer can immediately request again
        assertEquals(201, requestRide(c, "ECONOMY", "CASH").status());
    }

    @Test
    void radiusExpandsOverTimeAndIneligibleDriversAreSkipped() {
        Session c = customer();
        Session farAway = driver("ECONOMY", 43.2335 + 0.035, 76.9567);              // ~3.9 km: outside the initial 2 km radius
        Session wrongClass = driver("ECONOMY", 43.2336, 76.9568);                    // right place, but too low for BUSINESS
        Session suspended = driver("BUSINESS", 43.2337, 76.9569);
        put("/api/v1/admin/users/" + suspended.id() + "/status", admin("OPERATIONS_ADMIN").token(), Map.of("status", "SUSPENDED"));
        requestRide(c, "BUSINESS", "CASH");
        assertNull(currentOfferId(wrongClass));
        assertNull(currentOfferId(suspended));
        Session ok = driver("BUSINESS", 43.2338, 76.9566);
        dispatch.tick();
        assertNotNull(currentOfferId(ok));
        // radius expansion for a far eco driver
        post("/api/v1/rides/" + get("/api/v1/rides/active", c.token()).s("id") + "/cancel", c.token(), null);
        requestRide(c, "ECONOMY", "CASH");
        assertNotNull(currentOfferId(wrongClass));                                    // nearest eligible
        jdbc.sql("UPDATE ride_offers SET status='DECLINED'").update();
        jdbc.sql("UPDATE drivers SET availability='ONLINE' WHERE availability='OFFERED'").update();
        jdbc.sql("UPDATE rides SET search_started_at = now() - interval '35 seconds' WHERE status='SEARCHING_DRIVER'").update();
        jdbc.sql("DELETE FROM ride_offers").update();
        dispatch.tick();                                                              // radius now 2000 + 2*1000 = 4000 m
        assertTrue(currentOfferId(farAway) != null || currentOfferId(wrongClass) != null);
    }

    @Test
    void stalePositionDriversAreNotOffered() {
        Session c = customer();
        Session d = driver("ECONOMY", 43.2336, 76.9568);
        jdbc.sql("UPDATE driver_locations SET updated_at = now() - interval '5 minutes'").update();
        requestRide(c, "ECONOMY", "CASH");
        assertNull(currentOfferId(d));
    }

    @Test
    void oneDriverCanNeverHoldTwoOffersUnderConcurrency() throws Exception {
        Session d = driver("ECONOMY", 43.2336, 76.9568);
        int n = 6;
        List<Session> customers = new ArrayList<>();
        for (int i = 0; i < n; i++) customers.add(customer());
        // create rides as SEARCHING without dispatching, then dispatch all at once from many threads
        List<UUID> rides = new ArrayList<>();
        for (Session c : customers) {
            UUID id = jdbc.sql("""
                    INSERT INTO rides(customer_id,city_id,category_code,status,pickup_address,pickup,dropoff_address,dropoff,est_distance_m,est_duration_s,est_fare,payment_method,pricing_rule_id,search_started_at)
                    SELECT :c, city_id, 'ECONOMY','SEARCHING_DRIVER','a',ST_SetSRID(ST_MakePoint(76.9567,43.2335),4326)::geography,'b',ST_SetSRID(ST_MakePoint(76.9066,43.2025),4326)::geography,7000,900,2000,'CASH', id, now()
                    FROM pricing_rules WHERE category_code='ECONOMY' RETURNING id""").param("c", c.id()).query(UUID.class).single();
            rides.add(id);
        }
        ExecutorService ex = Executors.newFixedThreadPool(n);
        CountDownLatch go = new CountDownLatch(1);
        List<Future<?>> fs = new ArrayList<>();
        for (UUID r : rides) fs.add(ex.submit(() -> { go.await(); tx.executeWithoutResult(s -> dispatch.dispatchRound(r)); return null; }));
        go.countDown();
        for (Future<?> f : fs) f.get(30, TimeUnit.SECONDS);
        ex.shutdown();
        assertEquals(1, jdbc.sql("SELECT count(*) FROM ride_offers WHERE status='OFFERED'").query(Integer.class).single());
        assertEquals("OFFERED", jdbc.sql("SELECT availability FROM drivers WHERE user_id=:d").param("d", d.id()).query(String.class).single());
    }

    @Test
    void concurrentAcceptOfSameOfferAssignsOnce() throws Exception {
        Session c = customer();
        Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        String offer = currentOfferId(d);
        ExecutorService ex = Executors.newFixedThreadPool(4);
        List<Future<Integer>> fs = new ArrayList<>();
        CountDownLatch go = new CountDownLatch(1);
        for (int i = 0; i < 4; i++) fs.add(ex.submit(() -> { go.await(); return post("/api/v1/drivers/offers/" + offer + "/accept", d.token(), null).status(); }));
        go.countDown();
        int ok = 0;
        for (Future<Integer> f : fs) if (f.get(30, TimeUnit.SECONDS) == 200) ok++;
        ex.shutdown();
        assertEquals(1, ok);
        assertEquals(1, jdbc.sql("SELECT count(*) FROM rides WHERE driver_id=:d AND status='DRIVER_ASSIGNED'").param("d", d.id()).query(Integer.class).single());
        assertEquals("DRIVER_ASSIGNED", get("/api/v1/rides/" + rideId, c.token()).s("status"));
    }

    @Test
    void customerCannotHaveTwoActiveRides() {
        Session c = customer(); driver("ECONOMY", 43.2336, 76.9568);
        assertEquals(201, requestRide(c, "ECONOMY", "CASH").status());
        Resp second = requestRide(c, "COMFORT", "CASH");
        assertEquals(409, second.status());
        assertEquals("active_ride_exists", second.s("code"));
    }

    @Test
    void idempotentCreateReturnsSameRide() {
        Session c = customer();
        Resp a = call(org.springframework.http.HttpMethod.POST, "/api/v1/rides", c.token(), rideRequest("ECONOMY", "CASH"), Map.of("Idempotency-Key", "k1"));
        Resp b = call(org.springframework.http.HttpMethod.POST, "/api/v1/rides", c.token(), rideRequest("ECONOMY", "CASH"), Map.of("Idempotency-Key", "k1"));
        assertEquals(a.s("id"), b.s("id"));
        assertEquals(1, jdbc.sql("SELECT count(*) FROM rides").query(Integer.class).single());
    }

    @Test
    void customerCancelFreeThenLateFeeAndDriverIsReleased() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        topUp(c, 5000);
        String rideId = requestRide(c, "ECONOMY", "WALLET").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        jdbc.sql("UPDATE rides SET assigned_at = now() - interval '10 minutes'").update();     // past the free-cancel window
        Resp r = post("/api/v1/rides/" + rideId + "/cancel", c.token(), Map.of("reason", "changed plans"));
        assertEquals("CANCELLED", r.s("status"));
        assertEquals(0, new java.math.BigDecimal(r.s("cancellationFee")).compareTo(new java.math.BigDecimal("300")));
        assertEquals(0, balance(c).compareTo(new java.math.BigDecimal("4700")));
        assertEquals(0, balance(d).compareTo(new java.math.BigDecimal("300")));
        assertEquals("ONLINE", get("/api/v1/drivers/me", d.token()).s("availability"));
        assertEquals(409, post("/api/v1/rides/" + rideId + "/cancel", c.token(), null).status());   // terminal
        assertLedgerBalanced();
    }

    @Test
    void cancelWhileSearchingClosesOfferAndFreesDriver() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        assertNotNull(currentOfferId(d));
        assertEquals("CANCELLED", post("/api/v1/rides/" + rideId + "/cancel", c.token(), null).s("status"));
        assertNull(currentOfferId(d));
        assertEquals("ONLINE", get("/api/v1/drivers/me", d.token()).s("availability"));
    }

    @Test
    void driverCancellationRequeuesRideToAnotherDriver() {
        Session c = customer();
        Session d1 = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        post("/api/v1/drivers/offers/" + currentOfferId(d1) + "/accept", d1.token(), null);
        Session d2 = driver("ECONOMY", 43.2340, 76.9570);
        assertEquals(204, post("/api/v1/drivers/rides/" + rideId + "/cancel", d1.token(), Map.of("reason", "flat tyre")).status());
        Resp r = get("/api/v1/rides/" + rideId, c.token());
        assertEquals("SEARCHING_DRIVER", r.s("status"));
        assertNotNull(currentOfferId(d2));
        assertNull(currentOfferId(d1), "the cancelling driver is not re-offered the same ride");
    }

    @Test
    void invalidStateTransitionsAreRejected() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        assertEquals(404, post("/api/v1/drivers/rides/" + rideId + "/start", d.token(), null).status());   // not assigned to this driver
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        assertEquals(409, post("/api/v1/drivers/rides/" + rideId + "/complete", d.token(), null).status());
        assertEquals(409, post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null).status());    // must be en-route first
        post("/api/v1/drivers/rides/" + rideId + "/en-route", d.token(), null);
        jdbc.sql("UPDATE driver_locations SET location = ST_SetSRID(ST_MakePoint(76.95,43.30),4326)::geography").update();   // far from pickup
        assertEquals(409, post("/api/v1/drivers/rides/" + rideId + "/arrived", d.token(), null).status());
        assertEquals(409, post("/api/v1/rides/" + rideId + "/rating", c.token(), Map.of("stars", 5)).status());   // not completed
    }

    @Test
    void gpsTeleportIsRejected() {
        Session d = driver("ECONOMY", 43.2336, 76.9568);
        Resp r = moveDriver(d, 43.40, 77.10);
        assertEquals(400, r.status());
        assertEquals("implausible_location", r.s("code"));
    }

    @Test
    void unapprovedDriverCannotGoOnlineOrGetOffers() {
        Session d = register("DRIVER");
        post("/api/v1/drivers/register", d.token(), Map.of("vehicle", Map.of("brand", "Kia", "model", "Rio", "year", 2019, "color", "Black", "plate", "777ABC02", "category", "ECONOMY")));
        assertEquals(403, put("/api/v1/drivers/availability", d.token(), Map.of("online", true)).status());
        assertEquals(409, moveDriver(d, 43.2336, 76.9568).status());
    }

    @Test
    void aDriverWhoKeepsCancellingAfterAcceptingIsNotOfferedNewRidesUntilTheyAgeOut() {
        assertEquals(200, put("/api/v1/admin/settings/dispatch.cancel_cooldown_count", admin("SUPER_ADMIN").token(), Map.of("value", "2")).status());
        try {
            Session d = driver("ECONOMY", 43.2336, 76.9568);
            for (int i = 0; i < 2; i++) {
                Session c = customer();
                String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
                assertNotNull(currentOfferId(d), "cancellation " + i + ": the driver is still eligible");
                assertEquals(200, post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null).status());
                assertEquals(204, post("/api/v1/drivers/rides/" + rideId + "/cancel", d.token(), Map.of("reason", "changed my mind")).status());
                put("/api/v1/drivers/availability", d.token(), Map.of("online", true));
                moveDriver(d, 43.2336, 76.9568);
                post("/api/v1/rides/" + rideId + "/cancel", c.token(), Map.of("reason", "cleanup"));
            }
            Session c3 = customer();
            requestRide(c3, "ECONOMY", "CASH");
            assertNull(currentOfferId(d), "two cancellations in the window: no new offers");
            assertEquals(0, jdbc.sql("SELECT count(*) FROM ride_offers WHERE driver_id=:d AND status='OFFERED'").param("d", d.id()).query(Integer.class).single());

            // the cancellations age out of the window -> eligible again; nothing was charged or suspended
            jdbc.sql("UPDATE ride_status_history SET created_at = now() - interval '25 hours' WHERE actor = :a").param("a", "DRIVER:" + d.id()).update();
            post("/api/v1/rides/" + jdbc.sql("SELECT id FROM rides WHERE customer_id=:c").param("c", c3.id()).query(String.class).single() + "/cancel", c3.token(), Map.of("reason", "retry"));
            Session c4 = customer();
            requestRide(c4, "ECONOMY", "CASH");
            assertNotNull(currentOfferId(d), "older cancellations no longer count");
            assertEquals("ACTIVE", jdbc.sql("SELECT status FROM users WHERE id=:i").param("i", d.id()).query(String.class).single());
        } finally {
            put("/api/v1/admin/settings/dispatch.cancel_cooldown_count", admin("SUPER_ADMIN").token(), Map.of("value", "3"));
        }
    }
}
