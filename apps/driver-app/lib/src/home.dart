import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth.dart';
import 'data.dart';
import 'payouts.dart';

const tileUrl = String.fromEnvironment('TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

/// Decides what the driver sees based on server-side state: no profile -> vehicle registration,
/// PENDING/REJECTED/SUSPENDED -> status screen, APPROVED -> working app.
class DriverGate extends ConsumerWidget {
  const DriverGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(driverMeProvider);
    ref.listen(eventsProvider, (_, ev) { if (ev.value?.type == 'VERIFICATION_STATUS') ref.invalidate(driverMeProvider); });
    return me.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(driverMeProvider))),
      data: (d) {
        if (d == null) return const VehicleRegistration();
        if (d['verification'] != 'APPROVED') return VerificationStatus(me: d);
        return const DriverShell();
      },
    );
  }
}

class VehicleRegistration extends ConsumerStatefulWidget {
  const VehicleRegistration({super.key});
  @override
  ConsumerState<VehicleRegistration> createState() => _RegState();
}

class _RegState extends ConsumerState<VehicleRegistration> {
  final _form = GlobalKey<FormState>();
  final _brand = TextEditingController(), _model = TextEditingController(), _year = TextEditingController(), _color = TextEditingController(), _plate = TextEditingController();
  String _cat = 'ECONOMY';
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/drivers/register', body: {'vehicle': {'brand': _brand.text.trim(), 'model': _model.text.trim(), 'year': int.parse(_year.text), 'color': _color.text.trim(), 'plate': _plate.text.trim(), 'category': _cat}});
      ref.invalidate(driverMeProvider);
    } catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  String? _req(String? s) => (s == null || s.trim().isEmpty) ? ref.read(localeProvider).languageCode == 'en' ? 'Required' : tr(ref.read(localeProvider), 'val.name') : null;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(ref.t('driver.regTitle')), actions: const [LangRow(), SizedBox(width: 8)]),
        body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(key: const Key('v-brand'), controller: _brand, decoration: InputDecoration(labelText: ref.t('driver.brand')), validator: _req), const SizedBox(height: 12),
          TextFormField(controller: _model, decoration: InputDecoration(labelText: ref.t('driver.model')), validator: _req), const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _year, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ref.t('driver.year')), validator: (s) { final y = int.tryParse(s ?? ''); return (y == null || y < 1990 || y > DateTime.now().year + 1) ? ref.t('val.name') : null; })),
            const SizedBox(width: 12), Expanded(child: TextFormField(controller: _color, decoration: InputDecoration(labelText: ref.t('driver.color')), validator: _req)),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _plate, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: ref.t('driver.plate')), validator: (s) => RegExp(r'^[A-Za-z0-9 -]{4,15}$').hasMatch(s ?? '') ? null : ref.t('val.name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _cat, decoration: InputDecoration(labelText: ref.t('driver.category')), items: [for (final c in ['ECONOMY', 'COMFORT', 'BUSINESS', 'XL']) DropdownMenuItem(value: c, child: Text(c))], onChanged: (v) => setState(() => _cat = v ?? 'ECONOMY')),
          const SizedBox(height: 24),
          JolayButton(label: ref.t('btn.continue'), busy: _busy, onPressed: _submit),
        ])),
      );
}

class VerificationStatus extends ConsumerStatefulWidget {
  final Map<String, dynamic> me;
  const VerificationStatus({super.key, required this.me});
  @override
  ConsumerState<VerificationStatus> createState() => _VerifState();
}

