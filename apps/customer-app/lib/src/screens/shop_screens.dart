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
  double get total => lines.fold(
    0.0,
    (a, l) => a + double.parse(l.price) * l.qty,
  ); // display only: the server recomputes everything
}

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();
  void add(String storeId, String storeName, Map<String, dynamic> p) {
    var c = state;
    if (c.storeId != storeId) {
      c = Cart(storeId: storeId, storeName: storeName); // one store per order
    }
    final i = c.lines.indexWhere((l) => l.productId == p['id']);
    final lines = [...c.lines];
    if (i >= 0) {
      lines[i] = lines[i].withQty(lines[i].qty + 1);
    } else {
      lines.add(
        CartLine(
          p['id'] as String,
          p['name'] as String,
          p['price'].toString(),
          1,
        ),
      );
    }
    state = Cart(storeId: storeId, storeName: storeName, lines: lines);
  }

  void remove(String productId) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.productId == productId);
    if (i < 0) return;
    if (lines[i].qty > 1) {
      lines[i] = lines[i].withQty(lines[i].qty - 1);
    } else {
      lines.removeAt(i);
    }
    state = Cart(
      storeId: lines.isEmpty ? null : state.storeId,
      storeName: state.storeName,
      lines: lines,
    );
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

IconData _storeIcon(Object? category) => switch (category) {
  'FOOD' => Icons.restaurant_rounded,
  'GROCERY' => Icons.local_grocery_store_rounded,
  'PHARMACY' => Icons.local_pharmacy_rounded,
  _ => AppIcons.store,
};

