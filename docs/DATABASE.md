# Database

PostgreSQL 16 + PostGIS 3, schema managed by Flyway (`backend/src/main/resources/db/migration`).
* `V1__core_schema.sql` – all tables, constraints, indexes, immutability triggers.
* `V3__dispatch_pool_setting.sql`, `V4__driver_locations_tuning.sql` – KNN candidate pool setting; `driver_locations` UNLOGGED + fillfactor/autovacuum tuning (audit).
* `V5__safety_payouts_risk_legal.sql` – payout accounts + columns, incidents/incident_events, risk_events/risk_flags, legal_documents, `rides.route_line`, new settings.
* `V6__push_outbox.sql` – dev push mock outbox. `V11__staff_mfa.sql` – encrypted TOTP secret columns on `users`, `mfa_recovery_codes`. `V10__store_cash_on_delivery.sql` – `store_orders.payment_method`, `STORE_CASH` deliveries, cash limits. `V9__partner_payouts.sql` – `payouts.wallet_type`, payouts keyed by user (partners can request). `V8__marketplace.sql` – partners, stores, products, store orders and items, PARTNER role, PARTNER_WALLET/ORDER_ESCROW accounts, marketplace settings. `V7__delivery_express.sql` – delivery tariffs/orders/offers/history/ratings/code attempts, `drivers.accepts_delivery`.
* `V2__reference_data.sql` – Almaty city/zone, 4 vehicle categories, launch tariffs, dispatch settings, system ledger accounts, 12 landmarks.

Geography columns use `GEOGRAPHY(Point|Polygon, 4326)` with GiST indexes (`driver_locations`, `service_zones`, `places`).
Money is `NUMERIC(14,2)` (KZT); Java uses `BigDecimal` only. Timestamps are `timestamptz` (UTC); apps display Asia/Almaty.

## Tables (implemented)
identity: `users`, `user_roles`, `otp_verifications`, `refresh_tokens`, `user_devices` · customers: `customer_addresses` ·
platform: `cities`, `service_zones`, `places`, `vehicle_categories`, `pricing_rules`, `application_settings`, `audit_logs`, `notifications` ·
drivers: `drivers`, `vehicles`, `driver_documents`, `driver_locations`, `driver_status_history` ·
rides: `rides`, `ride_status_history`, `ride_offers`, `ride_locations`, `ride_fares`, `ratings` ·
money: `accounts`, `ledger_transactions`, `ledger_entries`, `payment_transactions`, `payment_webhook_events`, `payment_refunds`, `payouts` ·
support: `support_tickets`, `support_messages`.

Not created yet (from the brief): delivery_*, partners/stores/products, referral_codes, promotions, commissions (commission is a column of `pricing_rules` / `ride_fares`), driver_vehicle_assignments (one active vehicle per driver for now).

## Integrity rules enforced by the database
| Rule | Mechanism |
|---|---|
| One active ride per customer | partial unique index `ux_rides_customer_active` |
| One active ride per driver | partial unique index `ux_rides_driver_active` |
| One pending offer per ride / per driver | `ux_offer_one_active_per_ride`, `ux_offer_one_active_per_driver` |
| Ledger is append-only | triggers on `ledger_entries`, `ledger_transactions` raise on UPDATE/DELETE |
| Customer wallet never negative | `CHECK (type <> 'CUSTOMER_WALLET' OR balance >= 0)` |
| Idempotent payments / rides / postings | unique indexes on idempotency keys and `(provider, event_id)` |
| One payment attempt in flight per ride | `ux_pay_one_pending_ride` |

Invariant tested after every money scenario: `sum(accounts.balance) = 0`, every ledger transaction sums to 0, cached balances equal the ledger sums.

## PostGIS notes
* `geography` is used for driver/rider points and zones so distances are in metres (`ST_DWithin`, `<->`). PostGIS finds *geographic* candidates; the dispatch engine decides. Straight-line distance is not road distance — real ETA needs a routing provider.
* Candidate search is KNN over the GiST index (`ORDER BY location <-> pickup LIMIT pool`), then eligibility/ranking. Run the PostgreSQL server with `jit = off` for this workload (the app also sets it per connection).
* `driver_locations` is UNLOGGED (latest position only; empty after a crash until drivers re-send). Detailed plans and timings: CTO_FINAL_AUDIT.md §6.

## Query/perf notes
Dispatch candidate search = `ST_DWithin` on GiST + joins, `FOR UPDATE OF d SKIP LOCKED`. Measured with 300 drivers only (see DEPLOYMENT.md);
**query plans at city scale (10⁴–10⁵ drivers) have not been analysed.** `driver_locations` holds only the latest position (upsert);
`ride_locations` grows by one row per update during a trip and needs a retention/partitioning policy before production.