class _VerifState extends ConsumerState<VerificationStatus> {
  List<Map<String, dynamic>> _docs = [];
  bool _busy = false;
  static const _types = ['ID_CARD', 'DRIVER_LICENSE', 'VEHICLE_REGISTRATION', 'INSURANCE', 'PHOTO'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final j = await ref.read(apiProvider).get('/drivers/documents') as List; if (mounted) setState(() => _docs = j.cast<Map<String, dynamic>>()); } catch (_) {}
  }

  Future<void> _upload(String type) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({'type': type, 'file': await MultipartFile.fromFile(f.path, filename: f.name)});
      await ref.read(apiProvider).post('/drivers/documents', body: form);
      await _load();
    } catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.me['verification'] as String;
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('driver.docs')), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(driverMeProvider)), IconButton(icon: const Icon(Icons.logout), onPressed: () => ref.read(authProvider.notifier).logout())]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        JolayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(v == 'PENDING' ? Icons.hourglass_top : Icons.block, color: v == 'PENDING' ? JolayColors.yellow : JolayColors.error), const SizedBox(width: 10), Text(v == 'PENDING' ? ref.t('driver.pending') : ref.t('driver.rejected'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 8),
          Text(v == 'PENDING' ? ref.t('driver.pendingBody') : (widget.me['rejection_reason'] ?? '').toString(), style: const TextStyle(color: JolayColors.textSecondary)),
        ])),
        const SizedBox(height: 16),
        for (final t in _types) ListTile(
          leading: Icon(_docs.any((d) => d['type'] == t) ? Icons.check_circle : Icons.upload_file, color: _docs.any((d) => d['type'] == t) ? JolayColors.success : null),
          title: Text(t.replaceAll('_', ' ')), subtitle: Text(_docs.where((d) => d['type'] == t).map((d) => d['status']).join(', ')),
          trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_photo_alternate_outlined), onTap: _busy ? null : () => _upload(t)),
      ]),
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
        body: IndexedStack(index: _i, children: const [DriverHome(), OrdersTab(), EarningsTab(), DriverProfile()]),
        bottomNavigationBar: NavigationBar(selectedIndex: _i, onDestinationSelected: (i) => setState(() => _i = i), destinations: [
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map), label: ref.t('nav.home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: ref.t('nav.orders')),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments), label: ref.t('nav.earnings')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: ref.t('nav.profile')),
        ]),
      );
}

// ---------------- Home: online toggle, offers, active trip ----------------
class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});
  @override
  ConsumerState<DriverHome> createState() => _HomeState();
}

class _HomeState extends ConsumerState<DriverHome> {
  bool _online = false, _busy = false;
  Map<String, dynamic>? _offer, _ride, _dOffer, _delivery;
  Timer? _poll, _tick;
  int _left = 0;
  LatLng? _pos;

  @override
  void initState() {
    super.initState();
    final me = ref.read(driverMeProvider).value;
    final a = me?['availability'];
    _online = a == 'ONLINE' || a == 'OFFERED' || a == 'BUSY';
    if (_online) _startWork(resume: true);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if ((_offer != null || _dOffer != null) && mounted) { setState(() => _left = _left > 0 ? _left - 1 : 0); if (_left == 0) _refresh(); } });
    _refresh();
  }

  @override
  void dispose() { _poll?.cancel(); _tick?.cancel(); super.dispose(); }

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
          final o = await api.get('/drivers/offers'); offer = o is Map<String, dynamic> ? o : null;
          final dof = await api.get('/drivers/delivery-offers'); dOffer = dof is Map<String, dynamic> ? dof : null;
        }
      }
      final pos = ref.read(locationPublisherProvider).last;
      if (!mounted) return;
      setState(() {
        _ride = ride is Map<String, dynamic> ? ride : null;
        _offer = offer; _dOffer = dOffer; _delivery = delivery;
        final live = offer ?? dOffer;
        if (live != null) _left = (live['seconds_left'] as num).toInt();
        if (pos != null) _pos = LatLng(pos.latitude, pos.longitude);
      });
    } catch (_) {}
  }

  Future<void> _startWork({bool resume = false}) async {
    final pub = ref.read(locationPublisherProvider);
    if (!await pub.ensurePermission()) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.t('loc.denied')))); if (!resume) setState(() => _online = false); return; }
    await pub.start();
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on && !await ref.read(locationPublisherProvider).ensurePermission()) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.t('loc.denied')))); return; }
      await ref.read(apiProvider).put('/drivers/availability', body: {'online': on});
      if (on) { await _startWork(); } else { await ref.read(locationPublisherProvider).stop(); }
      if (mounted) setState(() { _online = on; if (!on) _offer = null; });
    } catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _act(String path) async {
    setState(() => _busy = true);
    try { await ref.read(apiProvider).post(path); await _refresh(); ref.invalidate(driverMeProvider); }
    catch (e) { if (mounted) toast(context, ref, e); await _refresh(); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(eventsProvider, (_, ev) { if (ev.value != null) _refresh(); });
    final me = ref.watch(driverMeProvider).value;
    final center = _pos ?? const LatLng(43.2389, 76.8897);
    return Stack(children: [
      Positioned.fill(child: FlutterMap(options: MapOptions(initialCenter: center, initialZoom: 14, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)), children: [
        TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'kz.jolay.driver'),
        MarkerLayer(markers: [
          if (_pos != null) Marker(point: _pos!, width: 40, height: 40, child: const Icon(Icons.navigation, color: JolayColors.midnight, size: 34)),
          if (_ride != null) Marker(point: LatLng((_ride!['pickup']['lat'] as num).toDouble(), (_ride!['pickup']['lng'] as num).toDouble()), width: 40, height: 40, child: const Icon(Icons.location_on, color: JolayColors.success, size: 38)),
          if (_ride != null) Marker(point: LatLng((_ride!['dropoff']['lat'] as num).toDouble(), (_ride!['dropoff']['lng'] as num).toDouble()), width: 40, height: 40, child: const Icon(Icons.flag, color: JolayColors.error, size: 36)),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors (dev tiles)')]),
      ])),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)), child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _online ? JolayColors.success : JolayColors.textSecondary, shape: BoxShape.circle)), const SizedBox(width: 10),
          Expanded(child: Text(_online ? ref.t('driver.online') : ref.t('driver.offline'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
          Text('★ ${me?['rating_avg'] ?? '5.0'}  ·  ${formatKzt(me?['todayEarnings'])}', style: const TextStyle(color: JolayColors.yellow, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Switch(key: const Key('online-switch'), value: _online, onChanged: (_busy || _ride != null || _delivery != null) ? null : _toggle, activeTrackColor: JolayColors.yellow, activeThumbColor: JolayColors.midnight),
        ])),
      ]))),
      if (_offer != null && _ride == null) Align(alignment: Alignment.bottomCenter, child: _OfferCard(offer: _offer!, left: _left, busy: _busy,
        onAccept: () => _act('/drivers/offers/${_offer!['offer_id']}/accept'), onDecline: () => _act('/drivers/offers/${_offer!['offer_id']}/decline'))),
      if (_ride != null) Align(alignment: Alignment.bottomCenter, child: _ActiveTrip(ride: _ride!, busy: _busy, onAct: _act)),
      if (_dOffer != null && _ride == null && _delivery == null) Align(alignment: Alignment.bottomCenter, child: _DeliveryOfferCard(offer: _dOffer!, left: _left, busy: _busy,
        onAccept: () => _act('/drivers/delivery-offers/${_dOffer!['offer_id']}/accept'), onDecline: () => _act('/drivers/delivery-offers/${_dOffer!['offer_id']}/decline'))),
      if (_delivery != null) Align(alignment: Alignment.bottomCenter, child: ActiveDeliveryCard(delivery: _delivery!, busy: _busy, onAct: _act, onRefresh: _refresh)),
    ]);
  }
}

