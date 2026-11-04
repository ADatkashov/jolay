import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import 'common.dart';

class _AuthScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _AuthScaffold({required this.title, this.subtitle, required this.children});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(actions: const [LanguageSwitcher(), SizedBox(width: 12)]),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: const TextStyle(color: JolayColors.textSecondary))],
              const SizedBox(height: 24),
              ...children,
            ]),
          ),
        ),
      );
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpState();
}

class _SignUpState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController(), _phone = TextEditingController(text: '+7 '), _pw = TextEditingController(), _pw2 = TextEditingController();
  bool _terms = false, _busy = false, _showTermsError = false, _obscure = true;

  Future<void> _submit() async {
    setState(() => _showTermsError = !_terms);
    if (!_form.currentState!.validate() || !_terms) return;
    setState(() => _busy = true);
    try {
      final phone = Validators.normalizePhone(_phone.text);
      await ref.read(authProvider.notifier).register(fullName: _name.text.trim(), phone: phone, email: _email.text.trim(), password: _pw.text, locale: ref.read(localeProvider).languageCode);
      if (mounted) context.push('/otp', extra: phone);
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: ref.t('auth.createTitle'), children: [
        Form(key: _form, child: Column(children: [
          TextFormField(key: const Key('signup-name'), controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: ref.t('auth.fullName')), validator: v(ref, Validators.name)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('signup-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('auth.phone')), validator: v(ref, Validators.phone)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('signup-email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: ref.t('auth.email')), validator: v(ref, Validators.email)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('signup-password'), controller: _pw, obscureText: _obscure, decoration: InputDecoration(labelText: ref.t('auth.password'),
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))), validator: v(ref, Validators.password)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('signup-confirm'), controller: _pw2, obscureText: _obscure, decoration: InputDecoration(labelText: ref.t('auth.confirm')), validator: v(ref, (s) => Validators.confirm(s, _pw.text))),
          const SizedBox(height: 8),
          CheckboxListTile(key: const Key('signup-terms'), value: _terms, onChanged: (x) => setState(() => _terms = x ?? false), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
              title: Text(ref.t('auth.terms'), style: const TextStyle(fontSize: 13)), activeColor: JolayColors.midnight),
          if (_showTermsError && !_terms) Align(alignment: Alignment.centerLeft, child: Text(ref.t('val.terms'), style: const TextStyle(color: JolayColors.error, fontSize: 12))),
          const SizedBox(height: 16),
          JolayButton(label: ref.t('btn.signup'), busy: _busy, onPressed: _submit),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.push('/login'), child: Text('${ref.t('auth.haveAccount')} ${ref.t('btn.login')}')),
        ])),
      ]);
}

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  ConsumerState<OtpScreen> createState() => _OtpState();
}

