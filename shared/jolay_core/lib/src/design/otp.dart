import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Six-box one-time-code input. A real (nearly invisible) text field receives the digits, so paste, SMS autofill and the
/// OS keyboard all work; the boxes only display them. [fieldKey] is the key of the underlying [TextField].
class OtpField extends StatefulWidget {
  final TextEditingController controller;
  final bool error;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  final String semanticLabel;
  final int length;
  const OtpField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.error = false,
    this.fieldKey,
    this.semanticLabel = '',
    this.length = 6,
  });
  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final text = widget.controller.text;
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      value: text,
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < widget.length; i++)
                    Flexible(
                      child: AnimatedContainer(
                        duration: context.motion(AppDurations.fast),
                        constraints: const BoxConstraints(maxWidth: 48),
                        height: 56,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: AppRadius.inputR,
                          border: Border.all(
                            color: widget.error
                                ? p.error
                                : (i == text.length && _focus.hasFocus
                                      ? (p.isDark
                                            ? p.accent
                                            : AppColors.midnight)
                                      : p.border),
                            width: i == text.length || widget.error ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          i < text.length ? text[i] : '',
                          style: t.headlineSmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.01,
                child: TextField(
                  key: widget.fieldKey,
                  controller: widget.controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  maxLength: widget.length,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enableInteractiveSelection: false,
                  showCursor: false,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