/// Round +/- control used on product rows.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool filled;
  const _StepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: onTap == null
                    ? p.divider
                    : (filled ? p.accent : p.surface),
                shape: BoxShape.circle,
                border: Border.all(
                  color: filled ? Colors.transparent : p.border,
                ),
              ),
              child: Icon(
                icon,
                size: 20,
                color: onTap == null
                    ? p.textSecondary
                    : (filled ? p.onAccent : p.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _stores = null;
    });
    final here = ref.read(draftProvider).pickup ?? almatyCenter;
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .get(
                    '/stores',
                    query: {
                      'lat': here.lat,
                      'lng': here.lng,
                      if (_cat != 'ALL') 'category': _cat,
                    },
                  )
              as List;
      if (mounted) setState(() => _stores = j.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(_shopOrdersProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('shop.title'),
        backLabel: ref.t('common.back'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              children: [
                for (final c in const [
                  'ALL',
                  'FOOD',
                  'GROCERY',
                  'PHARMACY',
                  'SHOP',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('cat-$c'),
                      label: Text(ref.t('shop.category.$c')),
                      selected: _cat == c,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _cat = c);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if ((orders.value ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: AppCard(
                key: const Key('ongoing-orders'),
                variant: AppCardVariant.inverse,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: () =>
                    context.push('/shop-order/${orders.value!.first['id']}'),
                child: Row(
                  children: [
                    const Icon(AppIcons.activity, color: AppColors.yellow),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${ref.t('shop.ongoing')}: ${orders.value!.length}',
                        style: t.titleSmall?.copyWith(color: Colors.white),
                      ),
                    ),
                    const Icon(AppIcons.chevron, color: Colors.white70),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _failed
                ? ErrorState(
                    message: ref.t('common.offline'),
                    retryLabel: ref.t('btn.retry'),
                    onRetry: _load,
                  )
                : _stores == null
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: SkeletonList(count: 5),
                  )
                : _stores!.isEmpty
                ? EmptyState(icon: AppIcons.store, title: ref.t('shop.none'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: _stores!.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final s = _stores![i];
                      return AppCard(
                        key: Key('store-${s['id']}'),
                        onTap: () => context.push('/store/${s['id']}'),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: p.selected,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _storeIcon(s['category']),
                                size: 28,
                                color: p.isDark ? p.accent : AppColors.midnight,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['name'] as String,
                                    style: t.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        AppIcons.time,
                                        size: 14,
                                        color: p.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${s['prep_minutes']} ${ref.t('shop.prep')}',
                                        style: t.bodySmall,
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        AppIcons.pin,
                                        size: 14,
                                        color: p.textSecondary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${formatKm(s['distance_m'] as int)} ${ref.t('ride.km')}',
                                        style: t.bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(AppIcons.chevron, color: p.textSecondary),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

final _shopOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) async =>
          ((await ref
                      .read(apiProvider)
                      .get('/store-orders', query: {'tab': 'ongoing'}))
                  as List)
              .cast<Map<String, dynamic>>(),
    );

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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final j =
          await ref.read(apiProvider).get('/stores/${widget.storeId}/menu')
              as Map<String, dynamic>;
      if (mounted) setState(() => _menu = j);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final m = _menu;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (m == null) {
      return Scaffold(
        appBar: AppHeader(title: '', backLabel: ref.t('common.back')),
        body: _failed
            ? ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: _load,
              )
            : const Padding(
                padding: EdgeInsets.all(20),
                child: SkeletonList(count: 5),
              ),
      );
    }
    final products = (m['products'] as List).cast<Map<String, dynamic>>();
    final open = m['accepting_orders'] == true;
    final inCart = cart.storeId == widget.storeId;
    // Group by the backend-provided section name, keeping the original order.
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final pr in products) {
      sections.putIfAbsent((pr['section'] ?? '').toString(), () => []).add(pr);
    }
    return Scaffold(
      appBar: AppHeader(
        title: m['name'] as String,
        backLabel: ref.t('common.back'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (!open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  label: ref.t('shop.closed'),
                  tone: StatusTone.error,
                  icon: AppIcons.block,
                ),
              ),
            ),
          Text(ref.t('shop.menu'), style: t.headlineSmall),
          const SizedBox(height: 8),
          for (final e in sections.entries) ...[
            if (e.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  e.key,
                  style: t.labelMedium?.copyWith(color: p.textSecondary),
                ),
              ),
            for (final pr in e.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(
                  builder: (_) {
                    final q = inCart
                        ? (cart.lines
                              .where((l) => l.productId == pr['id'])
                              .map((l) => l.qty)
                              .fold(0, (a, b) => a + b))
                        : 0;
                    final desc = (pr['description'] ?? '').toString();
                    return AppCard(
                      key: Key('product-${pr['id']}'),
                      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                      selected: q > 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pr['name'] as String, style: t.titleSmall),
                                if (desc.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                PriceLabel(
                                  amount: pr['price'],
                                  size: PriceSize.small,
                                ),
                              ],
                            ),
                          ),
                          if (q > 0) ...[
                            _StepButton(
                              key: Key('minus-${pr['id']}'),
                              icon: Icons.remove_rounded,
                              tooltip: ref.t('shop.remove'),
                              onTap: () => ref
                                  .read(cartProvider.notifier)
                                  .remove(pr['id'] as String),
                            ),
                            SizedBox(
                              width: 22,
                              child: Text(
                                '$q',
                                textAlign: TextAlign.center,
                                style: t.titleSmall,
                              ),
                            ),
                          ],
                          _StepButton(
                            key: Key('plus-${pr['id']}'),
                            icon: AppIcons.add,
                            tooltip: ref.t('shop.add'),
                            filled: true,
                            onTap: open
                                ? () => ref
                                      .read(cartProvider.notifier)
                                      .add(
                                        widget.storeId,
                                        m['name'] as String,
                                        pr,
                                      )
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: inCart && cart.count > 0
          ? Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.border)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SafeArea(
                top: false,
                child: PrimaryButton(
                  key: const Key('view-cart'),
                  icon: AppIcons.cart,
                  label:
                      '${ref.t('shop.viewCart')} · ${cart.count} · ${formatKzt(cart.total)}',
                  onPressed: () => context.push('/checkout'),
                ),
              ),
            )
          : null,
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
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _note = TextEditingController();
  Place? _address;
  String _pay = 'WALLET';
  Map<String, dynamic>? _quote;
  bool _busy = false, _quoting = false;
  late final String _idem = 'shop-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final u = ref.read(authProvider).user;
    _name.text = u?.fullName ?? '';
    _phone.text = u?.phone ?? '+7 ';
    _address = ref.read(draftProvider).pickup;
    WidgetsBinding.instance.addPostFrameCallback((_) => _estimate());
  }

  Map<String, dynamic> _body() {
    final cart = ref.read(cartProvider);
    return {
      'storeId': cart.storeId,
      'items': [
        for (final l in cart.lines)
          {'productId': l.productId, 'quantity': l.qty},
      ],
      'dropoff': {'lat': _address!.lat, 'lng': _address!.lng},
      'address': _address!.address.isNotEmpty
          ? _address!.address
          : _address!.name,
      'recipientName': _name.text.trim(),
      'recipientPhone': _phone.text.trim().isEmpty
          ? '+7'
          : Validators.phone(_phone.text) == null
          ? Validators.normalizePhone(_phone.text)
          : _phone.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      'paymentMethod': _pay,
    };
  }

  Future<void> _estimate() async {
    if (_address == null) return;
    setState(() {
      _quoting = true;
      _quote = null;
    });
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post('/store-orders/estimate', body: _body())
              as Map<String, dynamic>;
      if (mounted) setState(() => _quote = j);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _place() async {
    if (_address == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/store-orders',
                    headers: {'Idempotency-Key': _idem},
                    body: _body(),
                  )
              as Map<String, dynamic>;
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(walletProvider);
      if (mounted) context.pushReplacement('/shop-order/${j['id']}');
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('shop.checkout'),
        subtitle: cart.storeName,
        backLabel: ref.t('common.back'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  AppCard(
                    child: Column(
                      children: [
                        for (final l in cart.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: p.divider,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${l.qty}',
                                    style: t.labelMedium?.copyWith(
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${l.qty} × ${l.name}',
                                    style: t.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PriceLabel(
                                  amount: double.parse(l.price) * l.qty,
                                  size: PriceSize.small,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    key: const Key('address-card'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    onTap: null,
                    child: LocationField(
                      role: LocationRole.dropoff,
                      label: ref.t('shop.address'),
                      value: _address == null
                          ? null
                          : (_address!.name.isNotEmpty
                                ? _address!.name
                                : _address!.address),
                      placeholder: ref.t('express.chooseAddress'),
                      onTap: () async {
                        final x = await pickPlace(context, ref);
                        if (x != null) {
                          setState(() => _address = x);
                          _estimate();
                        }
                      },
                      trailing: Icon(AppIcons.chevron, color: p.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _name,
                    label: ref.t('shop.recipient'),
                    prefixIcon: AppIcons.person,
                    validator: v(ref, Validators.name),
                  ),
                  const SizedBox(height: 10),
                  AppTextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    label: ref.t('auth.phone'),
                    prefixIcon: Icons.phone_iphone_rounded,
                    validator: v(ref, Validators.phone),
                  ),
                  const SizedBox(height: 10),
                  AppTextField(
                    controller: _note,
                    maxLength: 300,
                    label: ref.t('shop.note'),
                  ),
                  const SizedBox(height: 8),
                  Text(ref.t('shop.payWith'), style: t.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final m in const ['WALLET', 'CASH']) ...[
                        Expanded(
                          child: AppCard(
                            key: Key('pay-$m'),
                            selected: _pay == m,
                            onTap: () => setState(() => _pay = m),
                            semanticLabel: ref.t(
                              m == 'CASH' ? 'shop.payCash' : 'shop.payWallet',
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  m == 'CASH'
                                      ? AppIcons.cash
                                      : AppIcons.walletOutlined,
                                  size: 22,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ref.t(
                                    m == 'CASH'
                                        ? 'shop.payCash'
                                        : 'shop.payWallet',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: t.labelMedium,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (m == 'WALLET') const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.info, size: 14, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ref.t(
                            _pay == 'CASH'
                                ? 'shop.cashNote'
                                : 'shop.walletOnly',
                          ),
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (_pay == 'WALLET')
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 20),
                      child: Text(ref.t('shop.refundNote'), style: t.bodySmall),
                    ),
                  const SizedBox(height: 16),
                  if (_quoting) const SkeletonLoader(height: 110, radius: 18),
                  if (_quote != null)
                    AppCard(
                      key: const Key('shop-quote'),
                      variant: AppCardVariant.filled,
                      child: Column(
                        children: [
                          InfoRow(
                            label: ref.t('shop.items'),
                            value: PriceLabel(
                              amount: _quote!['itemsTotal'],
                              size: PriceSize.small,
                            ),
                          ),
                          InfoRow(
                            label: ref.t('shop.delivery'),
                            value: PriceLabel(
                              amount: _quote!['deliveryFee'],
                              size: PriceSize.small,
                            ),
                          ),
                          Divider(color: p.border),
                          InfoRow(
                            label: ref.t('shop.total'),
                            emphasize: true,
                            value: PriceLabel(
                              amount: _quote!['total'],
                              size: PriceSize.large,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
                key: const Key('place-order'),
                label: ref.t('shop.place'),
                loading: _busy,
                onPressed: _quote == null ? null : _place,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = _o?['status'];
      if (s == 'PLACED' || s == 'ACCEPTED' || s == 'READY') _fetch();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final j =
          await ref.read(apiProvider).get('/store-orders/${widget.id}')
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _o = j;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && _o == null) setState(() => _failed = true);
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(apiProvider).post('/store-orders/${widget.id}/cancel');
      ref.invalidate(walletProvider);
      await _fetch();
    } catch (e) {
      if (mounted) showError(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      if (next.value != null) _fetch();
    });
    final o = _o;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (o == null) {
      return Scaffold(
        appBar: AppHeader(title: '', onBack: () => context.go('/home')),
        body: _failed
            ? ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: _fetch,
              )
            : const LoadingState(),
      );
    }
    final status = o['status'] as String;
    final d = o['delivery'] as Map<String, dynamic>?;
    final courier = d?['courier'] as Map<String, dynamic>?;
    final step = switch (status) {
      'PLACED' => 0,
      'ACCEPTED' => 1,
      'READY' => 2,
      'COMPLETED' => 3,
      _ => -1,
    };
    final bad =
        status == 'REJECTED' || status == 'CANCELLED' || status == 'FAILED';
    return Scaffold(
      appBar: AppHeader(
        title: '#${o['number']}',
        subtitle: o['storeName'] as String,
        onBack: () => context.go('/home'),
        backLabel: ref.t('common.close'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Row(
            children: [
              if (bad)
                Icon(Icons.error_rounded, color: p.error)
              else if (step == 3)
                Icon(AppIcons.checkCircle, color: p.success),
              if (bad || step == 3) const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    ref.t('shop.status.$status'),
                    key: const Key('shop-status'),
                    style: t.headlineSmall,
                  ),
                ),
              ),
            ],
          ),
          if (o['rejectReason'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${ref.t('shop.reject')}: ${o['rejectReason']}',
                style: t.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ),
          if (step >= 0 && step < 3)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      Expanded(
                        child: Container(
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
              ),
            ),
          const SizedBox(height: 16),
          if (d?['handoverCode'] != null)
            AppCard(
              key: const Key('shop-code'),
              variant: AppCardVariant.filled,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    ref.t('express.code'),
                    style: t.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d!['handoverCode'] as String,
                    style: t.displayMedium?.copyWith(
                      letterSpacing: 10,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ref.t('express.codeHint'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          if (courier != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                children: [
                  Avatar(name: courier['name'] as String, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(courier['name'] as String, style: t.titleSmall),
                        Text(
                          ref.t('express.status.${d!['status']}'),
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if ((courier['phone'] as String).isNotEmpty)
                    AppIconButton(
                      icon: AppIcons.call,
                      tooltip: ref.t('ride.call'),
                      style: AppIconButtonStyle.outlined,
                      onPressed: () =>
                          launchUrl(Uri.parse('tel:${courier['phone']}')),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                for (final i
                    in (o['items'] as List).cast<Map<String, dynamic>>())
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i['quantity']} × ${i['name']}',
                            style: t.bodyMedium,
                          ),
                        ),
                        PriceLabel(
                          amount:
                              double.parse(i['unit_price'].toString()) *
                              (i['quantity'] as int),
                          size: PriceSize.small,
                        ),
                      ],
                    ),
                  ),
                Divider(color: p.divider),
                InfoRow(
                  label: ref.t('shop.delivery'),
                  value: PriceLabel(
                    amount: o['deliveryFee'],
                    size: PriceSize.small,
                  ),
                ),
                InfoRow(
                  label: ref.t('shop.total'),
                  emphasize: true,
                  value: PriceLabel(amount: o['total'], size: PriceSize.medium),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (status == 'PLACED')
            AppButton(
              key: const Key('shop-cancel'),
              label: ref.t('shop.cancel'),
              variant: AppButtonVariant.outlined,
              onPressed: _cancel,
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
