import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth.dart';
import 'data.dart';

/// SOS: notifies JOLAY support (ride + position are attached by the backend) and offers to dial 112. It does not replace emergency services.
void driverSos(BuildContext context, WidgetRef ref) => showAppModal<void>(
  context,
  title: ref.t('sos.title'),
  body: Text(ref.t('sos.body')),
  actions: [
    Builder(
      builder: (c) => AppButton(
        label: ref.t('sos.call'),
        variant: AppButtonVariant.danger,
        icon: AppIcons.call,
        onPressed: () {
          Navigator.pop(c);
          launchUrl(Uri.parse('tel:112'));
        },
      ),
    ),
    Builder(
      builder: (c) => AppButton(
        key: const Key('sos-notify'),
        label: ref.t('sos.notify'),
        variant: AppButtonVariant.outlined,
        onPressed: () async {
          Navigator.pop(c);
          final pos = ref.read(locationPublisherProvider).last;
          try {
            await reportSos(
              ref.read(apiProvider),
              lat: pos?.latitude,
              lng: pos?.longitude,
            );
            if (context.mounted) {
              showAppToast(
                context,
                ref.t('sos.sent'),
                type: AppToastType.success,
              );
            }
          } catch (e) {
            if (context.mounted) toast(context, ref, e);
          }
        },
      ),
    ),
    Builder(
      builder: (c) => AppTextButton(
        label: ref.t('btn.cancel'),
        expand: true,
        onPressed: () => Navigator.pop(c),
      ),
    ),
  ],
);

/// Yellow call-out for cash the driver has to collect (store orders, or trips with a platform-funded promo).
class CashNotice extends StatelessWidget {
  final String label;
  final Object? amount;
  const CashNotice({super.key, required this.label, required this.amount});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.yellow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(AppIcons.cash, color: AppColors.midnight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.midnight,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PriceLabel(
          amount: amount,
          size: PriceSize.large,
          color: AppColors.midnight,
        ),
      ],
    ),
  );
}

/// Bottom card used for an active job: rounded sheet with the safe area handled.
class _JobPanel extends StatelessWidget {
  final Key panelKey;
  final Column child;
  const _JobPanel({required this.panelKey, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: panelKey,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sheet - 4),
        border: Border.all(color: p.border),
        boxShadow: AppElevation.sheet,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: child.children,
        ),
      ),
    );
  }
}

Future<void> _navigate(Map<String, dynamic> target) => launchUrl(
  Uri.parse(
    'geo:${target['lat']},${target['lng']}?q=${target['lat']},${target['lng']}',
  ),
  mode: LaunchMode.externalApplication,
);

/// Active parcel delivery: pick up at the sender, then hand over to the recipient with their 4-digit code.
class ActiveDeliveryCard extends ConsumerWidget {
  final Map<String, dynamic> delivery;
  final bool busy;
  final Future<void> Function(String path) onAct;
  final Future<void> Function() onRefresh;
  const ActiveDeliveryCard({
    super.key,
    required this.delivery,
    required this.busy,
    required this.onAct,
    required this.onRefresh,
  });

