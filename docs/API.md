# API (REST, `/api/v1`)

Interactive documentation: `/api/v1/swagger-ui` (OpenAPI JSON at `/api/v1/docs`). Errors: `{"code","message","fields?","traceId"}` — clients localise by `code`.
Auth: `Authorization: Bearer <access JWT>` (15 min); refresh tokens rotate on use; reuse revokes the whole family.
Idempotency: send `Idempotency-Key` on `POST /rides`, `POST /wallet/top-ups`, `POST /payments/initialize`.

| Area | Endpoints |
|---|---|
| Auth (public) | `POST /auth/register` · `resend-otp` · `verify-otp` · `login` · `refresh` · `logout` · `forgot-password` · `reset-password` |
| Catalog (public) | `GET /catalog/categories?lang=` · `/catalog/cities` |
| Geo | `GET /geo/places?q=&lat=&lng=` · `GET /geo/reverse?lat=&lng=` |
| Profile (any role) | `GET/PUT/DELETE /customers/me` · customer: `GET/POST/DELETE /customers/me/addresses` · `GET /customers/me/recent-destinations` |
| Rides (customer) | `POST /rides/estimate` · `POST /rides` · `GET /rides/active` · `GET /rides/history?tab=completed|ongoing|cancelled` · `GET /rides/{id}` · `GET /rides/{id}/fare` · `POST /rides/{id}/cancel` · `POST /rides/{id}/rating` |
| Driver | `POST /drivers/register` · `GET /drivers/me` · `POST/GET /drivers/documents` · `PUT /drivers/availability` · `POST /drivers/location` · `GET /drivers/offers` · `POST /drivers/offers/{id}/accept|decline` · `GET /drivers/rides/active|history` · `POST /drivers/rides/{id}/en-route|arrived|start|complete|cancel` · `GET /drivers/earnings?period=today|week|month` |
| Wallet / payments | `GET /wallet` · `GET /wallet/transactions` · `POST /wallet/top-ups` · `POST /payments/initialize` · `GET /payments/{id}` · `POST /payments/webhooks/{provider}` (signature) · `POST /payments/{id}/sandbox-checkout` (sandbox only) |
| Support | `POST/GET /support/tickets` · `GET/POST /support/tickets/{id}/messages` |
| Safety | `POST /incidents` (SOS/COMPLAINT/ACCIDENT/OTHER) · `GET /incidents` |
| Payouts (driver) | `POST/GET /drivers/payouts` |
| Legal (public) | `GET /catalog/legal/{TERMS|PRIVACY|ABOUT}?lang=` |
| Express (customer) | `POST /deliveries/estimate` · `POST /deliveries` · `GET /deliveries/history` · `GET /deliveries/{id}` · `POST /deliveries/{id}/cancel` · `POST /deliveries/{id}/rating` · public `GET /catalog/track/{trackingNumber}` |
| Express (courier) | `PUT /drivers/delivery` · `GET /drivers/delivery-offers` · `POST /drivers/delivery-offers/{id}/accept|decline` · `GET /drivers/deliveries/active|history` · `POST /drivers/deliveries/{id}/picked-up|deliver|cancel` |
| Notifications | `GET /notifications` · `POST /notifications/{id}/read` · `POST /notifications/devices` |
| Admin (staff roles) | `GET /admin/dashboard|live|rides|rides/{id}|rides/{id}/history|drivers|customers|pricing|payments|wallets|support/tickets|settings|audit-logs` · `PUT /admin/drivers/{id}/verification` · `PUT /admin/users/{id}/status` · `PUT /admin/pricing/{id}` · `POST /admin/payments/{id}/refund` · `POST /admin/support/tickets/{id}/messages` · `PUT /admin/settings/{key}` · `GET /admin/deliveries[/{id}]` · `GET /admin/incidents[/{id}]` · `POST /admin/incidents/{id}/ack|note|resolve` · `GET /admin/payouts` · `POST /admin/payouts/{id}/pay|reject` · `GET /admin/risk-flags` · `POST /admin/risk-flags/{id}/review` · `GET /admin/legal` · `PUT /admin/legal/{type}/{locale}` · `POST /admin/staff` · `GET /admin/finance/reconciliation` · `GET /admin/drivers/documents/{id}/file` |

Role matrix (incidents: SUPER/OPERATIONS/SUPPORT; payouts: SUPER/FINANCE; risk flags: SUPER/OPERATIONS/FINANCE; legal publishing: SUPER):
 `SUPER_ADMIN` all · `OPERATIONS_ADMIN` drivers/users/rides · `FINANCE_ADMIN` pricing/payments/refunds/wallets · `SUPPORT_AGENT` read + support replies.
Differences from the initial brief: `PUT /drivers/availability` takes `{online}`; an extra `en-route` step exists in the driver flow; `/payments/initialize` pays a **completed ride**.

## Marketplace (V8)

Customer: `GET /stores?lat&lng&category`, `GET /stores/{id}/menu`, `POST /store-orders/estimate` (no money moves), `POST /store-orders` (requires `Idempotency-Key`; pays from wallet into escrow), `GET /store-orders[?tab=ongoing]`, `GET /store-orders/{id}`, `POST /store-orders/{id}/cancel` (only while PLACED).
Partner (`ROLE_PARTNER`): `POST /partner/register`, `GET /partner/me`, stores and products CRUD under `/partner/stores…`, `POST /partner/orders/{id}/accept|reject|ready`, `GET /partner/reports/sales`.
Admin: `GET /admin/partners`, `POST /admin/partners/{id}/status`, `GET /admin/store-orders`.

Partner payouts (V9): `POST /partner/payouts` (amount, destination; holds PARTNER_WALLET funds), `GET /partner/payouts`. Finance pays/rejects through the same `/admin/payouts/{id}/pay|reject` endpoints as driver payouts; `GET /admin/payouts` returns `wallet_type`.

Cash on delivery (V10): `POST /store-orders` accepts `paymentMethod` = `WALLET` (default, escrow) or `CASH`. Errors: `cash_limit_exceeded`, `too_many_cash_orders`. The courier's active delivery carries `cashToCollect`.
