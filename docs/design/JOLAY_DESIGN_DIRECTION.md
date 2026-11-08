# JOLAY — Product Design Direction

**Brand:** JOLAY  
**Primary line:** Your City. Your Way.  
**Secondary line:** Mobility. Delivery. Everyday.  
**Market:** Kazakhstan · Almaty first  
**Languages:** Қазақша / Русский / English  
**Currency:** KZT (₸)

This document defines the visual direction and interface rules for the existing JOLAY product. It is a design specification, not a claim that every described screen or feature is already implemented. For implementation status, see [STATUS.md](../product/STATUS.md).

## 1. Design principles

1. **Confident simplicity.** One clear primary action per screen; remove decorative UI that does not help a task.
2. **Local by default.** Almaty addresses, KZT prices, +7 phone format, and Kazakh/Russian/English layouts must feel native.
3. **Map-first mobility.** Maps are the primary workspace during pickup, dispatch, and active rides. Keep controls in compact bottom sheets.
4. **Trust through clarity.** Show driver identity, vehicle/plate, ETA, fare, payment state, and safety actions with clear hierarchy.
5. **One ecosystem, distinct tools.** Customer, Driver, Partner, and Admin share brand tokens but have different information density and navigation.
6. **Honest states.** Distinguish estimated route data, sandbox payments, mocked push/SMS, and production-ready functionality. Never design a mock as if it were a confirmed live capability.

## 2. Brand tokens

Use the existing source of truth in `shared/design-tokens/tokens.json`.

| Token | Value | Use |
|---|---|---|
| Midnight | `#171717` | Brand surfaces, headings, driver work surfaces |
| JOLAY Yellow | `#F5BD35` | Primary actions, active states, key highlights |
| Cloud | `#F7F7F4` | App background |
| White | `#FFFFFF` | Cards and elevated surfaces |
| Text secondary | `#777777` | Supporting labels |
| Border | `#EAEAEA` | Dividers and outlines |
| Success | `#20A46B` | Confirmed/completed states |
| Error | `#E5484D` | Destructive and emergency states |

**Typography:** Manrope (Regular, Medium, SemiBold, Bold, ExtraBold); Inter/system sans-serif fallback.  
**Radius:** 8 / 14 / 20 px for small / medium / large.  
**Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32 px.

### Color behavior

- Yellow is the main action color. Use dark text on yellow.
- Midnight is for high-contrast brand moments, not every card.
- Cloud is the default canvas; white cards sit on Cloud.
- Reserve green and red for semantic status only.
- Do not use gradients as a default treatment.
- Verify text contrast for all three locales and all interactive states.

## 3. Shared component language

Build and reuse these primitives across Flutter and React:

- **Primary button:** JOLAY Yellow fill, Midnight label, 14 px radius, minimum 48 px height; clear pressed, disabled, and loading states.
- **Secondary button:** white or transparent fill, 1 px Border stroke, Midnight label.
- **Icon button:** 44–48 px hit area; use recognizable outlined icons and labels where ambiguity is possible.
- **Surface card:** White fill, 20 px radius, subtle shadow only when elevation communicates hierarchy.
- **Input:** 56 px minimum height, Cloud/White surface, Border outline, explicit label and validation/help text.
- **Status pill:** semantic color with readable text; never communicate status by color alone.
- **Bottom navigation:** 4 destinations maximum for the customer app; active item uses a compact yellow accent.
- **Bottom sheet:** map-related actions, fare choices, and live ride controls; rounded top corners and a visible drag handle.
- **Empty/loading/error states:** include explanation and a meaningful next action; avoid blank panels and indefinite spinners.

## 4. Customer app

The customer app is the consumer-facing flagship. Prioritize a calm, map-led home screen and a short path to the three main jobs: **Поехать / Заказать / Отправить**.

### Home

- Header: JOLAY wordmark, current city/location, avatar and notifications.
- Main destination module: “Куда направимся?” with pickup, destination search, Home and Work shortcuts.
- Three service tiles: Ride, Delivery, Express. Use simple original pictograms and short labels.
- Supporting content: recent destinations, active order/ride card, contextual promotion.
- Bottom navigation: Home, Activity, Wallet, Profile.
- Avoid turning the home screen into a crowded service catalogue.

### Ride flow

1. Pickup selection: full map with a clear pickup pin and compact address sheet.
2. Destination search: search field, recent places, saved Home/Work and map selection.
3. Ride options: vertically stacked Economy, Comfort, Business and XL rows; vehicle type, ETA, capacity and **large KZT fare**.
4. Finding a driver: dark Midnight surface, restrained animated search motif, pickup/drop-off summary and cancel action.
5. Driver assigned / in ride: map remains dominant; driver name, rating, car, plate, ETA and Call/Chat/Share/Safety actions are grouped in a bottom sheet.
6. Completion: concise fare breakdown, payment state, receipt and rating.

### Delivery and Express

- Use clear category selection for food, groceries, shops and parcels.
- Product browsing should emphasize imagery, price, availability and add-to-cart actions.
- Express parcel form should use a step-by-step layout for sender, recipient, addresses and parcel details.
- Tracking should show the current backend order state and next expected milestone.

### Wallet, activity and profile

- Wallet: prominent available balance, clear top-up action, chronological ledger activity.
- Activity: separate ride and delivery history with status, date, route and amount.
- Profile: identity first, then wallet/payment methods, saved places, language, support and settings.
- Keep safety and support reachable without digging through nested menus.

## 5. Driver app

Driver is an operational tool used in motion. It must be glanceable, high contrast, and optimized for one-handed use.

### Driver home / online state

