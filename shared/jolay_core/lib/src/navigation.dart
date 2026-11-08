import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'design/icons.dart';
import 'design/tokens.dart';
import 'format.dart';
import 'strings.dart';

/// One manoeuvre of the route ("Turn right onto ...").
class NavStep {
  final String text, icon;
  final int distanceM;
  final double? lat, lng;
  const NavStep({
    required this.text,
    required this.icon,
    required this.distanceM,
    this.lat,
    this.lng,
  });

  factory NavStep.fromJson(Map<String, dynamic> j) => NavStep(
    text: (j['text'] as String?) ?? '',
    icon: (j['icon'] as String?) ?? '',
    distanceM: (j['distanceM'] as num?)?.round() ?? 0,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  /// Material icon for a 2GIS manoeuvre icon name (matched by keyword, anything unknown is "straight on").
  IconData get iconData {
    final i = icon.toLowerCase();
    if (i.contains('finish') || i.contains('end') || i.contains('arriv')) {
      return AppIcons.flag;
    }
    if (i.contains('u_turn') || i.contains('uturn')) {
      return Icons.u_turn_left_rounded;
    }
    if (i.contains('round')) return Icons.roundabout_right_rounded;
    if (i.contains('left')) return Icons.turn_left_rounded;
    if (i.contains('right')) return Icons.turn_right_rounded;
    return Icons.straight_rounded;
  }
}

/// Road route of the current leg of a ride (driver to pickup, then the trip), from `GET /rides/{id}/navigation`.
class RideNavigation {
  /// `PICKUP` (driver on the way to the rider) or `TRIP`.
  final String leg;
  final int distanceM, durationS;

  /// `2GIS` for a real road route, `ESTIMATED` for a straight-line fallback.
  final String source;

  /// Route geometry as (lat, lng) pairs.
  final List<(double, double)> points;
  final List<NavStep> steps;
  const RideNavigation({
    required this.leg,
    required this.distanceM,
    required this.durationS,
    required this.source,
    required this.points,
    required this.steps,
  });

  bool get isEstimated => source != '2GIS';
  bool get isPickupLeg => leg == 'PICKUP';

  /// The manoeuvre to show next: the first one that has a text (the very first step is usually "start").
  NavStep? get nextStep {
    for (final s in steps) {
      if (s.text.isNotEmpty) return s;
    }
    return null;
  }

  factory RideNavigation.fromJson(Map<String, dynamic> j) {
    final pts = <(double, double)>[];
    for (final p in (j['polyline'] as List? ?? const [])) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    return RideNavigation(
      leg: (j['leg'] as String?) ?? 'TRIP',
      distanceM: (j['distanceM'] as num?)?.round() ?? 0,
      durationS: (j['durationS'] as num?)?.round() ?? 0,
      source: (j['source'] as String?) ?? 'ESTIMATED',
      points: pts,
      steps: [
        for (final s in (j['steps'] as List? ?? const []))
          if (s is Map) NavStep.fromJson(s.cast<String, dynamic>()),
      ],
    );
  }
}

/// Fetches the navigation of a ride; null when it is not available yet (no driver assigned) or the network fails. Never throws.
Future<RideNavigation?> fetchRideNavigation(
  ApiClient api,
  String rideId,
) async {
  try {
    final j = await api.get('/rides/$rideId/navigation');
    return j is Map ? RideNavigation.fromJson(j.cast<String, dynamic>()) : null;
  } catch (_) {
    return null;
  }
}

/// Keeps a ride's navigation fresh: one request now and then every [interval] (the server caches a leg for ~12 s and shares it between rider and driver).
class NavigationFeed {
  final ApiClient _api;
  final String rideId;
  final void Function(RideNavigation) onUpdate;
  final Duration interval;
  Timer? _timer;
  bool _busy = false, _disposed = false;
  RideNavigation? current;

  NavigationFeed(
    this._api,
    this.rideId,
    this.onUpdate, {
    this.interval = const Duration(seconds: 15),
  });

  void start() {
    refresh();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  /// Also called when the ride changes status (a new leg starts).
  Future<void> refresh() async {
    if (_busy || _disposed) return;
    _busy = true;
    final n = await fetchRideNavigation(_api, rideId);
    _busy = false;
    if (_disposed || n == null) return;
    current = n;
    onUpdate(n);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// "12 min · 3.4 km" plus the next manoeuvre; tap to open the full list of steps.
class NavSummary extends ConsumerWidget {
  final RideNavigation nav;
  final VoidCallback? onTap;

  /// The rider only needs the time and distance; the driver also sees the next manoeuvre.
  final bool showStep;
  const NavSummary({
    super.key,
    required this.nav,
    this.onTap,
    this.showStep = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final step = showStep ? nav.nextStep : null;
    return Semantics(
      button: onTap != null,
      label: ref.t('nav.steps'),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.elevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Icon(
                step?.iconData ?? AppIcons.navigate,
                color: p.textPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDuration(nav.durationS)} ${ref.t('ride.eta')} · ${formatKm(nav.distanceM)} ${ref.t('ride.km')}',
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (step != null)
                      Text(
                        step.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      )
                    else if (nav.isEstimated && showStep)
                      Text(
                        ref.t('nav.estimated'),
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                  ],
                ),
              ),
              if (onTap != null && nav.steps.isNotEmpty && showStep)
                Icon(AppIcons.chevron, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with every manoeuvre of the route.
Future<void> showNavStepsSheet(
  BuildContext context,
  WidgetRef ref,
  RideNavigation nav,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final p = c.palette;
      final t = Theme.of(c).textTheme;
      final steps = [
        for (final s in nav.steps)
          if (s.text.isNotEmpty) s,
      ];
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * .7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '${ref.t('nav.steps')} · ${formatDuration(nav.durationS)} ${ref.t('ride.eta')} · ${formatKm(nav.distanceM)} ${ref.t('ride.km')}',
                  style: t.titleMedium,
                ),
              ),
              if (steps.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    ref.t('nav.noSteps'),
                    style: t.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: steps.length,
                    separatorBuilder: (_, _) => Divider(color: p.divider),
                    itemBuilder: (_, i) => Row(
                      children: [
                        Icon(steps[i].iconData, color: p.textPrimary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(steps[i].text)),
                        if (steps[i].distanceM > 0)
                          Text(
                            steps[i].distanceM >= 1000
                                ? '${formatKm(steps[i].distanceM)} ${ref.t('ride.km')}'
                                : '${steps[i].distanceM} ${ref.t('nav.m')}',
                            style: t.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
