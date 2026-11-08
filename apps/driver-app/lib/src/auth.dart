import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

void toast(BuildContext context, WidgetRef ref, Object e) {
  final l = ref.read(localeProvider);
  final msg = e is ApiException
      ? (e.isNetwork ? tr(l, 'err.network') : errorText(l, e.code))
      : tr(l, 'common.error');
  showAppToast(context, msg, type: AppToastType.error);
}

FormFieldValidator<String> val(WidgetRef ref, String? Function(String?) fn) =>
    (s) {
      final k = fn(s);
      return k == null ? null : tr(ref.read(localeProvider), k);
    };

/// Kept for call-site compatibility; the shared [LanguageSelector] is the single implementation.
class LangRow extends StatelessWidget {
  const LangRow({super.key});
  @override
  Widget build(BuildContext context) => const LanguageSelector();
}

/// "DRIVER" tag next to the wordmark.
class DriverTag extends StatelessWidget {
  const DriverTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.yellow,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'DRIVER',
      style: TextStyle(
        fontFamily: AppTypography.family,
        package: AppTypography.package,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: .6,
        color: AppColors.midnight,
      ),
    ),
  );
}

/// Midnight auth shell (the driver app always opens in the dark brand surface; the tokens come from the shared dark theme).
class _DriverAuth extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _DriverAuth({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = jolayDarkTheme();
    final t = dark.textTheme;
    return Theme(
      data: dark.copyWith(scaffoldBackgroundColor: AppColors.midnight),
      child: Scaffold(
        backgroundColor: AppColors.midnight,
        body: SafeArea(
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
                    Row(
                      children: [
                        const JolayMark(size: 36),
                        const SizedBox(width: 10),
                        const JolayLogo(size: 22, color: Colors.white),
                        const SizedBox(width: 8),
                        const DriverTag(),
                        const Spacer(),
                        const LanguageSelector(onDark: true),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: t.headlineLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: t.bodyLarge?.copyWith(color: Colors.white70),
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
      ),
    );
  }
}

class _Eye extends ConsumerWidget {
  final bool obscure;
  final VoidCallback onTap;
  const _Eye({required this.obscure, required this.onTap});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: ref.t(obscure ? 'auth.showPassword' : 'auth.hidePassword'),
    icon: Icon(
      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
    ),
    onPressed: onTap,
  );
}

class DriverSplash extends ConsumerStatefulWidget {
  const DriverSplash({super.key});
  @override
  ConsumerState<DriverSplash> createState() => _SplashState();
}

class _SplashState extends ConsumerState<DriverSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future.wait([
      ref.read(authProvider.notifier).restore(),
      Future<void>.delayed(const Duration(milliseconds: 1000)),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) _in.value = 1;
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.midnight,
    body: Center(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const JolayMark(size: 80),
            const SizedBox(height: 22),
            const JolayLogo(size: 38, color: Colors.white),
            const SizedBox(height: 12),
            const DriverTag(),
          ],
        ),
      ),
    ),
  );
}

class DriverLogin extends ConsumerStatefulWidget {
  const DriverLogin({super.key});
  @override
  ConsumerState<DriverLogin> createState() => _LoginState();
}

