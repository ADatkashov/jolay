import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

/// Shows a localized message for any error thrown by the API layer.
void showError(BuildContext context, WidgetRef ref, Object e) {
  final l = ref.read(localeProvider);
  final msg = e is ApiException ? (e.isNetwork ? tr(l, 'err.network') : errorText(l, e.code)) : tr(l, 'common.error');
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Localizes a validator result (an i18n key) for FormField.validator.
FormFieldValidator<String> v(WidgetRef ref, String? Function(String?) fn) => (s) {
      final k = fn(s);
      return k == null ? null : tr(ref.read(localeProvider), k);
    };

class LanguageSwitcher extends ConsumerWidget {
  final bool dark;
  const LanguageSwitcher({super.key, this.dark = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(localeProvider).languageCode;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final c in const ['kk', 'ru', 'en'])
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            key: Key('lang-$c'),
            label: Text(c.toUpperCase()),
            selected: cur == c,
            onSelected: (_) => ref.read(localeProvider.notifier).set(Locale(c)),
            selectedColor: JolayColors.yellow,
            backgroundColor: dark ? const Color(0xFF2A2A2A) : Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: cur == c ? JolayColors.midnight : (dark ? Colors.white : JolayColors.midnight)),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ),
    ]);
  }
}
