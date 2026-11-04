import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

void toast(BuildContext context, WidgetRef ref, Object e) {
  final l = ref.read(localeProvider);
  final msg = e is ApiException ? (e.isNetwork ? tr(l, 'err.network') : errorText(l, e.code)) : tr(l, 'common.error');
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

FormFieldValidator<String> val(WidgetRef ref, String? Function(String?) fn) => (s) { final k = fn(s); return k == null ? null : tr(ref.read(localeProvider), k); };

class LangRow extends ConsumerWidget {
  const LangRow({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(localeProvider).languageCode;
    return Row(mainAxisSize: MainAxisSize.min, children: [for (final c in const ['kk', 'ru', 'en']) Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(key: Key('lang-$c'), label: Text(c.toUpperCase()), selected: cur == c, onSelected: (_) => ref.read(localeProvider.notifier).set(Locale(c)), selectedColor: JolayColors.yellow, visualDensity: VisualDensity.compact, side: BorderSide.none))]);
  }
}

/// Dark, driver-specific auth shell (intentionally different from the customer app).
class _DarkAuth extends ConsumerWidget {
  final String title;
  final List<Widget> children;
  const _DarkAuth({required this.title, required this.children});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: JolayColors.midnight,
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const JolayLogo(size: 26, color: Colors.white), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: JolayColors.yellow, borderRadius: BorderRadius.circular(6)), child: const Text('DRIVER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)))]), const LangRow()]),
          const SizedBox(height: 36),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Theme(data: ThemeData.dark(useMaterial3: true).copyWith(inputDecorationTheme: jolayTheme().inputDecorationTheme.copyWith(fillColor: const Color(0xFF262626), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)), colorScheme: const ColorScheme.dark(primary: JolayColors.yellow), filledButtonTheme: jolayTheme().filledButtonTheme), child: Column(children: children)),
        ]))),
      );
}

class DriverSplash extends ConsumerStatefulWidget {
  const DriverSplash({super.key});
  @override
  ConsumerState<DriverSplash> createState() => _SplashState();
}

class _SplashState extends ConsumerState<DriverSplash> {
  @override
  void initState() { super.initState(); Future.wait([ref.read(authProvider.notifier).restore(), Future<void>.delayed(const Duration(milliseconds: 1000))]); }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: JolayColors.midnight, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const JolayLogo(size: 52, color: Colors.white), const SizedBox(height: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: JolayColors.yellow, borderRadius: BorderRadius.circular(8)), child: const Text('DRIVER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3))),
      ])));
}

class DriverLogin extends ConsumerStatefulWidget {
  const DriverLogin({super.key});
  @override
  ConsumerState<DriverLogin> createState() => _LoginState();
}

class _LoginState extends ConsumerState<DriverLogin> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController(text: '+7 '), _pw = TextEditingController();
  bool _busy = false;

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try { await ref.read(authProvider.notifier).login(Validators.normalizePhone(_id.text), _pw.text); }
    catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _DarkAuth(title: ref.t('auth.loginTitle'), children: [
        Form(key: _form, child: Column(children: [
          TextFormField(key: const Key('d-phone'), controller: _id, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('auth.phone')), validator: val(ref, Validators.phone)),
          const SizedBox(height: 14),
          TextFormField(key: const Key('d-pw'), controller: _pw, obscureText: true, decoration: InputDecoration(labelText: ref.t('auth.password')), validator: (s) => (s == null || s.isEmpty) ? ref.t('val.password') : null),
          const SizedBox(height: 24),
          JolayButton(label: ref.t('btn.login'), busy: _busy, onPressed: _go),
          TextButton(onPressed: () => context.push('/signup'), child: Text('${ref.t('auth.noAccount')} ${ref.t('btn.signup')}', style: const TextStyle(color: Colors.white70))),
        ])),
      ]);
}

class DriverSignUp extends ConsumerStatefulWidget {
  const DriverSignUp({super.key});
  @override
  ConsumerState<DriverSignUp> createState() => _SignUpState();
}

class _SignUpState extends ConsumerState<DriverSignUp> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _phone = TextEditingController(text: '+7 '), _pw = TextEditingController();
  bool _terms = false, _busy = false, _termsErr = false;

  Future<void> _go() async {
    setState(() => _termsErr = !_terms);
    if (!_form.currentState!.validate() || !_terms) return;
    setState(() => _busy = true);
    try {
      final p = Validators.normalizePhone(_phone.text);
      await ref.read(authProvider.notifier).register(fullName: _name.text.trim(), phone: p, password: _pw.text, locale: ref.read(localeProvider).languageCode);
      if (mounted) context.push('/otp', extra: p);
    } catch (e) { if (mounted) toast(context, ref, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _DarkAuth(title: ref.t('auth.createTitle'), children: [
        Form(key: _form, child: Column(children: [
          TextFormField(key: const Key('d-name'), controller: _name, decoration: InputDecoration(labelText: ref.t('auth.fullName')), validator: val(ref, Validators.name)),
          const SizedBox(height: 14),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ref.t('auth.phone')), validator: val(ref, Validators.phone)),
          const SizedBox(height: 14),
          TextFormField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: ref.t('auth.password')), validator: val(ref, Validators.password)),
          CheckboxListTile(value: _terms, onChanged: (x) => setState(() => _terms = x ?? false), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, title: Text(ref.t('auth.terms'), style: const TextStyle(fontSize: 13, color: Colors.white70))),
          if (_termsErr && !_terms) Align(alignment: Alignment.centerLeft, child: Text(ref.t('val.terms'), style: const TextStyle(color: JolayColors.error, fontSize: 12))),
          const SizedBox(height: 16),
          JolayButton(label: ref.t('btn.signup'), busy: _busy, onPressed: _go),
        ])),
      ]);
}

class DriverOtp extends ConsumerStatefulWidget {
  final String phone;
  const DriverOtp({super.key, required this.phone});
  @override
  ConsumerState<DriverOtp> createState() => _OtpState();
}

class _OtpState extends ConsumerState<DriverOtp> {
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _verify() async {
    setState(() => _busy = true);
    try { await ref.read(authProvider.notifier).verifyOtp(widget.phone, _code.text); }
    catch (e) { if (mounted) { _code.clear(); toast(context, ref, e); } } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _DarkAuth(title: ref.t('auth.otpTitle'), children: [
        Text('${ref.t('auth.otpBody')} ${widget.phone}', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        TextField(key: const Key('d-otp'), controller: _code, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w800), decoration: const InputDecoration(counterText: ''), onChanged: (s) { setState(() {}); if (s.length == 6) _verify(); }),
        const SizedBox(height: 16),
        JolayButton(label: ref.t('btn.continue'), busy: _busy, onPressed: _code.text.length == 6 ? _verify : null),
        TextButton(onPressed: () async { try { await ref.read(authProvider.notifier).resendOtp(widget.phone); } catch (e) { if (mounted) toast(context, ref, e); } }, child: Text(ref.t('auth.resend'), style: const TextStyle(color: Colors.white70))),
      ]);
}
