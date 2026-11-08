# JOLAY design direction (implemented)

Premium minimalism, map-first, restrained yellow on Midnight/Cloud. This documents what is built — see [JOLAY_DESIGN_SYSTEM.md](JOLAY_DESIGN_SYSTEM.md) for tokens/components and [SCREEN_INVENTORY.md](SCREEN_INVENTORY.md) for coverage.

* **Customer:** Midnight splash → 3-slide onboarding with code-drawn illustrations, skip and language → phone/OTP auth (segmented OTP, inline error, resend timer) → map-first home (location-permission card, recenter, notifications, active-ride banner) → destination search → ride categories (RideTypeCard, promo, payment) → animated driver search (timer, cancel) → driver assigned/live trip (progress, vehicle plate, call, share, SOS) → completion (receipt, pay, rating, ride again). Ordering, parcel (Express), activity, wallet, profile, notifications share the same components.
* **Driver:** Midnight auth shell, map dashboard with a single online switch and today stats, request card where *earnings* and *Accept* dominate (countdown ring, pickup/trip time, route), active trip/delivery panel with one stage button, earnings, history, profile, documents checklist.
* **Web (admin/partner):** SaaS shell — grouped sidebar, breadcrumb topbar, skip link, `aria-current`, sticky-ready tables, icon+text status pills, dark mode, responsive.
* **Dark mode:** separate semantic tokens; customer/driver have System/Light/Dark in Profile → Appearance; web follows the OS.
Honest limits: no Manrope (Kazakh coverage); no customer↔driver chat, tipping, saved-address editor, payment-method vault or in-app merchant search because the backend does not provide them.
