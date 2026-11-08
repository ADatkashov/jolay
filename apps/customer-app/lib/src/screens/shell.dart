import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'map_widgets.dart';
import 'notifications_screen.dart';

/// Selected bottom-navigation tab. A provider so any screen (e.g. the avatar on Home) can switch tabs.
class ShellTab extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

class Shell extends ConsumerWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = ref.watch(shellTabProvider);
    final pages = [
      const HomeTab(),
      const ActivityTab(),
      const WalletTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      // Home draws edge-to-edge under the status bar (the map); the other tabs add their own safe area.
      body: IndexedStack(
        index: i,
        children: [
          for (var n = 0; n < pages.length; n++)
            n == 0 ? pages[n] : SafeArea(bottom: false, child: pages[n]),
        ],
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        selectedIndex: i,
        onSelected: (n) => ref.read(shellTabProvider.notifier).select(n),
        items: [
          AppNavItem(
            key: const Key('nav-home'),
            icon: AppIcons.homeOutlined,
            selectedIcon: AppIcons.home,
            label: ref.t('nav.home'),
          ),
          AppNavItem(
            key: const Key('nav-activity'),
            icon: AppIcons.activityOutlined,
            selectedIcon: AppIcons.activity,
            label: ref.t('nav.activity'),
          ),
          AppNavItem(
            key: const Key('nav-wallet'),
            icon: AppIcons.walletOutlined,
            selectedIcon: AppIcons.wallet,
            label: ref.t('nav.wallet'),
          ),
          AppNavItem(
            key: const Key('nav-profile'),
            icon: AppIcons.profileOutlined,
            selectedIcon: AppIcons.profile,
            label: ref.t('nav.profile'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Home ----------------
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});
  @override
  ConsumerState<HomeTab> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeTab> {
  LocationState? _loc;
  Place? _here;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await LocationService.status();
    if (!mounted) return;
    setState(() => _loc = s);
    if (s == LocationState.granted) _fetch();
  }

  Future<void> _fetch() async {
    final p = await LocationService.current();
    if (!mounted || p == null) return;
    setState(() => _here = p);
    try {
      _map.move(LatLng(p.lat, p.lng), 15);
    } catch (_) {
      /* map not laid out yet */
    }
    ref
        .read(draftProvider.notifier)
        .setPickup(
          Place(
            tr(ref.read(localeProvider), 'home.currentLocation'),
            '',
            p.lat,
            p.lng,
          ),
        );
  }

  Future<void> _allow() async {
    final s = await LocationService.request();
    if (!mounted) return;
    setState(() => _loc = s);
    if (s == LocationState.granted) {
      _fetch();
    } else if (s == LocationState.deniedForever) {
      await Geolocator.openAppSettings();
    } else if (s == LocationState.serviceOff) {
      await Geolocator.openLocationSettings();
    }
  }

  void _go(Place dest) {
    ref.read(draftProvider.notifier).setDropoff(dest);
    context.push('/ride/options');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final active = ref.watch(activeRideProvider);
    final saved = ref.watch(savedAddressesProvider);
    final recent = ref.watch(recentDestinationsProvider);
    final unread = unreadCount(ref.watch(notificationsProvider).value);
    ref.listen(realtimeEventsProvider, (_, _) {
      ref.invalidate(activeRideProvider);
      ref.invalidate(notificationsProvider);
    });
    final center = _here != null
        ? LatLng(_here!.lat, _here!.lng)
        : LatLng(almatyCenter.lat, almatyCenter.lng);
    final p = context.palette;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: JolayMap(
                  center: center,
                  zoom: 14,
                  controller: _map,
                  markers: [if (_here != null) userMarker(center)],
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Tooltip(
                            message: ref.t('home.openProfile'),
                            child: Semantics(
                              button: true,
                              label: ref.t('home.openProfile'),
                              excludeSemantics: true,
                              onTap: () =>
                                  ref.read(shellTabProvider.notifier).select(3),
                              child: InkResponse(
                                key: const Key('home-avatar'),
                                onTap: () => ref
                                    .read(shellTabProvider.notifier)
                                    .select(3),
                                radius: 30,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: p.surface,
                                    shape: BoxShape.circle,
                                    boxShadow: AppElevation.floating,
                                  ),
                                  child: Avatar(
                                    name: user?.fullName ?? '',
                                    size: 42,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AppIconButton(
                                key: const Key('home-bell'),
                                icon: Icons.notifications_none_rounded,
                                tooltip: ref.t('home.notifications'),
                                style: AppIconButtonStyle.floating,
                                onPressed: () => context.push('/notifications'),
                              ),
                              if (unread > 0)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: p.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.midnight,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_loc != null && _loc != LocationState.granted)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _LocationCard(
                            state: _loc!,
                            onAllow: _allow,
                            onManual: () => context.push('/ride/destination'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: MapControlButton(
                  key: const Key('map-recenter'),
                  icon: AppIcons.myLocation,
                  tooltip: ref.t('map.recenter'),
                  onPressed: () =>
                      _here != null ? _map.move(center, 15) : _allow(),
                ),
              ),
            ],
          ),
        ),
        MapPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active.value != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    key: const Key('active-ride-banner'),
                    variant: AppCardVariant.inverse,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: () => context.push('/ride/${active.value!.id}'),
                    semanticLabel:
                        '${ref.t('home.activeRide')}: ${active.value!.dropoffAddress}',
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: AppColors.yellow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            AppIcons.ride,
                            size: 20,
                            color: AppColors.midnight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ref.t('home.activeRide'),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              Text(
                                active.value!.dropoffAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const Icon(AppIcons.chevron, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              SearchField(
                key: const Key('where-to'),
                readOnly: true,
                hint: ref.t('home.where'),
                onTap: () => context.push('/ride/destination'),
                trailing: _here != null
                    ? Icon(AppIcons.myLocation, size: 18, color: p.success)
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ServiceTile(
                      key: const Key('tile-ride'),
                      icon: AppIcons.ride,
                      label: ref.t('service.ride'),
                      sub: ref.t('service.rideSub'),
                      primary: true,
                      onTap: () => context.push('/ride/destination'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ServiceTile(
                      key: const Key('tile-order'),
                      icon: AppIcons.order,
                      label: ref.t('service.order'),
                      sub: ref.t('service.orderSub'),
                      onTap: () => context.push('/shops'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ServiceTile(
                      key: const Key('tile-send'),
                      icon: AppIcons.send,
                      label: ref.t('service.send'),
                      sub: ref.t('service.sendSub'),
                      onTap: () => context.push('/express/new'),
                    ),
                  ),
                ],
              ),
              _Shortcuts(
                saved: saved,
                recent: recent,
                onPick: _go,
                onRetry: () {
                  ref.invalidate(recentDestinationsProvider);
                  ref.invalidate(savedAddressesProvider);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Saved + recent places as one scrollable chip row. Hidden when there is nothing to show.
class _Shortcuts extends ConsumerWidget {
  final AsyncValue<List<Place>> saved, recent;
  final void Function(Place) onPick;
  final VoidCallback onRetry;
  const _Shortcuts({
    required this.saved,
    required this.recent,
    required this.onPick,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    if (saved.isLoading && recent.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SkeletonLoader(width: 110, height: 40, radius: 20),
            SizedBox(width: 8),
            SkeletonLoader(width: 140, height: 40, radius: 20),
          ],
        ),
      );
    }
    if (saved.hasError && recent.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(AppIcons.offline, size: 18, color: p.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ref.t('common.offline'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            AppTextButton(
              label: ref.t('btn.retry'),
              onPressed: onRetry,
              size: AppButtonSize.small,
            ),
          ],
        ),
      );
    }
    final items = <(Place, IconData, bool)>[
      for (final s in saved.value ?? const <Place>[])
        (s, AppIcons.bookmark, true),
      for (final r in (recent.value ?? const <Place>[]).take(6))
        (r, AppIcons.history, false),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final (place, icon, isSaved) = items[i];
            final label = isSaved ? place.name : place.address;
            return Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              onTap: () => onPick(place),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => onPick(place),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSaved ? p.textPrimary : p.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: p.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  final LocationState state;
  final VoidCallback onAllow, onManual;
  const _LocationCard({
    required this.state,
    required this.onAllow,
    required this.onManual,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadius.cardR,
        boxShadow: AppElevation.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.selected,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.locationOff,
                  size: 20,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(ref.t('loc.title'), style: t.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state == LocationState.denied
                ? ref.t('loc.body')
                : ref.t('loc.denied'),
            style: t.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: ref.t('loc.allow'),
                  size: AppButtonSize.medium,
                  onPressed: onAllow,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: ref.t('loc.manual'),
                  size: AppButtonSize.medium,
                  variant: AppButtonVariant.outlined,
                  onPressed: onManual,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the three primary actions. The first (Ride) is the filled yellow one; the others are outlined.
class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final bool primary;
  final VoidCallback onTap;
  const _ServiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.sub,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final fg = primary ? p.onAccent : p.textPrimary;
    return Semantics(
      button: true,
      label: '$label, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: primary ? p.accent : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardR,
          side: BorderSide(color: primary ? Colors.transparent : p.border),
        ),
        child: InkWell(
          borderRadius: AppRadius.cardR,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primary ? AppColors.midnight : p.divider,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: primary ? AppColors.yellow : p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(
                          color: primary
                              ? AppColors.midnight.withValues(alpha: .7)
                              : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Activity ----------------
class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key});
  static const tabs = ['completed', 'ongoing', 'cancelled'];

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        ScreenTitle(ref.t('nav.activity')),
        TabBar(
          tabs: [
            Tab(text: ref.t('activity.completed')),
            Tab(text: ref.t('activity.ongoing')),
            Tab(text: ref.t('activity.cancelled')),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [for (final t in tabs) _RideList(tab: t)],
          ),
        ),
      ],
    ),
  );
}

class _RideList extends ConsumerWidget {
  final String tab;
  const _RideList({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(historyProvider(tab));
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return data.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonList(count: 4),
      ),
      error: (e, _) => ErrorState(
        message: ref.t('common.offline'),
        retryLabel: ref.t('btn.retry'),
        onRetry: () => ref.invalidate(historyProvider(tab)),
      ),
      data: (rides) => rides.isEmpty
          ? EmptyState(
              title: ref.t('activity.empty'),
              message: ref.t('activity.emptyBody'),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(historyProvider(tab)),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: rides.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final r = rides[i];
                  return AppCard(
                    onTap: () => context.push('/ride/${r.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatDateTime(r.createdAt),
                                style: t.bodySmall,
                              ),
                            ),
                            if (tab == 'cancelled')
                              StatusBadge(
                                label: ref.t('ride.cancelled'),
                                tone: StatusTone.error,
                              )
                            else if (tab == 'ongoing')
                              StatusBadge(
                                label: ref.t('ride.inProgress'),
                                tone: StatusTone.info,
                              ),
                            if (tab != 'cancelled' && tab != 'ongoing')
                              PriceLabel(
                                amount: r.fare,
                                size: PriceSize.medium,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RouteLines(
                          from: r.pickupAddress,
                          to: r.dropoffAddress,
                        ),
                        if (r.driver != null) ...[
                          const SizedBox(height: 12),
                          Divider(color: p.divider),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Avatar(name: r.driver!.name, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${r.driver!.name} · ${r.driver!.vehicle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall,
                                ),
                              ),
                              if (tab == 'completed' && r.rating != null)
                                RatingView(value: r.rating, size: 12),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Pickup → destination with a connector line (circle = pickup, square = destination).
class _RouteLines extends StatelessWidget {
  final String from, to;
  const _RouteLines({required this.from, required this.to});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.success,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  color: p.border,
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.error,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  from,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  to,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Wallet ----------------
class WalletTab extends ConsumerStatefulWidget {
  const WalletTab({super.key});
  @override
  ConsumerState<WalletTab> createState() => _WalletState();
}

class _WalletState extends ConsumerState<WalletTab> {
  Future<void> _topUp() async {
    final ctrl = TextEditingController(text: '5000');
    final amount = await showAppBottomSheet<int>(
      context,
      title: ref.t('wallet.topup'),
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              label: ref.t('wallet.amount'),
              onChanged: (_) => setS(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in const [2000, 5000, 10000, 20000])
                  ChoiceChip(
                    label: Text(formatKzt(a)),
                    selected: ctrl.text == '$a',
                    onSelected: (_) => setS(() => ctrl.text = '$a'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: ref.t('btn.continue'),
              onPressed: int.tryParse(ctrl.text) == null
                  ? null
                  : () => Navigator.pop(c, int.tryParse(ctrl.text)),
            ),
          ],
        ),
      ),
    );
    if (amount == null || !mounted) return;
    try {
      final p =
          await ref
                  .read(apiProvider)
                  .post(
                    '/wallet/top-ups',
                    body: {'amount': amount},
                    headers: {
                      'Idempotency-Key': DateTime.now().microsecondsSinceEpoch
                          .toString(),
                    },
                  )
              as Map<String, dynamic>;
      final url = p['checkoutUrl'] as String?;
      if (!mounted || url == null) return;
      if (url.contains('sandbox-checkout')) {
        // Sandbox gateway only: simulates the hosted checkout page. The balance changes ONLY after the backend verifies the gateway callback.
        final ok = await showAppModal<bool>(
          context,
          title: 'Sandbox checkout',
          body: Text(
            '${formatKzt(p['amount'])} — development gateway, no real money moves.',
          ),
          actions: [
            Builder(
              builder: (c) => PrimaryButton(
                label: ref.t('ride.pay'),
                onPressed: () => Navigator.pop(c, true),
              ),
            ),
            Builder(
              builder: (c) => AppOutlinedButton(
                label: ref.t('btn.cancel'),
                onPressed: () => Navigator.pop(c, false),
              ),
            ),
          ],
        );
        if (ok == true) {
          await ref
              .read(apiProvider)
              .post('/payments/${p['id']}/sandbox-checkout');
        }
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      ref.invalidate(walletProvider);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(walletProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    ref.listen(realtimeEventsProvider, (_, ev) {
      if (ev.value?.type == 'PAYMENT_STATUS_UPDATED') {
        ref.invalidate(walletProvider);
      }
    });
    return w.when(
      loading: () => Column(
        children: [
          ScreenTitle(ref.t('nav.wallet')),
          const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonLoader(height: 150, radius: 18),
          ),
        ],
      ),
      error: (e, _) => ErrorState(
        message: ref.t('common.offline'),
        retryLabel: ref.t('btn.retry'),
        onRetry: () => ref.invalidate(walletProvider),
      ),
      data: (d) {
        final tx = (d['transactions'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(walletProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ScreenTitle(ref.t('nav.wallet')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AppCard(
                  variant: AppCardVariant.inverse,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref.t('wallet.balance'),
                        style: t.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      PriceLabel(
                        amount: d['balance'],
                        size: PriceSize.hero,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: ref.t('wallet.topup'),
                        icon: AppIcons.add,
                        expand: false,
                        size: AppButtonSize.medium,
                        onPressed: _topUp,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                child: Text(ref.t('wallet.history'), style: t.titleMedium),
              ),
              if (tx.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: AppIcons.wallet,
                    title: ref.t('wallet.empty'),
                  ),
                ),
              for (final x in tx)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Builder(
                    builder: (_) {
                      final out = x['amount'].toString().startsWith('-');
                      return AddressCard(
                        title: (x['description'] ?? x['type']).toString(),
                        subtitle: formatDateTime(x['created_at']?.toString()),
                        icon: out
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                        trailing: Text(
                          formatKzt(x['amount']),
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: out ? p.textPrimary : p.success,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------- Profile ----------------
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    final mode = ref.watch(themeModeProvider);
    final t = Theme.of(context).textTheme;
    final modeLabel = switch (mode) {
      ThemeMode.light => ref.t('theme.light'),
      ThemeMode.dark => ref.t('theme.dark'),
      _ => ref.t('theme.system'),
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ScreenTitle(ref.t('nav.profile')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Avatar(name: u?.fullName ?? '', size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u?.fullName ?? '',
                        style: t.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        u?.phone ?? '',
                        style: t.bodyMedium?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                      if (u?.email != null && u!.email!.isNotEmpty)
                        Text(
                          u.email!,
                          style: t.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                AppIconButton(
                  key: const Key('profile-edit'),
                  icon: AppIcons.edit,
                  tooltip: ref.t('profile.edit'),
                  onPressed: () => _edit(context, ref),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SettingsGroup(
            title: ref.t('profile.account'),
            children: [
              SettingsRow(
                key: const Key('profile-invite'),
                icon: AppIcons.gift,
                title: ref.t('profile.invite'),
                onTap: () => context.push('/invite'),
              ),
              SettingsRow(
                key: const Key('profile-contacts'),
                icon: AppIcons.shield,
                title: ref.t('profile.contacts'),
                onTap: () => context.push('/contacts'),
              ),
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: ref.t('notif.title'),
                onTap: () => context.push('/notifications'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SettingsGroup(
            title: ref.t('profile.settings'),
            children: [
              SettingsRow(
                icon: AppIcons.language,
                title: ref.t('profile.language'),
                trailing: const LanguageSelector(),
              ),
              SettingsRow(
                key: const Key('profile-appearance'),
                icon: Icons.contrast_rounded,
                title: ref.t('profile.appearance'),
                subtitle: modeLabel,
                onTap: () => _appearance(context, ref, mode),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SettingsGroup(
            title: ref.t('profile.help'),
            children: [
              SettingsRow(
                icon: AppIcons.support,
                title: ref.t('profile.support'),
                onTap: () => context.push('/support'),
              ),
              SettingsRow(
                icon: AppIcons.document,
                title: ref.t('legal.terms'),
                onTap: () => context.push('/legal/TERMS'),
              ),
              SettingsRow(
                icon: AppIcons.privacy,
                title: ref.t('legal.privacy'),
                onTap: () => context.push('/legal/PRIVACY'),
              ),
              SettingsRow(
                icon: AppIcons.info,
                title: ref.t('legal.about'),
                onTap: () => context.push('/legal/ABOUT'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              AppOutlinedButton(
                key: const Key('logout'),
                label: ref.t('btn.logout'),
                icon: AppIcons.logout,
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
              const SizedBox(height: 4),
              AppTextButton(
                label: ref.t('profile.delete'),
                destructive: true,
                expand: true,
                onPressed: () async {
                  final ok = await showConfirmationDialog(
                    context,
                    title: ref.t('profile.delete'),
                    message: ref.t('profile.deleteConfirm'),
                    confirmLabel: ref.t('btn.delete'),
                    cancelLabel: ref.t('btn.cancel'),
                    destructive: true,
                  );
                  if (ok) {
                    try {
                      await ref.read(authProvider.notifier).deleteAccount();
                    } catch (e) {
                      if (context.mounted) showError(context, ref, e);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _appearance(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    await showAppBottomSheet<void>(
      context,
      title: ref.t('profile.appearance'),
      builder: (c) => RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (v) {
          if (v != null) {
            ref.read(themeModeProvider.notifier).set(v);
            Navigator.pop(c);
          }
        },
        child: Column(
          children: [
            for (final m in const [
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              RadioListTile<ThemeMode>(
                key: Key('theme-${m.name}'),
                value: m,
                contentPadding: EdgeInsets.zero,
                activeColor: c.palette.isDark
                    ? AppColors.yellow
                    : AppColors.midnight,
                title: Text(switch (m) {
                  ThemeMode.light => ref.t('theme.light'),
                  ThemeMode.dark => ref.t('theme.dark'),
                  _ => ref.t('theme.system'),
                }),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final u = ref.read(authProvider).user!;
    final name = TextEditingController(text: u.fullName),
        email = TextEditingController(text: u.email ?? '');
    final key = GlobalKey<FormState>();
    final ok = await showAppBottomSheet<bool>(
      context,
      title: ref.t('profile.edit'),
      builder: (c) => Form(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: name,
              label: ref.t('auth.fullName'),
              prefixIcon: AppIcons.person,
              textCapitalization: TextCapitalization.words,
              validator: v(ref, Validators.name),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: email,
              label: ref.t('auth.email'),
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: v(ref, Validators.email),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: ref.t('btn.save'),
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(c, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await ref
            .read(authProvider.notifier)
            .updateProfile(
              fullName: name.text.trim(),
              email: email.text.trim(),
            );
      } catch (e) {
        if (context.mounted) showError(context, ref, e);
      }
    }
  }
}
