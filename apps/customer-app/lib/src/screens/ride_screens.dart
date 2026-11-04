import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'map_widgets.dart';

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
  void dispose() { _debounce?.cancel(); super.dispose(); }

  void _onChanged(String s) {
    _debounce?.cancel();
    if (s.trim().length < 2) { setState(() => _results = []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      try {
        final d = ref.read(draftProvider).pickup ?? almatyCenter;
        final j = await ref.read(apiProvider).get('/geo/places', query: {'q': s.trim(), 'lat': d.lat, 'lng': d.lng}) as List;
        if (mounted) setState(() => _results = j.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList());
      } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _loading = false); }
    });
  }

  void _choose(Place p) { ref.read(draftProvider.notifier).setDropoff(p); context.pushReplacement('/ride/options'); }

  Future<void> _pickOnMap({required bool pickup}) async {
    final d = ref.read(draftProvider);
    final start = pickup ? (d.pickup ?? almatyCenter) : (d.dropoff ?? d.pickup ?? almatyCenter);
    final p = await Navigator.push<Place>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(start: LatLng(start.lat, start.lng), title: pickup ? ref.t('home.pickup') : ref.t('ride.destination'))));
    if (p == null || !mounted) return;
    if (pickup) { ref.read(draftProvider.notifier).setPickup(p); setState(() {}); } else { _choose(p); }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    final saved = ref.watch(savedAddressesProvider).value ?? [];
    final recent = ref.watch(recentDestinationsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('ride.destination'))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Column(children: [
          JolayCard(onTap: () => _pickOnMap(pickup: true), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
            const Icon(Icons.circle, size: 12, color: JolayColors.success), const SizedBox(width: 10),
            Expanded(child: Text(draft.pickup == null ? ref.t('home.pickup') : (draft.pickup!.name.isEmpty ? ref.t('home.currentLocation') : draft.pickup!.name), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.map_outlined, size: 20),
          ])),
          const SizedBox(height: 10),
          TextField(key: const Key('dest-search'), controller: _q, onChanged: _onChanged, autofocus: true, decoration: InputDecoration(hintText: ref.t('ride.search'), prefixIcon: const Icon(Icons.search, color: JolayColors.error),
              suffixIcon: IconButton(icon: const Icon(Icons.map_outlined), onPressed: () => _pickOnMap(pickup: false)))),
        ])),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final p in _results) ListTile(leading: const Icon(Icons.place_outlined), title: Text(p.name), subtitle: Text(p.address), onTap: () => _choose(p)),
          if (_results.isEmpty && _q.text.trim().length < 2) ...[
            for (final p in saved) ListTile(leading: const Icon(Icons.bookmark_outline), title: Text(p.name), subtitle: Text(p.address), onTap: () => _choose(p)),
            for (final p in recent) ListTile(leading: const Icon(Icons.history), title: Text(p.address), onTap: () => _choose(p)),
          ],
        ])),
      ]),
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
  late final String _idemKey = 'ride-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _error = null; _est = null; });
    final d = ref.read(draftProvider);
    final pickup = d.pickup ?? almatyCenter, drop = d.dropoff;
    if (drop == null) { setState(() => _error = 'common.error'); return; }
    try {
      final j = await ref.read(apiProvider).post('/rides/estimate', headers: {'Accept-Language': ref.read(localeProvider).languageCode},
          body: {'pickup': {'lat': pickup.lat, 'lng': pickup.lng}, 'dropoff': {'lat': drop.lat, 'lng': drop.lng}}) as Map<String, dynamic>;
      if (mounted) setState(() => _est = Estimate.fromJson(j));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? (e.isNetwork ? 'err.network' : 'err.${e.code}') : 'common.error');
    }
  }

  Future<void> _confirm() async {
    final d = ref.read(draftProvider);
    final pickup = d.pickup ?? almatyCenter, drop = d.dropoff!;
    setState(() => _busy = true);
    try {
      final j = await ref.read(apiProvider).post('/rides', headers: {'Idempotency-Key': _idemKey}, body: {
        'pickup': {'point': {'lat': pickup.lat, 'lng': pickup.lng}, if (pickup.address.isNotEmpty) 'address': pickup.address},
        'dropoff': {'point': {'lat': drop.lat, 'lng': drop.lng}, 'address': drop.address.isNotEmpty ? drop.address : drop.name},
        'category': _category, 'paymentMethod': _payment,
      }) as Map<String, dynamic>;
      if (mounted) context.pushReplacement('/ride/${j['id']}');
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(draftProvider);
    final pickup = d.pickup ?? almatyCenter;
    final drop = d.dropoff;
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('ride.chooseRide'))),
      body: Column(children: [
        SizedBox(height: 180, child: drop == null ? null : JolayMap(center: LatLng((pickup.lat + drop.lat) / 2, (pickup.lng + drop.lng) / 2), zoom: 12,
            markers: [pin(LatLng(pickup.lat, pickup.lng), Icons.location_on, JolayColors.success), pin(LatLng(drop.lat, drop.lng), Icons.location_on, JolayColors.error)],
            route: [LatLng(pickup.lat, pickup.lng), LatLng(drop.lat, drop.lng)])),
        if (_est != null) Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0), child: Row(children: [
          const Icon(Icons.route, size: 16, color: JolayColors.textSecondary), const SizedBox(width: 6),
          Expanded(child: Text('${formatKm(_est!.distanceM)} ${ref.t('ride.km')} · ${formatDuration(_est!.durationS)} ${ref.t('ride.eta')}${_est!.routeSource == 'ESTIMATED' ? ' · ${ref.t('ride.routeEstimated')}' : ''}', style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary))),
        ])),
        Expanded(child: _error != null
            ? ErrorView(message: ref.t(_error!), retryLabel: ref.t('btn.retry'), onRetry: _load)
            : _est == null ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final c in _est!.categories)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: _CategoryCard(key: Key('cat-${c.code}'), c: c, selected: c.code == _category, seatsLabel: ref.t('ride.seats'), etaLabel: ref.t('ride.eta'), noDrivers: ref.t('ride.noDrivers'), onTap: () => setState(() => _category = c.code))),
                const SizedBox(height: 8),
                Text(ref.t('ride.payment'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [for (final m in const [('CASH', 'pay.cash', Icons.payments_outlined), ('CARD', 'pay.card', Icons.credit_card), ('WALLET', 'pay.wallet', Icons.account_balance_wallet_outlined)])
                  ChoiceChip(key: Key('pay-${m.$1}'), avatar: Icon(m.$3, size: 18), label: Text(ref.t(m.$2)), selected: _payment == m.$1, selectedColor: JolayColors.yellow, onSelected: (_) => setState(() => _payment = m.$1))]),
                const SizedBox(height: 6),
                Text(ref.t('ride.cancelFee'), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)),
              ])),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: JolayButton(key: const Key('confirm-ride'), label: ref.t('ride.confirm'), busy: _busy, onPressed: _est == null ? null : _confirm))),
      ]),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryEstimate c;
  final bool selected;
  final String seatsLabel, etaLabel, noDrivers;
  final VoidCallback onTap;
  const _CategoryCard({super.key, required this.c, required this.selected, required this.seatsLabel, required this.etaLabel, required this.noDrivers, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(JolayRadius.md), onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(JolayRadius.md), border: Border.all(color: selected ? JolayColors.midnight : JolayColors.border, width: selected ? 2 : 1)),
          child: Row(children: [
            Container(width: 56, height: 40, decoration: BoxDecoration(color: selected ? JolayColors.yellow : JolayColors.cloud, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.directions_car_filled)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12)),
              Text(c.available ? '${formatDuration(c.etaSeconds ?? 0)} $etaLabel · ${c.capacity} $seatsLabel' : '$noDrivers · ${c.capacity} $seatsLabel', style: TextStyle(fontSize: 12, color: c.available ? JolayColors.success : JolayColors.textSecondary)),
            ])),
            Text(formatKzt(c.fare.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ]),
        ),
      );
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
  Timer? _poll;
  LatLng? _driverLive;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Polling is the safety net; WebSocket events (below) make updates instant. REST is the source of truth.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) { if (_ride?.isTerminal != true || _ride?.paymentStatus == 'PENDING') _fetch(); });
  }

  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      final j = await ref.read(apiProvider).get('/rides/${widget.rideId}') as Map<String, dynamic>;
      if (mounted) setState(() { _ride = Ride.fromJson(j); _failed = false; });
    } catch (_) { if (mounted && _ride == null) setState(() => _failed = true); }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(content: Text(ref.t('ride.cancelFee')), actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ref.t('ride.cancel'), style: const TextStyle(color: JolayColors.error)))]));
    if (ok != true) return;
    try { await ref.read(apiProvider).post('/rides/${widget.rideId}/cancel', body: {'reason': 'customer_cancelled'}); await _fetch(); }
    catch (e) { if (mounted) showError(context, ref, e); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final ev = next.value;
      if (ev == null) return;
      if (ev.type == 'DRIVER_LOCATION_UPDATED' && ev.data['rideId'] == widget.rideId) {
        setState(() => _driverLive = LatLng((ev.data['lat'] as num).toDouble(), (ev.data['lng'] as num).toDouble()));
      } else { _fetch(); }   // CONNECTED (reconnect), status changes, payments: re-read authoritative state
    });
    final r = _ride;
    if (r == null) {
      return Scaffold(appBar: AppBar(), body: _failed ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _fetch) : const Center(child: CircularProgressIndicator()));
    }
    return switch (r.status) {
      'SEARCHING_DRIVER' || 'CREATED' => _Searching(ride: r, onCancel: _cancel),
      'DRIVER_ASSIGNED' || 'DRIVER_ARRIVING' || 'DRIVER_ARRIVED' || 'IN_PROGRESS' => _Active(ride: r, live: _driverLive, onCancel: _cancel),
      'COMPLETED' => _Completed(ride: r, onRefresh: _fetch),
      _ => _Ended(ride: r),
    };
  }
}

