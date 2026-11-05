import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const HomeTab(), const ActivityTab(), const WalletTab(), const ProfileTab()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _i, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: ref.t('nav.home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: ref.t('nav.activity')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: ref.t('nav.wallet')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: ref.t('nav.profile')),
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

  @override
  void initState() { super.initState(); _init(); }

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
    ref.read(draftProvider.notifier).setPickup(Place(ref.read(localeProvider).languageCode == 'en' ? 'Current location' : tr(ref.read(localeProvider), 'home.currentLocation'), '', p.lat, p.lng));
  }

  Future<void> _allow() async {
    final s = await LocationService.request();
    if (!mounted) return;
    setState(() => _loc = s);
    if (s == LocationState.granted) { _fetch(); }
    else if (s == LocationState.deniedForever) { await Geolocator.openAppSettings(); }
    else if (s == LocationState.serviceOff) { await Geolocator.openLocationSettings(); }
  }

  void _go(Place dest) { ref.read(draftProvider.notifier).setDropoff(dest); context.push('/ride/options'); }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final active = ref.watch(activeRideProvider);
    final saved = ref.watch(savedAddressesProvider);
    final recent = ref.watch(recentDestinationsProvider);
    ref.listen(realtimeEventsProvider, (_, _) => ref.invalidate(activeRideProvider));

    return RefreshIndicator(
      onRefresh: () async { ref.invalidate(activeRideProvider); ref.invalidate(recentDestinationsProvider); ref.invalidate(savedAddressesProvider); },
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: JolayColors.midnight, child: Text((user?.fullName.isNotEmpty ?? false) ? user!.fullName[0].toUpperCase() : '?', style: const TextStyle(color: JolayColors.yellow, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${ref.t('home.greeting')}, ${user?.fullName.split(' ').first ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('Almaty', style: TextStyle(color: JolayColors.textSecondary)),
          ])),
          const LanguageSwitcher(),
        ]),
        const SizedBox(height: 20),
        if (active.value != null) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: JolayCard(key: const Key('active-ride-banner'), onTap: () => context.push('/ride/${active.value!.id}'), child: Row(children: [
            const Icon(Icons.local_taxi, color: JolayColors.midnight), const SizedBox(width: 12),
            Expanded(child: Text('${ref.t('home.ride')} · ${active.value!.dropoffAddress}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right),
          ])),
        ),
        if (_loc != null && _loc != LocationState.granted) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: JolayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ref.t('loc.title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(_loc == LocationState.denied ? ref.t('loc.body') : ref.t('loc.denied'), style: const TextStyle(color: JolayColors.textSecondary)),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: FilledButton(onPressed: _allow, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: Text(ref.t('loc.allow')))), const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () => context.push('/ride/destination'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: Text(ref.t('loc.manual'))))]),
          ])),
        ),
        JolayCard(
          key: const Key('where-to'),
          onTap: () => context.push('/ride/destination'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(children: [
            const Icon(Icons.search, color: JolayColors.midnight), const SizedBox(width: 12),
            Expanded(child: Text(ref.t('home.where'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            if (_here != null) const Icon(Icons.my_location, size: 18, color: JolayColors.success),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _Tile(icon: Icons.local_taxi, label: ref.t('home.ride'), active: true, onTap: () => context.push('/ride/destination'))),
          const SizedBox(width: 10),
          Expanded(child: _Tile(icon: Icons.delivery_dining, label: ref.t('home.delivery'), badge: ref.t('home.soon'))),
          const SizedBox(width: 10),
          Expanded(child: _Tile(icon: Icons.inventory_2_outlined, label: ref.t('home.express'), active: true, onTap: () => context.push('/express/new'))),
        ]),
        const SizedBox(height: 24),
        Text(ref.t('home.saved'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        saved.when(
          data: (l) => l.isEmpty ? const SizedBox.shrink() : Wrap(spacing: 8, runSpacing: 8, children: [for (final p in l) ActionChip(avatar: const Icon(Icons.bookmark, size: 18), label: Text(p.name), onPressed: () => _go(p))]),
          loading: () => const LinearProgressIndicator(), error: (_, _) => const SizedBox.shrink()),
        const SizedBox(height: 20),
        Text(ref.t('home.recent'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        recent.when(
          data: (l) => l.isEmpty ? Text(ref.t('home.noRecent'), style: const TextStyle(color: JolayColors.textSecondary)) : Column(children: [for (final p in l) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history), title: Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => _go(p))]),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(recentDestinationsProvider)),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool active;
  final VoidCallback? onTap;
  const _Tile({required this.icon, required this.label, this.badge, this.active = false, this.onTap});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .55 : 1,
        child: JolayCard(onTap: onTap, padding: const EdgeInsets.symmetric(vertical: 16), child: Column(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: active ? JolayColors.yellow : JolayColors.cloud, shape: BoxShape.circle), child: Icon(icon, color: JolayColors.midnight)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (badge != null) Text(badge!, style: const TextStyle(fontSize: 11, color: JolayColors.textSecondary)),
        ])),
      );
}

// ---------------- Activity ----------------
class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({super.key});
  @override
  ConsumerState<ActivityTab> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<ActivityTab> {
  static const tabs = ['completed', 'ongoing', 'cancelled'];
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Align(alignment: Alignment.centerLeft, child: Text(ref.t('nav.activity'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)))),
          TabBar(labelColor: JolayColors.midnight, indicatorColor: JolayColors.yellow, tabs: [Tab(text: ref.t('activity.completed')), Tab(text: ref.t('activity.ongoing')), Tab(text: ref.t('activity.cancelled'))]),
          Expanded(child: TabBarView(children: [for (final t in tabs) _RideList(tab: t)])),
        ]),
      );
}

