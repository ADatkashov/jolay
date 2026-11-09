import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';

import 'auth.dart';
import 'data.dart';
import 'offer_cards.dart';
import 'registration.dart';
import 'tabs.dart';
import 'trip_cards.dart';

// The screens used to live in this one file; they are re-exported so imports of `home.dart` keep working.
export 'offer_cards.dart';
export 'registration.dart';
export 'tabs.dart';
export 'trip_cards.dart';

/// Map tiles are 2GIS, fetched through the JOLAY backend (the 2GIS key stays on the server).
const tileUrl = String.fromEnvironment(
  'TILE_URL',
  defaultValue: '${ApiConfig.baseUrl}/api/v1/geo/tiles/{z}/{x}/{y}.png',
);

/// Dark-mode tile wrapper shared with the customer app's look (see [JolayMapStyle.darkTiles]).
Widget _darkTiles(BuildContext context, Widget tile, TileImage image) =>
    ColorFiltered(colorFilter: JolayMapStyle.darkTiles, child: tile);

/// Decides what the driver sees based on server-side state: no profile -> vehicle registration,
/// PENDING/REJECTED/SUSPENDED -> status screen, APPROVED -> working app.
class DriverGate extends ConsumerWidget {
  const DriverGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(driverMeProvider);
    ref.listen(eventsProvider, (_, ev) {
      if (ev.value?.type == 'VERIFICATION_STATUS') {
        ref.invalidate(driverMeProvider);
      }
    });
    return me.when(
      loading: () => const Scaffold(body: LoadingState()),
      error: (e, _) => Scaffold(
        body: ErrorState(
          message: ref.t('common.offline'),
          retryLabel: ref.t('btn.retry'),
          onRetry: () => ref.invalidate(driverMeProvider),
        ),
      ),
      data: (d) {
        if (d == null) return const VehicleRegistration();
        if (d['verification'] != 'APPROVED') return VerificationStatus(me: d);
        return const DriverShell();
      },
    );
  }
}

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});
  @override
  ConsumerState<DriverShell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<DriverShell> {
  int _i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _i,
      children: const [
        DriverHome(),
        EarningsTab(),
        OrdersTab(),
        DriverProfile(),
      ],
    ),
    bottomNavigationBar: AppBottomNavigationBar(
      selectedIndex: _i,
      onSelected: (i) => setState(() => _i = i),
      items: [
        AppNavItem(
          key: const Key('nav-home'),
          icon: AppIcons.mapOutlined,
          selectedIcon: AppIcons.map,
          label: ref.t('nav.home'),
        ),
        AppNavItem(
          key: const Key('nav-earnings'),
          icon: AppIcons.earningsOutlined,
          selectedIcon: AppIcons.earnings,
          label: ref.t('nav.earnings'),
        ),
        AppNavItem(
          key: const Key('nav-history'),
          icon: AppIcons.activityOutlined,
          selectedIcon: AppIcons.activity,
          label: ref.t('nav.history'),
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

// ---------------- Home: online toggle, offers, active trip ----------------
class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});
  @override
  ConsumerState<DriverHome> createState() => _HomeState();
}

class _HomeState extends ConsumerState<DriverHome> {
  bool _online = false, _busy = false, _locDenied = false;
  Map<String, dynamic>? _offer, _ride, _dOffer, _delivery;
  Timer? _poll, _tick;
  int _left = 0;
  LatLng? _pos;
  final _map = MapController();

  // In-app navigation: the road route of the current leg, the rider's dot while they wait, and a camera that follows the driver.
  NavigationFeed? _navFeed;
  String? _navRideId, _navStatus;
  RideNavigation? _nav;
  LatLng? _customerPos;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    final me = ref.read(driverMeProvider).value;
    final a = me?['availability'];
    _online = a == 'ONLINE' || a == 'OFFERED' || a == 'BUSY';
    if (_online) _startWork(resume: true);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if ((_offer != null || _dOffer != null) && mounted) {
        setState(() => _left = _left > 0 ? _left - 1 : 0);
        if (_left == 0) _refresh();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _navFeed?.dispose();
    super.dispose();
  }