class _OfferCard extends ConsumerWidget {
  final Map<String, dynamic> offer;
  final int left;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const _OfferCard({required this.offer, required this.left, required this.busy, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const Key('offer-card'),
        margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(ref.t('driver.newOrder'), style: const TextStyle(color: JolayColors.yellow, fontWeight: FontWeight.w900, fontSize: 18))), Text('${left}s', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: (left / 15).clamp(0, 1).toDouble(), color: JolayColors.yellow, backgroundColor: const Color(0xFF333333)),
          const SizedBox(height: 12),
          Text(offer['dropoff_address'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            _stat(ref.t('driver.pickupDistance'), '${((offer['pickup_distance_m'] as num) / 1000).toStringAsFixed(1)} ${ref.t('ride.km')}'),
            _stat(ref.t('driver.expected'), formatKzt(offer['expected_earnings'])),
            _stat(ref.t('ride.payment'), switch (offer['payment_method']) { 'CASH' => ref.t('pay.cash'), 'CARD' => ref.t('pay.card'), _ => ref.t('pay.wallet') }),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(key: const Key('decline'), onPressed: busy ? null : onDecline, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), child: Text(ref.t('driver.decline')))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(key: const Key('accept'), onPressed: busy ? null : onAccept, child: Text(ref.t('driver.accept')))),
          ]),
        ])),
      );
  Widget _stat(String k, String v) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(color: Colors.white54, fontSize: 11)), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]));
}

/// SOS: notifies JOLAY support (ride + position are attached by the backend) and offers to dial 112. It does not replace emergency services.
void _sos(BuildContext context, WidgetRef ref) => showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: Text(ref.t('sos.title')),
      content: Text(ref.t('sos.body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(ref.t('btn.cancel'))),
        OutlinedButton(key: const Key('sos-notify'), onPressed: () async {
          Navigator.pop(c);
          final pos = ref.read(locationPublisherProvider).last;
          try { await reportSos(ref.read(apiProvider), lat: pos?.latitude, lng: pos?.longitude); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.t('sos.sent')))); }
          catch (e) { if (context.mounted) toast(context, ref, e); }
        }, style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)), child: Text(ref.t('sos.notify'))),
        FilledButton(onPressed: () { Navigator.pop(c); launchUrl(Uri.parse('tel:112')); }, style: FilledButton.styleFrom(backgroundColor: JolayColors.error, foregroundColor: Colors.white, minimumSize: const Size(120, 44)), child: Text(ref.t('sos.call'))),
      ],
    ));