class _Searching extends ConsumerStatefulWidget {
  final Ride ride;
  final VoidCallback onCancel;
  const _Searching({required this.ride, required this.onCancel});
  @override
  ConsumerState<_Searching> createState() => _SearchingState();
}

class _SearchingState extends ConsumerState<_Searching> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: JolayColors.midnight,
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          const Spacer(),
          SizedBox(width: 200, height: 200, child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(animation: _c, builder: (_, _) => Container(width: 80 + 120 * _c.value, height: 80 + 120 * _c.value, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: JolayColors.yellow.withValues(alpha: 1 - _c.value), width: 3)))),
            Container(padding: const EdgeInsets.all(22), decoration: const BoxDecoration(color: JolayColors.yellow, shape: BoxShape.circle), child: const Icon(Icons.local_taxi, size: 40, color: JolayColors.midnight)),
          ])),
          const SizedBox(height: 28),
          Text(ref.t('ride.finding'), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(ref.t('ride.findingBody'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF262626), borderRadius: BorderRadius.circular(JolayRadius.md)), child: Column(children: [
            Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.success), const SizedBox(width: 10), Expanded(child: Text(widget.ride.pickupAddress, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.error), const SizedBox(width: 10), Expanded(child: Text(widget.ride.dropoffAddress, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis))]),
          ])),
          const Spacer(),
          OutlinedButton(key: const Key('cancel-search'), onPressed: widget.onCancel, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), child: Text(ref.t('btn.cancel'))),
        ]))),
      );
}

