import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

enum AppButtonVariant { primary, secondary, outlined, ghost, danger }

/// [xl] is the 60 dp action for work-in-motion screens (driver accept / start / finish).
enum AppButtonSize { xl, large, medium, small }

/// The one JOLAY button. [PrimaryButton], [SecondaryButton] and [AppOutlinedButton] are presets of it.
///
/// States: enabled, pressed (subtle scale, off under reduced motion), focused (2px ring), disabled, loading
/// (spinner replaces the label but the button keeps its width, so the layout never jumps).
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _down = false, _focused = false;

  void _press() {
    // Primary and destructive actions get a light haptic tick; secondary ones stay silent.
    if (widget.variant == AppButtonVariant.primary ||
        widget.variant == AppButtonVariant.danger) {
      HapticFeedback.lightImpact();
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final (bg, fg, border) = switch (widget.variant) {
      AppButtonVariant.primary => (p.accent, p.onAccent, Colors.transparent),
      AppButtonVariant.secondary => (
        p.isDark ? p.elevated : AppColors.midnight,
        p.isDark ? p.textPrimary : AppColors.white,
        Colors.transparent,
      ),
      AppButtonVariant.outlined => (
        Colors.transparent,
        p.textPrimary,
        p.border,
      ),
      AppButtonVariant.ghost => (
        Colors.transparent,
        p.textPrimary,
        Colors.transparent,
      ),
      AppButtonVariant.danger => (
        p.error,
        p.isDark ? AppColors.midnight : AppColors.white,
        Colors.transparent,
      ),
    };
    final disabledBg =
        widget.variant == AppButtonVariant.outlined ||
            widget.variant == AppButtonVariant.ghost
        ? Colors.transparent
        : p.divider;
    final height = switch (widget.size) {
      AppButtonSize.xl => AppLayout.driverAction,
      AppButtonSize.large => AppSizes.buttonL,
      AppButtonSize.medium => AppSizes.buttonM,
      AppButtonSize.small => AppSizes.buttonS,
    };
    final textStyle = (switch (widget.size) {
      AppButtonSize.small => Theme.of(context).textTheme.labelMedium,
      AppButtonSize.xl => Theme.of(context).textTheme.titleMedium,
      _ => Theme.of(context).textTheme.labelLarge,
    })!;
    final color = enabled || widget.loading ? fg : p.textSecondary;
    final label = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        else ...[
          if (widget.icon != null) ...[
            Icon(widget.icon, size: AppIconSize.md, color: color),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              // Long Kazakh / Russian labels wrap to a second line instead of being cut off.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textStyle.copyWith(color: color),
            ),
          ),
        ],
      ],
    );
    final scale = _down && enabled && !context.reduceMotion ? .98 : 1.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? _press : null,
      value: widget.loading ? '…' : null,
      child: AnimatedScale(
        scale: scale,
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        child: Container(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: widget.expand ? double.infinity : 0,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.buttonR,
            border: Border.all(
              color: _focused
                  ? (p.isDark ? p.accent : AppColors.midnight)
                  : (enabled
                        ? border
                        : (widget.variant == AppButtonVariant.outlined
                              ? p.divider
                              : Colors.transparent)),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Material(
            color: enabled || widget.loading ? bg : disabledBg,
            borderRadius: AppRadius.buttonR,
            child: InkWell(
              borderRadius: AppRadius.buttonR,
              onTap: enabled ? _press : null,
              onHighlightChanged: (v) => setState(() => _down = v),
              onFocusChange: (v) => setState(() => _focused = v),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.size == AppButtonSize.small ? 14 : 20,
                  vertical: 8,
                ),
                child: Center(
                  widthFactor: widget.expand ? null : 1,
                  heightFactor: 1,
                  child: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends AppButton {
  const PrimaryButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.loading,
    super.size,
    super.expand,
  });
}

class SecondaryButton extends AppButton {
  const SecondaryButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.loading,
    super.size,
    super.expand,
  }) : super(variant: AppButtonVariant.secondary);
}

class AppOutlinedButton extends AppButton {
  const AppOutlinedButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.loading,
    super.size,
    super.expand,
  }) : super(variant: AppButtonVariant.outlined);
}

class AppTextButton extends AppButton {
  const AppTextButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.size = AppButtonSize.medium,
    super.expand = false,
    bool destructive = false,
  }) : super(
         variant: destructive
             ? AppButtonVariant.danger
             : AppButtonVariant.ghost,
       );
}

enum AppIconButtonStyle { filled, tonal, outlined, danger, floating }

/// Icon-only button with a ≥ 48 dp touch target. [tooltip] is mandatory: it is the accessible name.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonStyle style;
  final double size;
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.style = AppIconButtonStyle.tonal,
    this.size = AppSizes.minTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, border) = switch (style) {
      AppIconButtonStyle.filled => (p.accent, p.onAccent, Colors.transparent),
      AppIconButtonStyle.tonal => (
        p.divider,
        p.textPrimary,
        Colors.transparent,
      ),
      AppIconButtonStyle.outlined => (
        Colors.transparent,
        p.textPrimary,
        p.border,
      ),
      AppIconButtonStyle.danger => (
        p.error,
        p.isDark ? AppColors.midnight : AppColors.white,
        Colors.transparent,
      ),
      AppIconButtonStyle.floating => (
        p.surface,
        p.textPrimary,
        Colors.transparent,
      ),
    };
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: style == AppIconButtonStyle.floating
                  ? AppElevation.floating
                  : AppElevation.none,
            ),
            child: Material(
              color: onPressed == null ? p.divider : bg,
              shape: CircleBorder(side: BorderSide(color: border)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Center(
                  child: Icon(
                    icon,
                    size: AppIconSize.lg,
                    color: onPressed == null ? p.textSecondary : fg,
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
