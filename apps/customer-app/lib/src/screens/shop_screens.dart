import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'express_screens.dart' show pickPlace;

/// Cart state: line items for one store at a time.
class CartLine {
  final String productId, name;
  final String price;
  final int qty;
  const CartLine(this.productId, this.name, this.price, this.qty);
  CartLine withQty(int q) => CartLine(productId, name, price, q);
}

class Cart {
  final String? storeId;
  final String storeName;
  final List<CartLine> lines;
  const Cart({this.storeId, this.storeName = '', this.lines = const []});
  int get count => lines.fold(0, (a, l) => a + l.qty);
  double get total => lines.fold(0.0, (a, l) => a + double.parse(l.price) * l.qty);   // display only: the server recomputes everything
}

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();
  void add(String storeId, String storeName, Map<String, dynamic> p) {
    var c = state;
    if (c.storeId != storeId) c = Cart(storeId: storeId, storeName: storeName);      // one store per order
    final i = c.lines.indexWhere((l) => l.productId == p['id']);
    final lines = [...c.lines];
    if (i >= 0) { lines[i] = lines[i].withQty(lines[i].qty + 1); } else { lines.add(CartLine(p['id'] as String, p['name'] as String, p['price'].toString(), 1)); }
    state = Cart(storeId: storeId, storeName: storeName, lines: lines);
  }
  void remove(String productId) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.productId == productId);
    if (i < 0) return;
    if (lines[i].qty > 1) { lines[i] = lines[i].withQty(lines[i].qty - 1); } else { lines.removeAt(i); }
    state = Cart(storeId: lines.isEmpty ? null : state.storeId, storeName: state.storeName, lines: lines);
  }
  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});
  @override
  ConsumerState<ShopsScreen> createState() => _ShopsState();
}

class _ShopsState extends ConsumerState<ShopsScreen> {
  String _cat = 'ALL';
  List<Map<String, dynamic>>? _stores;
  bool _failed = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _failed = false; _stores = null; });
    final here = ref.read(draftProvider).pickup ?? almatyCenter;
    try {
      final j = await ref.read(apiProvider).get('/stores', query: {'lat': here.lat, 'lng': here.lng, if (_cat != 'ALL') 'category': _cat}) as List;
      if (mounted) setState(() => _stores = j.cast<Map<String, dynamic>>());
    } catch (_) { if (mounted) setState(() => _failed = true); }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(_shopOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('shop.title'))),
      body: Column(children: [
        SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final c in const ['ALL', 'FOOD', 'GROCERY', 'PHARMACY', 'SHOP']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(key: Key('cat-$c'), label: Text(ref.t('shop.category.$c')), selected: _cat == c, selectedColor: JolayColors.yellow, onSelected: (_) { setState(() => _cat = c); _load(); })),
        ])),
        if ((orders.value ?? []).isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: JolayCard(key: const Key('ongoing-orders'), onTap: () => context.push('/shop-order/${orders.value!.first['id']}'), child: Row(children: [const Icon(Icons.receipt_long), const SizedBox(width: 10), Expanded(child: Text('${ref.t('shop.ongoing')}: ${orders.value!.length}', style: const TextStyle(fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right)]))),
        Expanded(child: _failed
            ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _load)
            : _stores == null ? const Center(child: CircularProgressIndicator())
            : _stores!.isEmpty ? Center(child: Text(ref.t('shop.none'), style: const TextStyle(color: JolayColors.textSecondary)))
            : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _stores!.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) {
                final s = _stores![i];
                return JolayCard(key: Key('store-${s['id']}'), onTap: () => context.push('/store/${s['id']}'), child: Row(children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: JolayColors.yellow, borderRadius: BorderRadius.circular(12)), child: Icon(switch (s['category']) { 'FOOD' => Icons.restaurant, 'GROCERY' => Icons.local_grocery_store, 'PHARMACY' => Icons.local_pharmacy, _ => Icons.storefront })),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text('${s['prep_minutes']} ${ref.t('shop.prep')} · ${formatKm(s['distance_m'] as int)} ${ref.t('ride.km')}', style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12))])),
                  const Icon(Icons.chevron_right),
                ]));
              })),
      ]),
    );
  }
}

final _shopOrdersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    ((await ref.read(apiProvider).get('/store-orders', query: {'tab': 'ongoing'})) as List).cast<Map<String, dynamic>>());

class StoreScreen extends ConsumerStatefulWidget {
  final String storeId;
  const StoreScreen({super.key, required this.storeId});
  @override
  ConsumerState<StoreScreen> createState() => _StoreState();
}

