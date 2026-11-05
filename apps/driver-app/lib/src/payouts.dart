import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'auth.dart';
import 'data.dart';

final payoutsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    ((await ref.read(apiProvider).get('/drivers/payouts')) as List).cast<Map<String, dynamic>>());

/// Driver payout requests. The requested amount is held in the wallet immediately; finance pays it out and records the bank reference.
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});
  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsState();
}

class _PayoutsState extends ConsumerState<PayoutsScreen> {
  final _amount = TextEditingController(), _dest = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/drivers/payouts', body: {'amount': num.parse(_amount.text.replaceAll(',', '.')), 'destination': _dest.text.trim()});
      _amount.clear();
      ref.invalidate(payoutsProvider); ref.invalidate(walletProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.t('payout.sent'))));
    } catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final list = ref.watch(payoutsProvider);
    ref.listen(eventsProvider, (_, ev) { final t = ev.value?.type; if (t == 'PAYOUT_PAID' || t == 'PAYOUT_REJECTED') { ref.invalidate(payoutsProvider); ref.invalidate(walletProvider); } });
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('payout.title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        wallet.maybeWhen(data: (d) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: JolayColors.midnight, borderRadius: BorderRadius.circular(JolayRadius.lg)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ref.t('wallet.balance'), style: const TextStyle(color: Colors.white70)), Text(formatKzt(d['balance']), key: const Key('payout-balance'), style: const TextStyle(color: JolayColors.yellow, fontSize: 32, fontWeight: FontWeight.w900))])), orElse: () => const SizedBox.shrink()),
        const SizedBox(height: 16),
        Form(key: _form, child: Column(children: [
          TextFormField(key: const Key('payout-amount'), controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ref.t('payout.amount')),
              validator: (s) => (num.tryParse((s ?? '').replaceAll(',', '.')) ?? 0) > 0 ? null : ref.t('err.payout_below_minimum')),
          const SizedBox(height: 12),
          TextFormField(key: const Key('payout-destination'), controller: _dest, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: ref.t('payout.destination')),
              validator: (s) => RegExp(r'^[A-Za-z0-9 ]{8,44}$').hasMatch(s ?? '') ? null : ref.t('err.invalid_destination')),
          const SizedBox(height: 16),
          JolayButton(key: const Key('payout-submit'), label: ref.t('payout.request'), busy: _busy, onPressed: _submit),
        ])),
        const SizedBox(height: 24),
        Text(ref.t('payout.history'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => ErrorView(message: ref.t('common.offline'), retryLabel: ref.t('btn.retry'), onRetry: () => ref.invalidate(payoutsProvider)),
          data: (l) => l.isEmpty ? Text(ref.t('activity.empty'), style: const TextStyle(color: JolayColors.textSecondary)) : Column(children: [
            for (final p in l) ListTile(contentPadding: EdgeInsets.zero, title: Text(formatKzt(p['amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${formatDateTime(p['created_at']?.toString())} · ${p['destination']}${p['note'] != null ? ' · ${p['note']}' : ''}'),
              trailing: Text(ref.t('payout.${p['status']}'), style: TextStyle(fontWeight: FontWeight.w700, color: p['status'] == 'PAID' ? JolayColors.success : p['status'] == 'REJECTED' ? JolayColors.error : JolayColors.textSecondary))),
          ]),
        ),
      ]),
    );
  }
}
