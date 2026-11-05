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

/// Searches places through the backend and returns the chosen one.
Future<Place?> pickPlace(BuildContext context, WidgetRef ref) => showModalBottomSheet<Place>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (c) => _PlaceSheet(ref: ref),
    );

class _PlaceSheet extends StatefulWidget {
  final WidgetRef ref;
  const _PlaceSheet({required this.ref});
  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  List<Place> _results = [];
  Timer? _debounce;
  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }
  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _results = []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final j = await widget.ref.read(apiProvider).get('/geo/places', query: {'q': q.trim()}) as List;
        if (mounted) setState(() => _results = j.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList());
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(height: 420, child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: TextField(key: const Key('place-search'), autofocus: true, onChanged: _search, decoration: InputDecoration(hintText: widget.ref.t('ride.search'), prefixIcon: const Icon(Icons.search)))),
          Expanded(child: ListView(children: [for (final p in _results) ListTile(leading: const Icon(Icons.place_outlined), title: Text(p.name), subtitle: Text(p.address), onTap: () => Navigator.pop(context, p))])),
        ])),
      );
}

class ExpressCreateScreen extends ConsumerStatefulWidget {
  const ExpressCreateScreen({super.key});
  @override
  ConsumerState<ExpressCreateScreen> createState() => _CreateState();
}

class _CreateState extends ConsumerState<ExpressCreateScreen> {
  final _form = GlobalKey<FormState>();
  Place? _from, _to;
  String _size = 'SMALL', _payment = 'CASH';
  final _weight = TextEditingController(text: '1'), _desc = TextEditingController();
  final _sName = TextEditingController(), _sPhone = TextEditingController(), _rName = TextEditingController(), _rPhone = TextEditingController(text: '+7 ');
  Map<String, dynamic>? _quote;
  bool _busy = false, _quoting = false;
  late final String _idem = 'express-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final u = ref.read(authProvider).user;
    _sName.text = u?.fullName ?? ''; _sPhone.text = u?.phone ?? '+7 ';
    final d = ref.read(draftProvider);
    _from = d.pickup;
  }

  double? get _kg => double.tryParse(_weight.text.replaceAll(',', '.'));

  Future<void> _calc() async {
    if (_from == null || _to == null || _kg == null || _kg! <= 0) return;
    setState(() { _quoting = true; _quote = null; });
    try {
      final j = await ref.read(apiProvider).post('/deliveries/estimate', body: {'pickup': {'lat': _from!.lat, 'lng': _from!.lng}, 'dropoff': {'lat': _to!.lat, 'lng': _to!.lng}, 'sizeClass': _size, 'weightKg': _kg}) as Map<String, dynamic>;
      if (mounted) setState(() => _quote = j);
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _quoting = false); }
  }

  Future<void> _order() async {
    if (_from == null || _to == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.t('express.chooseAddress')))); return; }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final j = await ref.read(apiProvider).post('/deliveries', headers: {'Idempotency-Key': _idem}, body: {
        'pickup': {'point': {'lat': _from!.lat, 'lng': _from!.lng}, 'address': _from!.address.isNotEmpty ? _from!.address : _from!.name},
        'dropoff': {'point': {'lat': _to!.lat, 'lng': _to!.lng}, 'address': _to!.address.isNotEmpty ? _to!.address : _to!.name},
        'sizeClass': _size, 'weightKg': _kg, 'description': _desc.text.trim(), 'paymentMethod': _payment,
        'sender': {'name': _sName.text.trim(), 'phone': Validators.normalizePhone(_sPhone.text)}, 'recipient': {'name': _rName.text.trim(), 'phone': Validators.normalizePhone(_rPhone.text)},
      }) as Map<String, dynamic>;
      if (mounted) context.pushReplacement('/express/${j['id']}');
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _addr(String label, Place? p, ValueChanged<Place> on) => JolayCard(
        onTap: () async { final x = await pickPlace(context, ref); if (x != null) { on(x); _calc(); } },
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [const Icon(Icons.place_outlined), const SizedBox(width: 10), Expanded(child: Text(p == null ? '$label · ${ref.t('express.chooseAddress')}' : '$label · ${p.name.isNotEmpty ? p.name : p.address}', maxLines: 1, overflow: TextOverflow.ellipsis))]),
      );

  @override
  Widget build(BuildContext context) {
    final fee = _quote?['fee'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('express.title'))),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(key: const Key('from-card'), child: _addr(ref.t('express.from'), _from, (p) => setState(() => _from = p))),
        const SizedBox(height: 8),
        Container(key: const Key('to-card'), child: _addr(ref.t('express.to'), _to, (p) => setState(() => _to = p))),
        const SizedBox(height: 16),
        Text(ref.t('express.size'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final s in const ['SMALL', 'MEDIUM', 'LARGE']) ChoiceChip(key: Key('size-$s'), label: Text(ref.t('express.size.$s')), selected: _size == s, selectedColor: JolayColors.yellow, onSelected: (_) { setState(() => _size = s); _calc(); })]),
        const SizedBox(height: 12),
        TextFormField(key: const Key('weight'), controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: ref.t('express.weight')), onChanged: (_) => _calc(),
            validator: (s) => (double.tryParse((s ?? '').replaceAll(',', '.')) ?? 0) > 0 ? null : ref.t('express.weight')),
        const SizedBox(height: 12),
        TextFormField(key: const Key('desc'), controller: _desc, maxLength: 300, decoration: InputDecoration(labelText: ref.t('express.description')), validator: (s) => (s == null || s.trim().isEmpty) ? ref.t('express.description') : null),
        Text(ref.t('express.sender'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextFormField(key: const Key('s-name'), controller: _sName, decoration: InputDecoration(labelText: ref.t('express.name')), validator: v(ref, Validators.name)),
        const SizedBox(height: 8),
        TextFormField(key: const Key('s-phone'), controller: _sPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('express.phone')), validator: v(ref, Validators.phone)),
        const SizedBox(height: 16),
        Text(ref.t('express.recipient'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextFormField(key: const Key('r-name'), controller: _rName, decoration: InputDecoration(labelText: ref.t('express.name')), validator: v(ref, Validators.name)),
        const SizedBox(height: 8),
        TextFormField(key: const Key('r-phone'), controller: _rPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('express.phone')), validator: v(ref, Validators.phone)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [for (final m in const [('CASH', 'pay.cash'), ('WALLET', 'pay.wallet')]) ChoiceChip(key: Key('dpay-${m.$1}'), label: Text(ref.t(m.$2)), selected: _payment == m.$1, selectedColor: JolayColors.yellow, onSelected: (_) => setState(() => _payment = m.$1))]),
        const SizedBox(height: 16),
        if (_quoting) const LinearProgressIndicator(),
        if (fee != null) JolayCard(key: const Key('quote'), child: Column(children: [
          Row(children: [Expanded(child: Text(ref.t('express.fee'), style: const TextStyle(fontWeight: FontWeight.w800))), Text(formatKzt(fee['total']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22))]),
          Text('${formatKm(_quote!['distanceM'] as int)} ${ref.t('ride.km')} · ${ref.t('ride.routeEstimated')}', style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)),
          if (_quote!['courierAvailable'] != true) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ref.t('express.noCourier'), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary))),
        ])),
        const SizedBox(height: 16),
        JolayButton(key: const Key('express-order'), label: ref.t('express.order'), busy: _busy, onPressed: _order),
      ])),
    );
  }
}

