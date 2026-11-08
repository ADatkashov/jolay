# JOLAY Design System

Single source of truth: `shared/jolay_core/lib/src/design/` (Flutter) and `shared/design-tokens/tokens.css|json` (web). Change both together.

## Brand
Your City. Your Way. Midnight `#171717`, Jolay Yellow `#F5BD35`, Cloud `#F7F7F4`, White. Yellow is for primary actions, selected states and highlights — never whole screens. Never use yellow as text on white.

## Colour tokens
Use `context.palette` (`JolayPalette`) in screens, never raw hex. Light and dark are separate semantic sets.

| Token | Light | Dark |
|---|---|---|
| background | #F7F7F4 | #0E0E0E |
| surface / elevated | #FFFFFF | #1A1A19 / #252524 |
| textPrimary | #171717 | #F4F4F0 |
| textSecondary | **#6B6B6B** | #A6A6A1 |
| border | #E8E8E5 | #34342F |
| selected | #FDF3D6 | #3A3120 |
| success / warning / error / info | #198754 / #E9A23B (text #9A6200) / #DC3545 / #2878D0 | #3DBB7E / #F0B45A / #F2707A / #6AAEF0 |

Deviation from the brief: secondary text is `#6B6B6B`, not `#777777` — `#777` is 4.48:1 on white and ~4.1:1 on Cloud (below WCAG AA 4.5:1). Warning text uses a darker amber for the same reason.

## Typography
**Inter** (bundled, SIL OFL). The brief prefers Manrope, but Manrope has no Kazakh letters (Ә Ғ Қ Ң Ұ), which would break kk. Scale: Display 36/32, H1 28, H2 24/22, H3 20, Body 14–16, Caption 12.5, Button 15/600. Prices use tabular figures.

## Shape, spacing, elevation, motion
4/8 spacing (`AppSpacing`). Radius: button/input 14, card 18, sheet 28 (`AppRadius`). Cards are outlined, not shadowed; only floating map UI and sheets use shadows (`AppElevation`). Heights: button 52/44/36, input 52, min tap 48 (`AppSizes`). Durations 120/200/320 ms (`AppDurations`); `context.motion(d)` returns zero under OS reduce-motion, and ambient animations (pulse, shimmer, dots) stop.

## Components (`jolay_core`)
Buttons: `PrimaryButton`, `SecondaryButton`, `AppOutlinedButton`, `AppTextButton`, `AppIconButton` (tooltip mandatory = accessible name). Inputs: `AppTextField`, `SearchField`, `LocationField`, `OtpField`. Surfaces: `AppCard`, `MapPanel`, `showAppBottomSheet`, `showAppModal`, `showConfirmationDialog`, `showAppToast`. Display: `StatusBadge`, `PriceLabel`, `RatingView`/`RatingInput`, `Avatar`, `DriverAvatar`, `VehicleCard`, `RideTypeCard`, `AddressCard`, `InfoRow`. States: `EmptyState`, `ErrorState`, `LoadingState`, `SkeletonLoader`/`SkeletonList`. Navigation: `AppBottomNavigationBar`, `AppHeader`, `ScreenTitle`, `SettingsGroup`/`SettingsRow`. Brand/map: `JolayMark`, `JolayLogo`, `JolayIllustration`, `UserLocationDot`, `RoutePin`, `CarMarker`, `MapControlButton`. `LanguageSelector`, `themeModeProvider`.
All interactive components support disabled/pressed/focused (2 px ring); buttons support loading; cards/ride types support selected. Legacy `JolayButton/JolayCard/ErrorView` are thin aliases.

## Navigation rules
Customer: Home · Activity · Wallet · Profile. Driver: Home · Earnings · History · Profile. Home is map-first: bottom panel = search, three actions (**Поехать / Заказать / Отправить**), saved/recent chips. Detail screens use `AppHeader` with back. One nav pattern, no duplicates.

## Screen principles
Map stays visible; one primary action per screen, biggest control = the next step; every list has loading (skeleton), empty, error (retry) states; money is formatted from backend strings only (KZT), never computed.

## Localization
kk/ru/en in `strings.dart` (`tr`/`ref.t`); `kk`/`ru`/`en` key parity is tested. No hard-coded UI copy in widgets. Dates Asia/Almaty, currency `formatKzt`.

## Accessibility
Status = icon + text, never colour alone (`StatusBadge`, location shapes: circle pickup / square destination). ≥48 dp targets, semantic labels/live regions, visible focus, reduced motion respected, contrast per above.

## Implementation conventions
Screens read colours from `context.palette`; cards sit on `Material` (so ink and ListTiles work); a `Stack` with only `Positioned.fill` + small child needs `StackFit.expand`; buttons must not expand vertically in loose constraints (tested).
