> Full audit with evidence and verdict: [../CTO_FINAL_AUDIT.md](../CTO_FINAL_AUDIT.md). Roadmap: [../JOLAY_PRODUCT_ROADMAP_2027.md](../JOLAY_PRODUCT_ROADMAP_2027.md).

# Implementation status (honest)

Legend: ✅ implemented **and** covered by automated tests · 🟡 implemented, not covered by an automated test · 🧪 development-only integration · ⛔ not built

## Backend
| Area | Status | Notes |
|---|---|---|
| Auth: register, OTP, login, refresh rotation + reuse detection, forgot/reset, logout | ✅ | OTP attempts + hourly + resend throttles, login lockout |
| Roles & authorization (customer / driver / 4 staff roles) | ✅ | method-level checks, suspended accounts blocked immediately |
| Service zones, places search, reverse geocode | ✅ | default: seeded DB table (12 Almaty landmarks) 🧪. **2GIS** (`JOLAY_2GIS_KEY`: Suggest + geocode, seeded places are the fallback on any error, with a circuit breaker): tested against local stubs of the documented format and (address search) confirmed working with a real demo key; the reverse endpoint is unverified against a live key |
| Routing / ETA | 🧪 | default `EstimatedRouteProvider` = great-circle × detour factor, flagged `ESTIMATED`. **2GIS Routing adapter** (`JOLAY_2GIS_KEY`, falls back to the estimate on any error with a circuit breaker): tested against a local stub of the documented format only — **never run against the real 2GIS API** |
| Pricing engine (base, km, minute, min fare, booking fee, demand multiplier, rounding, commission, cancellation fee) | ✅ | admin-editable, audited. Peak-hour windows (V17, Admin → Pricing; none defined by default) ✅. Promo codes (V18, Admin → Promo codes; none by default; platform-funded through the PROMO account, ride/cash/wallet/card/refund legs tested) ✅. Zone surcharges (V19, Admin → Pricing → Tariff zones; none by default) ✅ — flat fee for trips starting/ending in a circle (e.g. airport); fully polygon-based zones and per-zone rates ⛔ |
| Ride state machine | ✅ | invalid transitions rejected, tested |
| Dispatch (PostGIS radius, category eligibility, scoring, expiry, re-offer, radius expansion, concurrency safety) | ✅ | concurrency tests included. Real-road ETA / traffic scoring ⛔ |
| Ledger (double entry, append-only, idempotent, DB-enforced immutability) | ✅ | |
| Wallet top-up, wallet/cash/card ride settlement, refunds | ✅ | against the **sandbox** gateway 🧪 |
| Payment webhooks: HMAC verification, dedupe, amount check | ✅ | real providers (Kaspi / FreedomPay) ⛔ — need merchant contracts |
| Driver and partner payouts (hold → paid/rejected through the ledger; V9), hourly reconciliation job + metric | ✅ | bank transfer itself is manual; no bank integration |
| Ratings, support tickets/chat (REST + notification event), notifications (dedupe), audit log | ✅ | |
| WebSocket events with reconnect hints | ✅ | integration test: token-checked handshake, ping/pong, per-user delivery after commit, multiple devices |
| Driver documents upload (type/size/magic-byte checks, per-driver cap, path containment, admin-only audited download) | ✅ | **storage is local disk: unencrypted, unscanned, not durable on containers without a volume** — production blocker (docs/DEPLOYMENT.md#driver-documents) |
| Account deletion (anonymisation) | ✅ | legal retention rules need counsel review |
| JOLAY Express — parcel delivery (tariffs by size/weight, courier dispatch, offers, pickup/handover with recipient code and brute-force lock, cash/wallet settlement through the ledger, tracking number + public status, rating, admin list) | ✅ | card payment for deliveries ⛔; courier cancellation fees ⛔; |
| Push notifications | 🧪 | localized texts + fan-out implemented; delivery is a DEV MOCK (`push_outbox`) until an FCM service account is configured; FCM adapter tested only against a local stub; apps register a MOCK per-install token (`MockPushTokenSource`, platform `mock`) after sign-in; a Firebase-backed `PushTokenSource` is still to be supplied |
| SOS / complaints → incidents with staff notification, investigation history, admin handling | ✅ | apps also dial 112; no on-call schedule/SLA/escalation |
| Trip sharing (V14): tokenised public read-only link + viewer page, no phones/fares, live position only while active, revocable, expires after a grace period; "Share" button in the customer app copies the link | ✅ | no push/SMS to a chosen contact (needs a real SMS gateway) |
| Emergency contacts (V15, up to 3 per customer): SOS during a ride texts each contact a live trip link; best effort, never blocks the SOS; repeated presses do not re-send. Customer app: Profile → Trusted contacts | ✅ | SMS goes through `SmsSender` = **mock** until a real gateway exists 🧪 |
| Risk flags (7 rules, human review, no auto-suspension) | ✅ | thresholds are uncalibrated defaults |
| Real SMS gateway, verified FCM push | ⛔ | interfaces exist (`SmsSender`, `Notifier`); WhatsApp OTP adapter exists but is unverified against a live account |
| Multi-instance operation (shared rate limits, lockout, realtime) | ⛔ | single instance only (docs/ARCHITECTURE.md#scaling-one-backend-instance-only) |

## Apps
| App | Status |
|---|---|
| Customer (Flutter): splash, onboarding, signup, OTP, login, forgot/reset, location permission handling, home, destination search, map picker, ride options, searching, live tracking, SOS (dials 112), payment, rating, history, wallet, profile, support chat | ✅ widget-tested (8 tests); never run on a device/emulator in this environment |
| Driver (Flutter): auth, vehicle registration, document upload, verification status, online toggle + location publishing, offer card with countdown, active-trip stages, navigation hand-off, earnings, orders, profile | 🟡 4 widget tests; never run on a device |
| Admin (React): dashboard, live ops (tables, no map), rides, drivers approve/reject/suspend, customers, payments/refunds, pricing, support, settings, audit | ✅ builds, 7 tests |
| Staff two-factor (TOTP + recovery codes, admin console login and "My security" page) | ✅ optional; enforcement for super/finance roles behind `security.staff_mfa_required` (off by default) | enforcement for other staff roles; no QR code (key + link only); no admin reset UI |
| Partner portal (`apps/partner-web`: registration, stores, menu, order accept/reject/ready, sales report; 7 tests) | ✅ (never opened in a real browser against a live backend) |
| Customer marketplace (shops list, menu, cart, checkout with server quote, wallet or cash on delivery, order tracking with handover code; 4 widget tests) | ✅ (not run on a device) |
| Terms/Privacy/About screens + publishing mechanism | ✅ mechanism; ⛔ content (needs counsel) |
| Customer Express (parcel create + tracking) and country-code picker on phone fields (9 tests incl. picker) | ✅ widget-tested |
| Referral programme (V16): personal code, optional code at sign-up, one-off PROMO→wallet bonus for both sides after the invited customer's first completed ride (min fare, per-referrer cap, ledger idempotent); **off by default** (`referral.enabled`, amounts editable in Admin → Settings). App: Profile → Invite friends | ✅ backend ITs + widget tests; promo budget is the owner's decision |
| Live contract test (apps' data layer ↔ real backend, 7 scenarios) | ✅ | runs in CI (`live-contract`); found a real bug on its first run (shared trip link stopped refreshing while a driver was still being searched) |

## Mocks (owner's part — to be replaced when accounts/keys/contracts exist)
| Area | What runs today | To go live |
|---|---|---|
| SMS / OTP | WhatsApp Cloud API is the primary channel (`JOLAY_WHATSAPP_*`, authentication template with Copy code button; tested only against a local stub, **never against a live Meta account**); `LogSmsSender` is the development fallback and delivers nothing (code in the log only when `JOLAY_SMS_LOG_CODE=true`). The `prod` profile refuses to start with no delivering channel | Meta account, approved templates; a real `SmsSender` bean named `productionSmsSender` for people without WhatsApp; handle Meta status webhooks |
| Push | `DevPushSender` → `push_outbox`; `FcmPushSender` auto-activates with `JOLAY_FCM_SERVICE_ACCOUNT_FILE` | Firebase project, service account, `google-services.json` / APNs key; implement `PushTokenSource` with `firebase_messaging` and override `pushTokenSourceProvider` in each app's main() |
| Maps / routing / geocoding | `EstimatedRouteProvider` (straight line × factor, flagged `ESTIMATED`), 12 seeded places, no map tiles | set `JOLAY_2GIS_KEY` (see DEPLOYMENT.md): address search, routing and map tiles all come from 2GIS through the backend; confirm the 2GIS terms (raster tiles in flutter_map/Leaflet, attribution, result storage) before launch |
| Card payments | `SandboxPaymentProvider` exists only with `JOLAY_PAYMENT_PROVIDER=sandbox` (signed callbacks, no real money; refused in `prod` unless the closed-demo flag and a strong secret are set). Public deployments run `JOLAY_PAYMENT_PROVIDER=none`: card rides and top-ups answer 503, cash and wallet work | merchant contract + adapter (docs/PAYMENT_INTEGRATION.md) |
| Bank payouts | finance transfers manually, records the reference | bank API / payout provider |
| Legal texts | none (apps show "not published yet") | counsel's texts via Admin → Legal documents |
| Store accounts / signing | local builds use the debug key only with `JOLAY_ALLOW_DEBUG_SIGNED_RELEASE=true`; release tasks otherwise fail without `android/key.properties`; the manual release workflow verifies APK and AAB signatures (Gradle guard unverified: no Android SDK in the audit environment) | Google Play / Apple accounts and release keys |

## Known limitations
* **Not production-ready.** Open blockers are listed in docs/DEPLOYMENT.md#production-readiness. The Render Blueprint is a pilot/staging template with card payments off.
* Map tiles are 2GIS raster tiles proxied by the backend (`/api/v1/geo/tiles`); without `JOLAY_2GIS_KEY` the map is blank. 2GIS does not guarantee third-party libraries work with raster tiles.
* The apps' **screens** have not been exercised on a device or against a live backend (widget tests use a faked API). What *is* verified live: the apps' real data layer (ApiClient, AuthController, WebSocket client, the customer app's providers and models, plus the keys the driver app reads) against the real backend — sign-up/OTP, driver onboarding and approval, a full cash ride with the WebSocket event, Express parcel with handover code, wallet top-up, a promo + peak + zone-surcharge wallet ride, SOS, logout (`scripts/live-contract-test.sh`, CI job `live-contract`). It does not cover layout, navigation, permissions, background location or push.
* Kazakh/Russian strings were written by the model and need review by native speakers.
* Load/soak testing: see docs/DEPLOYMENT.md#load-test for the measured numbers and their limits.
