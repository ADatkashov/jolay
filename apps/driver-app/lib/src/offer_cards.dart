import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

/// How long an offer stays open (the backend sends `seconds_left`; this is only the denominator of the ring).
const offerSeconds = 15;

/// Circular countdown. The number is the truth; the ring is decoration (and has no motion of its own, so reduced-motion safe).
class CountdownRing extends StatelessWidget {
  final int left;
  final double size;
  const CountdownRing({super.key, required this.left, this.size = 56});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: false,
    label: '$left',
    child: ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: (left / offerSeconds).clamp(0, 1).toDouble(),
                strokeWidth: 5,
                color: left <= 5 ? JolayPalette.dark.error : AppColors.yellow,
                backgroundColor: const Color(0xFF3A3A38),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(
              '$left',
              style: TextStyle(
                fontFamily: AppTypography.family,
                package: AppTypography.package,
                fontSize: size * .36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Stat({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A28),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white60),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared chrome for ride and parcel requests: title + countdown, earnings hero, three facts, the route, accept/decline.
/// Hierarchy on purpose: *earnings* are the biggest thing, *Accept* the biggest control.
class OfferShell extends ConsumerWidget {
  final Key cardKey, acceptKey, declineKey;
  final IconData icon;
  final String title;
  final Object? earnings;
  final int left;
  final bool busy;
  final List<Widget> stats;
  final String? from;
  final String to;
  final Widget? extra;
  final Widget? heroTrailing;
  final VoidCallback onAccept, onDecline;
  const OfferShell({
    super.key,
    required this.cardKey,
    required this.acceptKey,
    required this.declineKey,
    required this.icon,
    required this.title,
    required this.earnings,
    required this.left,
    required this.busy,
    required this.stats,
    this.from,
    required this.to,
    this.extra,
    this.heroTrailing,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = JolayPalette.dark;
    return Theme(
      data: jolayDarkTheme(),
      child: Container(
        key: cardKey,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.midnight,
          borderRadius: BorderRadius.circular(AppRadius.sheet - 4),
          boxShadow: AppElevation.sheet,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.yellow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: AppColors.midnight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          ref.t('driver.expiresIn'),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CountdownRing(left: left),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.t('driver.expected'),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                          ),
                        ),
                        PriceLabel(
                          amount: earnings,
                          size: PriceSize.hero,
                          color: AppColors.yellow,
                        ),
                      ],
                    ),
                  ),
                  ?heroTrailing,
                ],
              ),
              const SizedBox(height: 12),
              Row(children: stats),
              const SizedBox(height: 14),
              if (from != null && from!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dark.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          from!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dark.error,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      to,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              ?extra,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      key: declineKey,
                      label: ref.t('driver.decline'),
                      variant: AppButtonVariant.outlined,
                      onPressed: busy ? null : onDecline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: AppButton(
                      key: acceptKey,
                      label: ref.t('driver.accept'),
                      loading: busy,
                      onPressed: busy ? null : onAccept,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _payLabel(WidgetRef ref, Object? m) => switch (m) {
  'CASH' => ref.t('pay.cash'),
  'CARD' => ref.t('pay.card'),
  _ => ref.t('pay.wallet'),
};
String _km(Object? m) => ((m as num? ?? 0) / 1000).toStringAsFixed(1);

class RideOfferCard extends ConsumerWidget {
  final Map<String, dynamic> offer;
  final int left;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const RideOfferCard({
    super.key,
    required this.offer,
    required this.left,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eta = offer['eta_s'] as num?;
    final dist = offer['est_distance_m'] as num?;
    final dur = offer['est_duration_s'] as num?;
    return OfferShell(
      cardKey: const Key('offer-card'),
      acceptKey: const Key('accept'),
      declineKey: const Key('decline'),
      icon: AppIcons.ride,
      title: ref.t('driver.newOrder'),
      earnings: offer['expected_earnings'],
      left: left,
      busy: busy,
      from: offer['pickup_address']?.toString(),
      to: offer['dropoff_address'].toString(),
      onAccept: onAccept,
      onDecline: onDecline,
      heroTrailing: _PayChip(
        icon: offer['payment_method'] == 'CASH'
            ? AppIcons.cash
            : offer['payment_method'] == 'CARD'
            ? AppIcons.card
            : AppIcons.walletOutlined,
        label: _payLabel(ref, offer['payment_method']),
      ),
      stats: [
        _Stat(
          icon: AppIcons.navigate,
          label: ref.t('driver.toPickup'),
          value:
              '${_km(offer['pickup_distance_m'])} ${ref.t('ride.km')}${eta == null ? '' : ' · ${formatDuration(eta.toInt())} ${ref.t('driver.minAway')}'}',
        ),
        _Stat(
          icon: AppIcons.flag,
          label: ref.t('driver.tripLabel'),
          value: dist == null
              ? '—'
              : '${_km(dist)} ${ref.t('ride.km')}${dur == null ? '' : ' · ${formatDuration(dur.toInt())} ${ref.t('driver.minAway')}'}',
        ),
      ],
    );
  }
}

class _PayChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PayChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A28),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class DeliveryOfferCard extends ConsumerWidget {
  final Map<String, dynamic> offer;
  final int left;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const DeliveryOfferCard({
    super.key,
    required this.offer,
    required this.left,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => OfferShell(
    cardKey: const Key('delivery-offer-card'),
    acceptKey: const Key('d-accept'),
    declineKey: const Key('d-decline'),
    icon: AppIcons.send,
    title: ref.t('delivery.newOrder'),
    earnings: offer['expected_earnings'],
    left: left,
    busy: busy,
    from: offer['pickup_address']?.toString(),
    to: offer['dropoff_address'].toString(),
    onAccept: onAccept,
    onDecline: onDecline,
    stats: [
      _Stat(
        icon: AppIcons.navigate,
        label: ref.t('driver.toPickup'),
        value: '${_km(offer['pickup_distance_m'])} ${ref.t('ride.km')}',
      ),
      _Stat(
        icon: AppIcons.send,
        label: ref.t('delivery.parcel'),
        value: '${offer['weight_kg']} kg',
      ),
    ],
    extra: offer['parcel_description'] == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              offer['parcel_description'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
          ),
  );
}
