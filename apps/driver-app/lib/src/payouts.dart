import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'auth.dart';
import 'data.dart';

final payoutsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async => ((await ref.read(apiProvider).get('/drivers/payouts')) as List)
      .cast<Map<String, dynamic>>(),
);

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
      await ref
          .read(apiProvider)
          .post(
            '/drivers/payouts',
            body: {
              'amount': num.parse(_amount.text.replaceAll(',', '.')),
              'destination': _dest.text.trim(),
            },
          );
      _amount.clear();
      ref.invalidate(payoutsProvider);
      ref.invalidate(walletProvider);
      if (mounted) {
        showAppToast(context, ref.t('payout.sent'), type: AppToastType.success);
      }
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final list = ref.watch(payoutsProvider);
    final t = Theme.of(context).textTheme;
    ref.listen(eventsProvider, (_, ev) {
      final t = ev.value?.type;
      if (t == 'PAYOUT_PAID' || t == 'PAYOUT_REJECTED') {
        ref.invalidate(payoutsProvider);
        ref.invalidate(walletProvider);
      }
    });
    return Scaffold(
      appBar: AppHeader(
        title: ref.t('payout.title'),
        backLabel: ref.t('common.back'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          wallet.maybeWhen(
            data: (d) => AppCard(
              variant: AppCardVariant.inverse,
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.t('wallet.balance'),
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    PriceLabel(
                      key: const Key('payout-balance'),
                      amount: d['balance'],
                      size: PriceSize.hero,
                      color: AppColors.yellow,
                    ),
                  ],
                ),
              ),
            ),
            orElse: () => const SkeletonLoader(height: 100, radius: 18),
          ),
          const SizedBox(height: 20),
          Form(
            key: _form,
            child: Column(
              children: [
                AppTextField(
                  key: const Key('payout-amount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  label: ref.t('payout.amount'),
                  prefixIcon: AppIcons.cash,
                  validator: (s) =>
                      (num.tryParse((s ?? '').replaceAll(',', '.')) ?? 0) > 0
                      ? null
                      : ref.t('err.payout_below_minimum'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('payout-destination'),
                  controller: _dest,
                  textCapitalization: TextCapitalization.characters,
                  label: ref.t('payout.destination'),
                  prefixIcon: Icons.account_balance_outlined,
                  validator: (s) =>
                      RegExp(r'^[A-Za-z0-9 ]{8,44}$').hasMatch(s ?? '')
                      ? null
                      : ref.t('err.invalid_destination'),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  key: const Key('payout-submit'),
                  label: ref.t('payout.request'),
                  loading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(ref.t('payout.history'), style: t.titleMedium),
          const SizedBox(height: 8),
          list.when(
            loading: () => const SkeletonList(count: 3),
            error: (_, _) => SizedBox(
              height: 200,
              child: ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: () => ref.invalidate(payoutsProvider),
              ),
            ),
            data: (l) => l.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: EmptyState(
                      icon: AppIcons.wallet,
                      title: ref.t('activity.empty'),
                    ),
                  )
                : Column(
                    children: [
                      for (final x in l)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      PriceLabel(
                                        amount: x['amount'],
                                        size: PriceSize.medium,
                                      ),
                                      Text(
                                        '${formatDateTime(x['created_at']?.toString())} · ${x['destination']}${x['note'] != null ? ' · ${x['note']}' : ''}',
                                        style: t.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusBadge(
                                  label: ref.t('payout.${x['status']}'),
                                  tone: x['status'] == 'PAID'
                                      ? StatusTone.success
                                      : x['status'] == 'REJECTED'
                                      ? StatusTone.error
                                      : StatusTone.warning,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
