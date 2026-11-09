# Security

## Implemented (and where it is tested)
* Passwords: BCrypt (cost 11); policy ≥ 8 chars, letter + digit. Login lockout after 5 failures / 15 min per identifier (in memory — per instance). Unknown accounts and wrong passwords are indistinguishable.
* OTP: 6 digits, 5 min TTL, 5 attempts, single use, ≤5 per hour per phone, 30 s resend throttle; stored as salted SHA-256; never logged unless `JOLAY_SMS_LOG_CODE=true` (dev; refused in prod). Delivery: WhatsApp first, SMS fallback. A gateway failure answers `503 otp_delivery_failed` on register/resend (the sign-up is rolled back, so the user can retry) and is swallowed by forgot-password, so no outcome differs between known and unknown accounts (`OtpDeliveryIT`). Forgot-password never reveals whether an account exists.
* JWT access (15 min, HMAC-SHA384, secret ≥ 32 bytes from `JOLAY_JWT_SECRET`) + opaque refresh tokens (30 d, stored hashed, rotated on use, family revoked on reuse). `AuthSecurityIT`.
* Authorization on the backend via `@PreAuthorize` + URL rules; per-object checks (rides, tickets, payments belong to the caller). Suspended users blocked even with valid JWTs. `AuthSecurityIT`.
* Input validation (Bean Validation + DB constraints); SQL is parameterised (JdbcClient named parameters; the few dynamic fragments are server constants).
* Payment webhooks: HMAC-SHA256 over the raw body, constant-time compare, event-id dedupe, exact amount verification (missing/malformed amounts fail the payment), idempotent ledger keys. `PaymentLedgerIT`. The sandbox gateway and its self-service checkout helper exist only when `JOLAY_PAYMENT_PROVIDER=sandbox` (`CardPaymentsDisabledIT`).
* Documents: whitelist (JPEG/PNG/PDF by magic bytes), ≤5 MB, at most 30 files per driver, random server-side file names (created with `CREATE_NEW`), stored outside any web root, admin-only download (OPERATIONS/SUPER) with audit record, `Content-Disposition: attachment`, `nosniff`, and a containment check so a tampered `storage_key` can never read outside the document directory (`DocumentUploadIT`). **Storage itself is local disk, not encrypted and not malware-scanned — see Known gaps.**
* Mobile tokens in Keychain/EncryptedSharedPreferences (`flutter_secure_storage`); release builds are HTTPS-only (cleartext allowed in debug manifests only).
* CORS limited to configured origins; stateless API so CSRF protection is disabled by design (no cookies).
* Secrets only via environment; `.env` is git-ignored; no default admin password (bootstrap requires env vars).
* Correlation ids on every response/log line; logs avoid phone numbers (masked) and never include tokens/OTPs/card data. No card data is handled at all.

* Startup guard (`ProductionSafetyCheck`, `ProductionSafetyCheckTest`): the `prod` profile refuses to start with a development/short JWT secret (< 32 bytes), OTP logging, an OTP channel that delivers nothing (only the development log sender), `localhost`/`*`/`http://` CORS origins, a non-https or localhost `JOLAY_PUBLIC_URL`, a weak bootstrap admin password (< 12 characters or a published default), or the sandbox payment gateway. The sandbox gateway needs the separate explicit flag `JOLAY_ALLOW_SANDBOX_PAYMENTS=true` **and** a strong `JOLAY_SANDBOX_WEBHOOK_SECRET`; that flag relaxes nothing else, and it is not set in `render.yaml`. Public deployments use `JOLAY_PAYMENT_PROVIDER=none` (no sandbox bean exists, card payments answer 503). Swagger is disabled and `/actuator/*` moves to a private management port (8081) in `prod`. The Docker image defaults to `SPRING_PROFILES_ACTIVE=prod`.

* Safety & fraud: SOS/incident handling is audited (views, notes, resolution); risk flags are review-only and never change accounts automatically; payouts and refunds are ledger-backed, role-restricted and audited; reconciliation runs hourly.