- Header: driver identity, verification state and daily earnings.
- A large online/offline control with a clearly visible current state.
- Map or active-job area occupies the majority of the available space.
- Incoming offer card: pickup distance, trip destination/area, estimated earnings/fare, payment method and a prominent accept action with countdown.
- Do not rely on color alone for offer urgency.

### Active ride

- One dominant next-step action reflecting the real ride state.
- Pickup/drop-off address and navigation handoff.
- Passenger contact action where available.
- Emergency action separated from routine actions and visually unmistakable.
- Delivery acceptance toggle and delivery-specific task cards should not compete with the active ride.

### Earnings and profile

- Today / Week / Month segmented selector.
- Net earnings as the primary metric; trips, gross and commission as supporting metrics.
- Vehicle and verification information in profile.
- Payout status must distinguish requested, pending, paid and rejected.

## 6. Partner portal

Partner is a desktop-first operational workspace for stores and restaurants.

- Left navigation: Overview, Orders, Catalog, Stores, Reports, Payouts, Settings.
- Top bar: selected store, service status, notifications and account.
- Orders view: clear incoming / accepted / preparing / ready / completed lanes or tabs.
- Order cards: order number, age, items, total, delivery method and one primary next action.
- Catalog: searchable table with product image, name, category, price, availability and edit action.
- Reports: sales, order count, average order value and commission; always label the selected date range.
- Responsive tablet layout; on narrow screens, collapse navigation and preserve order actions.

## 7. Admin console

Admin is an information-dense staff product. Favor clarity, scanability and safe actions over consumer-style decoration.

- Persistent left sidebar and compact top bar.
- Dashboard cards for active rides, orders, revenue, pending driver reviews and open support tickets.
- Operational tables with search, filters, sort, pagination and clear empty/loading/error states.
- Detail pages use a consistent header, status, key facts, activity timeline and action panel.
- Destructive actions require confirmation and explain consequences.
- Financial screens must show currency, date range, transaction status and audit context.
- Keep role-based actions visible only to authorized staff.

## 8. Responsive and accessibility rules

- Customer and Driver: design around a 390 × 844 logical-pixel reference viewport, then validate compact and large phones.
- Partner/Admin: desktop baseline 1440 px; support tablet widths and a usable 1280 px layout.
- Minimum interactive target: 44 × 44 px.
- Body text: 14–16 px minimum; secondary text should not become too faint.
- Do not truncate addresses, prices, license plates or critical statuses.
- Check long Kazakh and Russian strings, not only English.
- Support system text scaling and safe areas.
- Provide visible focus states on web and semantic labels for icon-only controls.
- Respect reduced-motion settings.

## 9. Product truth and design handoff

The repository currently has a working taxi foundation, customer ride flow, driver operations, admin console, partner portal, marketplace and Express flows. Some infrastructure integrations are still mocked or sandboxed, and the UI has not yet been exercised on physical devices. The design must reflect those boundaries.

Before marking a screen production-ready:
- Map every visible action to an implemented route/state or mark it explicitly as future scope.
- Verify all loading, empty, error, disabled, success and permission states.
- Validate localization in kk / ru / en.
- Check fare and balance formatting in KZT.
- Confirm map/routing, payment, SMS and push states match the actual configured providers.
- Review the final layout on real iOS and Android devices and on supported web breakpoints.

## 10. Source references

- [Brand tokens](../../shared/design-tokens/tokens.json)
- [Product implementation status](../product/STATUS.md)
- [Owner product brief](../product/OWNER_PROMPTS.md)
- [Repository README](../../README.md)


---

## Implemented direction (design-system release)


Premium minimalism, map-first, restrained yellow on Midnight/Cloud. This documents what is built — see [JOLAY_DESIGN_SYSTEM.md](JOLAY_DESIGN_SYSTEM.md) for tokens/components and [SCREEN_INVENTORY.md](SCREEN_INVENTORY.md) for coverage.

* **Customer:** Midnight splash → 3-slide onboarding with code-drawn illustrations, skip and language → phone/OTP auth (segmented OTP, inline error, resend timer) → map-first home (location-permission card, recenter, notifications, active-ride banner) → destination search → ride categories (RideTypeCard, promo, payment) → animated driver search (timer, cancel) → driver assigned/live trip (progress, vehicle plate, call, share, SOS) → completion (receipt, pay, rating, ride again). Ordering, parcel (Express), activity, wallet, profile, notifications share the same components.
* **Driver:** Midnight auth shell, map dashboard with a single online switch and today stats, request card where *earnings* and *Accept* dominate (countdown ring, pickup/trip time, route), active trip/delivery panel with one stage button, earnings, history, profile, documents checklist.
* **Web (admin/partner):** SaaS shell — grouped sidebar, breadcrumb topbar, skip link, `aria-current`, sticky-ready tables, icon+text status pills, dark mode, responsive.
* **Dark mode:** separate semantic tokens; customer/driver have System/Light/Dark in Profile → Appearance; web follows the OS.
Honest limits: no Manrope (Kazakh coverage); no customer↔driver chat, tipping, saved-address editor, payment-method vault or in-app merchant search because the backend does not provide them.

### Deviations from the specification above
| Spec | Implemented | Why |
|---|---|---|
| Manrope | **Inter** (bundled) | Manrope lacks Kazakh Ә Ғ Қ Ң Ұ |
| Text secondary `#777777` | `#6B6B6B` | WCAG AA (4.5:1) on Cloud |
| Success `#20A46B`, Error `#E5484D`, Border `#EAEAEA` | `#198754`, `#DC3545`, `#E8E8E5` | Brand brief for this release; tokens in `shared/design-tokens/` |
| Input min height 56 | 52 | Matches button scale |
Full token and component reference: [JOLAY_DESIGN_SYSTEM.md](JOLAY_DESIGN_SYSTEM.md).
