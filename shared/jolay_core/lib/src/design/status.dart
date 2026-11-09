import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Coloured dot + label. Colour is never the only signal: the label always states the state.
/// [active] draws the green "live" glow (static under reduced motion).
class StatusIndicator extends StatelessWidget {
  final bool active;
  final String label;
  final String? caption;
  const StatusIndicator({
    super.key,
    required this.active,
    required this.label,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        AnimatedContainer(
          duration: context.motion(AppDurations.base),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: active ? p.success : p.textSecondary,
            shape: BoxShape.circle,
            boxShadow: [
              if (active)
                BoxShadow(
                  color: p.success.withValues(alpha: .45),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: t.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: t.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Large two-state switch for one-handed use while working: 76×44 touch area, green when on, grey when off,
/// animated knob, haptic click. [onChanged] null = disabled. Does **not** change by itself: the owner decides
/// (so a confirmation can be inserted before going offline).
class JolayToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  const JolayToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onChanged != null;
    final d = context.motion(AppDurations.base);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.mediumImpact();
                onChanged!(!value);
              }
            : null,
        child: SizedBox(
          width: 80,
          height: AppLayout.minTouch,
          child: Center(
            child: AnimatedContainer(
              duration: d,
              curve: Curves.easeOutCubic,
              width: 68,
              height: 38,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: !enabled
                    ? p.divider
                    : value
                    ? p.success
                    : p.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: AnimatedAlign(
                duration: d,
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: value ? AppColors.midnight : p.textSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    value ? Icons.check_rounded : Icons.power_settings_new,
                    size: 18,
                    color: value ? p.success : p.background,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