* Staff two-factor (TOTP, RFC 6238; `identity/Totp`, `MfaService`, `MfaController`): enrol at `/api/v1/account/mfa/setup` then `/enable` with a code; 8 single-use recovery codes (stored hashed) are shown once. Once enabled, login without a valid code returns `mfa_required` and no tokens; wrong codes count toward the same lockout as wrong passwords; the lockout counter is reset only after every factor passes; a used code cannot be replayed (last accepted time step is stored). Turning it off needs the current password plus a code. Secrets are stored AES-GCM encrypted with a key derived from `JOLAY_MFA_KEY` (falls back to the JWT secret; **changing the key makes enrolled secrets unreadable** — a super admin must reset them in the DB). Tests: `TotpTest` (RFC vectors), `MfaIT` (incl. enforcement).

## Review of 2026-11-07 (self-review by the development assistant, not an independent audit)
Scope: the code added in this working session (trip sharing, emergency contacts, referrals, promo codes, peak pricing, zone surcharges, routing/geocoding adapters, WebSocket) plus a sweep of the whole API surface. Method: inventory of all 168 endpoints, an automated authorization matrix, hostile-input tests, dependency check, secret scan, reading of the dynamic-SQL sites.

| Finding | Severity | Status |
|---|---|---|
| A signed-in caller without the required role got **400 with validation details** instead of 403, because `@PreAuthorize` runs after the request body is bound. Access was never granted, but the shape of the request leaked and parsing ran before authorization. | Low | **Fixed**: `RolePreCheckInterceptor` rejects with 403 before argument binding (method security stays the authority). |
| JSON request bodies were not size-limited: a multi-megabyte body was fully read and parsed, including on unauthenticated endpoints such as login. | Medium (availability) | **Fixed**: `RequestSizeLimitFilter` (256 KB, 413 `payload_too_large`; chunked bodies are cut off while read). |
| Promo codes are short human words; a signed-in user could guess them at the general API rate. | Low-medium (fraud) | **Fixed**: 10 unknown codes per 10 minutes per rider, then `429 promo_attempts_exceeded` (right code refused too). |
| `prod` could start with `JOLAY_CORS_ORIGINS=*` or localhost origins. | Low | **Fixed**: `ProductionSafetyCheck` refuses it (sandbox demo excepted). |
| `prod` could start without a public https URL, which would put `localhost` links into SMS. | Medium | **Fixed** earlier the same day. |
| Spring Boot 3.4.1 (Tomcat 10.1.34, out of support). | Medium | **Fixed**: upgraded to **3.5.16** (Tomcat 10.1.55, Jackson 2.21.4, Spring Security 6.5); full test suite and the live contract test pass. |
| A shared trip link opened while searching for a driver stopped refreshing. | Functional | **Fixed** (found by the live contract test). |
| Documentation said JWT HS256; the code uses HS384. | Doc | **Fixed**. |

Checked and found sound: every endpoint without a role rule is public on purpose or scoped by the caller's id (listed in `AuthorizationMatrixIT.everyEndpointWithoutARoleRuleIsOnTheReviewedList`; adding a new unreviewed one fails the test); all dynamic SQL fragments are server constants; no secrets or private keys in the repository (`git grep`); `npm audit` reports 0 vulnerabilities for the admin and partner web apps; trip-share tokens are 192 bits from `SecureRandom`, the public view exposes no phone, fare or payment data and the viewer page uses `textContent` and a restrictive CSP; emergency contacts and shares are only readable/removable by their owner.

Regression tests: `AuthorizationMatrixIT` (every role-guarded endpoint × every role it does not list + anonymous, 400+ combinations over real HTTP), `InputAbuseIT`, `PromoCodeIT.guessingPromoCodesIsStoppedAfterTenUnknownOnes`, `ProductionSafetyCheckTest`.

**Not covered by this review** (needs an independent party): penetration testing of a deployed environment, TLS/ingress configuration, the mobile apps' binary hardening, third-party SDKs once real ones are added, Java dependency CVE scanning with a database (no such tool is wired in), denial-of-service at network level, and business-logic abuse that needs real-world data (antifraud thresholds are uncalibrated).

## Review of 2026-11-09 (self-review by the development assistant, not an independent audit)
Scope: payments/Render configuration, OTP and sign-in, driver documents, production guard, release signing, documentation accuracy.

