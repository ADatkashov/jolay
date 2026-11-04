# Security

## Implemented (and where it is tested)
* Passwords: BCrypt (cost 11); policy ≥ 8 chars, letter + digit. Login lockout after 5 failures / 15 min per identifier (in memory — per instance). Unknown accounts and wrong passwords are indistinguishable.
* OTP: 6 digits, 5 min TTL, 5 attempts, single use, ≤5 per hour per phone, 30 s resend throttle; stored as salted SHA-256; never logged unless `JOLAY_SMS_LOG_CODE=true` (dev). Forgot-password never reveals whether an account exists.
* JWT access (15 min, HS256, secret ≥ 32 bytes from `JOLAY_JWT_SECRET`) + opaque refresh tokens (30 d, stored hashed, rotated on use, family revoked on reuse). `AuthSecurityIT`.
* Authorization on the backend via `@PreAuthorize` + URL rules; per-object checks (rides, tickets, payments belong to the caller). Suspended users blocked even with valid JWTs. `AuthSecurityIT`.
* Input validation (Bean Validation + DB constraints); SQL is parameterised (JdbcClient named parameters; the few dynamic fragments are server constants).
* Payment webhooks: HMAC-SHA256 over the raw body, constant-time compare, event-id dedupe, amount verification, idempotent ledger keys. `PaymentLedgerIT`.
* Documents: whitelist (JPEG/PNG/PDF by magic bytes), ≤5 MB, random file names, stored outside any web root, admin-only download with audit record and `Content-Disposition: attachment`.
* Mobile tokens in Keychain/EncryptedSharedPreferences (`flutter_secure_storage`); release builds are HTTPS-only (cleartext allowed in debug manifests only).
* CORS limited to configured origins; stateless API so CSRF protection is disabled by design (no cookies).
* Secrets only via environment; `.env` is git-ignored; no default admin password (bootstrap requires env vars).
* Correlation ids on every response/log line; logs avoid phone numbers (masked) and never include tokens/OTPs/card data. No card data is handled at all.

* Startup guard (`ProductionSafetyCheck`): the `prod` profile refuses to start with the default JWT secret, OTP logging, or the sandbox payment gateway. Swagger is disabled and `/actuator/*` moves to a private management port (8081) in `prod`.

## Known gaps — do before production
* Rate limiting is per instance (`RateLimitFilter`: auth endpoints per IP, API per user). Add a global limit at the gateway/ingress.
* Login lockout is per-instance memory; move to the DB/Redis for multi-replica.
* WebSocket takes the JWT in the query string — redact in proxy logs or switch to a ticket exchange.
* No MFA for staff, no IP allow-listing for the admin console, no session listing/revocation UI.
* Driver document files are on local disk — use encrypted object storage with signed URLs and malware scanning.
* No dependency/SAST scanning in CI yet; no penetration test; no formal threat model.
* Personal-data retention/erasure rules are **not** verified against Kazakhstan law (see below).

## Legal / compliance — requires qualified Kazakhstan counsel (nothing here is verified legal advice)
Topics to review with local lawyers/accountants before launch: Law on Personal Data and its Protection (consent, storage/processing of citizens' data in Kazakhstan, cross-border transfer),
taxi/passenger-transport licensing and driver/vehicle documentation rules (incl. local-authority requirements in Almaty), electronic-payment and e-money regulation (NBK) and fiscal receipts,
consumer-protection duties (price disclosure, refunds), tax/accounting for marketplace/agent models, terms of service/privacy policy text (kk/ru), data-retention periods for financial records.
The app contains **no** legal texts; Terms/Privacy screens must be supplied by counsel.