class _OtpState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  int _left = 60;
  Timer? _t;

  @override
  void initState() { super.initState(); _tick(); }
  void _tick() { _t?.cancel(); setState(() => _left = 60); _t = Timer.periodic(const Duration(seconds: 1), (t) { if (_left <= 1) { t.cancel(); } if (mounted) setState(() => _left = _left > 0 ? _left - 1 : 0); }); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    setState(() => _busy = true);
    try { await ref.read(authProvider.notifier).verifyOtp(widget.phone, _code.text); }
    catch (e) { if (mounted) { _code.clear(); showError(context, ref, e); } } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _resend() async {
    try { await ref.read(authProvider.notifier).resendOtp(widget.phone); _tick(); } catch (e) { if (mounted) showError(context, ref, e); }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: ref.t('auth.otpTitle'), subtitle: '${ref.t('auth.otpBody')} ${widget.phone}', children: [
        TextField(key: const Key('otp-field'), controller: _code, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w800),
            decoration: InputDecoration(hintText: ref.t('auth.code'), counterText: ''), onChanged: (s) { setState(() {}); if (s.length == 6) _verify(); }),
        const SizedBox(height: 16),
        JolayButton(label: ref.t('btn.continue'), busy: _busy, onPressed: _code.text.length == 6 ? _verify : null),
        const SizedBox(height: 12),
        Center(child: _left > 0 ? Text('${ref.t('auth.resendIn')} 00:${_left.toString().padLeft(2, '0')}', style: const TextStyle(color: JolayColors.textSecondary)) : TextButton(onPressed: _resend, child: Text(ref.t('auth.resend')))),
      ]);
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
      await ref.read(authProvider.notifier).login(id.contains('@') ? id : Validators.normalizePhone(id), _pw.text);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'phone_not_verified') {
        // Account exists but the phone was never verified: send a fresh code and continue verification.
        final router = GoRouter.of(context);
        try { final p = Validators.normalizePhone(_id.text); await ref.read(authProvider.notifier).resendOtp(p); router.push('/otp', extra: p); return; } catch (_) {}
        if (!mounted) return;
      }
      showError(context, ref, e);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  String? _idValidator(String? s) {
    if (s == null || s.trim().isEmpty) return 'val.phone';
    return s.contains('@') ? Validators.email(s) : Validators.phone(s);
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: ref.t('auth.loginTitle'), children: [
        Form(key: _form, child: Column(children: [
          TextFormField(key: const Key('login-id'), controller: _id, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: ref.t('auth.phoneOrEmail')), validator: v(ref, _idValidator)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('login-password'), controller: _pw, obscureText: _obscure, decoration: InputDecoration(labelText: ref.t('auth.password'),
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))),
              validator: (s) => (s == null || s.isEmpty) ? ref.t('val.password') : null),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => context.push('/forgot'), child: Text(ref.t('auth.forgot')))),
          const SizedBox(height: 8),
          JolayButton(label: ref.t('btn.login'), busy: _busy, onPressed: _submit),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.push('/signup'), child: Text('${ref.t('auth.noAccount')} ${ref.t('btn.signup')}')),
        ])),
      ]);
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
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: ref.t('auth.forgotTitle'), subtitle: ref.t('auth.forgotBody'), children: [
        Form(key: _form, child: Column(children: [
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('auth.phone')), validator: v(ref, Validators.phone)),
          const SizedBox(height: 20),
          JolayButton(label: ref.t('btn.send'), busy: _busy, onPressed: _submit),
        ])),
      ]);
}

class ResetScreen extends ConsumerStatefulWidget {
  final String identifier;
  const ResetScreen({super.key, required this.identifier});
  @override
  ConsumerState<ResetScreen> createState() => _ResetState();
}

class _ResetState extends ConsumerState<ResetScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController(), _pw = TextEditingController(), _pw2 = TextEditingController();
  bool _busy = false, _obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).reset(widget.identifier, _code.text.trim(), _pw.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(localeProvider).languageCode == 'en' ? tr(const Locale('en'), 'auth.resetDone') : tr(ref.read(localeProvider), 'auth.resetDone'))));
      context.go('/login');
    } catch (e) { if (mounted) showError(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: ref.t('auth.resetTitle'), subtitle: '${ref.t('auth.otpBody')} ${widget.identifier}', children: [
        Form(key: _form, child: Column(children: [
          TextFormField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: ref.t('auth.code'), counterText: ''),
              validator: (s) => (s == null || s.length != 6) ? ref.t('auth.code') : null),
          const SizedBox(height: 8),
          TextFormField(controller: _pw, obscureText: _obscure, decoration: InputDecoration(labelText: ref.t('auth.newPassword'),
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))), validator: v(ref, Validators.password)),
          const SizedBox(height: 14),
          TextFormField(controller: _pw2, obscureText: _obscure, decoration: InputDecoration(labelText: ref.t('auth.confirm')), validator: v(ref, (s) => Validators.confirm(s, _pw.text))),
          const SizedBox(height: 20),
          JolayButton(label: ref.t('btn.save'), busy: _busy, onPressed: _submit),
        ])),
      ]);
}
