import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../strings.dart';
import 'tokens.dart';

/// KK / RU / EN switcher. Each segment is a ≥ 44 dp target with the selected one filled; keys are `lang-kk|ru|en`.
class LanguageSelector extends ConsumerWidget {
  /// Set when drawn over a Midnight surface.
  final bool onDark;
  const LanguageSelector({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(localeProvider).languageCode;
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF2A2A28) : p.divider,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in const ['kk', 'ru', 'en'])
            Semantics(
              button: true,
              selected: cur == c,
              label: switch (c) {
                'kk' => 'Қазақша',
                'ru' => 'Русский',
                _ => 'English',
              },
              excludeSemantics: true,
              onTap: () => ref.read(localeProvider.notifier).set(Locale(c)),
              child: InkWell(
                key: Key('lang-$c'),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => ref.read(localeProvider.notifier).set(Locale(c)),
                child: AnimatedContainer(
                  duration: context.motion(AppDurations.base),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 36,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: cur == c ? AppColors.yellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    c.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cur == c
                          ? AppColors.midnight
                          : (onDark ? Colors.white70 : p.textSecondary),
                      fontWeight: FontWeight.w700,
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