class _DeliveryOfferCard extends ConsumerWidget {
  final Map<String, dynamic> offer;
  final int left;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const _DeliveryOfferCard({required this.offer, required this.left, required this.busy, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const Key('delivery-offer-card'),
        margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.inventory_2, color: JolayColors.yellow), const SizedBox(width: 8), Expanded(child: Text(ref.t('delivery.newOrder'), style: const TextStyle(color: JolayColors.yellow, fontWeight: FontWeight.w900, fontSize: 18))), Text('${left}s', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: (left / 15).clamp(0, 1).toDouble(), color: JolayColors.yellow, backgroundColor: const Color(0xFF333333)),
          const SizedBox(height: 12),
          Text('${offer['pickup_address']} → ${offer['dropoff_address']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Text('${offer['parcel_description']} · ${offer['weight_kg']} kg', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ref.t('driver.pickupDistance'), style: const TextStyle(color: Colors.white54, fontSize: 11)), Text('${((offer['pickup_distance_m'] as num) / 1000).toStringAsFixed(1)} ${ref.t('ride.km')}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ref.t('driver.expected'), style: const TextStyle(color: Colors.white54, fontSize: 11)), Text(formatKzt(offer['expected_earnings']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(key: const Key('d-decline'), onPressed: busy ? null : onDecline, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), child: Text(ref.t('driver.decline')))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(key: const Key('d-accept'), onPressed: busy ? null : onAccept, child: Text(ref.t('driver.accept')))),
          ]),
        ])),
      );
}

/// Active parcel delivery: pick up at the sender, then hand over to the recipient with their 4-digit code.
class ActiveDeliveryCard extends ConsumerWidget {
  final Map<String, dynamic> delivery;
  final bool busy;
  final Future<void> Function(String path) onAct;
  final Future<void> Function() onRefresh;
  const ActiveDeliveryCard({super.key, required this.delivery, required this.busy, required this.onAct, required this.onRefresh});

  Future<void> _deliver(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: Text(ref.t('delivery.deliver')),
      content: TextField(key: const Key('code-field'), controller: ctrl, keyboardType: TextInputType.number, maxLength: 4, autofocus: true, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w800), decoration: InputDecoration(labelText: ref.t('delivery.enterCode'), counterText: '')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(ref.t('btn.cancel'))), FilledButton(key: const Key('code-submit'), onPressed: () => Navigator.pop(c, ctrl.text), style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('btn.continue')))],
    ));
    if (code == null || !RegExp(r'^\d{4}$').hasMatch(code)) return;
    try {
      await ref.read(apiProvider).post('/drivers/deliveries/${delivery['id']}/deliver', body: {'code': code});
      await onRefresh();
    } catch (e) { if (context.mounted) toast(context, ref, e); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = delivery['id'];
    final picked = delivery['status'] == 'PICKED_UP';
    final target = picked ? delivery['dropoff'] : delivery['pickup'];
    final phone = picked ? delivery['recipientPhone'] : delivery['senderPhone'];
    return Container(
      key: const Key('active-delivery'),
      margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(JolayRadius.lg), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)]),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.inventory_2_outlined), const SizedBox(width: 8), Expanded(child: Text('${ref.t('delivery.parcel')} · ${delivery['trackingNumber']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), Text(formatKzt(delivery['courierEarnings']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))]),
        const SizedBox(height: 6),
        Text('${picked ? delivery['dropoffAddress'] : delivery['pickupAddress']} · ${picked ? delivery['recipientName'] : delivery['senderName']}'),
        Text('${delivery['parcelDescription']} · ${delivery['weightKg']} kg', style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12)),
        if (delivery['cashToCollect'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Container(key: const Key('cash-to-collect'), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: JolayColors.yellow, borderRadius: BorderRadius.circular(10)), child: Row(children: [const Icon(Icons.payments_outlined), const SizedBox(width: 8), Expanded(child: Text(ref.t('delivery.collectCash'), style: const TextStyle(fontWeight: FontWeight.w700))), Text(formatKzt(delivery['cashToCollect']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('geo:${target['lat']},${target['lng']}?q=${target['lat']},${target['lng']}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.navigation_outlined), label: Text(ref.t('nav.home')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)))),
          if (phone != null) ...[const SizedBox(width: 8), IconButton.outlined(onPressed: () => launchUrl(Uri.parse('tel:$phone')), icon: const Icon(Icons.call))],
        ]),
        const SizedBox(height: 10),
        if (!picked) JolayButton(key: const Key('picked-up'), label: ref.t('delivery.pickedUp'), busy: busy, onPressed: () => onAct('/drivers/deliveries/$id/picked-up'))
        else JolayButton(key: const Key('deliver'), label: ref.t('delivery.deliver'), busy: busy, onPressed: () => _deliver(context, ref)),
        if (!picked) TextButton(onPressed: busy ? null : () => onAct('/drivers/deliveries/$id/cancel'), child: Text(ref.t('delivery.handBack'), style: const TextStyle(color: JolayColors.error))),
      ])),
    );
  }
}

