# Payment integration

## Current state
| Piece | Status |
|---|---|
| Cash rides (commission debited from driver wallet) | implemented, tested |
| Wallet rides (ledger) | implemented, tested |
| Card / wallet top-up through `PaymentProvider` | implemented against **`SandboxPaymentProvider`** (HMAC-signed callbacks; no money moves) |
| Kaspi, FreedomPay or any bank gateway | **not integrated** — requires a merchant agreement, API documentation and credentials |
| Tokenised saved cards, 3-DS redirect handling, reconciliation job, driver payouts | not built |

Never claim a payment is complete from the client. Flow: client calls `POST /payments/initialize` → backend creates `payment_transactions(PENDING)` and returns the provider checkout URL →
the gateway calls `POST /payments/webhooks/{provider}` → signature verified → amount checked → ledger posted → ride `PAID` → `PAYMENT_STATUS_UPDATED` event.

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
