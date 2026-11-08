import 'package:flutter/material.dart';

import 'design/buttons.dart';
import 'design/states.dart';
import 'design/surfaces.dart';

export 'design/brand.dart' show JolayLogo, CityTaxiIllustration;

/// Backwards-compatible aliases over the design system ([AppButton], [AppCard], [ErrorState]).
/// New code should use the design-system names directly.
class JolayButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool secondary;
  const JolayButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.secondary = false,
  });
  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onPressed: onPressed,
    loading: busy,
    variant: secondary ? AppButtonVariant.outlined : AppButtonVariant.primary,
  );
}

class JolayCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const JolayCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  @override
  Widget build(BuildContext context) =>
      AppCard(padding: padding, onTap: onTap, child: child);
}

class ErrorView extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  const ErrorView({
    super.key,
    required this.message,
    required this.retryLabel,
    this.onRetry,
  });
  @override
  Widget build(BuildContext context) =>
      ErrorState(message: message, retryLabel: retryLabel, onRetry: onRetry);
}