class _ActiveTrip extends ConsumerWidget {
  final Map<String, dynamic> ride;
  final bool busy;
  final Future<void> Function(String path) onAct;
  const _ActiveTrip({required this.ride, required this.busy, required this.onAct});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ride['id'];
    final st = ride['status'] as String;
    final (label, path) = switch (st) {
      'DRIVER_ASSIGNED' => (ref.t('driver.enRoute'), '/drivers/rides/$id/en-route'),
      'DRIVER_ARRIVING' => (ref.t('driver.imHere'), '/drivers/rides/$id/arrived'),
      'DRIVER_ARRIVED' => (ref.t('driver.start'), '/drivers/rides/$id/start'),
      _ => (ref.t('driver.complete'), '/drivers/rides/$id/complete'),
    };
    final toPickup = st == 'DRIVER_ASSIGNED' || st == 'DRIVER_ARRIVING' || st == 'DRIVER_ARRIVED';
    final target = toPickup ? ride['pickup'] : ride['dropoff'];
    return Container(
      key: const Key('active-trip'),
      margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(JolayRadius.lg), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)]),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ride['customerName']?.toString() ?? ref.t('driver.passenger'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
          Text(formatKzt(ride['estimatedFare']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
        const SizedBox(height: 8),
        Row(children: [Icon(toPickup ? Icons.circle : Icons.flag, size: 12, color: toPickup ? JolayColors.success : JolayColors.error), const SizedBox(width: 8), Expanded(child: Text((toPickup ? ride['pickupAddress'] : ride['dropoffAddress']).toString()))]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const Key('navigate'), onPressed: () => launchUrl(Uri.parse('geo:${target['lat']},${target['lng']}?q=${target['lat']},${target['lng']}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.navigation_outlined), label: Text(ref.t('nav.home')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)))),
          if (ride['customerPhone'] != null) ...[const SizedBox(width: 8), IconButton.outlined(onPressed: () => launchUrl(Uri.parse('tel:${ride['customerPhone']}')), icon: const Icon(Icons.call))],
          const SizedBox(width: 8),
          IconButton.filled(key: const Key('sos'), onPressed: () => _sos(context, ref), icon: const Icon(Icons.warning_amber_rounded), style: IconButton.styleFrom(backgroundColor: JolayColors.error, foregroundColor: Colors.white)),
        ]),
        const SizedBox(height: 10),
        JolayButton(key: const Key('stage-button'), label: label, busy: busy, onPressed: () => onAct(path)),
        if (st != 'IN_PROGRESS') TextButton(onPressed: busy ? null : () => onAct('/drivers/rides/$id/cancel'), child: Text(ref.t('ride.cancel'), style: const TextStyle(color: JolayColors.error))),
      ])),
    );
  }
}

// ---------------- Orders / Earnings / Profile ----------------
class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(historyProvider);
    return SafeArea(child: h.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(historyProvider)),
      data: (l) => RefreshIndicator(onRefresh: () async => ref.invalidate(historyProvider), child: l.isEmpty ? ListView(children: [const SizedBox(height: 120), Center(child: Text(ref.t('activity.empty')))]) : ListView.separated(padding: const EdgeInsets.all(16), itemCount: l.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) => JolayCard(child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(formatDateTime(l[i]['createdAt']?.toString()), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)), Text('${l[i]['pickupAddress']} → ${l[i]['dropoffAddress']}', maxLines: 2, overflow: TextOverflow.ellipsis)])),
        Text(formatKzt(l[i]['finalFare']), style: const TextStyle(fontWeight: FontWeight.w900)),
      ])))),
    ));
  }
}

