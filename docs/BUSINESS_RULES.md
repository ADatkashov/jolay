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
| 30 | Store order: total (items + delivery fee) is held in ORDER_ESCROW from the customer wallet at placement; nothing is charged twice | `StoreSettlement.hold` |
| 31 | On hand-over: escrow → partner wallet (items − commission), courier wallet (delivery share), platform (commission + delivery cut) | `StoreSettlement.settleDelivered` |
| 32 | Store reject / cancel while PLACED / no courier found → full refund from escrow | `StoreSettlement.refundAndClose` |
| 33 | Prices are snapshots at order time; the server recomputes everything, the client price is never trusted; max 30 lines, one store per order, distance limit from settings | `StoreOrderService.price` |
| 34 | Store order paid in cash on delivery: nothing is held; the courier collects the total, keeps their earnings and owes the rest (wallet debit), partner and platform are credited at hand-over | `StoreSettlement.settleDeliveredCash` |
| 35 | Cash store orders are capped per order (`marketplace.cash_max_total`, 20 000 ₸) and per customer (`marketplace.cash_max_open`, 2 open at once); reject/cancel of a cash order moves no money | `StoreOrderService.place` |
| 36 | A courier is not offered a cash store order if collecting it would push their wallet below the debt floor (`wallet.driver_min_balance`, −20 000 ₸); the same floor already applies to all offers | `DeliveryDispatchService` |
| 37 | A driver/courier with `dispatch.cancel_cooldown_count` (3) cancellations after accepting (rides + deliveries) inside `dispatch.cancel_cooldown_hours` (24) is skipped by dispatch until the oldest age out; nothing is charged and the account is never suspended automatically. Courier cancellations raise the same advisory REPEATED_CANCELLATIONS flag as drivers (`risk.courier_cancels_24h`) | `DispatchService`, `DeliveryDispatchService`, `RiskService.onCourierCancel` |

Customer cancellation fee and free window, commission, base/km/minute/minimum fares, demand multiplier, dispatch radii/timeouts are all configurable (Admin → Pricing / Settings).
**Rules not yet implemented:** promo codes, peak-hour/surge automation, scheduled rides, delivery rules.