  /// Starts/stops the route feed with the active ride and refreshes it when a new leg begins (to the pickup, then to the destination).
  void _syncNav() {
    final id = _ride?['id']?.toString();
    final status = _ride?['status']?.toString();
    if (id != _navRideId) {
      _navFeed?.dispose();
      _navFeed = null;
      _nav = null;
      _customerPos = null;
      _navRideId = id;
      _navStatus = status;
      _follow = true;
      if (id != null) {
        _navFeed = NavigationFeed(ref.read(apiProvider), id, (n) {
          if (mounted) setState(() => _nav = n);
        })..start();
      }
    } else if (status != _navStatus) {
      _navStatus = status;
      _navFeed?.refresh();
    }
  }

  /// While a trip is active the camera stays on the driver until they pan the map themselves.
  void _followDriver() {
    final pos = _pos;
    if (!_follow || _ride == null || pos == null) return;
    try {
      _map.move(pos, _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
    } catch (_) {
      // the map is not attached yet
    }
  }

  Future<void> _refresh() async {
    if (!_online && _ride == null && _delivery == null) return;
    try {
      final api = ref.read(apiProvider);
      final ride = await api.get('/drivers/rides/active');
      Map<String, dynamic>? offer, dOffer, delivery;
      final noRide = ride == null || (ride is String && ride.isEmpty);
      if (noRide) {
        final dl = await api.get('/drivers/deliveries/active');
        delivery = dl is Map<String, dynamic> ? dl : null;
        if (delivery == null) {
          final o = await api.get('/drivers/offers');
          offer = o is Map<String, dynamic> ? o : null;
          final dof = await api.get('/drivers/delivery-offers');
          dOffer = dof is Map<String, dynamic> ? dof : null;
        }
      }
      final pos = ref.read(locationPublisherProvider).last;
      if (!mounted) return;
      setState(() {
        _ride = ride is Map<String, dynamic> ? ride : null;
        _offer = offer;
        _dOffer = dOffer;
        _delivery = delivery;
        final live = offer ?? dOffer;
        if (live != null) _left = (live['seconds_left'] as num).toInt();
        if (pos != null) _pos = LatLng(pos.latitude, pos.longitude);
      });
      _syncNav();
      _followDriver();
    } catch (_) {}
  }

  Future<void> _startWork({bool resume = false}) async {
    final pub = ref.read(locationPublisherProvider);
    if (!await pub.ensurePermission()) {
      if (!mounted) return;
      setState(() {
        _locDenied = true;
        if (!resume) _online = false;
      });
      if (!resume) {
        showAppToast(context, ref.t('loc.denied'), type: AppToastType.error);
      }
      return;
    }
    if (mounted) setState(() => _locDenied = false);
    await pub.start();
  }

  /// Going online is one tap; going offline asks first so a bump in a moving car cannot drop the driver off the line.
  Future<void> _requestToggle(bool on) async {
    if (!on && _online) {
      final ok = await showConfirmationDialog(
        context,
        title: ref.t('driver.offlineConfirmTitle'),
        message: ref.t('driver.offlineConfirmBody'),
        confirmLabel: ref.t('driver.goOffline'),
        cancelLabel: ref.t('driver.stayOnline'),
      );
      if (!ok || !mounted) return;
    }
    await _toggle(on);
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on && !await ref.read(locationPublisherProvider).ensurePermission()) {
        if (mounted) {
          setState(() => _locDenied = true);
          showAppToast(context, ref.t('loc.denied'), type: AppToastType.error);
        }
        return;
      }
      await ref
          .read(apiProvider)
          .put('/drivers/availability', body: {'online': on});
      if (on) {
        await _startWork();
      } else {
        await ref.read(locationPublisherProvider).stop();
      }
      if (mounted) {
        setState(() {
          _online = on;
          if (!on) _offer = null;
        });
      }
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String path) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post(path);
      await _refresh();
      ref.invalidate(driverMeProvider);
      ref.invalidate(earningsProvider('today'));
    } catch (e) {
      if (mounted) toast(context, ref, e);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LatLng _ll(Map<String, dynamic> m) =>
      LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    ref.listen(eventsProvider, (_, ev) {
      final e = ev.value;
      if (e == null) return;
      if (e.type == 'CUSTOMER_LOCATION_UPDATED') {
        // the rider's position is a hint for the map only; nothing to re-fetch
        if (e.data['rideId'] == _ride?['id'] && mounted) {
          setState(
            () => _customerPos = LatLng(
              (e.data['lat'] as num).toDouble(),
              (e.data['lng'] as num).toDouble(),
            ),
          );
        }
        return;
      }
      _refresh();
    });
    final me = ref.watch(driverMeProvider).value;
    final today = ref.watch(earningsProvider('today')).value;
    final center = _pos ?? const LatLng(43.2389, 76.8897);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final hasOffer = _offer != null && _ride == null;
    final hasDOffer = _dOffer != null && _ride == null && _delivery == null;
    final busyWithJob = _ride != null || _delivery != null;
    final idle = !hasOffer && !hasDOffer && !busyWithJob;
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
              onPositionChanged: (_, byGesture) {
                if (byGesture && _follow && _ride != null) {
                  setState(() => _follow = false);
                }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'kz.jolay.driver',
                tileBuilder: p.isDark ? _darkTiles : null,
              ),
              if (_ride != null && _nav != null && _nav!.points.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        for (final (lat, lng) in _nav!.points) LatLng(lat, lng),
                      ],
                      strokeWidth: JolayMapStyle.routeCasingWidth,
                      color: JolayMapStyle.routeCasing(p.isDark),
                    ),
                    Polyline(
                      points: [
                        for (final (lat, lng) in _nav!.points) LatLng(lat, lng),
                      ],
                      strokeWidth: JolayMapStyle.routeCoreWidth,
                      color: JolayMapStyle.routeCore,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_pos != null)
                    Marker(
                      point: _pos!,
                      width: 56,
                      height: 56,
                      child: const UserLocationDot(),
                    ),
                  if (_ride != null &&
                      _customerPos != null &&
                      _ride!['status'] != 'IN_PROGRESS')
                    Marker(
                      point: _customerPos!,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: ref.t('nav.clientHere'),
                        child: Icon(
                          Icons.person_pin_circle_rounded,
                          size: 44,
                          color: p.isDark
                              ? AppColors.white
                              : AppColors.midnight,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  if (_ride != null)
                    Marker(
                      point: _ll(_ride!['pickup'] as Map<String, dynamic>),
                      width: 40,
                      height: 40,
                      child: const RoutePin(),
                    ),
                  if (_ride != null)
                    Marker(
                      point: _ll(_ride!['dropoff'] as Map<String, dynamic>),
                      width: 40,
                      height: 40,
                      child: const RoutePin(dropoff: true),
                    ),
                ],
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('© 2GIS')],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                // Status bar: the one control a driver needs at all times. Big, unambiguous, and going offline is confirmed.
                AnimatedContainer(
                  duration: context.motion(AppDurations.base),
                  padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: AppRadius.cardR,
                    border: Border.all(
                      color: _online
                          ? p.success.withValues(alpha: .55)
                          : p.border,
                    ),
                    boxShadow: AppElevation.floating,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: StatusIndicator(
                            active: _online,
                            label: _online
                                ? ref.t('driver.statusOnline')
                                : ref.t('driver.statusOffline'),
                            caption: _online
                                ? ref.t('driver.onlineHint')
                                : ref.t('driver.offlineHint'),
                          ),
                        ),
                      ),
                      JolayToggle(
                        key: const Key('online-switch'),
                        value: _online,
                        semanticLabel: _online
                            ? ref.t('driver.goOffline')
                            : ref.t('driver.goOnline'),
                        onChanged: (_busy || busyWithJob)
                            ? null
                            : _requestToggle,
                      ),
                    ],
                  ),
                ),
                if (_locDenied && _online)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.warningSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: p.warning.withValues(alpha: .35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            AppIcons.locationOff,
                            size: 20,
                            color: p.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                ref.t('loc.denied'),
                                style: t.bodySmall?.copyWith(
                                  color: p.isDark
                                      ? p.textPrimary
                                      : const Color(0xFF5C3A00),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!busyWithJob && !hasOffer && !hasDOffer && !_locDenied)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            icon: AppIcons.earnings,
                            label: ref.t('driver.today'),
                            value: formatKzt(
                              today?['net'] ?? me?['todayEarnings'],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniStat(
                            icon: AppIcons.ride,
                            label: ref.t('driver.trips'),
                            value: '${today?['trips'] ?? '—'}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniStat(
                            icon: AppIcons.star,
                            label: ref.t('driver.rating'),
                            value:
                                double.tryParse('${me?['rating_avg']}')
                                    ?.toStringAsFixed(1) ??
                                '—',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasOffer)
                RideOfferCard(
                  offer: _offer!,
                  left: _left,
                  busy: _busy,
                  onAccept: () =>
                      _act('/drivers/offers/${_offer!['offer_id']}/accept'),
                  onDecline: () =>
                      _act('/drivers/offers/${_offer!['offer_id']}/decline'),
                ),
              if (_ride != null && !_follow)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AppIconButton(
                      key: const Key('follow-driver'),
                      icon: AppIcons.navigate,
                      tooltip: ref.t('nav.follow'),
                      style: AppIconButtonStyle.floating,
                      onPressed: () {
                        setState(() => _follow = true);
                        _followDriver();
                      },
                    ),
                  ),
                ),
              if (_ride != null && _nav != null && _nav!.points.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: NavSummary(
                    nav: _nav!,
                    onTap: () => showNavStepsSheet(context, ref, _nav!),
                  ),
                ),
              if (_ride != null)
                ActiveTripCard(ride: _ride!, busy: _busy, onAct: _act),
              if (hasDOffer)
                DeliveryOfferCard(
                  offer: _dOffer!,
                  left: _left,
                  busy: _busy,
                  onAccept: () => _act(
                    '/drivers/delivery-offers/${_dOffer!['offer_id']}/accept',
                  ),
                  onDecline: () => _act(
                    '/drivers/delivery-offers/${_dOffer!['offer_id']}/decline',
                  ),
                ),
              if (_delivery != null)
                ActiveDeliveryCard(
                  delivery: _delivery!,
                  busy: _busy,
                  onAct: _act,
                  onRefresh: _refresh,
                ),
              if (idle && !_online)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: PrimaryButton(
                    key: const Key('go-online'),
                    label: ref.t('driver.goOnline'),
                    icon: AppIcons.navigate,
                    loading: _busy,
                    onPressed: () => _toggle(true),
                  ),
                ),
              if (idle && _online)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _SearchingPill(label: ref.t('driver.onlineHint')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppElevation.floating,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: p.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: t.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Looking for requests…" pill with three travelling dots (static under reduced motion).
class _SearchingPill extends StatefulWidget {
  final String label;
  const _SearchingPill({required this.label});
  @override
  State<_SearchingPill> createState() => _SearchingPillState();
}

class _SearchingPillState extends State<_SearchingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: context.palette.elevated,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: context.palette.border),
      boxShadow: AppElevation.floating,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.yellow.withValues(
                        alpha: context.reduceMotion
                            ? .9
                            : .3 +
                                  .7 *
                                      ((_c.value * 3 - i).clamp(0, 1) *
                                          (1 -
                                              (_c.value * 3 - i - 1).clamp(
                                                0,
                                                1,
                                              ))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}