class EarningsTab extends ConsumerStatefulWidget {
  const EarningsTab({super.key});
  @override
  ConsumerState<EarningsTab> createState() => _EarnState();
}

class _EarnState extends ConsumerState<EarningsTab> {
  String _p = 'today';
  @override
  Widget build(BuildContext context) {
    final e = ref.watch(earningsProvider(_p));
    final w = ref.watch(walletProvider);
    return SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      Text(ref.t('nav.earnings'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SegmentedButton<String>(segments: [ButtonSegment(value: 'today', label: Text(ref.t('driver.today'))), ButtonSegment(value: 'week', label: Text(ref.t('driver.week'))), ButtonSegment(value: 'month', label: Text(ref.t('driver.month')))], selected: {_p}, onSelectionChanged: (s) => setState(() => _p = s.first)),
      const SizedBox(height: 16),
      e.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(earningsProvider(_p))),
        data: (d) => Column(children: [
          Container(padding: const EdgeInsets.all(22), width: double.infinity, decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ref.t('driver.net'), style: const TextStyle(color: Colors.white70)), Text(formatKzt(d['net']), key: const Key('net'), style: const TextStyle(color: JolayColors.yellow, fontSize: 36, fontWeight: FontWeight.w900)),
          ])),
          const SizedBox(height: 12),
          JolayCard(child: Column(children: [_r(ref.t('driver.trips'), '${d['trips']}'), _r(ref.t('driver.gross'), formatKzt(d['gross'])), _r(ref.t('driver.commission'), formatKzt(d['commission']))])),
        ]),
      ),
      const SizedBox(height: 12),
      w.maybeWhen(data: (d) => JolayCard(child: _r(ref.t('wallet.balance'), formatKzt(d['balance']))), orElse: () => const SizedBox.shrink()),
    ]));
  }
  Widget _r(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: JolayColors.textSecondary))), Text(v, style: const TextStyle(fontWeight: FontWeight.w800))]));
}

class DriverProfile extends ConsumerWidget {
  const DriverProfile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    final me = ref.watch(driverMeProvider).value;
    final v = me?['vehicle'] as Map<String, dynamic>?;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      Text(ref.t('nav.profile'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(height: 12),
      JolayCard(child: Row(children: [CircleAvatar(radius: 28, backgroundColor: JolayColors.midnight, child: Text((u?.fullName.isNotEmpty ?? false) ? u!.fullName[0] : '?', style: const TextStyle(color: JolayColors.yellow, fontSize: 22, fontWeight: FontWeight.w800))), const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(u?.phone ?? '', style: const TextStyle(color: JolayColors.textSecondary)), Text('★ ${me?['rating_avg'] ?? ''} (${me?['rating_count'] ?? 0})')]))])),
      if (v != null) ...[const SizedBox(height: 12), JolayCard(child: Row(children: [const Icon(Icons.directions_car), const SizedBox(width: 12), Expanded(child: Text('${v['brand']} ${v['model']} ${v['year']} · ${v['color']}')), Text(v['plate'].toString(), style: const TextStyle(fontWeight: FontWeight.w900))]))],
      const SizedBox(height: 12),
      JolayCard(padding: EdgeInsets.zero, child: Column(children: [
        ListTile(leading: const Icon(Icons.language), title: Text(ref.t('profile.language')), trailing: const LangRow()),
        SwitchListTile(key: const Key('accept-deliveries'), secondary: const Icon(Icons.inventory_2_outlined), title: Text(ref.t('delivery.accept')), value: me?['accepts_delivery'] == true,
          onChanged: (v) async { try { await ref.read(apiProvider).put('/drivers/delivery', body: {'enabled': v}); ref.invalidate(driverMeProvider); } catch (e) { if (context.mounted) toast(context, ref, e); } }),
        ListTile(key: const Key('open-payouts'), leading: const Icon(Icons.account_balance_outlined), title: Text(ref.t('payout.title')), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PayoutsScreen()))),
        ListTile(leading: const Icon(Icons.health_and_safety_outlined), title: Text(ref.t('driver.safety')), subtitle: const Text('112'), onTap: () => launchUrl(Uri.parse('tel:112'))),
      ])),
      const SizedBox(height: 16),
      JolayButton(label: ref.t('btn.logout'), secondary: true, onPressed: () async { await ref.read(locationPublisherProvider).stop(); await ref.read(authProvider.notifier).logout(); }),
    ]));
  }
}
