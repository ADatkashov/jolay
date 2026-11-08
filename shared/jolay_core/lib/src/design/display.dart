import 'package:flutter/material.dart';

import '../format.dart';
import 'icons.dart';
import 'surfaces.dart';
import 'tokens.dart';

enum StatusTone { neutral, success, warning, error, info, accent }

/// Status pill. Always carries an icon next to the text so state is not conveyed by colour alone.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, defIcon) = switch (tone) {
      StatusTone.success => (p.successSoft, p.success, AppIcons.checkCircle),
      StatusTone.warning => (p.warningSoft, p.warning, AppIcons.time),
      StatusTone.error => (p.errorSoft, p.error, Icons.error_rounded),
      StatusTone.info => (p.infoSoft, p.info, AppIcons.info),
      StatusTone.accent => (p.selected, p.textPrimary, AppIcons.star),
      StatusTone.neutral => (p.divider, p.textSecondary, Icons.circle),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? defIcon,
            size: tone == StatusTone.neutral && icon == null ? 8 : 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: fg, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

enum PriceSize { small, medium, large, hero }

/// Money in KZT. The amount is only *formatted* here — prices always come from the backend.
class PriceLabel extends StatelessWidget {
  final Object? amount;
  final PriceSize size;
  final Object? oldAmount;
  final bool approximate;
  final Color? color;
  final Key? oldKey;
  const PriceLabel({
    super.key,
    required this.amount,
    this.size = PriceSize.medium,
    this.oldAmount,
    this.approximate = false,
    this.color,
    this.oldKey,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = switch (size) {
      PriceSize.small => t.titleSmall,
      PriceSize.medium => t.titleMedium,
      PriceSize.large => t.headlineSmall,
      PriceSize.hero => t.displayMedium,
    }!;
    final style = base.copyWith(
      fontWeight: FontWeight.w800,
      color: color ?? context.palette.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: formatKzt(amount),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (oldAmount != null) ...[
              Text(
                formatKzt(oldAmount),
                key: oldKey,
                style: t.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              '${approximate ? '≈ ' : ''}${formatKzt(amount)}',
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only rating: star + value (+ count).
class RatingView extends StatelessWidget {
  final Object? value;
  final int? count;
  final double size;
  const RatingView({
    super.key,
    required this.value,
    this.count,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = double.tryParse('$value');
    if (v == null) return const SizedBox.shrink();
    return Semantics(
      label: '${v.toStringAsFixed(1)}${count == null ? '' : ' ($count)'}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.star,
              size: size + 2,
              color: p.isDark ? p.accent : const Color(0xFFD9980B),
            ),
            const SizedBox(width: 3),
            Text(
              v.toStringAsFixed(1),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontSize: size, color: p.textPrimary),
            ),
            if (count != null)
              Text(
                ' ($count)',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: size - 1),
              ),
          ],
        ),
      ),
    );
  }
}

/// Five tappable stars (each ≥ 48 dp). Keys are `${keyPrefix}-1 … ${keyPrefix}-5`.
class RatingInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final String keyPrefix;
  final String Function(int)? labelFor;
  const RatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'star',
    this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: i <= value,
            label: labelFor?.call(i) ?? '$i',
            excludeSemantics: true,
            onTap: () => onChanged(i),
            child: InkResponse(
              key: Key('$keyPrefix-$i'),
              onTap: () => onChanged(i),
              radius: 28,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: AnimatedScale(
                    scale: i <= value ? 1.08 : 1,
                    duration: context.motion(AppDurations.base),
                    child: Icon(
                      i <= value ? AppIcons.star : AppIcons.starOutlined,
                      size: 38,
                      color: i <= value
                          ? (p.isDark ? p.accent : const Color(0xFFE5A50F))
                          : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Circular avatar with initials fallback.
class Avatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final bool inverse;
  const Avatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.inverse = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((s) => s[0].toUpperCase()).join();
    final fallback = Center(
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: AppTypography.family,
          package: AppTypography.package,
          fontSize: size * .38,
          fontWeight: FontWeight.w800,
          color: inverse ? AppColors.midnight : AppColors.yellow,
        ),
      ),
    );
    return Semantics(
      label: name,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: inverse
                ? AppColors.yellow
                : (p.isDark ? p.elevated : AppColors.midnight),
          ),
          child: imageUrl == null
              ? fallback
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

/// Larger avatar with the rating chip overlapping the bottom edge.
class DriverAvatar extends StatelessWidget {
  final String name;
  final Object? rating;
  final String? imageUrl;
  final double size;
  const DriverAvatar({
    super.key,
    required this.name,
    this.rating,
    this.imageUrl,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: size,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Avatar(name: name, imageUrl: imageUrl, size: size),
          if (double.tryParse('$rating') != null)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: p.border),
                  boxShadow: AppElevation.card,
                ),
                child: RatingView(value: rating, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vehicle summary: model + colour and the licence plate drawn as a plate.
class VehicleCard extends StatelessWidget {
  final String model, plate;
  final String? color;
  final Widget? trailing;
  const VehicleCard({
    super.key,
    required this.model,
    required this.plate,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.divider,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(AppIcons.car, size: AppIconSize.lg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model,
                style: t.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (color != null && color!.isNotEmpty)
                Text(color!, style: t.bodySmall),
            ],
          ),
        ),
        Semantics(
          label: plate,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.midnight, width: 1.5),
              ),
              child: Text(
                plate,
                style: t.titleSmall?.copyWith(
                  color: AppColors.midnight,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A selectable ride category. Selection is signalled by the outline, the tint *and* a check mark.
/// [info] is the availability line (e.g. "4 min · 4 seats"); [oldPrice] shows a struck-through price when a promo applies.
class RideTypeCard extends StatelessWidget {
  final String name;
  final String description;
  final Object? price;
  final Object? oldPrice;
  final Key? oldPriceKey;
  final String? info;
  final bool infoPositive;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? badge;
  const RideTypeCard({
    super.key,
    required this.name,
    required this.description,
    required this.price,
    this.oldPrice,
    this.oldPriceKey,
    this.info,
    this.infoPositive = false,
    this.icon = AppIcons.car,
    this.selected = false,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppCard(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      semanticLabel:
          '$name, ${formatKzt(price)}${info == null ? '' : ', $info'}',
      child: Row(
        children: [
          AnimatedContainer(
            duration: context.motion(AppDurations.base),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: selected ? p.accent : p.divider,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 30,
              color: selected ? p.onAccent : p.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: t.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(
                        AppIcons.checkCircle,
                        size: 18,
                        color: p.isDark ? p.accent : AppColors.midnight,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: t.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (info != null)
                  Text(
                    info!,
                    style: t.bodySmall?.copyWith(
                      color: infoPositive ? p.success : p.textSecondary,
                      fontWeight: infoPositive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (badge != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: badge),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (oldPrice != null)
                Text(
                  formatKzt(oldPrice),
                  key: oldPriceKey,
                  style: t.bodySmall?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              PriceLabel(amount: price, size: PriceSize.medium),
            ],
          ),
        ],
      ),
    );
  }
}

/// One saved/recent/search-result address.
class AddressCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  const AddressCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.pin,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: subtitle == null || subtitle!.isEmpty
          ? title
          : '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: AppRadius.buttonR,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.divider,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: AppIconSize.md, color: p.textPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label + value line used in receipts and detail cards.
class InfoRow extends StatelessWidget {
  final String label;
  final Widget value;
  final bool emphasize;
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? Theme.of(context).textTheme.titleSmall
                : Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.palette.textSecondary),
          ),
        ),
        value,
      ],
    ),
  );
}