class ExpressTrackScreen extends ConsumerStatefulWidget {
  final String id;
  const ExpressTrackScreen({super.key, required this.id});
  @override
  ConsumerState<ExpressTrackScreen> createState() => _TrackState();
}

class _TrackState extends ConsumerState<ExpressTrackScreen> {
  Map<String, dynamic>? _d;
  bool _failed = false, _rated = false, _busy = false;
  int _stars = 0;
  Timer? _poll;
  LatLng? _live;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) { final s = _d?['status']; if (s != 'DELIVERED' && s != 'CANCELLED' && s != 'EXPIRED') _fetch(); });
  }
  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      final j = await ref.read(apiProvider).get('/deliveries/${widget.id}') as Map<String, dynamic>;
      if (mounted) setState(() { _d = j; _failed = false; _rated = j['rating'] != null; _stars = (j['rating'] as int?) ?? _stars; });
    } catch (_) { if (mounted && _d == null) setState(() => _failed = true); }
  }

  Future<void> _cancel() async {
    try { await ref.read(apiProvider).post('/deliveries/${widget.id}/cancel', body: {'reason': 'customer_cancelled'}); await _fetch(); } catch (e) { if (mounted) showError(context, ref, e); }
  }

  Future<void> _rate() async {
    setState(() => _busy = true);
    try { await ref.read(apiProvider).post('/deliveries/${widget.id}/rating', body: {'stars': _stars}); if (mounted) setState(() => _rated = true); } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final ev = next.value;
      if (ev == null) return;
      if (ev.type == 'DELIVERY_COURIER_LOCATION' && ev.data['deliveryId'] == widget.id) { setState(() => _live = LatLng((ev.data['lat'] as num).toDouble(), (ev.data['lng'] as num).toDouble())); } else { _fetch(); }
    });
    final d = _d;
    if (d == null) return Scaffold(appBar: AppBar(), body: _failed ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _fetch) : const Center(child: CircularProgressIndicator()));
    final status = d['status'] as String;
    final courier = d['courier'] as Map<String, dynamic>?;
    final pickup = LatLng((d['pickup']['lat'] as num).toDouble(), (d['pickup']['lng'] as num).toDouble()), drop = LatLng((d['dropoff']['lat'] as num).toDouble(), (d['dropoff']['lng'] as num).toDouble());
    final cl = courier?['lat'];
    final courierPos = _live ?? (cl is num ? LatLng(cl.toDouble(), (courier!['lng'] as num).toDouble()) : null);
    final active = status == 'SEARCHING_COURIER' || status == 'COURIER_ASSIGNED' || status == 'PICKED_UP';
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('express.title')), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/home'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(ref.t('express.status.$status'), key: const Key('express-status'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('${ref.t('express.tracking')}: ${d['trackingNumber']}', style: const TextStyle(color: JolayColors.textSecondary)),
        if (active) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        const SizedBox(height: 16),
        SizedBox(height: 200, child: ClipRRect(borderRadius: BorderRadius.circular(JolayRadius.md), child: JolayMap(center: courierPos ?? pickup, zoom: 13, markers: [pin(pickup, Icons.inventory_2, JolayColors.success), pin(drop, Icons.flag, JolayColors.error), if (courierPos != null) pin(courierPos, Icons.two_wheeler, JolayColors.midnight)], route: [pickup, drop]))),
        const SizedBox(height: 16),
        if (d['handoverCode'] != null) JolayCard(key: const Key('handover-code'), child: Column(children: [
          Text(ref.t('express.code'), style: const TextStyle(color: JolayColors.textSecondary)),
          Text(d['handoverCode'] as String, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8)),
          Text(ref.t('express.codeHint'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)),
        ])),
        const SizedBox(height: 12),
        JolayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.success), const SizedBox(width: 8), Expanded(child: Text(d['pickupAddress'] as String))]),
          const SizedBox(height: 6),
          Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.error), const SizedBox(width: 8), Expanded(child: Text('${d['dropoffAddress']} · ${d['recipientName']}'))]),
          const Divider(),
          Row(children: [Expanded(child: Text(ref.t('express.fee'), style: const TextStyle(color: JolayColors.textSecondary))), Text(formatKzt(d['fee']), style: const TextStyle(fontWeight: FontWeight.w800))]),
          Row(children: [Expanded(child: Text(ref.t('ride.payment'), style: const TextStyle(color: JolayColors.textSecondary))), Text(d['paymentMethod'] == 'CASH' ? ref.t('pay.cash') : ref.t('pay.wallet')), const SizedBox(width: 8), if (d['paymentStatus'] == 'PAID') Text(ref.t('ride.paid'), style: const TextStyle(color: JolayColors.success, fontWeight: FontWeight.w700)) else if (d['paymentStatus'] == 'FAILED') Text(ref.t('ride.paymentFailed'), style: const TextStyle(color: JolayColors.error))]),
        ])),
        if (courier != null) ...[
          const SizedBox(height: 12),
          JolayCard(child: Row(children: [const CircleAvatar(child: Icon(Icons.person)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(courier['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), Text('★ ${courier['rating']} · ${courier['vehicle']}', style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary))])),
            if ((courier['phone'] as String).isNotEmpty) IconButton.outlined(onPressed: () => launchUrl(Uri.parse('tel:${courier['phone']}')), icon: const Icon(Icons.call))])),
        ],
        const SizedBox(height: 16),
        if (status == 'SEARCHING_COURIER' || status == 'COURIER_ASSIGNED') OutlinedButton(key: const Key('express-cancel'), onPressed: _cancel, style: OutlinedButton.styleFrom(foregroundColor: JolayColors.error), child: Text(ref.t('express.cancel'))),
        if (status == 'DELIVERED') ...[
          Center(child: Text(_rated ? ref.t('ride.thanks') : ref.t('express.rate'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(key: Key('dstar-$i'), iconSize: 36, onPressed: _rated ? null : () => setState(() => _stars = i), icon: Icon(i <= _stars ? Icons.star : Icons.star_border, color: JolayColors.yellow))]),
          if (!_rated) JolayButton(key: const Key('express-rate'), label: ref.t('btn.send'), busy: _busy, onPressed: _stars == 0 ? null : _rate),
        ],
      ]),
    );
  }
}
