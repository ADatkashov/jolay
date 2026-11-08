import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth.dart';
import 'data.dart';
import 'payouts.dart';
import 'registration.dart';

// ---------------- History ----------------
class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(historyProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ScreenTitle(ref.t('nav.history')),
          Expanded(
            child: h.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: SkeletonList(count: 5),
              ),
              error: (e, _) => ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: () => ref.invalidate(historyProvider),
              ),
              data: (l) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(historyProvider),
                child: l.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            title: ref.t('driver.noRides'),
                            message: ref.t('driver.noRidesBody'),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: l.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      formatDateTime(
                                        l[i]['createdAt']?.toString(),
                                      ),
                                      style: t.bodySmall,
                                    ),
                                  ),
                                  PriceLabel(
                                    amount: l[i]['finalFare'],
                                    size: PriceSize.medium,
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
                                      color: p.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${l[i]['pickupAddress']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
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
                                      '${l[i]['dropoffAddress']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Earnings ----------------
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
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ScreenTitle(ref.t('nav.earnings')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 'today',
                    label: Text(ref.t('driver.today')),
                  ),
                  ButtonSegment(
                    value: 'week',
                    label: Text(ref.t('driver.week')),
                  ),
                  ButtonSegment(
                    value: 'month',
                    label: Text(ref.t('driver.month')),
                  ),
                ],
                selected: {_p},
                onSelectionChanged: (s) => setState(() => _p = s.first),
              ),
            ),
          ),
          const SizedBox(height: 16),
          e.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SkeletonLoader(height: 130, radius: 18),
            ),
            error: (_, _) => SizedBox(
              height: 260,
              child: ErrorState(
                message: ref.t('common.offline'),
                retryLabel: ref.t('btn.retry'),
                onRetry: () => ref.invalidate(earningsProvider(_p)),
              ),
            ),
            data: (d) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  AppCard(
                    variant: AppCardVariant.inverse,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            ref.t('driver.net'),
                            style: t.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        PriceLabel(
                          key: const Key('net'),
                          amount: d['net'],
                          size: PriceSize.hero,
                          color: AppColors.yellow,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        InfoRow(
                          label: ref.t('driver.trips'),
                          value: Text('${d['trips']}', style: t.titleSmall),
                        ),
                        InfoRow(
                          label: ref.t('driver.gross'),
                          value: PriceLabel(
                            amount: d['gross'],
                            size: PriceSize.small,
                          ),
                        ),
                        InfoRow(
                          label: ref.t('driver.commission'),
                          value: PriceLabel(
                            amount: d['commission'],
                            size: PriceSize.small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          w.maybeWhen(
            data: (d) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PayoutsScreen(),
                  ),
                ),
                semanticLabel: ref.t('payout.title'),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.divider,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(AppIcons.wallet, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ref.t('wallet.balance'), style: t.bodySmall),
                          PriceLabel(
                            amount: d['balance'],
                            size: PriceSize.medium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ref.t('payout.title'),
                      style: t.labelMedium?.copyWith(color: p.textPrimary),
                    ),
                    Icon(AppIcons.chevron, color: p.textSecondary),
                  ],
                ),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ---------------- Profile ----------------
class DriverProfile extends ConsumerWidget {
  const DriverProfile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    final me = ref.watch(driverMeProvider).value;
    final mode = ref.watch(themeModeProvider);
    final v = me?['vehicle'] as Map<String, dynamic>?;
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final modeLabel = switch (mode) {
      ThemeMode.light => ref.t('theme.light'),
      ThemeMode.dark => ref.t('theme.dark'),
      _ => ref.t('theme.system'),
    };
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ScreenTitle(ref.t('nav.profile')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppCard(
              child: Row(
                children: [
                  Avatar(name: u?.fullName ?? '', size: 60),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u?.fullName ?? '',
                          style: t.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          u?.phone ?? '',
                          style: t.bodyMedium?.copyWith(color: p.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            RatingView(
                              value: me?['rating_avg'],
                              count:
                                  (me?['rating_count'] as num?)?.toInt() ?? 0,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (v != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: AppCard(
                child: VehicleCard(
                  model: '${v['brand']} ${v['model']} ${v['year']}',
                  color: v['color']?.toString(),
                  plate: v['plate'].toString(),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SettingsGroup(
              title: ref.t('profile.account'),
              children: [
                SwitchListTile(
                  key: const Key('accept-deliveries'),
                  secondary: Icon(AppIcons.send, color: p.textSecondary),
                  title: Text(
                    ref.t('delivery.accept'),
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  value: me?['accepts_delivery'] == true,
                  onChanged: (v) async {
                    try {
                      await ref
                          .read(apiProvider)
                          .put('/drivers/delivery', body: {'enabled': v});
                      ref.invalidate(driverMeProvider);
                    } catch (e) {
                      if (context.mounted) toast(context, ref, e);
                    }
                  },
                ),
                SettingsRow(
                  key: const Key('open-payouts'),
                  icon: Icons.account_balance_outlined,
                  title: ref.t('payout.title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PayoutsScreen(),
                    ),
                  ),
                ),
                SettingsRow(
                  key: const Key('open-docs'),
                  icon: AppIcons.document,
                  title: ref.t('driver.docs'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DocumentsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SettingsGroup(
              title: ref.t('profile.settings'),
              children: [
                SettingsRow(
                  icon: AppIcons.language,
                  title: ref.t('profile.language'),
                  trailing: const LanguageSelector(),
                ),
                SettingsRow(
                  key: const Key('profile-appearance'),
                  icon: Icons.contrast_rounded,
                  title: ref.t('profile.appearance'),
                  subtitle: modeLabel,
                  onTap: () => showAppBottomSheet<void>(
                    context,
                    title: ref.t('profile.appearance'),
                    builder: (c) => RadioGroup<ThemeMode>(
                      groupValue: mode,
                      onChanged: (m) {
                        if (m != null) {
                          ref.read(themeModeProvider.notifier).set(m);
                          Navigator.pop(c);
                        }
                      },
                      child: Column(
                        children: [
                          for (final m in const [
                            ThemeMode.system,
                            ThemeMode.light,
                            ThemeMode.dark,
                          ])
                            RadioListTile<ThemeMode>(
                              value: m,
                              contentPadding: EdgeInsets.zero,
                              activeColor: c.palette.isDark
                                  ? AppColors.yellow
                                  : AppColors.midnight,
                              title: Text(switch (m) {
                                ThemeMode.light => ref.t('theme.light'),
                                ThemeMode.dark => ref.t('theme.dark'),
                                _ => ref.t('theme.system'),
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SettingsRow(
                  icon: AppIcons.shield,
                  title: ref.t('driver.safety'),
                  subtitle: '112',
                  onTap: () => launchUrl(Uri.parse('tel:112')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppOutlinedButton(
              key: const Key('logout'),
              label: ref.t('btn.logout'),
              icon: AppIcons.logout,
              onPressed: () async {
                await ref.read(locationPublisherProvider).stop();
                await ref.read(authProvider.notifier).logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}
