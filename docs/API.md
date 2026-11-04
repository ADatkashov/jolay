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
| Notifications | `GET /notifications` · `POST /notifications/{id}/read` · `POST /notifications/devices` |
| Admin (staff roles) | `GET /admin/dashboard|live|rides|rides/{id}|rides/{id}/history|drivers|customers|pricing|payments|wallets|support/tickets|settings|audit-logs` · `PUT /admin/drivers/{id}/verification` · `PUT /admin/users/{id}/status` · `PUT /admin/pricing/{id}` · `POST /admin/payments/{id}/refund` · `POST /admin/support/tickets/{id}/messages` · `PUT /admin/settings/{key}` · `POST /admin/staff` · `GET /admin/drivers/documents/{id}/file` |

Role matrix: `SUPER_ADMIN` all · `OPERATIONS_ADMIN` drivers/users/rides · `FINANCE_ADMIN` pricing/payments/refunds/wallets · `SUPPORT_AGENT` read + support replies.
Differences from the initial brief: `PUT /drivers/availability` takes `{online}`; an extra `en-route` step exists in the driver flow; `/payments/initialize` pays a **completed ride**.
