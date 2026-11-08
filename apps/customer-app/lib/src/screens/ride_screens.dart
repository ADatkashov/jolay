import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'map_widgets.dart';

String _placeLabel(WidgetRef ref, Place? p) =>
    p == null ? '' : (p.name.isEmpty ? ref.t('home.currentLocation') : p.name);

// ---------------- Destination ----------------
class DestinationScreen extends ConsumerStatefulWidget {
  const DestinationScreen({super.key});
  @override
  ConsumerState<DestinationScreen> createState() => _DestinationState();
}

class _DestinationState extends ConsumerState<DestinationScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String s) {
    _debounce?.cancel();
    setState(() {});
    if (s.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      try {
        final d = ref.read(draftProvider).pickup ?? almatyCenter;
        final j =
            await ref
                    .read(apiProvider)
                    .get(
                      '/geo/places',
                      query: {'q': s.trim(), 'lat': d.lat, 'lng': d.lng},
                    )
                as List;
        if (mounted) {
          setState(
            () => _results = j
                .map((e) => Place.fromJson(e as Map<String, dynamic>))
                .toList(),
          );
        }
      } catch (e) {
        if (mounted) showError(context, ref, e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _choose(Place p) {
    ref.read(draftProvider.notifier).setDropoff(p);
    context.pushReplacement('/ride/options');
  }

  Future<void> _pickOnMap({required bool pickup}) async {
    final d = ref.read(draftProvider);
    final start = pickup
        ? (d.pickup ?? almatyCenter)
        : (d.dropoff ?? d.pickup ?? almatyCenter);
    final p = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          start: LatLng(start.lat, start.lng),
          title: pickup ? ref.t('home.pickup') : ref.t('ride.destination'),
        ),
      ),
    );
    if (p == null || !mounted) return;
    if (pickup) {
      ref.read(draftProvider.notifier).setPickup(p);
      setState(() {});
    } else {
      _choose(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    final saved = ref.watch(savedAddressesProvider).value ?? [];
    final recent = ref.watch(recentDestinationsProvider).value ?? [];
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final typing = _q.text.trim().length >= 2;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('ride.destination'),
        backLabel: ref.t('common.back'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: LocationField(
                    role: LocationRole.pickup,
                    label: ref.t('ride.from'),
                    value: _placeLabel(ref, draft.pickup),
                    placeholder: ref.t('home.pickup'),
                    onTap: () => _pickOnMap(pickup: true),
                    trailing: Icon(
                      AppIcons.map,
                      size: 20,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SearchField(
                  key: const Key('dest-search'),
                  controller: _q,
                  hint: ref.t('ride.search'),
                  onChanged: _onChanged,
                  autofocus: true,
                  loading: _loading,
                  onClear: _q.text.isEmpty
                      ? null
                      : () {
                          _q.clear();
                          _onChanged('');
                        },
                  trailing: IconButton(
                    tooltip: ref.t('ride.chooseOnMap'),
                    icon: const Icon(AppIcons.map),
                    onPressed: () => _pickOnMap(pickup: false),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                AddressCard(
                  key: const Key('choose-on-map'),
                  title: ref.t('ride.chooseOnMap'),
                  icon: AppIcons.pin,
                  onTap: () => _pickOnMap(pickup: false),
                  trailing: Icon(AppIcons.chevron, color: p.textSecondary),
                ),
                for (final r in _results)
                  AddressCard(
                    title: r.name,
                    subtitle: r.address,
                    onTap: () => _choose(r),
                  ),
                if (typing && !_loading && _results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: AppIcons.search,
                      title: ref.t('ride.noResults'),
                      message: ref.t('ride.searchHint'),
                    ),
                  ),
                if (!typing) ...[
                  if (saved.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 4),
                      child: Text(
                        ref.t('home.saved'),
                        style: t.labelMedium?.copyWith(color: p.textSecondary),
                      ),
                    ),
                    for (final s in saved)
                      AddressCard(
                        title: s.name,
                        subtitle: s.address,
                        icon: AppIcons.bookmark,
                        onTap: () => _choose(s),
                      ),
                  ],
                  if (recent.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 4),
                      child: Text(
                        ref.t('home.recent'),
                        style: t.labelMedium?.copyWith(color: p.textSecondary),
                      ),
                    ),
                    for (final r in recent)
                      AddressCard(
                        title: r.address,
                        icon: AppIcons.history,
                        onTap: () => _choose(r),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Options ----------------
class RideOptionsScreen extends ConsumerStatefulWidget {
  const RideOptionsScreen({super.key});
  @override
  ConsumerState<RideOptionsScreen> createState() => _OptionsState();
}

class _OptionsState extends ConsumerState<RideOptionsScreen> {
  Estimate? _est;
  String? _error;
  String _category = 'ECONOMY';
  String _payment = 'CASH';
  bool _busy = false;
  final _promoCtl = TextEditingController();
  String? _promo, _promoError; // the code the backend accepted, and the last rejection (localized key)
  late final String _idemKey = 'ride-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _promoCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _est = null;
    });
    final d = ref.read(draftProvider);
    final pickup = d.pickup ?? almatyCenter, drop = d.dropoff;
    if (drop == null) {
      setState(() => _error = 'common.error');
      return;
    }
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/rides/estimate',
                    headers: {
                      'Accept-Language': ref.read(localeProvider).languageCode,
                    },
                    body: {
                      'pickup': {'lat': pickup.lat, 'lng': pickup.lng},
                      'dropoff': {'lat': drop.lat, 'lng': drop.lng},
                      if (_promo != null) 'promoCode': _promo,
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) setState(() => _est = Estimate.fromJson(j));
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is ApiException
            ? (e.isNetwork ? 'err.network' : 'err.${e.code}')
            : 'common.error',
      );
    }
  }

  /// Tries the typed promo code against the backend (the estimate endpoint validates it); a rejected code is shown inline and not kept.
  Future<void> _applyPromo() async {
    final code = _promoCtl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _promo = null;
        _promoError = null;
      });
      await _load();
      return;
    }
    final d = ref.read(draftProvider);
    final pickup = d.pickup ?? almatyCenter, drop = d.dropoff;
    if (drop == null) return;
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/rides/estimate',
                    headers: {
                      'Accept-Language': ref.read(localeProvider).languageCode,
                    },
                    body: {
                      'pickup': {'lat': pickup.lat, 'lng': pickup.lng},
                      'dropoff': {'lat': drop.lat, 'lng': drop.lng},
                      'promoCode': code,
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _promo = code;
          _promoError = null;
          _est = Estimate.fromJson(j);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _promo = null;
        _promoError = e is ApiException && e.code.startsWith('promo_')
            ? 'err.${e.code}'
            : (e is ApiException && e.isNetwork
                  ? 'err.network'
                  : 'common.error');
      });
    }
  }

  Future<void> _confirm() async {
    final d = ref.read(draftProvider);
    final pickup = d.pickup ?? almatyCenter, drop = d.dropoff!;
    setState(() => _busy = true);
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/rides',
                    headers: {'Idempotency-Key': _idemKey},
                    body: {
                      'pickup': {
                        'point': {'lat': pickup.lat, 'lng': pickup.lng},
                        if (pickup.address.isNotEmpty)
                          'address': pickup.address,
                      },
                      'dropoff': {
                        'point': {'lat': drop.lat, 'lng': drop.lng},
                        'address': drop.address.isNotEmpty
                            ? drop.address
                            : drop.name,
                      },
                      'category': _category,
                      'paymentMethod': _payment,
                      if (_promo != null) 'promoCode': _promo,
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) context.pushReplacement('/ride/${j['id']}');
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(draftProvider);
    final pickup = d.pickup ?? almatyCenter;
    final drop = d.dropoff;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final mapH = (MediaQuery.sizeOf(context).height * .27).clamp(150.0, 260.0);
    final from = LatLng(pickup.lat, pickup.lng);
    final to = drop == null ? null : LatLng(drop.lat, drop.lng);
    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: mapH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: to == null
                      ? ColoredBox(color: p.divider)
                      : JolayMap(
                          center: LatLng(
                            (from.latitude + to.latitude) / 2,
                            (from.longitude + to.longitude) / 2,
                          ),
                          zoom: 12,
                          interactive: false,
                          fitPoints: [from, to],
                          fitPadding: const EdgeInsets.fromLTRB(56, 80, 56, 40),
                          markers: [pickupMarker(from), dropoffMarker(to)],
                          route: [from, to],
                        ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AppIconButton(
                        icon: AppIcons.back,
                        tooltip: ref.t('common.back'),
                        style: AppIconButtonStyle.floating,
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: p.background,
                borderRadius: AppRadius.sheetR,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            ref.t('ride.chooseRide'),
                            style: t.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              AppIcons.flag,
                              size: 14,
                              color: p.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _est == null
                                    ? _placeLabel(ref, drop)
                                    : '${_placeLabel(ref, drop)} · ${formatKm(_est!.distanceM)} ${ref.t('ride.km')} · ${formatDuration(_est!.durationS)} ${ref.t('ride.eta')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        if (_est != null && _est!.routeSource == 'ESTIMATED')
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              ref.t('ride.routeEstimated'),
                              style: t.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _error != null
                        ? ErrorState(
                            message: ref.t(_error!),
                            retryLabel: ref.t('btn.retry'),
                            onRetry: _load,
                          )
                        : _est == null
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                            children: const [
                              SkeletonLoader(height: 80, radius: 18),
                              SizedBox(height: 10),
                              SkeletonLoader(height: 80, radius: 18),
                              SizedBox(height: 10),
                              SkeletonLoader(height: 80, radius: 18),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                            children: [
                              for (final c in _est!.categories)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: RideTypeCard(
                                    key: Key('cat-${c.code}'),
                                    name: c.name,
                                    description: c.description,
                                    selected: c.code == _category,
                                    onTap: () =>
                                        setState(() => _category = c.code),
                                    price: c.fare.payable,
                                    oldPrice: c.fare.payable != c.fare.total
                                        ? c.fare.total
                                        : null,
                                    oldPriceKey: Key('gross-${c.code}'),
                                    info: c.available
                                        ? '${formatDuration(c.etaSeconds ?? 0)} ${ref.t('ride.eta')} · ${c.capacity} ${ref.t('ride.seats')}'
                                        : '${ref.t('ride.noDrivers')} · ${c.capacity} ${ref.t('ride.seats')}',
                                    infoPositive: c.available,
                                    badge: c.fare.multiplier > 1
                                        ? StatusBadge(
                                            key: Key('peak-${c.code}'),
                                            label:
                                                '${ref.t('ride.highDemand')} ×${c.fare.multiplier.toStringAsFixed(c.fare.multiplier * 10 % 1 == 0 ? 1 : 2)}',
                                            tone: StatusTone.warning,
                                            icon: Icons.trending_up_rounded,
                                          )
                                        : null,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(ref.t('ride.payment'), style: t.titleSmall),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (final m in const [
                                    ('CASH', 'pay.cash', AppIcons.cash),
                                    ('CARD', 'pay.card', AppIcons.card),
                                    (
                                      'WALLET',
                                      'pay.wallet',
                                      AppIcons.walletOutlined,
                                    ),
                                  ]) ...[
                                    Expanded(
                                      child: AppCard(
                                        key: Key('pay-${m.$1}'),
                                        selected: _payment == m.$1,
                                        onTap: () =>
                                            setState(() => _payment = m.$1),
                                        semanticLabel: ref.t(m.$2),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 6,
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(m.$3, size: 22),
                                            const SizedBox(height: 4),
                                            Text(
                                              ref.t(m.$2),
                                              style: t.labelMedium,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (m.$1 != 'WALLET')
                                      const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: AppTextField(
                                      key: const Key('promo-field'),
                                      controller: _promoCtl,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      label: ref.t('promo.have'),
                                      prefixIcon: Icons.sell_outlined,
                                      errorText: _promoError == null
                                          ? null
                                          : ref.t(_promoError!),
                                      helper: _promo == null
                                          ? null
                                          : ref.t('promo.applied'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: AppButton(
                                      key: const Key('promo-apply'),
                                      label: ref.t('promo.apply'),
                                      variant: AppButtonVariant.outlined,
                                      expand: false,
                                      onPressed: _applyPromo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    AppIcons.info,
                                    size: 14,
                                    color: p.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      ref.t('ride.cancelFee'),
                                      style: t.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border(top: BorderSide(color: p.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: SafeArea(
                      top: false,
                      child: PrimaryButton(
                        key: const Key('confirm-ride'),
                        label: ref.t('ride.confirm'),
                        loading: _busy,
                        onPressed: _est == null ? null : _confirm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Track / detail ----------------
class RideTrackScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RideTrackScreen({super.key, required this.rideId});
  @override
  ConsumerState<RideTrackScreen> createState() => _TrackState();
}

class _TrackState extends ConsumerState<RideTrackScreen> {
  Ride? _ride;
  bool _failed = false;
  Timer? _poll, _shareTimer;
  LatLng? _driverLive;
  NavigationFeed? _navFeed;
  RideNavigation? _nav;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Road route + live ETA of the current leg, and the rider's own position for the driver while the driver is coming.
    _navFeed = NavigationFeed(ref.read(apiProvider), widget.rideId, (n) {
      if (mounted) setState(() => _nav = n);
    })..start();
    _shareTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _shareLocation(),
    );
    // Polling is the safety net; WebSocket events (below) make updates instant. REST is the source of truth.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_ride?.isTerminal != true || _ride?.paymentStatus == 'PENDING') {
        _fetch();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _shareTimer?.cancel();
    _navFeed?.dispose();
    super.dispose();
  }

  /// The driver sees the rider on their map only while coming to the pickup; nothing is sent once the trip starts.
  Future<void> _shareLocation() async {
    final s = _ride?.status;
    if (s != 'DRIVER_ASSIGNED' && s != 'DRIVER_ARRIVING' && s != 'DRIVER_ARRIVED') {
      return;
    }
    try {
      final p = await LocationService.current();
      if (p == null || !mounted) return;
      await ref
          .read(apiProvider)
          .post(
            '/rides/${widget.rideId}/customer-location',
            body: {'lat': p.lat, 'lng': p.lng},
          );
    } catch (_) {
      // best effort: the driver simply does not see the rider's dot
    }
  }

  Future<void> _fetch() async {
    try {
      final j =
          await ref.read(apiProvider).get('/rides/${widget.rideId}')
              as Map<String, dynamic>;
      if (mounted) {
        final ride = Ride.fromJson(j);
        final changed = _lastStatus != null && _lastStatus != ride.status;
        _lastStatus = ride.status;
        setState(() {
          _ride = ride;
          _failed = false;
        });
        if (changed) _navFeed?.refresh(); // a new leg starts: route to pickup, then to the destination
      }
    } catch (_) {
      if (mounted && _ride == null) setState(() => _failed = true);
    }
  }

  Future<void> _cancel() async {
    final ok = await showConfirmationDialog(
      context,
      title: ref.t('ride.confirmCancelTitle'),
      message: ref.t('ride.cancelFee'),
      confirmLabel: ref.t('ride.cancel'),
      cancelLabel: ref.t('ride.keep'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref
          .read(apiProvider)
          .post(
            '/rides/${widget.rideId}/cancel',
            body: {'reason': 'customer_cancelled'},
          );
      await _fetch();
    } catch (e) {
      if (mounted) showError(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final ev = next.value;
      if (ev == null) return;
      if (ev.type == 'DRIVER_LOCATION_UPDATED' &&
          ev.data['rideId'] == widget.rideId) {
        setState(
          () => _driverLive = LatLng(
            (ev.data['lat'] as num).toDouble(),
            (ev.data['lng'] as num).toDouble(),
          ),
        );
      } else {
        _fetch();
      } // CONNECTED (reconnect), status changes, payments: re-read authoritative state
    });
    final r = _ride;
    if (r == null) {
      return Scaffold(
        appBar: AppHeader(title: ''),
        body: _failed
            ? ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: _fetch,
              )
            : const LoadingState(),
      );
    }
    return switch (r.status) {
      'SEARCHING_DRIVER' || 'CREATED' => _Searching(ride: r, onCancel: _cancel),
      'DRIVER_ASSIGNED' ||
      'DRIVER_ARRIVING' ||
      'DRIVER_ARRIVED' ||
      'IN_PROGRESS' => _Active(
        ride: r,
        live: _driverLive,
        nav: _nav,
        onCancel: _cancel,
      ),
      'COMPLETED' => _Completed(ride: r, onRefresh: _fetch),
      _ => _Ended(ride: r),
    };
  }
}

/// Searching for a driver: calm radar pulse, elapsed time, the route, and an always-available cancel.
class _Searching extends ConsumerStatefulWidget {
  final Ride ride;
  final VoidCallback onCancel;
  const _Searching({required this.ride, required this.onCancel});
  @override
  ConsumerState<_Searching> createState() => _SearchingState();
}

class _SearchingState extends ConsumerState<_Searching>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final DateTime _start =
      DateTime.tryParse(widget.ride.createdAt ?? '')?.toLocal() ??
      DateTime.now();
  Timer? _tick;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(_start).isNegative
        ? Duration.zero
        : DateTime.now().difference(_start);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

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
    _tick?.cancel();
    super.dispose();
  }

  String get _mmss =>
      '${_elapsed.inMinutes.toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.ride;
    return Scaffold(
      backgroundColor: AppColors.midnight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Semantics(
                liveRegion: true,
                label: ref.t('ride.finding'),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        for (final off in const [0.0, .5])
                          Builder(
                            builder: (_) {
                              final v = context.reduceMotion
                                  ? .5
                                  : (_c.value + off) % 1.0;
                              return Container(
                                width: 84 + 136 * v,
                                height: 84 + 136 * v,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.yellow.withValues(
                                      alpha: (1 - v) * .9,
                                    ),
                                    width: 2.5,
                                  ),
                                ),
                              );
                            },
                          ),
                        Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(
                            color: AppColors.yellow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            AppIcons.ride,
                            size: 38,
                            color: AppColors.midnight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                ref.t('ride.finding'),
                textAlign: TextAlign.center,
                style: t.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                ref.t('ride.findingBody'),
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${ref.t('ride.searchElapsed')} $_mmss',
                  style: t.labelMedium?.copyWith(
                    color: AppColors.yellow,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: AppRadius.cardR,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3DBB7E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.pickupAddress,
                            style: t.bodyMedium?.copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2707A),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.dropoffAddress,
                            style: t.bodyMedium?.copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ref.t('ride.searchTip'),
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: Colors.white54),
              ),
              const Spacer(),
              Theme(
                data: Theme.of(context)
                    .copyWith(extensions: [JolayPalette.dark]),
                child: AppOutlinedButton(
                  key: const Key('cancel-search'),
                  label: ref.t('btn.cancel'),
                  onPressed: widget.onCancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Driver assigned → arriving → arrived → live trip. Map first; one panel with only what the passenger needs.
class _Active extends ConsumerWidget {
  final Ride ride;
  final LatLng? live;
  final RideNavigation? nav;
  final VoidCallback onCancel;
  const _Active({
    required this.ride,
    required this.live,
    required this.nav,
    required this.onCancel,
  });

  int get _step => switch (ride.status) {
    'DRIVER_ASSIGNED' => 0,
    'DRIVER_ARRIVING' => 1,
    'DRIVER_ARRIVED' => 2,
    _ => 3,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ride.driver;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final driverPos = live ?? (d?.lat != null ? LatLng(d!.lat!, d.lng!) : null);
    final title = switch (ride.status) {
      'DRIVER_ASSIGNED' => ref.t('ride.found'),
      'DRIVER_ARRIVING' => ref.t('ride.arriving'),
      'DRIVER_ARRIVED' => ref.t('ride.arrived'),
      _ => ref.t('ride.inProgress'),
    };
    final pickup = LatLng(ride.pickupLat, ride.pickupLng),
        drop = LatLng(ride.dropLat, ride.dropLng);
    final inTrip = ride.status == 'IN_PROGRESS';
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: JolayMap(
              center: driverPos ?? pickup,
              zoom: 14,
              fitPoints: [?driverPos, inTrip ? drop : pickup, drop],
              fitPadding: EdgeInsets.fromLTRB(
                48,
                110,
                48,
                MediaQuery.sizeOf(context).height * .5,
              ),
              markers: [
                if (!inTrip) pickupMarker(pickup),
                dropoffMarker(drop),
                if (driverPos != null) carMarker(driverPos),
              ],
              // the real road route of the current leg; a straight line until the server has one
              route: nav != null && nav!.points.length > 1
                  ? [for (final (lat, lng) in nav!.points) LatLng(lat, lng)]
                  : [pickup, drop],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.back,
                    tooltip: ref.t('common.back'),
                    style: AppIconButtonStyle.floating,
                    onPressed: () => context.go('/home'),
                  ),
                  const Spacer(),
                  _MapPill(
                    key: const Key('share-trip'),
                    icon: AppIcons.share,
                    label: ref.t('ride.share'),
                    onTap: () => _share(context, ref),
                  ),
                  const SizedBox(width: 8),
                  _MapPill(
                    key: const Key('sos'),
                    icon: AppIcons.sos,
                    label: ref.t('ride.sos'),
                    danger: true,
                    onTap: () => _sos(context, ref),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MapPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(title, style: t.titleLarge),
                        ),
                      ),
                      if (ride.driverEtaSeconds != null && !inTrip)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${formatDuration(ride.driverEtaSeconds!)} ${ref.t('ride.eta')}',
                            style: t.titleSmall?.copyWith(
                              color: p.onAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StatusSteps(step: _step),
                  if (nav != null && nav!.points.length > 1) ...[
                    const SizedBox(height: 12),
                    NavSummary(nav: nav!, showStep: false),
                  ],
                  if (d != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DriverAvatar(name: d.name, rating: d.rating, size: 56),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: t.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                VehicleCard(
                                  model: d.vehicle,
                                  color: d.color,
                                  plate: d.plate,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (d?.phone != null)
                        Expanded(
                          child: AppOutlinedButton(
                            label: ref.t('ride.call'),
                            icon: AppIcons.call,
                            size: AppButtonSize.medium,
                            onPressed: () =>
                                launchUrl(Uri.parse('tel:${d!.phone}')),
                          ),
                        ),
                      if (d?.phone != null && ride.canCancel)
                        const SizedBox(width: 10),
                      if (ride.canCancel)
                        Expanded(
                          child: AppButton(
                            key: const Key('cancel-ride'),
                            label: ref.t('ride.cancelShort'),
                            variant: AppButtonVariant.outlined,
                            size: AppButtonSize.medium,
                            onPressed: onCancel,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(AppIcons.flag, size: 14, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ride.dropoffAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PriceLabel(
                        amount: ride.estimatedFare,
                        size: PriceSize.small,
                        approximate: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Trip sharing: creates (or reuses) a read-only public link for this ride and copies it so it can be pasted into any messenger.
  Future<void> _share(BuildContext context, WidgetRef ref) async {
    try {
      final r =
          await ref.read(apiProvider).post('/rides/${ride.id}/share') as Map;
      await Clipboard.setData(ClipboardData(text: r['url'] as String));
      if (context.mounted) {
        showAppToast(
          context,
          ref.t('ride.shareCopied'),
          type: AppToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, ref, e);
    }
  }

  /// SOS: notifies JOLAY support with the position, and offers to dial the national emergency number (112). It does not replace emergency services.
  void _sos(BuildContext context, WidgetRef ref) => showAppModal<void>(
    context,
    title: ref.t('sos.title'),
    body: Text(ref.t('sos.body')),
    actions: [
      Builder(
        builder: (c) => AppButton(
          label: ref.t('sos.call'),
          variant: AppButtonVariant.danger,
          icon: AppIcons.call,
          onPressed: () {
            Navigator.pop(c);
            launchUrl(Uri.parse('tel:112'));
          },
        ),
      ),
      Builder(
        builder: (c) => AppButton(
          key: const Key('sos-notify'),
          label: ref.t('sos.notify'),
          variant: AppButtonVariant.outlined,
          onPressed: () async {
            Navigator.pop(c);
            final pos =
                live ??
                (ride.driver?.lat != null
                    ? LatLng(ride.driver!.lat!, ride.driver!.lng!)
                    : LatLng(ride.pickupLat, ride.pickupLng));
            try {
              await reportSos(
                ref.read(apiProvider),
                lat: pos.latitude,
                lng: pos.longitude,
              );
              if (context.mounted) {
                showAppToast(
                  context,
                  ref.t('sos.sent'),
                  type: AppToastType.success,
                );
              }
            } catch (e) {
              if (context.mounted) showError(context, ref, e);
            }
          },
        ),
      ),
      Builder(
        builder: (c) => AppTextButton(
          label: ref.t('btn.cancel'),
          expand: true,
          onPressed: () => Navigator.pop(c),
        ),
      ),
    ],
  );
}

/// Four-stage progress: assigned · on the way · arrived · in trip.
class _StatusSteps extends StatelessWidget {
  final int step;
  const _StatusSteps({required this.step});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: context.motion(AppDurations.slow),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step
                      ? (p.isDark ? p.accent : AppColors.midnight)
                      : p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 3) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _MapPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _MapPill({
    super.key,
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = danger ? p.error : p.surface;
    final fg = danger
        ? (p.isDark ? AppColors.midnight : Colors.white)
        : p.textPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppElevation.floating,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: fg),
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

class _Completed extends ConsumerStatefulWidget {
  final Ride ride;
  final Future<void> Function() onRefresh;
  const _Completed({required this.ride, required this.onRefresh});
  @override
  ConsumerState<_Completed> createState() => _CompletedState();
}

class _CompletedState extends ConsumerState<_Completed> {
  int _stars = 0;
  final _comment = TextEditingController();
  final Set<String> _tags = {};
  bool _busy = false, _rated = false;
  List<Map<String, dynamic>> _fare = [];

  @override
  void initState() {
    super.initState();
    _loadFare();
    _rated = widget.ride.rating != null;
    _stars = widget.ride.rating ?? 0;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadFare() async {
    try {
      final j =
          await ref.read(apiProvider).get('/rides/${widget.ride.id}/fare')
              as List;
      if (mounted) setState(() => _fare = j.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final method = widget.ride.paymentMethod == 'WALLET' ? 'WALLET' : 'CARD';
      final p =
          await ref
                  .read(apiProvider)
                  .post(
                    '/payments/initialize',
                    body: {'rideId': widget.ride.id, 'method': method},
                  )
              as Map<String, dynamic>;
      final url = p['checkoutUrl'] as String?;
      if (url != null && url.contains('sandbox-checkout') && mounted) {
        final ok = await showAppModal<bool>(
          context,
          title: 'Sandbox checkout',
          body: Text('${formatKzt(p['amount'])} — development gateway.'),
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
      } else if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      await widget.onRefresh(); // paid state comes from the backend, never from this client
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rate() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .post(
            '/rides/${widget.ride.id}/rating',
            body: {
              'stars': _stars,
              'tags': _tags.toList(),
              if (_comment.text.trim().isNotEmpty)
                'comment': _comment.text.trim(),
            },
          );
      if (mounted) setState(() => _rated = true);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Repeats the same route: the estimate screen then re-prices it with live data.
  void _again() {
    final r = widget.ride;
    ref
        .read(draftProvider.notifier)
        .setPickup(
          Place(r.pickupAddress, r.pickupAddress, r.pickupLat, r.pickupLng),
        );
    ref
        .read(draftProvider.notifier)
        .setDropoff(
          Place(r.dropoffAddress, r.dropoffAddress, r.dropLat, r.dropLng),
        );
    context.pushReplacement('/ride/options');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final unpaid = r.paymentStatus == 'PENDING' || r.paymentStatus == 'FAILED';
    final f = _fare.isEmpty ? null : _fare.first;
    final (badgeLabel, badgeTone) = r.paymentStatus == 'PAID'
        ? (ref.t('ride.paid'), StatusTone.success)
        : r.paymentStatus == 'FAILED'
        ? (ref.t('ride.paymentFailed'), StatusTone.error)
        : (ref.t('ride.paymentPending'), StatusTone.warning);
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('ride.completed'),
        onBack: () => context.go('/home'),
        backLabel: ref.t('common.close'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Center(
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: context.reduceMotion ? 1 : 0, end: 1),
                  duration: AppDurations.slow * 2,
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.success,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.check,
                      color: p.isDark ? AppColors.midnight : Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  ref.t('ride.total'),
                  style: t.bodyMedium?.copyWith(color: p.textSecondary),
                ),
                PriceLabel(
                  key: const Key('final-fare'),
                  amount: r.payable,
                  size: PriceSize.hero,
                ),
                const SizedBox(height: 10),
                StatusBadge(label: badgeLabel, tone: badgeTone),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ref.t('ride.tripSummary'), style: t.titleSmall),
                const SizedBox(height: 12),
                _SummaryRoute(from: r.pickupAddress, to: r.dropoffAddress),
                const SizedBox(height: 8),
                Divider(color: p.divider),
                InfoRow(
                  label: ref.t('ride.distance'),
                  value: Text(
                    '${formatKm(r.distanceM)} ${ref.t('ride.km')}',
                    style: t.titleSmall,
                  ),
                ),
                InfoRow(
                  label: ref.t('ride.duration'),
                  value: Text(
                    '${formatDuration(r.durationS)} ${ref.t('ride.eta')}',
                    style: t.titleSmall,
                  ),
                ),
                if (f != null) ...[
                  Divider(color: p.divider),
                  InfoRow(
                    label: ref.t('ride.base'),
                    value: Text(formatKzt(f['base_fare']), style: t.titleSmall),
                  ),
                  InfoRow(
                    label: ref.t('ride.distanceFare'),
                    value: Text(
                      formatKzt(f['distance_fare']),
                      style: t.titleSmall,
                    ),
                  ),
                  InfoRow(
                    label: ref.t('ride.timeFare'),
                    value: Text(formatKzt(f['time_fare']), style: t.titleSmall),
                  ),
                  if (double.parse(f['fees'].toString()) > 0)
                    InfoRow(
                      label: ref.t('ride.fees'),
                      value: Text(formatKzt(f['fees']), style: t.titleSmall),
                    ),
                  if (r.hasPromo)
                    InfoRow(
                      label:
                          '${ref.t('promo.discount')} (${r.promoCode ?? ''})',
                      value: Text(
                        '−${formatKzt(r.promoDiscount)}',
                        style: t.titleSmall?.copyWith(color: p.success),
                      ),
                    ),
                ],
                Divider(color: p.divider),
                InfoRow(
                  label: ref.t('ride.payment'),
                  value: Text(switch (r.paymentMethod) {
                    'CASH' => ref.t('pay.cash'),
                    'CARD' => ref.t('pay.card'),
                    _ => ref.t('pay.wallet'),
                  }, style: t.titleSmall),
                ),
              ],
            ),
          ),
          if (unpaid) ...[
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('pay-now'),
              label: '${ref.t('ride.pay')} · ${formatKzt(r.payable)}',
              loading: _busy,
              onPressed: _pay,
            ),
          ],
          const SizedBox(height: 24),
          if (r.driver != null)
            AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Avatar(name: r.driver!.name, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.driver!.name, style: t.titleSmall),
                            Text(
                              '${r.driver!.vehicle} · ${r.driver!.plate}',
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _rated ? ref.t('ride.thanks') : ref.t('ride.rate'),
                    style: t.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  IgnorePointer(
                    ignoring: _rated,
                    child: RatingInput(
                      value: _stars,
                      keyPrefix: 'star',
                      onChanged: (i) => setState(() => _stars = i),
                      labelFor: (i) => '$i / 5',
                    ),
                  ),
                  if (!_rated) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final tg in const [
                          ('FRIENDLY', 'tag.friendly'),
                          ('CLEAN_VEHICLE', 'tag.clean'),
                          ('SAFE_DRIVING', 'tag.safe'),
                          ('ON_TIME', 'tag.ontime'),
                          ('COMMUNICATION', 'tag.comm'),
                        ])
                          FilterChip(
                            label: Text(ref.t(tg.$2)),
                            selected: _tags.contains(tg.$1),
                            showCheckmark: true,
                            onSelected: (s) => setState(
                              () => s ? _tags.add(tg.$1) : _tags.remove(tg.$1),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _comment,
                      maxLines: 2,
                      maxLength: 500,
                      hint: ref.t('ride.comment'),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      key: const Key('submit-rating'),
                      label: ref.t('btn.send'),
                      loading: _busy,
                      onPressed: _stars == 0 ? null : _rate,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          PrimaryButton(
            key: const Key('ride-again'),
            label: ref.t('ride.again'),
            icon: AppIcons.refresh,
            onPressed: _again,
          ),
          const SizedBox(height: 10),
          AppOutlinedButton(
            label: ref.t('btn.done'),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRoute extends StatelessWidget {
  final String from, to;
  const _SummaryRoute({required this.from, required this.to});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: p.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                from,
                style: t.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: p.error,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                to,
                style: t.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Expired (no driver found) or cancelled: say what happened, and offer the obvious next step.
class _Ended extends ConsumerWidget {
  final Ride ride;
  const _Ended({required this.ride});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = ride.status == 'EXPIRED';
    final fee = double.tryParse(ride.cancellationFee) ?? 0;
    return Scaffold(
      appBar: AppHeader(
        title: '',
        onBack: () => context.go('/home'),
        backLabel: ref.t('common.close'),
      ),
      body: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: expired ? Icons.search_off_rounded : Icons.cancel_outlined,
              title: expired ? ref.t('ride.expired') : ref.t('ride.cancelled'),
              message: expired
                  ? ref.t('ride.expiredBody')
                  : (fee > 0
                        ? '${ref.t('ride.cancelFee')}: ${formatKzt(ride.cancellationFee)}'
                        : ref.t('ride.cancelledBody')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (expired) ...[
                    PrimaryButton(
                      key: const Key('try-again'),
                      label: ref.t('ride.again'),
                      icon: AppIcons.refresh,
                      onPressed: () {
                        ref
                            .read(draftProvider.notifier)
                            .setPickup(
                              Place(
                                ride.pickupAddress,
                                ride.pickupAddress,
                                ride.pickupLat,
                                ride.pickupLng,
                              ),
                            );
                        ref
                            .read(draftProvider.notifier)
                            .setDropoff(
                              Place(
                                ride.dropoffAddress,
                                ride.dropoffAddress,
                                ride.dropLat,
                                ride.dropLng,
                              ),
                            );
                        context.pushReplacement('/ride/options');
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  expired
                      ? AppOutlinedButton(
                          label: ref.t('btn.done'),
                          onPressed: () => context.go('/home'),
                        )
                      : PrimaryButton(
                          label: ref.t('btn.done'),
                          onPressed: () => context.go('/home'),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
