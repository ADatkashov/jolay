> Full audit with evidence and verdict: [../CTO_FINAL_AUDIT.md](../CTO_FINAL_AUDIT.md). Roadmap: [../JOLAY_PRODUCT_ROADMAP_2027.md](../JOLAY_PRODUCT_ROADMAP_2027.md).

# Implementation status (honest)

Legend: ✅ implemented **and** covered by automated tests · 🟡 implemented, not covered by an automated test · 🧪 development-only integration · ⛔ not built

## Backend
| Area | Status | Notes |
|---|---|---|
| Auth: register, OTP, login, refresh rotation + reuse detection, forgot/reset, logout | ✅ | OTP attempts + hourly + resend throttles, login lockout |
| Roles & authorization (customer / driver / 4 staff roles) | ✅ | method-level checks, suspended accounts blocked immediately |
| Service zones, places search, reverse geocode | ✅ | places are a seeded DB table (12 Almaty landmarks) — real geocoder not integrated 🧪 |
| Routing / ETA | 🧪 | `EstimatedRouteProvider` = great-circle × detour factor; flagged `ESTIMATED`. No Google/Mapbox/2GIS adapter yet |
| Pricing engine (base, km, minute, min fare, booking fee, demand multiplier, rounding, commission, cancellation fee) | ✅ | admin-editable, audited. Peak-hour rules, promo codes, per-zone tariffs ⛔ |
| Ride state machine | ✅ | invalid transitions rejected, tested |
| Dispatch (PostGIS radius, category eligibility, scoring, expiry, re-offer, radius expansion, concurrency safety) | ✅ | concurrency tests included. Real-road ETA / traffic scoring ⛔ |
| Ledger (double entry, append-only, idempotent, DB-enforced immutability) | ✅ | |
| Wallet top-up, wallet/cash/card ride settlement, refunds | ✅ | against the **sandbox** gateway 🧪 |
| Payment webhooks: HMAC verification, dedupe, amount check | ✅ | real providers (Kaspi / FreedomPay) ⛔ — need merchant contracts |
| Driver payouts (hold → paid/rejected through the ledger), hourly reconciliation job + metric | ✅ | bank transfer itself is manual; no bank integration |
| Ratings, support tickets/chat (REST + notification event), notifications (dedupe), audit log | ✅ | |
| WebSocket events with reconnect hints | 🟡 | event delivery after commit; no WS integration test |
| Driver documents upload (type/size/magic-byte checks, admin-only download) | 🟡 | |
| Account deletion (anonymisation) | ✅ | legal retention rules need counsel review |
| Delivery (food/grocery/parcel), partners, stores, products | ⛔ | not started |
| SOS / complaints → incidents with staff notification, investigation history, admin handling | ✅ | apps also dial 112; no on-call schedule/SLA/escalation; trip sharing links and emergency contacts ⛔ |
| Risk flags (7 rules, human review, no auto-suspension) | ✅ | thresholds are uncalibrated defaults |
| FCM push, real SMS gateway | ⛔ | interfaces exist (`SmsSender`, `Notifier`) |

## Apps
| App | Status |
|---|---|
| Customer (Flutter): splash, onboarding, signup, OTP, login, forgot/reset, location permission handling, home, destination search, map picker, ride options, searching, live tracking, SOS (dials 112), payment, rating, history, wallet, profile, support chat | ✅ widget-tested (8 tests); never run on a device/emulator in this environment |
| Driver (Flutter): auth, vehicle registration, document upload, verification status, online toggle + location publishing, offer card with countdown, active-trip stages, navigation hand-off, earnings, orders, profile | 🟡 4 widget tests; never run on a device |
| Admin (React): dashboard, live ops (tables, no map), rides, drivers approve/reject/suspend, customers, payments/refunds, pricing, support, settings, audit | ✅ builds, 7 tests |
| Partner portal | ⛔ |
| Terms/Privacy/About screens + publishing mechanism | ✅ mechanism; ⛔ content (needs counsel) |
| Customer screens not built: Select Country picker, Delivery/Express flows, referral | ⛔ |

## Known limitations
* Map tiles default to public OpenStreetMap (dev only — policy forbids production use).
* The apps have not been exercised against a live backend on a device; only widget tests with a faked API.
* Kazakh/Russian strings were written by the model and need review by native speakers.
* Load/soak testing: see docs/DEPLOYMENT.md#load-test for the measured numbers and their limits.
