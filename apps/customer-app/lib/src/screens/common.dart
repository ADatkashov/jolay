import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

/// Shows a localized message for any error thrown by the API layer.
void showError(BuildContext context, WidgetRef ref, Object e) {
  final l = ref.read(localeProvider);
  final msg = e is ApiException
      ? (e.isNetwork ? tr(l, 'err.network') : errorText(l, e.code))
      : tr(l, 'common.error');
  showAppToast(context, msg, type: AppToastType.error);
}

/// Localizes a validator result (an i18n key) for FormField.validator.
FormFieldValidator<String> v(WidgetRef ref, String? Function(String?) fn) =>
    (s) {
      final k = fn(s);
      return k == null ? null : tr(ref.read(localeProvider), k);
    };

/// Kept for call-site compatibility; the shared [LanguageSelector] is the single implementation.
class LanguageSwitcher extends StatelessWidget {
  final bool dark;
  const LanguageSwitcher({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => LanguageSelector(onDark: dark);
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
  return '$code ${rest.startsWith('-') ? rest.substring(1) : rest}'
          .trimRight() +
      (rest.isEmpty ? ' ' : '');
}

/// Phone field with a country picker (bottom sheet) that rewrites the dial-code prefix.
class PhoneField extends ConsumerWidget {
  final TextEditingController controller;
  final Key? fieldKey;
  const PhoneField({super.key, required this.controller, this.fieldKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(localeProvider).languageCode;
    String name((String, String, String, String) c) => l == 'kk'
        ? c.$2
        : l == 'ru'
        ? c.$3
        : c.$4;
    return AppTextField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.phone,
      label: ref.t('auth.phone'),
      prefixIcon: Icons.phone_iphone_rounded,
      suffix: IconButton(
        key: const Key('country-picker'),
        tooltip: ref.t('auth.country'),
        icon: const Icon(AppIcons.language),
        onPressed: () async {
          final picked =
              await showAppBottomSheet<(String, String, String, String)>(
                context,
                title: ref.t('auth.country'),
                builder: (c) => Column(
                  children: [
                    for (final c2 in _countries)
                      AddressCard(
                        key: Key('country-${c2.$4}'),
                        title: name(c2),
                        icon: Icons.flag_outlined,
                        trailing: Text(
                          c2.$1,
                          style: Theme.of(c).textTheme.titleSmall,
                        ),
                        onTap: () => Navigator.pop(c, c2),
                      ),
                  ],
                ),
              );
          if (picked != null) {
            controller.text = withDialCode(controller.text, picked.$1);
            controller.selection = TextSelection.collapsed(
              offset: controller.text.length,
            );
          }
        },
      ),
      validator: v(ref, Validators.phone),
    );
  }
}