class _StoreState extends ConsumerState<StoreScreen> {
  Map<String, dynamic>? _menu;
  bool _failed = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _failed = false);
    try { final j = await ref.read(apiProvider).get('/stores/${widget.storeId}/menu') as Map<String, dynamic>; if (mounted) setState(() => _menu = j); } catch (_) { if (mounted) setState(() => _failed = true); }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final m = _menu;
    if (m == null) return Scaffold(appBar: AppBar(), body: _failed ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _load) : const Center(child: CircularProgressIndicator()));
    final products = (m['products'] as List).cast<Map<String, dynamic>>();
    final open = m['accepting_orders'] == true;
    final inCart = cart.storeId == widget.storeId;
    return Scaffold(
      appBar: AppBar(title: Text(m['name'] as String)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        if (!open) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(ref.t('shop.closed'), style: const TextStyle(color: JolayColors.error, fontWeight: FontWeight.w700))),
        Text(ref.t('shop.menu'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final p in products) Builder(builder: (_) {
          final q = inCart ? (cart.lines.where((l) => l.productId == p['id']).map((l) => l.qty).fold(0, (a, b) => a + b)) : 0;
          return ListTile(key: Key('product-${p['id']}'), contentPadding: EdgeInsets.zero, title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p['description'] ?? ''}${p['section'] != null ? ' · ${p['section']}' : ''}'.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(formatKzt(p['price']), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 8),
              if (q > 0) ...[IconButton(key: Key('minus-${p['id']}'), icon: const Icon(Icons.remove_circle_outline), onPressed: () => ref.read(cartProvider.notifier).remove(p['id'] as String)), Text('$q', style: const TextStyle(fontWeight: FontWeight.w800))],
              IconButton(key: Key('plus-${p['id']}'), icon: const Icon(Icons.add_circle, color: JolayColors.midnight), onPressed: open ? () => ref.read(cartProvider.notifier).add(widget.storeId, m['name'] as String, p) : null),
            ]));
        }),
      ]),
      bottomNavigationBar: inCart && cart.count > 0 ? SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: JolayButton(key: const Key('view-cart'), label: '${ref.t('shop.viewCart')} · ${cart.count} · ${formatKzt(cart.total)}', onPressed: () => context.push('/checkout')))) : null,
    );
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends ConsumerState<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _phone = TextEditingController(), _note = TextEditingController();
  Place? _address;
  String _pay = 'WALLET';
  Map<String, dynamic>? _quote;
  bool _busy = false, _quoting = false;
  late final String _idem = 'shop-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final u = ref.read(authProvider).user;
    _name.text = u?.fullName ?? ''; _phone.text = u?.phone ?? '+7 ';
    _address = ref.read(draftProvider).pickup;
    WidgetsBinding.instance.addPostFrameCallback((_) => _estimate());
  }

  Map<String, dynamic> _body() {
    final cart = ref.read(cartProvider);
    return {
      'storeId': cart.storeId, 'items': [for (final l in cart.lines) {'productId': l.productId, 'quantity': l.qty}],
      'dropoff': {'lat': _address!.lat, 'lng': _address!.lng}, 'address': _address!.address.isNotEmpty ? _address!.address : _address!.name,
      'recipientName': _name.text.trim(), 'recipientPhone': _phone.text.trim().isEmpty ? '+7' : Validators.phone(_phone.text) == null ? Validators.normalizePhone(_phone.text) : _phone.text.trim(), if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(), 'paymentMethod': _pay,
    };
  }

  Future<void> _estimate() async {
    if (_address == null) return;
    setState(() { _quoting = true; _quote = null; });
    try { final j = await ref.read(apiProvider).post('/store-orders/estimate', body: _body()) as Map<String, dynamic>; if (mounted) setState(() => _quote = j); }
    catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _quoting = false); }
  }

  Future<void> _place() async {
    if (_address == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final j = await ref.read(apiProvider).post('/store-orders', headers: {'Idempotency-Key': _idem}, body: _body()) as Map<String, dynamic>;
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(walletProvider);
      if (mounted) context.pushReplacement('/shop-order/${j['id']}');
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('shop.checkout'))),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(cart.storeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final l in cart.lines) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('${l.qty} × ${l.name}'), trailing: Text(formatKzt(double.parse(l.price) * l.qty))),
        const Divider(),
        JolayCard(key: const Key('address-card'), onTap: () async { final p = await pickPlace(context, ref); if (p != null) { setState(() => _address = p); _estimate(); } }, child: Row(children: [const Icon(Icons.place_outlined), const SizedBox(width: 10), Expanded(child: Text(_address == null ? ref.t('shop.address') : (_address!.name.isNotEmpty ? _address!.name : _address!.address)))])),
        const SizedBox(height: 12),
        TextFormField(controller: _name, decoration: InputDecoration(labelText: ref.t('shop.recipient')), validator: v(ref, Validators.name)),
        const SizedBox(height: 8),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('auth.phone')), validator: v(ref, Validators.phone)),
        const SizedBox(height: 8),
        TextFormField(controller: _note, maxLength: 300, decoration: InputDecoration(labelText: ref.t('shop.note'))),
        if (_quoting) const LinearProgressIndicator(),
        if (_quote != null) JolayCard(key: const Key('shop-quote'), child: Column(children: [
          _row(ref.t('shop.items'), formatKzt(_quote!['itemsTotal'])), _row(ref.t('shop.delivery'), formatKzt(_quote!['deliveryFee'])), const Divider(),
          Row(children: [Expanded(child: Text(ref.t('shop.total'), style: const TextStyle(fontWeight: FontWeight.w800))), Text(formatKzt(_quote!['total']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22))]),
        ])),
        const SizedBox(height: 8),
        Text(ref.t('shop.payWith'), style: const TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 8, children: [for (final m in const ['WALLET', 'CASH']) ChoiceChip(key: Key('pay-$m'), label: Text(ref.t(m == 'CASH' ? 'shop.payCash' : 'shop.payWallet')), selected: _pay == m, selectedColor: JolayColors.yellow, onSelected: (_) => setState(() => _pay = m))]),
        Text(ref.t(_pay == 'CASH' ? 'shop.cashNote' : 'shop.walletOnly'), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)),
        if (_pay == 'WALLET') Text(ref.t('shop.refundNote'), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary)),
        const SizedBox(height: 16),
        JolayButton(key: const Key('place-order'), label: ref.t('shop.place'), busy: _busy, onPressed: _quote == null ? null : _place),
      ])),
    );
  }

  Widget _row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: JolayColors.textSecondary))), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class ShopOrderScreen extends ConsumerStatefulWidget {
  final String id;
  const ShopOrderScreen({super.key, required this.id});
  @override
  ConsumerState<ShopOrderScreen> createState() => _ShopOrderState();
}

