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
Future<Place?> pickPlace(BuildContext context, WidgetRef ref) =>
    showAppBottomSheet<Place>(
      context,
      title: ref.t('express.chooseAddress'),
      scrollable: false,
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
  bool _loading = false, _searched = false;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      try {
        final j =
            await widget.ref
                    .read(apiProvider)
                    .get('/geo/places', query: {'q': q.trim()})
                as List;
        if (mounted) {
          setState(() {
            _results = j
                .map((e) => Place.fromJson(e as Map<String, dynamic>))
                .toList();
            _searched = true;
          });
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 420,
    child: Column(
      children: [
        SearchField(
          key: const Key('place-search'),
          autofocus: true,
          onChanged: _search,
          hint: widget.ref.t('ride.search'),
          loading: _loading,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _searched && _results.isEmpty && !_loading
              ? EmptyState(
                  icon: AppIcons.search,
                  title: widget.ref.t('ride.noResults'),
                )
              : ListView(
                  children: [
                    for (final p in _results)
                      AddressCard(
                        title: p.name,
                        subtitle: p.address,
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section(this.title, this.child);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        child,
      ],
    ),
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
  final _weight = TextEditingController(text: '1'),
      _desc = TextEditingController();
  final _sName = TextEditingController(),
      _sPhone = TextEditingController(),
      _rName = TextEditingController(),
      _rPhone = TextEditingController(text: '+7 ');
  Map<String, dynamic>? _quote;
  bool _busy = false, _quoting = false;
  late final String _idem = 'express-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final u = ref.read(authProvider).user;
    _sName.text = u?.fullName ?? '';
    _sPhone.text = u?.phone ?? '+7 ';
    final d = ref.read(draftProvider);
    _from = d.pickup;
  }

  double? get _kg => double.tryParse(_weight.text.replaceAll(',', '.'));

  Future<void> _calc() async {
    if (_from == null || _to == null || _kg == null || _kg! <= 0) return;
    setState(() {
      _quoting = true;
      _quote = null;
    });
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/deliveries/estimate',
                    body: {
                      'pickup': {'lat': _from!.lat, 'lng': _from!.lng},
                      'dropoff': {'lat': _to!.lat, 'lng': _to!.lng},
                      'sizeClass': _size,
                      'weightKg': _kg,
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) setState(() => _quote = j);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _order() async {
    if (_from == null || _to == null) {
      showAppToast(
        context,
        ref.t('express.chooseAddress'),
        type: AppToastType.error,
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final j =
          await ref
                  .read(apiProvider)
                  .post(
                    '/deliveries',
                    headers: {'Idempotency-Key': _idem},
                    body: {
                      'pickup': {
                        'point': {'lat': _from!.lat, 'lng': _from!.lng},
                        'address': _from!.address.isNotEmpty
                            ? _from!.address
                            : _from!.name,
                      },
                      'dropoff': {
                        'point': {'lat': _to!.lat, 'lng': _to!.lng},
                        'address': _to!.address.isNotEmpty
                            ? _to!.address
                            : _to!.name,
                      },
                      'sizeClass': _size,
                      'weightKg': _kg,
                      'description': _desc.text.trim(),
                      'paymentMethod': _payment,
                      'sender': {
                        'name': _sName.text.trim(),
                        'phone': Validators.normalizePhone(_sPhone.text),
                      },
                      'recipient': {
                        'name': _rName.text.trim(),
                        'phone': Validators.normalizePhone(_rPhone.text),
                      },
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) context.pushReplacement('/express/${j['id']}');
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _addr(
    LocationRole role,
    String label,
    Place? p,
    ValueChanged<Place> on,
  ) => LocationField(
    role: role,
    label: label,
    value: p == null ? null : (p.name.isNotEmpty ? p.name : p.address),
    placeholder: ref.t('express.chooseAddress'),
    onTap: () async {
      final x = await pickPlace(context, ref);
      if (x != null) {
        on(x);
        _calc();
      }
    },
    trailing: Icon(AppIcons.chevron, color: context.palette.textSecondary),
  );

  @override
  Widget build(BuildContext context) {
    final fee = _quote?['fee'] as Map<String, dynamic>?;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('express.title'),
        subtitle: ref.t('service.sendSub'),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        Container(
                          key: const Key('from-card'),
                          child: _addr(
                            LocationRole.pickup,
                            ref.t('express.from'),
                            _from,
                            (x) => setState(() => _from = x),
                          ),
                        ),
                        Divider(height: 1, indent: 36, color: p.divider),
                        Container(
                          key: const Key('to-card'),
                          child: _addr(
                            LocationRole.dropoff,
                            ref.t('express.to'),
                            _to,
                            (x) => setState(() => _to = x),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    ref.t('express.size'),
                    Column(
                      children: [
                        for (final sz in const [
                          ('SMALL', Icons.mail_outline_rounded),
                          ('MEDIUM', Icons.inventory_2_outlined),
                          ('LARGE', Icons.all_inbox_outlined),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              key: Key('size-${sz.$1}'),
                              selected: _size == sz.$1,
                              onTap: () {
                                setState(() => _size = sz.$1);
                                _calc();
                              },
                              semanticLabel: ref.t('express.size.${sz.$1}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(sz.$2, size: 26),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      ref.t('express.size.${sz.$1}'),
                                      style: t.titleSmall,
                                    ),
                                  ),
                                  if (_size == sz.$1)
                                    Icon(
                                      AppIcons.checkCircle,
                                      color: p.isDark
                                          ? p.accent
                                          : AppColors.midnight,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        AppTextField(
                          key: const Key('weight'),
                          controller: _weight,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          label: ref.t('express.weight'),
                          prefixIcon: Icons.scale_outlined,
                          onChanged: (_) => _calc(),
                          validator: (s) =>
                              (double.tryParse(
                                        (s ?? '').replaceAll(',', '.'),
                                      ) ??
                                      0) >
                                  0
                              ? null
                              : ref.t('express.weight'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          key: const Key('desc'),
                          controller: _desc,
                          maxLength: 300,
                          label: ref.t('express.description'),
                          validator: (s) => (s == null || s.trim().isEmpty)
                              ? ref.t('express.description')
                              : null,
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    ref.t('express.sender'),
                    Column(
                      children: [
                        AppTextField(
                          key: const Key('s-name'),
                          controller: _sName,
                          label: ref.t('express.name'),
                          prefixIcon: AppIcons.person,
                          validator: v(ref, Validators.name),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          key: const Key('s-phone'),
                          controller: _sPhone,
                          keyboardType: TextInputType.phone,
                          label: ref.t('express.phone'),
                          prefixIcon: Icons.phone_iphone_rounded,
                          validator: v(ref, Validators.phone),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    ref.t('express.recipient'),
                    Column(
                      children: [
                        AppTextField(
                          key: const Key('r-name'),
                          controller: _rName,
                          label: ref.t('express.name'),
                          prefixIcon: AppIcons.person,
                          validator: v(ref, Validators.name),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          key: const Key('r-phone'),
                          controller: _rPhone,
                          keyboardType: TextInputType.phone,
                          label: ref.t('express.phone'),
                          prefixIcon: Icons.phone_iphone_rounded,
                          validator: v(ref, Validators.phone),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    ref.t('ride.payment'),
                    Row(
                      children: [
                        for (final m in const [
                          ('CASH', 'pay.cash', AppIcons.cash),
                          ('WALLET', 'pay.wallet', AppIcons.walletOutlined),
                        ]) ...[
                          Expanded(
                            child: AppCard(
                              key: Key('dpay-${m.$1}'),
                              selected: _payment == m.$1,
                              onTap: () => setState(() => _payment = m.$1),
                              semanticLabel: ref.t(m.$2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Icon(m.$3, size: 22),
                                  const SizedBox(height: 4),
                                  Text(ref.t(m.$2), style: t.labelMedium),
                                ],
                              ),
                            ),
                          ),
                          if (m.$1 == 'CASH') const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  if (_quoting) const SkeletonLoader(height: 76, radius: 18),
                  if (fee != null)
                    AppCard(
                      key: const Key('quote'),
                      variant: AppCardVariant.filled,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ref.t('express.fee'),
                                  style: t.titleSmall,
                                ),
                              ),
                              PriceLabel(
                                amount: fee['total'],
                                size: PriceSize.large,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${formatKm(_quote!['distanceM'] as int)} ${ref.t('ride.km')} · ${ref.t('ride.routeEstimated')}',
                              style: t.bodySmall,
                            ),
                          ),
                          if (_quote!['courierAvailable'] != true)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  ref.t('express.noCourier'),
                                  style: t.bodySmall,
                                ),
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
                key: const Key('express-order'),
                label: ref.t('express.order'),
                loading: _busy,
                onPressed: _order,
              ),
            ),
          ),
        ],
      ),
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
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      final s = _d?['status'];
      if (s != 'DELIVERED' && s != 'CANCELLED' && s != 'EXPIRED') _fetch();
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
          await ref.read(apiProvider).get('/deliveries/${widget.id}')
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _d = j;
          _failed = false;
          _rated = j['rating'] != null;
          _stars = (j['rating'] as int?) ?? _stars;
        });
      }
    } catch (_) {
      if (mounted && _d == null) setState(() => _failed = true);
    }
  }

  Future<void> _cancel() async {
    try {
      await ref
          .read(apiProvider)
          .post(
            '/deliveries/${widget.id}/cancel',
            body: {'reason': 'customer_cancelled'},
          );
      await _fetch();
    } catch (e) {
      if (mounted) showError(context, ref, e);
    }
  }

  Future<void> _rate() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .post('/deliveries/${widget.id}/rating', body: {'stars': _stars});
      if (mounted) setState(() => _rated = true);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final ev = next.value;
      if (ev == null) return;
      if (ev.type == 'DELIVERY_COURIER_LOCATION' &&
          ev.data['deliveryId'] == widget.id) {
        setState(
          () => _live = LatLng(
            (ev.data['lat'] as num).toDouble(),
            (ev.data['lng'] as num).toDouble(),
          ),
        );
      } else {
        _fetch();
      }
    });
    final d = _d;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (d == null) {
      return Scaffold(
        appBar: AppHeader(
          title: ref.t('express.title'),
          onBack: () => context.go('/home'),
        ),
        body: _failed
            ? ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: _fetch,
              )
            : const LoadingState(),
      );
    }
    final status = d['status'] as String;
    final courier = d['courier'] as Map<String, dynamic>?;
    final pickup = LatLng(
          (d['pickup']['lat'] as num).toDouble(),
          (d['pickup']['lng'] as num).toDouble(),
        ),
        drop = LatLng(
          (d['dropoff']['lat'] as num).toDouble(),
          (d['dropoff']['lng'] as num).toDouble(),
        );
    final cl = courier?['lat'];
    final courierPos =
        _live ??
        (cl is num
            ? LatLng(cl.toDouble(), (courier!['lng'] as num).toDouble())
            : null);
    final active =
        status == 'SEARCHING_COURIER' ||
        status == 'COURIER_ASSIGNED' ||
        status == 'PICKED_UP';
    final step = switch (status) {
      'SEARCHING_COURIER' => 0,
      'COURIER_ASSIGNED' => 1,
      'PICKED_UP' => 2,
      'DELIVERED' => 3,
      _ => 0,
    };
    final tone = status == 'DELIVERED'
        ? StatusTone.success
        : (status == 'CANCELLED' || status == 'EXPIRED')
        ? StatusTone.error
        : StatusTone.info;
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('express.title'),
        onBack: () => context.go('/home'),
        backLabel: ref.t('common.close'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SizedBox(
            height: 210,
            child: ClipRRect(
              borderRadius: AppRadius.cardR,
              child: JolayMap(
                center: courierPos ?? pickup,
                zoom: 13,
                markers: [
                  pickupMarker(pickup),
                  dropoffMarker(drop),
                  if (courierPos != null) carMarker(courierPos),
                ],
                route: [pickup, drop],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              ref.t('express.status.$status'),
              key: const Key('express-status'),
              style: t.headlineSmall,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                status == 'DELIVERED'
                    ? AppIcons.checkCircle
                    : (status == 'CANCELLED' || status == 'EXPIRED')
                    ? Icons.error_rounded
                    : AppIcons.time,
                size: 16,
                color: tone == StatusTone.success
                    ? p.success
                    : tone == StatusTone.error
                    ? p.error
                    : p.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${ref.t('express.tracking')}: ${d['trackingNumber']}',
                  style: t.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
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
                      if (i < 2) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (d['handoverCode'] != null)
            AppCard(
              key: const Key('handover-code'),
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
                    d['handoverCode'] as String,
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
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        d['pickupAddress'] as String,
                        style: t.bodyMedium,
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
                        '${d['dropoffAddress']} · ${d['recipientName']}',
                        style: t.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(color: p.divider),
                InfoRow(
                  label: ref.t('express.fee'),
                  value: PriceLabel(amount: d['fee'], size: PriceSize.small),
                ),
                InfoRow(
                  label: ref.t('ride.payment'),
                  value: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d['paymentMethod'] == 'CASH'
                            ? ref.t('pay.cash')
                            : ref.t('pay.wallet'),
                        style: t.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      if (d['paymentStatus'] == 'PAID')
                        StatusBadge(
                          label: ref.t('ride.paid'),
                          tone: StatusTone.success,
                        )
                      else if (d['paymentStatus'] == 'FAILED')
                        StatusBadge(
                          label: ref.t('ride.paymentFailed'),
                          tone: StatusTone.error,
                        ),
                    ],
                  ),
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
                        Row(
                          children: [
                            RatingView(value: courier['rating']),
                            Text(
                              ' · ${courier['vehicle']}',
                              style: t.bodySmall,
                            ),
                          ],
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
          const SizedBox(height: 16),
          if (status == 'SEARCHING_COURIER' || status == 'COURIER_ASSIGNED')
            AppButton(
              key: const Key('express-cancel'),
              label: ref.t('express.cancel'),
              variant: AppButtonVariant.outlined,
              onPressed: _cancel,
            ),
          if (status == 'DELIVERED')
            AppCard(
              child: Column(
                children: [
                  Text(
                    _rated ? ref.t('ride.thanks') : ref.t('express.rate'),
                    style: t.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  IgnorePointer(
                    ignoring: _rated,
                    child: RatingInput(
                      value: _stars,
                      keyPrefix: 'dstar',
                      onChanged: (i) => setState(() => _stars = i),
                    ),
                  ),
                  if (!_rated)
                    PrimaryButton(
                      key: const Key('express-rate'),
                      label: ref.t('btn.send'),
                      loading: _busy,
                      onPressed: _stars == 0 ? null : _rate,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