class _LoginState extends ConsumerState<DriverLogin> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController(text: '+7 '), _pw = TextEditingController();
  bool _busy = false, _obscure = true;

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authProvider.notifier)
          .login(Validators.normalizePhone(_id.text), _pw.text);
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _DriverAuth(
    title: ref.t('auth.loginTitle'),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            AppTextField(
              key: const Key('d-phone'),
              controller: _id,
              keyboardType: TextInputType.phone,
              label: ref.t('auth.phone'),
              prefixIcon: Icons.phone_iphone_rounded,
              validator: val(ref, Validators.phone),
            ),
            const SizedBox(height: 14),
            AppTextField(
              key: const Key('d-pw'),
              controller: _pw,
              obscure: _obscure,
              label: ref.t('auth.password'),
              prefixIcon: Icons.lock_outline_rounded,
              suffix: _Eye(
                obscure: _obscure,
                onTap: () => setState(() => _obscure = !_obscure),
              ),
              validator: (s) =>
                  (s == null || s.isEmpty) ? ref.t('val.password') : null,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: ref.t('btn.login'),
              loading: _busy,
              onPressed: _go,
            ),
            const SizedBox(height: 8),
            Theme(
              data: jolayDarkTheme(),
              child: AppTextButton(
                expand: true,
                onPressed: () => context.push('/signup'),
                label: '${ref.t('auth.noAccount')} ${ref.t('btn.signup')}',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class DriverSignUp extends ConsumerStatefulWidget {
  const DriverSignUp({super.key});
  @override
  ConsumerState<DriverSignUp> createState() => _SignUpState();
}

class _SignUpState extends ConsumerState<DriverSignUp> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(text: '+7 '),
      _pw = TextEditingController();
  bool _terms = false, _busy = false, _termsErr = false, _obscure = true;

  Future<void> _go() async {
    setState(() => _termsErr = !_terms);
    if (!_form.currentState!.validate() || !_terms) return;
    setState(() => _busy = true);
    try {
      final p = Validators.normalizePhone(_phone.text);
      await ref
          .read(authProvider.notifier)
          .register(
            fullName: _name.text.trim(),
            phone: p,
            password: _pw.text,
            locale: ref.read(localeProvider).languageCode,
          );
      if (mounted) context.push('/otp', extra: p);
    } catch (e) {
      if (mounted) toast(context, ref, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _DriverAuth(
    title: ref.t('auth.createTitle'),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            AppTextField(
              key: const Key('d-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              label: ref.t('auth.fullName'),
              prefixIcon: AppIcons.person,
              validator: val(ref, Validators.name),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              label: ref.t('auth.phone'),
              prefixIcon: Icons.phone_iphone_rounded,
              validator: val(ref, Validators.phone),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _pw,
              obscure: _obscure,
              label: ref.t('auth.password'),
              prefixIcon: Icons.lock_outline_rounded,
              suffix: _Eye(
                obscure: _obscure,
                onTap: () => setState(() => _obscure = !_obscure),
              ),
              validator: val(ref, Validators.password),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _terms,
              onChanged: (x) => setState(() => _terms = x ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                ref.t('auth.terms'),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
            if (_termsErr && !_terms)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ref.t('val.terms'),
                  style: TextStyle(
                    color: JolayPalette.dark.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: ref.t('btn.signup'),
              loading: _busy,
              onPressed: _go,
            ),
          ],
        ),
      ),
    ],
  );
}

class DriverOtp extends ConsumerStatefulWidget {
  final String phone;
  const DriverOtp({super.key, required this.phone});
  @override
  ConsumerState<DriverOtp> createState() => _OtpState();
}

class _OtpState extends ConsumerState<DriverOtp> {
  final _code = TextEditingController();
  bool _busy = false, _error = false;

  Future<void> _verify() async {
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
        toast(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authProvider.notifier).resendOtp(widget.phone);
    } catch (e) {
      if (!mounted) return;
      toast(context, ref, e);
    }
  }

  @override
  Widget build(BuildContext context) => _DriverAuth(
    title: ref.t('auth.otpTitle'),
    subtitle: '${ref.t('auth.otpBody')} ${widget.phone}',
    children: [
      Theme(
        data: jolayDarkTheme(),
        child: Column(
          children: [
            OtpField(
              fieldKey: const Key('d-otp'),
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
                child: Row(
                  children: [
                    Icon(
                      Icons.error_rounded,
                      size: 16,
                      color: JolayPalette.dark.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ref.t('auth.otpError'),
                        style: TextStyle(
                          color: JolayPalette.dark.error,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: ref.t('btn.continue'),
              loading: _busy,
              onPressed: _code.text.length == 6 ? _verify : null,
            ),
            const SizedBox(height: 8),
            AppTextButton(
              expand: true,
              onPressed: _resend,
              label: ref.t('auth.resend'),
            ),
          ],
        ),
      ),
    ],
  );
}