  Future<void> _deliver(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final code = await showAppBottomSheet<String>(
      context,
      title: ref.t('delivery.deliver'),
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const Key('code-field'),
            controller: ctrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            autofocus: true,
            textAlign: TextAlign.center,
            style: Theme.of(c).textTheme.displayMedium
                ?.copyWith(letterSpacing: 10),
            label: ref.t('delivery.enterCode'),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            key: const Key('code-submit'),
            label: ref.t('btn.continue'),
            onPressed: () => Navigator.pop(c, ctrl.text),
          ),
        ],
      ),
    );
    if (code == null || !RegExp(r'^\d{4}$').hasMatch(code)) return;
    try {
      await ref
          .read(apiProvider)
          .post(
            '/drivers/deliveries/${delivery['id']}/deliver',
            body: {'code': code},
          );
      await onRefresh();
    } catch (e) {
      if (context.mounted) toast(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = delivery['id'];
    final picked = delivery['status'] == 'PICKED_UP';
    final target =
        (picked ? delivery['dropoff'] : delivery['pickup'])
            as Map<String, dynamic>;
    final phone = picked ? delivery['recipientPhone'] : delivery['senderPhone'];
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return _JobPanel(
      panelKey: const Key('active-delivery'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.selected,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.send,
                  size: 22,
                  color: p.isDark ? p.accent : AppColors.midnight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ref.t('delivery.parcel')} · ${delivery['trackingNumber']}',
                      style: t.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      picked
                          ? ref.t('driver.stage.inProgress')
                          : ref.t('driver.stage.toPickup'),
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              PriceLabel(
                amount: delivery['courierEarnings'],
                size: PriceSize.large,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                picked ? AppIcons.flag : AppIcons.pin,
                size: 18,
                color: picked ? p.error : p.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${picked ? delivery['dropoffAddress'] : delivery['pickupAddress']} · ${picked ? delivery['recipientName'] : delivery['senderName']}',
                  style: t.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 28),
            child: Text(
              '${delivery['parcelDescription']} · ${delivery['weightKg']} kg',
              style: t.bodySmall,
            ),
          ),
          if (delivery['cashToCollect'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: KeyedSubtree(
                key: const Key('cash-to-collect'),
                child: CashNotice(
                  label: ref.t('delivery.collectCash'),
                  amount: delivery['cashToCollect'],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppOutlinedButton(
                  label: ref.t('driver.navigate'),
                  icon: AppIcons.navigate,
                  size: AppButtonSize.medium,
                  onPressed: () => _navigate(target),
                ),
              ),
              if (phone != null) ...[
                const SizedBox(width: 8),
                AppIconButton(
                  icon: AppIcons.call,
                  tooltip: ref.t('ride.call'),
                  style: AppIconButtonStyle.outlined,
                  onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!picked)
            PrimaryButton(
              key: const Key('picked-up'),
              label: ref.t('delivery.pickedUp'),
              loading: busy,
              onPressed: () => onAct('/drivers/deliveries/$id/picked-up'),
            )
          else
            PrimaryButton(
              key: const Key('deliver'),
              label: ref.t('delivery.deliver'),
              loading: busy,
              onPressed: () => _deliver(context, ref),
            ),
          if (!picked)
            AppTextButton(
              label: ref.t('delivery.handBack'),
              destructive: true,
              expand: true,
              onPressed: busy
                  ? null
                  : () => onAct('/drivers/deliveries/$id/cancel'),
            ),
        ],
      ),
    );
  }
}

/// Active ride: one big stage button (arrive → start → complete), navigation, call, SOS.
class ActiveTripCard extends ConsumerWidget {
  final Map<String, dynamic> ride;
  final bool busy;
  final Future<void> Function(String path) onAct;
  const ActiveTripCard({
    super.key,
    required this.ride,
    required this.busy,
    required this.onAct,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ride['id'];
    final st = ride['status'] as String;
    final (label, path) = switch (st) {
      'DRIVER_ASSIGNED' => (
        ref.t('driver.enRoute'),
        '/drivers/rides/$id/en-route',
      ),
      'DRIVER_ARRIVING' => (
        ref.t('driver.imHere'),
        '/drivers/rides/$id/arrived',
      ),
      'DRIVER_ARRIVED' => (ref.t('driver.start'), '/drivers/rides/$id/start'),
      _ => (ref.t('driver.complete'), '/drivers/rides/$id/complete'),
    };
    final toPickup =
        st == 'DRIVER_ASSIGNED' ||
        st == 'DRIVER_ARRIVING' ||
        st == 'DRIVER_ARRIVED';
    final target =
        (toPickup ? ride['pickup'] : ride['dropoff']) as Map<String, dynamic>;
    final stage = switch (st) {
      'DRIVER_ARRIVED' => ref.t('driver.stage.arrived'),
      'IN_PROGRESS' => ref.t('driver.stage.inProgress'),
      _ => ref.t('driver.stage.toPickup'),
    };
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return _JobPanel(
      panelKey: const Key('active-trip'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Avatar(
                name:
                    ride['customerName']?.toString() ??
                    ref.t('driver.passenger'),
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride['customerName']?.toString() ??
                          ref.t('driver.passenger'),
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text(stage, style: t.bodySmall),
                    ),
                  ],
                ),
              ),
              PriceLabel(amount: ride['estimatedFare'], size: PriceSize.large),
            ],
          ),
          // The platform pays a promo discount, so a cash rider hands over less than the fare: tell the driver exactly how much to collect.
          if (ride['paymentMethod'] == 'CASH' &&
              (double.tryParse('${ride['promoDiscount'] ?? 0}') ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: KeyedSubtree(
                key: const Key('promo-cash'),
                child: CashNotice(
                  label: ref.t('driver.collectPromo'),
                  amount: ride['payable'],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                toPickup ? AppIcons.pin : AppIcons.flag,
                size: 18,
                color: toPickup ? p.success : p.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (toPickup ? ride['pickupAddress'] : ride['dropoffAddress'])
                      .toString(),
                  style: t.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const Key('navigate'),
                  label: ref.t('driver.navigate'),
                  icon: AppIcons.navigate,
                  variant: AppButtonVariant.outlined,
                  size: AppButtonSize.medium,
                  onPressed: () => _navigate(target),
                ),
              ),
              if (ride['customerPhone'] != null) ...[
                const SizedBox(width: 8),
                AppIconButton(
                  icon: AppIcons.call,
                  tooltip: ref.t('ride.call'),
                  style: AppIconButtonStyle.outlined,
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:${ride['customerPhone']}')),
                ),
              ],
              const SizedBox(width: 8),
              AppIconButton(
                key: const Key('sos'),
                icon: AppIcons.sos,
                tooltip: ref.t('ride.sos'),
                style: AppIconButtonStyle.danger,
                onPressed: () => driverSos(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            key: const Key('stage-button'),
            label: label,
            loading: busy,
            onPressed: () => onAct(path),
          ),
          if (st != 'IN_PROGRESS')
            AppTextButton(
              label: ref.t('ride.cancel'),
              destructive: true,
              expand: true,
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await showConfirmationDialog(
                        context,
                        title: ref.t('driver.cancelTitle'),
                        message: ref.t('ride.cancelFee'),
                        confirmLabel: ref.t('ride.cancel'),
                        cancelLabel: ref.t('ride.keep'),
                        destructive: true,
                      );
                      if (ok) await onAct('/drivers/rides/$id/cancel');
                    },
            ),
        ],
      ),
    );
  }
}
