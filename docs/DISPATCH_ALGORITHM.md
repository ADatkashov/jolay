# Dispatch algorithm

Implemented in `kz.jolay.dispatch.DispatchService`. All thresholds live in `application_settings` (admin-editable).

1. **Trigger.** On ride creation (first round, same transaction) and every 2 s via a scheduler for rides in `SEARCHING_DRIVER` that hold no live offer.
2. **Lock.** The ride row is locked (`FOR UPDATE`), so one dispatcher works on a ride at a time. Pending offer present → no-op.
3. **Timeout.** If `now - search_started_at > dispatch.search_timeout_seconds` (120) → ride `EXPIRED`, customer notified.
4. **Radius.** `min(max_radius_m, initial_radius_m + radius_step_m × floor(elapsed / offer_timeout_seconds))` → 2 km, growing 1 km every 15 s up to 6 km.
5. **Candidates** (PostGIS `ST_DWithin`): driver `APPROVED` and `ONLINE`, user `ACTIVE`, same city, position fresher than `location_max_age_seconds` (60), approved active vehicle
   whose category is eligible (XL ↔ XL only; otherwise vehicle rank ≥ requested rank), wallet balance ≥ `wallet.driver_min_balance`, not already offered this ride.
6. **Ranking.** `distance × (1 + 0.5 × (1 − acceptance_rate))` ascending (acceptance rate = offers_accepted / offers_total, 1.0 for new drivers). Straight-line distance; no traffic/road ETA yet.
7. **Offer.** Candidates are selected `FOR UPDATE OF drivers SKIP LOCKED` so concurrent dispatchers cannot choose the same driver; the best one is moved `ONLINE → OFFERED`
   (conditional UPDATE) and a `ride_offers` row is inserted (expires in `offer_timeout_seconds`, 15 s). Partial unique indexes guarantee ≤1 live offer per ride and per driver.
8. **Response.** Accept: locks offer then ride, verifies not expired and ride still searching, assigns driver+vehicle, driver → `BUSY`. Decline/expiry: driver → `ONLINE`, next round immediately (decline) or on next tick (expiry).
9. **Re-queue.** Driver cancel after assignment returns the ride to `SEARCHING_DRIVER` with a fresh search window; the previous driver is excluded because he already has an offer row for the ride.

Verified by tests: nearest-first, decline → next, timeout/late accept, expiry with no drivers, radius expansion, ineligible/suspended/stale drivers skipped, 6 rides vs 1 driver in parallel (one offer),
4 parallel accepts of one offer (one winner). **Not implemented:** road ETA/traffic from a routing provider, demand-aware batching (global optimisation), configurable scoring weights (the 0.5 factor is a constant).
