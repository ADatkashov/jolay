import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import 'common.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashState();
}

class _SplashState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    // Shows the splash for at least ~1.2 s, then the router redirect takes over based on auth status.
    Future.wait([ref.read(authProvider.notifier).restore(), Future<void>.delayed(const Duration(milliseconds: 1200))]);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JolayColors.yellow,
      body: SafeArea(
        child: Column(children: [
          const Spacer(flex: 2),
          FadeTransition(opacity: _c, child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)), child: const JolayLogo(size: 56))),
          const SizedBox(height: 12),
          FadeTransition(opacity: _c, child: Text(ref.t('app.slogan'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JolayColors.midnight))),
          const Spacer(),
          const SizedBox(height: 180, width: double.infinity, child: CityTaxiIllustration()),
        ]),
      ),
    );
  }
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<WelcomeScreen> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final slides = [
      (ref.t('welcome.title'), ref.t('welcome.body')),
      (ref.t('home.ride'), ref.t('welcome.s2')),
      (ref.t('ride.fareBreakdown'), ref.t('welcome.s3')),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [JolayLogo(size: 26), LanguageSwitcher()]),
            const SizedBox(height: 12),
            Expanded(
              flex: 5,
              child: ClipRRect(borderRadius: BorderRadius.circular(JolayRadius.lg), child: Container(color: Colors.white, child: const CityTaxiIllustration())),
            ),
            Expanded(
              flex: 3,
              child: PageView(controller: _pc, onPageChanged: (i) => setState(() => _page = i), children: [
                for (final s in slides)
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(s.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
                    const SizedBox(height: 10),
                    Text(s.$2, textAlign: TextAlign.center, style: const TextStyle(color: JolayColors.textSecondary, fontSize: 15)),
                  ]),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.all(3), width: i == _page ? 22 : 8, height: 8,
                    decoration: BoxDecoration(color: i == _page ? JolayColors.midnight : JolayColors.border, borderRadius: BorderRadius.circular(8))),
            ]),
            const SizedBox(height: 16),
            JolayButton(label: ref.t('btn.start'), onPressed: () => context.push('/signup')),
            const SizedBox(height: 10),
            JolayButton(label: ref.t('btn.login'), secondary: true, onPressed: () => context.push('/login')),
          ]),
        ),
      ),
    );
  }
}