class _RideList extends ConsumerWidget {
  final String tab;
  const _RideList({required this.tab});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(historyProvider(tab));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(historyProvider(tab))),
      data: (rides) => rides.isEmpty
          ? Center(child: Text(ref.t('activity.empty'), style: const TextStyle(color: JolayColors.textSecondary)))
          : RefreshIndicator(onRefresh: () async => ref.invalidate(historyProvider(tab)), child: ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: rides.length, separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = rides[i];
                return JolayCard(onTap: () => context.push('/ride/${r.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(formatDateTime(r.createdAt), style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12))), Text(formatKzt(r.fare), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.success), const SizedBox(width: 8), Expanded(child: Text(r.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis))]),
                  const SizedBox(height: 4),
                  Row(children: [const Icon(Icons.circle, size: 10, color: JolayColors.error), const SizedBox(width: 8), Expanded(child: Text(r.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis))]),
                  if (r.driver != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${r.driver!.name} · ${r.driver!.vehicle}', style: const TextStyle(color: JolayColors.textSecondary, fontSize: 12))),
                ]));
              })),
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
    final amount = await showDialog<int>(context: context, builder: (c) => AlertDialog(
      title: Text(ref.t('wallet.topup')),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ref.t('wallet.amount'))),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)), style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('btn.continue')))],
    ));
    if (amount == null || !mounted) return;
    try {
      final p = await ref.read(apiProvider).post('/wallet/top-ups', body: {'amount': amount}, headers: {'Idempotency-Key': DateTime.now().microsecondsSinceEpoch.toString()}) as Map<String, dynamic>;
      final url = p['checkoutUrl'] as String?;
      if (!mounted || url == null) return;
      if (url.contains('sandbox-checkout')) {
        // Sandbox gateway only: simulates the hosted checkout page. The balance changes ONLY after the backend verifies the gateway callback.
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('Sandbox checkout'), content: Text('${formatKzt(p['amount'])} — development gateway, no real money moves.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('ride.pay')))]));
        if (ok == true) await ref.read(apiProvider).post('/payments/${p['id']}/sandbox-checkout');
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      ref.invalidate(walletProvider);
    } catch (e) { if (mounted) showError(context, ref, e); }
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(walletProvider);
    ref.listen(realtimeEventsProvider, (_, ev) { if (ev.value?.type == 'PAYMENT_STATUS_UPDATED') ref.invalidate(walletProvider); });
    return w.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(walletProvider)),
      data: (d) => ListView(padding: const EdgeInsets.all(20), children: [
        Text(ref.t('nav.wallet'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ref.t('wallet.balance'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(formatKzt(d['balance']), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _topUp, icon: const Icon(Icons.add), label: Text(ref.t('wallet.topup')), style: FilledButton.styleFrom(minimumSize: const Size(160, 46))),
        ])),
        const SizedBox(height: 24),
        Text(ref.t('wallet.history'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if ((d['transactions'] as List).isEmpty) Text(ref.t('activity.empty'), style: const TextStyle(color: JolayColors.textSecondary)),
        for (final t in (d['transactions'] as List).cast<Map<String, dynamic>>())
          ListTile(contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: JolayColors.cloud, child: Icon(t['amount'].toString().startsWith('-') ? Icons.north_east : Icons.south_west, color: t['amount'].toString().startsWith('-') ? JolayColors.error : JolayColors.success)),
            title: Text((t['description'] ?? t['type']).toString()), subtitle: Text(formatDateTime(t['created_at']?.toString())),
            trailing: Text(formatKzt(t['amount']), style: TextStyle(fontWeight: FontWeight.w800, color: t['amount'].toString().startsWith('-') ? JolayColors.error : JolayColors.success))),
      ]),
    );
  }
}