| Finding | Severity | Status |
|---|---|---|
| `render.yaml` ran a **public** deployment on the sandbox payment gateway with `JOLAY_ALLOW_SANDBOX_PAYMENTS=true`; any customer could mark their own card payments as paid through `/payments/{id}/sandbox-checkout`, and that flag also switched off the CORS and https checks. | High | **Fixed**: Render uses `JOLAY_PAYMENT_PROVIDER=none`; the sandbox flag no longer relaxes any other check; `SandboxPaymentProvider` is only a bean when selected, so its endpoints and the default webhook secret do not exist otherwise. |
| The `prod` profile started with the development log sender, so no user could receive an OTP (sign-up and password reset impossible, silently). | High (availability) | **Fixed**: startup is refused unless WhatsApp and/or a real `SmsSender` is configured. |
| An OTP gateway exception became a 500, and for forgot-password it differed between existing and unknown accounts (enumeration). | Medium | **Fixed** (`OtpDeliveryIT`). |
| `JOLAY_ADMIN_PASSWORD` could be a published default in `prod`. | Medium | **Fixed**: ≥ 12 characters and not a known default. |
| Document download did not verify the resolved path stays inside the document directory; unlimited uploads per driver. | Low (defence in depth) / Low | **Fixed** (`DocumentUploadIT`). |
| A malformed `amount` in a signed webhook raised an unhandled exception instead of failing the payment. | Low | **Fixed** (`PaymentLedgerIT`). |
| Kubernetes manifest ran 2 replicas although realtime events, rate limits and lockout are per instance. | Medium | **Fixed**: pinned to 1 with an explanation. |
| Release Android builds silently fell back to the debug key (CI verified only the APK). | High for publishing | **Fixed (unverified here)**: Gradle refuses release tasks without `key.properties`; the release workflow also verifies the AAB. No Android SDK was available to run it. |
| Driver documents are on local disk without encryption or malware scanning, and not durable on Render/containers. | High for real documents | **Open — cannot be fixed inside this repository** (needs a durable encrypted volume or object storage). The prod profile logs a warning at every start; see docs/DEPLOYMENT.md#driver-documents. |

## Known gaps — do before production
* Rate limiting is per instance (`RateLimitFilter`: auth endpoints per IP, API per user): with N instances every limit is multiplied by N. Add a global limit at the gateway/ingress and run a single backend instance (docs/ARCHITECTURE.md#scaling-one-backend-instance-only).
* Login lockout is per-instance memory; move to the DB/Redis before running more than one instance.
* WebSocket events are delivered from the memory of the instance that owns the connection; with more than one instance events are silently lost (clients re-sync through REST). No shared event bus exists.
* WebSocket takes the JWT in the query string — redact in proxy logs or switch to a ticket exchange.
* Staff MFA (TOTP) is optional by default. Setting `security.staff_mfa_required=true` (off by default) confines SUPER_ADMIN and FINANCE_ADMIN accounts without a second factor to the enrolment endpoints (`403 mfa_enrollment_required` everywhere else, checked on every request in `JwtAuthFilter`), and the console shows only the setup page. Turn it on only after the owner has enrolled their own account. Operations admins and support agents are not enforced yet. No IP allow-listing for the admin console, no session listing/revocation UI.
* Driver document files (IDs, licences) are on local disk, **unencrypted, unscanned and, on Render or any container without a mounted volume, not durable**. This repository does not implement encrypted or object storage (and deliberately has no home-made encryption): mount a durable, encrypted volume or use object storage with signed URLs and malware scanning before accepting real documents. Account deletion anonymises customers only; driver documents are not removed by it.
* Dependency updates are proposed weekly by Dependabot (`.github/dependabot.yml`) and CI runs `npm audit --omit=dev --audit-level=high` for both web apps; there is **no** Java dependency vulnerability scan, no SAST, no penetration test and no formal threat model yet.
* Promo-code guess limiting (10 unknown codes / 10 min per rider) is in memory per instance, like the other limiters.
* Personal-data retention/erasure rules are **not** verified against Kazakhstan law (see below).

## Legal / compliance — requires qualified Kazakhstan counsel (nothing here is verified legal advice)
Topics to review with local lawyers/accountants before launch: Law on Personal Data and its Protection (consent, storage/processing of citizens' data in Kazakhstan, cross-border transfer),
taxi/passenger-transport licensing and driver/vehicle documentation rules (incl. local-authority requirements in Almaty), electronic-payment and e-money regulation (NBK) and fiscal receipts,
consumer-protection duties (price disclosure, refunds), tax/accounting for marketplace/agent models, terms of service/privacy policy text (kk/ru), data-retention periods for financial records.
The app contains **no** legal texts; Terms/Privacy screens must be supplied by counsel.
