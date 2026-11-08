import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'tokens.dart';

/// Standard text input (52 dp, 14 dp radius, floating label, inline error text with an icon-free, colour-independent message).
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label, hint, helper, errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscure, autofocus, enabled, readOnly;
  final int? maxLength, maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final TextStyle? style;
  final AutovalidateMode? autovalidateMode;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLength,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.style,
    this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscure,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      maxLength: maxLength,
      maxLines: obscure ? 1 : maxLines,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textAlign: textAlign,
      autovalidateMode: autovalidateMode,
      style: style ?? Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        errorText: errorText,
        counterText: '',
        helperStyle: Theme.of(context).textTheme.bodySmall,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: AppIconSize.md, color: p.textSecondary),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Search box. Editable by default; with [onTap] and `readOnly` it is a large tappable entry point (e.g. "Where to?").
class SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool autofocus, readOnly, loading;
  final VoidCallback? onClear;
  final Widget? trailing;
  const SearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onChanged,
    this.onTap,
    this.autofocus = false,
    this.readOnly = false,
    this.loading = false,
    this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (readOnly) {
      return Semantics(
        button: true,
        label: hint,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: p.surface,
          borderRadius: AppRadius.buttonR,
          child: InkWell(
            borderRadius: AppRadius.buttonR,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonR,
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.search, size: AppIconSize.lg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hint,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: t.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(AppIcons.search, size: AppIconSize.lg),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (onClear != null
                  ? IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .deleteButtonTooltip,
                      icon: const Icon(AppIcons.close, size: AppIconSize.md),
                      onPressed: onClear,
                    )
                  : trailing),
      ),
    );
  }
}

enum LocationRole { pickup, dropoff, stop }

/// Pickup / destination row. Role is shown by shape *and* colour (filled circle vs. square) so it never relies on colour alone.
class LocationField extends StatelessWidget {
  final LocationRole role;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final Widget? trailing;
  const LocationField({
    super.key,
    required this.role,
    required this.label,
    this.value,
    required this.placeholder,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final has = value != null && value!.isNotEmpty;
    return Semantics(
      button: onTap != null,
      label: '$label: ${has ? value : placeholder}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: AppRadius.buttonR,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTap + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child: role == LocationRole.dropoff
                        ? Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: p.error,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )
                        : Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: role == LocationRole.pickup
                                  ? p.success
                                  : p.textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: t.bodySmall),
                      Text(
                        has ? value! : placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          color: has ? p.textPrimary : p.textSecondary,
                        ),
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
