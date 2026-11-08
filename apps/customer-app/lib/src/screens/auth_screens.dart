import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import 'common.dart';

class _AuthScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _AuthScaffold({
    required this.title,
    this.subtitle,
    required this.children,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  if (Navigator.canPop(context))
                    AppIconButton(
                      icon: AppIcons.back,
                      tooltip: ref.t('common.back'),
                      style: AppIconButtonStyle.outlined,
                      onPressed: () => Navigator.maybePop(context),
                    )
                  else
                    const SizedBox(width: 12),
                  const Spacer(),
                  const LanguageSelector(),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const JolayMark(size: 44),
                        const SizedBox(height: 20),
                        Semantics(
                          header: true,
                          child: Text(title, style: t.headlineLarge),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle!,
                            style: t.bodyLarge?.copyWith(
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password visibility toggle with an accessible name.
class _EyeButton extends ConsumerWidget {
  final bool obscure;
  final VoidCallback onTap;
  const _EyeButton({required this.obscure, required this.onTap});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: ref.t(obscure ? 'auth.showPassword' : 'auth.hidePassword'),
    icon: Icon(
      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
    ),
    onPressed: onTap,
  );
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpState();
}

class _SignUpState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController(text: '+7 '),
      _pw = TextEditingController(),
      _pw2 = TextEditingController(),
      _ref = TextEditingController();
  bool _terms = false, _busy = false, _showTermsError = false, _obscure = true;

  Future<void> _submit() async {
    setState(() => _showTermsError = !_terms);
    if (!_form.currentState!.validate() || !_terms) return;
    setState(() => _busy = true);
    try {
      final phone = Validators.normalizePhone(_phone.text);
      await ref
          .read(authProvider.notifier)
          .register(
            fullName: _name.text.trim(),
            phone: phone,
            email: _email.text.trim(),
            password: _pw.text,
            locale: ref.read(localeProvider).languageCode,
            referralCode: _ref.text.trim(),
          );
      if (mounted) context.push('/otp', extra: phone);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: ref.t('auth.createTitle'),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const Key('signup-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: ref.t('auth.fullName')),
              validator: v(ref, Validators.name),
            ),
            const SizedBox(height: 14),
            PhoneField(fieldKey: const Key('signup-phone'), controller: _phone),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('signup-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: ref.t('auth.email')),
              validator: v(ref, Validators.email),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('signup-password'),
              controller: _pw,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: ref.t('auth.password'),
                suffixIcon: _EyeButton(
                  obscure: _obscure,
                  onTap: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: v(ref, Validators.password),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('signup-confirm'),
              controller: _pw2,
              obscureText: _obscure,
              decoration: InputDecoration(labelText: ref.t('auth.confirm')),
              validator: v(ref, (s) => Validators.confirm(s, _pw.text)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('signup-referral'),
              controller: _ref,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: ref.t('referral.have')),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('signup-terms'),
              value: _terms,
              onChanged: (x) => setState(() => _terms = x ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                ref.t('auth.terms'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Row(
              children: [
                TextButton(
                  key: const Key('open-terms'),
                  onPressed: () => context.push('/legal/TERMS'),
                  child: Text(
                    ref.t('legal.terms'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/legal/PRIVACY'),
                  child: Text(
                    ref.t('legal.privacy'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            if (_showTermsError && !_terms)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ref.t('val.terms'),
                  style: TextStyle(color: context.palette.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: ref.t('btn.signup'),
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            AppTextButton(
              expand: true,
              onPressed: () => context.push('/login'),
              label: '${ref.t('auth.haveAccount')} ${ref.t('btn.login')}',
            ),
          ],
        ),
      ),
    ],
  );
}

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  ConsumerState<OtpScreen> createState() => _OtpState();
}

class _OtpState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false, _error = false;
  int _left = 60;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _t?.cancel();
    setState(() => _left = 60);
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _left = _left > 0 ? _left - 1 : 0);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await ref.read(authProvider.notifier).verifyOtp(widget.phone, _code.text);
    } catch (e) {
      if (mounted) {
        _code.clear();
        setState(() => _error = true);
        showError(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authProvider.notifier).resendOtp(widget.phone);
      _tick();
      setState(() => _error = false);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final text = _code.text;
    return _AuthScaffold(
      title: ref.t('auth.otpTitle'),
      subtitle: '${ref.t('auth.otpBody')} ${widget.phone}',
      children: [
        OtpField(
          fieldKey: const Key('otp-field'),
          controller: _code,
          error: _error,
          semanticLabel: ref.t('auth.code'),
          onChanged: (s) {
            setState(() => _error = false);
            if (s.length == 6) _verify();
          },
        ),
        if (_error)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.error_rounded, size: 16, color: p.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ref.t('auth.otpError'),
                      style: t.bodySmall?.copyWith(color: p.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: ref.t('btn.continue'),
          loading: _busy,
          onPressed: text.length == 6 ? _verify : null,
        ),
        const SizedBox(height: 12),
        Center(
          child: _left > 0
              ? Text(
                  '${ref.t('auth.resendIn')} 00:${_left.toString().padLeft(2, '0')}',
                  style: t.bodyMedium?.copyWith(color: p.textSecondary),
                )
              : AppTextButton(label: ref.t('auth.resend'), onPressed: _resend),
        ),
      ],
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController(), _pw = TextEditingController();
  bool _busy = false, _obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final id = _id.text.trim();
      await ref
          .read(authProvider.notifier)
          .login(
            id.contains('@') ? id : Validators.normalizePhone(id),
            _pw.text,
          );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'phone_not_verified') {
        // Account exists but the phone was never verified: send a fresh code and continue verification.
        final router = GoRouter.of(context);
        try {
          final p = Validators.normalizePhone(_id.text);
          await ref.read(authProvider.notifier).resendOtp(p);
          router.push('/otp', extra: p);
          return;
        } catch (_) {}
        if (!mounted) return;
      }
      showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _idValidator(String? s) {
    if (s == null || s.trim().isEmpty) return 'val.phone';
    return s.contains('@') ? Validators.email(s) : Validators.phone(s);
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: ref.t('auth.loginTitle'),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const Key('login-id'),
              controller: _id,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: ref.t('auth.phoneOrEmail'),
              ),
              validator: v(ref, _idValidator),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('login-password'),
              controller: _pw,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: ref.t('auth.password'),
                suffixIcon: _EyeButton(
                  obscure: _obscure,
                  onTap: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (s) =>
                  (s == null || s.isEmpty) ? ref.t('val.password') : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AppTextButton(
                onPressed: () => context.push('/forgot'),
                label: ref.t('auth.forgot'),
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: ref.t('btn.login'),
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            AppTextButton(
              expand: true,
              onPressed: () => context.push('/signup'),
              label: '${ref.t('auth.noAccount')} ${ref.t('btn.signup')}',
            ),
          ],
        ),
      ),
    ],
  );
}

class ForgotScreen extends ConsumerStatefulWidget {
  const ForgotScreen({super.key});
  @override
  ConsumerState<ForgotScreen> createState() => _ForgotState();
}

class _ForgotState extends ConsumerState<ForgotScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController(text: '+7 ');
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final p = Validators.normalizePhone(_phone.text);
      await ref.read(authProvider.notifier).forgot(p);
      if (mounted) context.push('/reset', extra: p);
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: ref.t('auth.forgotTitle'),
    subtitle: ref.t('auth.forgotBody'),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            PhoneField(controller: _phone),
            const SizedBox(height: 20),
            PrimaryButton(
              label: ref.t('btn.send'),
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    ],
  );
}

class ResetScreen extends ConsumerStatefulWidget {
  final String identifier;
  const ResetScreen({super.key, required this.identifier});
  @override
  ConsumerState<ResetScreen> createState() => _ResetState();
}

class _ResetState extends ConsumerState<ResetScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController(),
      _pw = TextEditingController(),
      _pw2 = TextEditingController();
  bool _busy = false, _obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authProvider.notifier)
          .reset(widget.identifier, _code.text.trim(), _pw.text);
      if (!mounted) return;
      showAppToast(
        context,
        tr(ref.read(localeProvider), 'auth.resetDone'),
        type: AppToastType.success,
      );
      context.go('/login');
    } catch (e) {
      if (mounted) showError(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: ref.t('auth.resetTitle'),
    subtitle: '${ref.t('auth.otpBody')} ${widget.identifier}',
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: ref.t('auth.code'),
                counterText: '',
              ),
              validator: (s) =>
                  (s == null || s.length != 6) ? ref.t('auth.code') : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _pw,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: ref.t('auth.newPassword'),
                suffixIcon: _EyeButton(
                  obscure: _obscure,
                  onTap: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: v(ref, Validators.password),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pw2,
              obscureText: _obscure,
              decoration: InputDecoration(labelText: ref.t('auth.confirm')),
              validator: v(ref, (s) => Validators.confirm(s, _pw.text)),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: ref.t('btn.save'),
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    ],
  );
}
