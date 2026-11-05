# Business rules (enforced by the backend)

| # | Rule | Where |
|---|---|---|
| 1 | Only `APPROVED` drivers with an approved, active vehicle can go online and receive offers | `DriverService.setAvailability`, dispatch query |
| 2 | Vehicle eligibility: XL rides need XL vehicles; other rides need rank ≥ requested (Economy<Comfort<Business) | dispatch, `nearestEta` |
| 3 | A driver cannot hold two offers or two active rides; a customer cannot have two active rides | partial unique indexes |
| 4 | Fares are computed server-side from admin-configured `pricing_rules`; clients cannot submit a price | `PricingService`, `RideService.create/complete` |
| 5 | Final fare is recomputed from the recorded GPS track + elapsed time and capped at estimate × `rides.max_fare_over_estimate` (1.5) | `RideService.complete` |
| 6 | Commission = total × `commission_rate` (per category, 0–50 %), stored per ride in `ride_fares` | |
| 7 | Cash rides: driver keeps the cash; platform commission is debited from the driver wallet (can go negative down to `wallet.driver_min_balance`, then the driver gets no offers) | `PaymentService.settleRideOnCompletion` |
| 8 | Wallet rides need balance ≥ estimate at request time and are settled through the ledger at completion; insufficient → payment `FAILED`, customer must pay another way | |
| 9 | Card payment is `PAID` only after a signature-verified gateway callback with the exact amount | `PaymentService.handleWebhook` |
| 10 | Customer cancel is free until assigned or within `free_cancel_seconds` (120) of assignment; later → `cancellation_fee`, charged immediately only for wallet rides, otherwise recorded on the ride (collection workflow not built) | `RideService.cancelByCustomer` |
| 11 | Cancel is impossible once `IN_PROGRESS`; completed/cancelled/expired rides are final | state machine |
| 12 | "Arrived" requires the driver to be within `rides.arrive_radius_m` (400 m) of pickup | `RideService.arrived` |
| 13 | Location updates from offline/unapproved/suspended drivers are rejected; jumps above 220 km/h (>500 m) are rejected | `DriverService.updateLocation` |
| 14 | Refunds reverse every ledger leg; double refund and refund of spent top-ups are rejected | `PaymentService.refund` |
| 15 | Suspended/deleted users lose access immediately (valid JWTs are re-checked against the DB) and their refresh tokens are revoked | `JwtAuthFilter`, `AdminController.userStatus` |
| 16 | Staff actions (verification, status, pricing, refunds, settings, document views, staff creation) are written to `audit_logs` | |
| 17 | A customer can rate a completed ride once; rating updates the driver's running average | `RideService.rate` |
| 18 | Ride addresses must lie inside an active service zone of the same city | `GeoService.cityFor` |

| 19 | Driver payout: needs APPROVED driver, amount ≥ `payouts.min_amount`, ≤ wallet balance, one open request per driver; funds are held in `PAYOUT_CLEARING` at request time, released on reject, moved to `EXTERNAL_BANK` when finance marks it paid | `PayoutService` |
| 20 | An SOS creates a CRITICAL incident, links the active ride and counterpart, notifies all SUPPORT/OPERATIONS/SUPER staff; repeated SOS within 30 min reuses the open incident | `IncidentController` |
| 21 | Risk flags are advisory: no automatic suspension, blocking or charging; each decision needs a note and is audited | `RiskService`, `RiskController` |
| 22 | Raw GPS points are deleted after `rides.raw_track_retention_days` (14); the simplified route stays | `TrackRetentionJob` |
| 23 | Legal texts are versioned and published only by SUPER_ADMIN; none is pre-filled | `LegalController` |
| 24 | Express: only couriers who opted in (`accepts_delivery`), approved, online, with a fresh position are offered parcels; one offer at a time; weight must fit the size class; route ≤ `delivery.max_distance_m` | `DeliveryDispatchService`, `DeliveryService.quote` |
| 25 | Express fee = max(min fare, base + km × rate + extra kg × rate) rounded up; commission per tariff; computed only on the server | `DeliveryService.quote` |
| 26 | Pickup/hand-over must be confirmed within `delivery.arrive_radius_m` of the point; hand-over needs the recipient's 4-digit code (shown only to the customer); 5 wrong codes lock the order for support | `DeliveryService` |
| 27 | A parcel cannot be cancelled by the customer once picked up; a courier can hand an unpicked order back (it is re-queued, excluding that courier) | `DeliveryService` |
| 28 | Cash delivery: courier owes the commission (wallet debit); wallet delivery: ledger customer → courier + platform at hand-over | `DeliveryService.settlePayment` |
| 29 | Public tracking returns status and timestamps only (no names, phones, addresses) | `DeliveryService.publicTrack` |

Customer cancellation fee and free window, commission, base/km/minute/minimum fares, demand multiplier, dispatch radii/timeouts are all configurable (Admin → Pricing / Settings).
**Rules not yet implemented:** promo codes, peak-hour/surge automation, scheduled rides, delivery rules.
