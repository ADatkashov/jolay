# Payment integration

## Current state
| Piece | Status |
|---|---|
| Cash rides (commission debited from driver wallet) | implemented, tested |
| Wallet rides (ledger) | implemented, tested |
| Card / wallet top-up through `PaymentProvider` | implemented against **`SandboxPaymentProvider`** (HMAC-signed callbacks; no money moves). The sandbox bean and its `/payments/{id}/sandbox-checkout` helper exist **only** when `JOLAY_PAYMENT_PROVIDER=sandbox` |
| Public/production deployments | `JOLAY_PAYMENT_PROVIDER=none`: card rides and card top-ups answer `503 card_payments_unavailable`; cash and wallet rides work. The `prod` profile refuses `sandbox` unless `JOLAY_ALLOW_SANDBOX_PAYMENTS=true` (closed internal demo only, with a strong `JOLAY_SANDBOX_WEBHOOK_SECRET`) |
| Kaspi, FreedomPay or any bank gateway | **not integrated** — requires a merchant agreement, API documentation and credentials |
| Hourly reconciliation job, driver and partner payouts (manual bank transfer) | built (see STATUS.md) |
| Tokenised saved cards, 3-DS redirect handling, gateway-report reconciliation | not built |

Never claim a payment is complete from the client. Flow: client calls `POST /payments/initialize` → backend creates `payment_transactions(PENDING)` and returns the provider checkout URL →
the gateway calls `POST /payments/webhooks/{provider}` → signature verified (HMAC-SHA256 over the raw body, constant-time compare) → event id de-duplicated → amount checked exactly (a missing, malformed or different amount fails the payment) → ledger posted → ride `PAID` → `PAYMENT_STATUS_UPDATED` event.

## Writing a real adapter
Implement `kz.jolay.payments.PaymentProvider` (`name`, `initiate`, `verifySignature`, `refund`) as a Spring `@Component`, set `JOLAY_PAYMENT_PROVIDER=<name>`.
Per provider you must obtain and configure (names are placeholders until the contract exists):
* merchant id / terminal id, API secret/signing key (env/secret manager, never in git), callback + success/failure URLs (`JOLAY_PUBLIC_URL` must be reachable by the gateway),
* the exact signature algorithm and canonical string, status codes/enumeration, refund endpoint, reconciliation/report API, settlement schedule and fees,
* sandbox credentials for CI, and the gateway's IP allow-list for the webhook.
Open items for any adapter: map gateway statuses → `SUCCEEDED/FAILED`, handle `PENDING` timeouts (query status API), partial refunds, chargebacks, and a nightly reconciliation comparing `payment_transactions` with the gateway report.

Kaspi note: availability of a public merchant API for ride-hailing is a **commercial question to confirm with Kaspi**; this repo makes no assumption.

## Ledger
Double-entry accounts: `CUSTOMER_WALLET`, `DRIVER_WALLET`, `PLATFORM_REVENUE`, `EXTERNAL_CARD`, `EXTERNAL_CASH`, `PROMO`. Examples (signed amounts):
card ride 1000 with 15 %: `EXTERNAL_CARD −1000, DRIVER_WALLET +850, PLATFORM_REVENUE +150` · cash ride: `DRIVER_WALLET −150, PLATFORM_REVENUE +150` · top-up: `EXTERNAL_CARD −X, CUSTOMER_WALLET +X`.
Postings are idempotent (`ride-pay-<id>`, `pay-<id>`, `refund-<id>`) and rejected unless they sum to zero.
