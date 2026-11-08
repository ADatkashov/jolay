import 'package:flutter/material.dart';

import 'buttons.dart';
import 'icons.dart';
import 'tokens.dart';

/// Neutral "nothing here yet" state. Use inside lists and tabs; give it an action when one exists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    this.icon = AppIcons.activityOutlined,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: p.divider,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: p.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: t.bodyMedium?.copyWith(color: p.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                size: AppButtonSize.medium,
                variant: AppButtonVariant.outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Failed-to-load state with a retry action.
class ErrorState extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  final IconData icon;
  const ErrorState({
    super.key,
    required this.message,
    required this.retryLabel,
    this.onRetry,
    this.icon = AppIcons.offline,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.errorSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: p.error),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                AppButton(
                  label: retryLabel,
                  onPressed: onRetry,
                  expand: false,
                  size: AppButtonSize.medium,
                  variant: AppButtonVariant.outlined,
                  icon: AppIcons.refresh,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  final String? label;
  const LoadingState({super.key, this.label});
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: label ?? 'Loading',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    ),
  );
}

/// Shimmering placeholder block. The shimmer stops when the OS asks for reduced motion.
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonLoader({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });
  @override
  State<SkeletonLoader> createState() => _SkeletonState();
}

class _SkeletonState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.ambient,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(p.divider, p.border, _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Placeholder list rows (avatar + two lines) used while a list loads.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < count; i++)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SkeletonLoader(width: 40, height: 40, radius: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(height: 14),
                    SizedBox(height: 8),
                    SkeletonLoader(width: 120, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