// ---------------- Profile ----------------
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(ref.t('nav.profile'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      JolayCard(child: Row(children: [
        CircleAvatar(radius: 28, backgroundColor: JolayColors.midnight, child: Text((u?.fullName.isNotEmpty ?? false) ? u!.fullName[0].toUpperCase() : '?', style: const TextStyle(color: JolayColors.yellow, fontSize: 22, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u?.fullName ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text(u?.phone ?? '', style: const TextStyle(color: JolayColors.textSecondary)), if (u?.email != null) Text(u!.email!, style: const TextStyle(color: JolayColors.textSecondary))])),
      ])),
      const SizedBox(height: 16),
      JolayCard(padding: EdgeInsets.zero, child: Column(children: [
        ListTile(leading: const Icon(Icons.edit_outlined), title: Text(ref.t('profile.edit')), trailing: const Icon(Icons.chevron_right), onTap: () => _edit(context, ref)),
        ListTile(leading: const Icon(Icons.language), title: Text(ref.t('profile.language')), trailing: const LanguageSwitcher()),
        ListTile(leading: const Icon(Icons.support_agent), title: Text(ref.t('profile.support')), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/support')),
        ListTile(leading: const Icon(Icons.description_outlined), title: Text(ref.t('legal.terms')), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/legal/TERMS')),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(ref.t('legal.privacy')), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/legal/PRIVACY')),
        ListTile(leading: const Icon(Icons.info_outline), title: Text(ref.t('legal.about')), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/legal/ABOUT')),
      ])),
      const SizedBox(height: 16),
      JolayButton(label: ref.t('btn.logout'), secondary: true, onPressed: () => ref.read(authProvider.notifier).logout()),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(content: Text(ref.t('profile.deleteConfirm')), actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ref.t('btn.delete'), style: const TextStyle(color: JolayColors.error)))]));
          if (ok == true) {
            try { await ref.read(authProvider.notifier).deleteAccount(); } catch (e) { if (context.mounted) showError(context, ref, e); }
          }
        },
        child: Text(ref.t('profile.delete'), style: const TextStyle(color: JolayColors.error)),
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final u = ref.read(authProvider).user!;
    final name = TextEditingController(text: u.fullName), email = TextEditingController(text: u.email ?? '');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(ref.t('profile.edit')),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: InputDecoration(labelText: ref.t('auth.fullName')), validator: v(ref, Validators.name)),
        const SizedBox(height: 12),
        TextFormField(controller: email, decoration: InputDecoration(labelText: ref.t('auth.email')), validator: v(ref, Validators.email)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ref.t('btn.cancel'))), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), child: Text(ref.t('btn.save')))],
    ));
    if (ok == true) {
      try { await ref.read(authProvider.notifier).updateProfile(fullName: name.text.trim(), email: email.text.trim()); } catch (e) { if (context.mounted) showError(context, ref, e); }
    }
  }
}
