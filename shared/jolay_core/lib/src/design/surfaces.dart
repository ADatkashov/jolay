import 'package:flutter/material.dart';

import 'buttons.dart';
import 'icons.dart';
import 'tokens.dart';

enum AppCardVariant { outlined, filled, elevated, inverse }

/// Base surface. Outlined by default (no shadow); [selected] adds the yellow outline + tint.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final AppCardVariant variant;
  final String? semanticLabel;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
    this.variant = AppCardVariant.outlined,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = switch (variant) {
      AppCardVariant.outlined ||
      AppCardVariant.elevated => selected ? p.selected : p.surface,
      AppCardVariant.filled => p.divider,
      AppCardVariant.inverse => AppColors.midnight,
    };
    // A Material (not a coloured DecoratedBox) so InkWell splashes and ListTiles inside the card paint on top of the fill.
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardR,
        boxShadow: variant == AppCardVariant.elevated
            ? AppElevation.card
            : AppElevation.none,
      ),
      child: Material(
        color: bg,
        animationDuration: context.motion(AppDurations.base),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardR,
          side:
              variant == AppCardVariant.outlined ||
                  variant == AppCardVariant.elevated
              ? BorderSide(
                  color: selected ? p.selectedBorder : p.border,
                  width: selected ? 2 : 1,
                )
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel,
      child: card,
    );
  }
}

/// Wraps content for a bottom sheet: grabber, optional title, keyboard-aware padding and safe area.
class AppSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppSheet({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.gutter,
      0,
      AppSpacing.gutter,
      AppSpacing.s16,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40,
                height: AppSizes.grabber,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  12,
                ),
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            Flexible(
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal bottom sheet with JOLAY chrome (28 dp top radius, grabber, scrim, max 90 % height).
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool scrollable = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .9,
  ),
  builder: (c) => AppSheet(
    title: title,
    child: scrollable ? SingleChildScrollView(child: builder(c)) : builder(c),
  ),
);

/// Persistent (non-modal) panel that sits over a map: rounded top, soft shadow, safe-area aware.
class MapPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const MapPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.gutter,
      0,
      AppSpacing.gutter,
      AppSpacing.s16,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadius.sheetR,
        boxShadow: AppElevation.sheet,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                width: 40,
                height: AppSizes.grabber,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Centred modal with a title, body and actions.
Future<T?> showAppModal<T>(
  BuildContext context, {
  required String title,
  Widget? body,
  required List<Widget> actions,
  bool dismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  builder: (c) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              if (body != null) ...[
                const SizedBox(height: 12),
                DefaultTextStyle.merge(
                  style: Theme.of(c).textTheme.bodyMedium,
                  child: body,
                ),
              ],
              const SizedBox(height: 24),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actions[i],
              ],
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Yes/no confirmation. Resolves to `true` only when the user confirms. [destructive] paints the confirm button red.
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final r = await showAppModal<bool>(
    context,
    title: title,
    body: message == null ? null : Text(message),
    actions: [
      Builder(
        builder: (c) => AppButton(
          label: confirmLabel,
          variant: destructive
              ? AppButtonVariant.danger
              : AppButtonVariant.primary,
          onPressed: () => Navigator.pop(c, true),
        ),
      ),
      Builder(
        builder: (c) => AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.outlined,
          onPressed: () => Navigator.pop(c, false),
        ),
      ),
    ],
  );
  return r ?? false;
}

enum AppToastType { info, success, error }

/// Floating message. Always has an icon, so meaning never rests on colour alone.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final p = context.palette;
  final (icon, color) = switch (type) {
    AppToastType.success => (
      AppIcons.checkCircle,
      p.isDark ? AppColors.darkSuccess : const Color(0xFF7AD9A8),
    ),
    AppToastType.error => (
      Icons.error_rounded,
      p.isDark ? AppColors.darkError : const Color(0xFFFF9AA3),
    ),
    AppToastType.info => (
      AppIcons.info,
      p.isDark ? AppColors.darkInfo : const Color(0xFF9CC7F5),
    ),
  };
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: color, size: AppIconSize.lg),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}