class _Active extends ConsumerWidget {
  final Ride ride;
  final LatLng? live;
  final VoidCallback onCancel;
  const _Active({required this.ride, required this.live, required this.onCancel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ride.driver;
    final driverPos = live ?? (d?.lat != null ? LatLng(d!.lat!, d.lng!) : null);
    final title = switch (ride.status) { 'DRIVER_ASSIGNED' => ref.t('ride.found'), 'DRIVER_ARRIVING' => ref.t('ride.arriving'), 'DRIVER_ARRIVED' => ref.t('ride.arrived'), _ => ref.t('ride.inProgress') };
    final pickup = LatLng(ride.pickupLat, ride.pickupLng), drop = LatLng(ride.dropLat, ride.dropLng);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: JolayMap(center: driverPos ?? pickup, zoom: 14, markers: [
          pin(pickup, Icons.location_on, JolayColors.success), pin(drop, Icons.flag, JolayColors.error),
          if (driverPos != null) pin(driverPos, Icons.local_taxi, JolayColors.midnight),
        ], route: [pickup, drop])),
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home'))), const Spacer(),
          FilledButton.icon(key: const Key('sos'), onPressed: () => _sos(context, ref), icon: const Icon(Icons.warning_amber_rounded), label: Text(ref.t('ride.sos')),
              style: FilledButton.styleFrom(backgroundColor: JolayColors.error, foregroundColor: Colors.white, minimumSize: const Size(90, 40))),
        ])))),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)]),
          child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), if (ride.driverEtaSeconds != null) Text('${formatDuration(ride.driverEtaSeconds!)} ${ref.t('ride.eta')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))]),
            const SizedBox(height: 12),
            if (d != null) Row(children: [
              const CircleAvatar(radius: 24, backgroundColor: JolayColors.cloud, child: Icon(Icons.person)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('★ ${d.rating} · ${d.vehicle} · ${d.color}', style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: JolayColors.yellow, borderRadius: BorderRadius.circular(8)), child: Text(d.plate, style: const TextStyle(fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              if (d?.phone != null) Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${d!.phone}')), icon: const Icon(Icons.call), label: Text(ref.t('ride.call')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)))),
              if (d?.phone != null && ride.canCancel) const SizedBox(width: 10),
              if (ride.canCancel) Expanded(child: OutlinedButton(key: const Key('cancel-ride'), onPressed: onCancel, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: JolayColors.error), child: Text(ref.t('ride.cancel')))),
            ]),
            const SizedBox(height: 8),
            Text('${ride.dropoffAddress} · ${formatKzt(ride.estimatedFare)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12)),
          ])),
        )),
      ]),
    );
  }

  /// SOS: there is no operator integration yet, so the honest behaviour is to dial the national emergency number (112).
  void _sos(BuildContext context, WidgetRef ref) => showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: Text(ref.t('ride.sos')),
        content: const Text('112'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () { Navigator.pop(c); launchUrl(Uri.parse('tel:112')); }, style: FilledButton.styleFrom(backgroundColor: JolayColors.error, foregroundColor: Colors.white, minimumSize: const Size(120, 44)), child: Text('${ref.t('ride.call')} 112'))],
      ));
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
  void initState() { super.initState(); _loadFare(); _rated = widget.ride.rating != null; _stars = widget.ride.rating ?? 0; }

  Future<void> _loadFare() async {
    try { final j = await ref.read(apiProvider).get('/rides/${widget.ride.id}/fare') as List; if (mounted) setState(() => _fare = j.cast<Map<String, dynamic>>()); } catch (_) {}
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final method = widget.ride.paymentMethod == 'WALLET' ? 'WALLET' : 'CARD';
      final p = await ref.read(apiProvider).post('/payments/initialize', body: {'rideId': widget.ride.id, 'method': method}) as Map<String, dynamic>;
      final url = p['checkoutUrl'] as String?;
      if (url != null && url.contains('sandbox-checkout') && mounted) {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Sandbox checkout'), content: Text('${formatKzt(p['amount'])} — development gateway.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('ride.pay')))]));
        if (ok == true) await ref.read(apiProvider).post('/payments/${p['id']}/sandbox-checkout');
      } else if (url != null) { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
      await widget.onRefresh();   // paid state comes from the backend, never from this client
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _rate() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/rides/${widget.ride.id}/rating', body: {'stars': _stars, 'tags': _tags.toList(), if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim()});
      if (mounted) setState(() => _rated = true);
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final unpaid = r.paymentStatus == 'PENDING' || r.paymentStatus == 'FAILED';
    final f = _fare.isEmpty ? null : _fare.first;
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('ride.completed')), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/home'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Column(children: [
          const CircleAvatar(radius: 32, backgroundColor: JolayColors.success, child: Icon(Icons.check, color: Colors.white, size: 36)),
          const SizedBox(height: 12),
          Text(ref.t('ride.total'), style: const TextStyle(color: JolayColors.textSecondary)),
          Text(formatKzt(r.finalFare), key: const Key('final-fare'), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Chip(label: Text(r.paymentStatus == 'PAID' ? ref.t('ride.paid') : r.paymentStatus == 'FAILED' ? ref.t('ride.paymentFailed') : ref.t('ride.paymentPending')),
              backgroundColor: r.paymentStatus == 'PAID' ? const Color(0xFFD9F3E8) : r.paymentStatus == 'FAILED' ? const Color(0xFFFDE1E2) : const Color(0xFFFDF0CF), side: BorderSide.none),
        ])),
        const SizedBox(height: 16),
        JolayCard(child: Column(children: [
          _row(ref.t('ride.distance'), '${formatKm(r.distanceM)} ${ref.t('ride.km')}'), _row(ref.t('ride.duration'), '${formatDuration(r.durationS)} ${ref.t('ride.eta')}'),
          if (f != null) ...[const Divider(), _row(ref.t('ride.base'), formatKzt(f['base_fare'])), _row(ref.t('ride.distanceFare'), formatKzt(f['distance_fare'])), _row(ref.t('ride.timeFare'), formatKzt(f['time_fare'])), if (double.parse(f['fees'].toString()) > 0) _row(ref.t('ride.fees'), formatKzt(f['fees']))],
          const Divider(), _row(ref.t('ride.payment'), switch (r.paymentMethod) { 'CASH' => ref.t('pay.cash'), 'CARD' => ref.t('pay.card'), _ => ref.t('pay.wallet') }),
        ])),
        const SizedBox(height: 16),
        if (unpaid) JolayButton(key: const Key('pay-now'), label: ref.t('ride.pay'), busy: _busy, onPressed: _pay),
        const SizedBox(height: 20),
        if (r.driver != null) ...[
          Center(child: Text(_rated ? ref.t('ride.thanks') : '${ref.t('ride.rate')} · ${r.driver!.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(key: Key('star-$i'), iconSize: 38, onPressed: _rated ? null : () => setState(() => _stars = i), icon: Icon(i <= _stars ? Icons.star : Icons.star_border, color: JolayColors.yellow))]),
          if (!_rated) ...[
            Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [for (final t in const [('FRIENDLY', 'tag.friendly'), ('CLEAN_VEHICLE', 'tag.clean'), ('SAFE_DRIVING', 'tag.safe'), ('ON_TIME', 'tag.ontime'), ('COMMUNICATION', 'tag.comm')])
              FilterChip(label: Text(ref.t(t.$2)), selected: _tags.contains(t.$1), onSelected: (s) => setState(() => s ? _tags.add(t.$1) : _tags.remove(t.$1)))]),
            const SizedBox(height: 10),
            TextField(controller: _comment, maxLines: 2, maxLength: 500, decoration: InputDecoration(hintText: ref.t('ride.comment'))),
            JolayButton(key: const Key('submit-rating'), label: ref.t('btn.send'), busy: _busy, onPressed: _stars == 0 ? null : _rate),
          ],
        ],
        const SizedBox(height: 12),
        JolayButton(label: ref.t('btn.done'), secondary: true, onPressed: () => context.go('/home')),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: JolayColors.textSecondary))), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class _Ended extends ConsumerWidget {
  final Ride ride;
  const _Ended({required this.ride});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/home'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ride.status == 'EXPIRED' ? Icons.search_off : Icons.cancel_outlined, size: 64, color: JolayColors.textSecondary),
          const SizedBox(height: 12),
          Text(ride.status == 'EXPIRED' ? ref.t('ride.expired') : ref.t('ride.cancelled'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (double.tryParse(ride.cancellationFee) != null && double.parse(ride.cancellationFee) > 0) Text(formatKzt(ride.cancellationFee), style: const TextStyle(color: JolayColors.textSecondary)),
          const SizedBox(height: 24),
          JolayButton(label: ref.t('btn.done'), onPressed: () => context.go('/home')),
        ]))),
      );
}