class _ShopOrderState extends ConsumerState<ShopOrderScreen> {
  Map<String, dynamic>? _o;
  bool _failed = false;
  Timer? _poll;
  @override
  void initState() { super.initState(); _fetch(); _poll = Timer.periodic(const Duration(seconds: 5), (_) { final s = _o?['status']; if (s == 'PLACED' || s == 'ACCEPTED' || s == 'READY') _fetch(); }); }
  @override
  void dispose() { _poll?.cancel(); super.dispose(); }
  Future<void> _fetch() async {
    try { final j = await ref.read(apiProvider).get('/store-orders/${widget.id}') as Map<String, dynamic>; if (mounted) setState(() { _o = j; _failed = false; }); } catch (_) { if (mounted && _o == null) setState(() => _failed = true); }
  }
  Future<void> _cancel() async { try { await ref.read(apiProvider).post('/store-orders/${widget.id}/cancel'); ref.invalidate(walletProvider); await _fetch(); } catch (e) { if (mounted) showError(context, ref, e); } }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) { if (next.value != null) _fetch(); });
    final o = _o;
    if (o == null) return Scaffold(appBar: AppBar(), body: _failed ? ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: _fetch) : const Center(child: CircularProgressIndicator()));
    final status = o['status'] as String;
    final d = o['delivery'] as Map<String, dynamic>?;
    final courier = d?['courier'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text('#${o['number']}'), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/home'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(ref.t('shop.status.$status'), key: const Key('shop-status'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        if (o['rejectReason'] != null) Text('${ref.t('shop.reject')}: ${o['rejectReason']}', style: const TextStyle(color: JolayColors.textSecondary)),
        const SizedBox(height: 4),
        Text(o['storeName'] as String, style: const TextStyle(color: JolayColors.textSecondary)),
        const SizedBox(height: 16),
        if (d?['handoverCode'] != null) JolayCard(key: const Key('shop-code'), child: Column(children: [
          Text(ref.t('express.code'), style: const TextStyle(color: JolayColors.textSecondary)),
          Text(d!['handoverCode'] as String, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8)),
          Text(ref.t('express.codeHint'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary))])),
        if (courier != null) ...[const SizedBox(height: 12), JolayCard(child: Row(children: [const CircleAvatar(child: Icon(Icons.two_wheeler)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(courier['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), Text(ref.t('express.status.${d!['status']}'), style: const TextStyle(fontSize: 12, color: JolayColors.textSecondary))])),
          if ((courier['phone'] as String).isNotEmpty) IconButton.outlined(onPressed: () => launchUrl(Uri.parse('tel:${courier['phone']}')), icon: const Icon(Icons.call))]))],
        const SizedBox(height: 12),
        JolayCard(child: Column(children: [
          for (final i in (o['items'] as List).cast<Map<String, dynamic>>()) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text('${i['quantity']} × ${i['name']}')), Text(formatKzt(double.parse(i['unit_price'].toString()) * (i['quantity'] as int)))])),
          const Divider(),
          Row(children: [Expanded(child: Text(ref.t('shop.delivery'), style: const TextStyle(color: JolayColors.textSecondary))), Text(formatKzt(o['deliveryFee']))]),
          Row(children: [Expanded(child: Text(ref.t('shop.total'), style: const TextStyle(fontWeight: FontWeight.w800))), Text(formatKzt(o['total']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]),
        ])),
        const SizedBox(height: 16),
        if (status == 'PLACED') OutlinedButton(key: const Key('shop-cancel'), onPressed: _cancel, style: OutlinedButton.styleFrom(foregroundColor: JolayColors.error), child: Text(ref.t('shop.cancel'))),
        const SizedBox(height: 8),
        JolayButton(label: ref.t('btn.done'), secondary: true, onPressed: () => context.go('/home')),
      ]),
    );
  }
}
