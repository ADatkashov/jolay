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

/// Countries offered in the phone-prefix picker: dial code and names (kk, ru, en).
const _countries = <(String, String, String, String)>[
  ('+7', 'Қазақстан', 'Казахстан', 'Kazakhstan'),
  ('+7', 'Ресей', 'Россия', 'Russia'),
  ('+996', 'Қырғызстан', 'Кыргызстан', 'Kyrgyzstan'),
  ('+998', 'Өзбекстан', 'Узбекистан', 'Uzbekistan'),
  ('+375', 'Беларусь', 'Беларусь', 'Belarus'),
  ('+992', 'Тәжікстан', 'Таджикистан', 'Tajikistan'),
  ('+994', 'Әзірбайжан', 'Азербайджан', 'Azerbaijan'),
  ('+374', 'Армения', 'Армения', 'Armenia'),
];

/// Replaces the leading dial code of [text] (e.g. "+7 701 …") with [code], keeping the rest.
String withDialCode(String text, String code) {
  final rest = text.trim().replaceFirst(RegExp(r'^\+?\d{1,3}'), '').trim();
  return '$code ${rest.startsWith('-') ? rest.substring(1) : rest}'.trimRight() + (rest.isEmpty ? ' ' : '');
}

/// Phone field with a country picker (bottom sheet) that rewrites the dial-code prefix.
class PhoneField extends ConsumerWidget {
  final TextEditingController controller;
  final Key? fieldKey;
  const PhoneField({super.key, required this.controller, this.fieldKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(localeProvider).languageCode;
    String name((String, String, String, String) c) => l == 'kk' ? c.$2 : l == 'ru' ? c.$3 : c.$4;
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: ref.t('auth.phone'),
        suffixIcon: IconButton(
          key: const Key('country-picker'),
          icon: const Icon(Icons.public),
          onPressed: () async {
            final picked = await showModalBottomSheet<(String, String, String, String)>(
              context: context,
              builder: (_) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  for (final c in _countries)
                    ListTile(key: Key('country-${c.$4}'), title: Text(name(c)), trailing: Text(c.$1), onTap: () => Navigator.pop(context, c)),
                ]),
              ),
            );
            if (picked != null) {
              controller.text = withDialCode(controller.text, picked.$1);
              controller.selection = TextSelection.collapsed(offset: controller.text.length);
            }
          },
        ),
      ),
      validator: v(ref, Validators.phone),
    );
  }
}
