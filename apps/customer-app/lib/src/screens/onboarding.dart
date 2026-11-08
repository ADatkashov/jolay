import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

/// Midnight splash: logo mark, wordmark, tagline and a three-dot loader in the brand yellow. Auth restore runs behind it;
/// the router redirect then moves to onboarding or home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashState();
}

class _SplashState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    // Shows the splash for at least ~1.2 s, then the router redirect takes over based on auth status.
    Future.wait([
      ref.read(authProvider.notifier).restore(),
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _in.value = 1;
      _dots.stop();
    } else if (!_dots.isAnimating) {
      _dots.repeat();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _in, curve: Curves.easeOut);
    return Scaffold(
      backgroundColor: AppColors.midnight,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 5),
            FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: Tween(begin: .92, end: 1.0).animate(
                  CurvedAnimation(parent: _in, curve: Curves.easeOutBack),
                ),
                child: Column(
                  children: [
                    const JolayMark(size: 88),
                    const SizedBox(height: 24),
                    const JolayLogo(size: 40, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      ref.t('app.slogan'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 4),
            Semantics(
              label: ref.t('common.loading'),
              liveRegion: true,
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _dots,
                  builder: (_, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.yellow.withValues(
                              alpha: context.reduceMotion
                                  ? .8
                                  : (.25 + .75 * _wave(_dots.value, i)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }

  double _wave(double t, int i) {
    final x = (t - i * .18) % 1.0;
    return x < .5 ? x * 2 : (1 - x) * 2;
  }
}

/// Three-step onboarding (move · order · send) with skip, language selection and page indicators.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<WelcomeScreen> {
  final _pc = PageController();
  int _page = 0;
  static const _scenes = [JolayScene.ride, JolayScene.order, JolayScene.send];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _scenes.length - 1) {
      _pc.nextPage(
        duration: context.motion(AppDurations.slow),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.push('/signup');
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _scenes.length - 1;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  const JolayLogo(size: 24),
                  const Spacer(),
                  const LanguageSelector(),
                  const SizedBox(width: 4),
                  AnimatedOpacity(
                    duration: context.motion(AppDurations.base),
                    opacity: last ? 0 : 1,
                    child: IgnorePointer(
                      ignoring: last,
                      child: AppTextButton(
                        key: const Key('onb-skip'),
                        label: ref.t('btn.skip'),
                        onPressed: () => context.push('/signup'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _scenes.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final art = (c.maxHeight * .55).clamp(160.0, 340.0);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: art,
                            width: art,
                            child: JolayIllustration(_scenes[i]),
                          ),
                          SizedBox(
                            height: (c.maxHeight * .05).clamp(12.0, 32.0),
                          ),
                          Semantics(
                            header: true,
                            child: Text(
                              ref.t('onb.${i + 1}.t'),
                              textAlign: TextAlign.center,
                              style: t.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            ref.t('onb.${i + 1}.b'),
                            textAlign: TextAlign.center,
                            style: t.bodyLarge?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _scenes.length; i++)
                  AnimatedContainer(
                    duration: context.motion(AppDurations.base),
                    margin: const EdgeInsets.all(3),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? (p.isDark ? p.accent : AppColors.midnight)
                          : p.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                children: [
                  PrimaryButton(
                    key: const Key('onb-next'),
                    label: last ? ref.t('btn.start') : ref.t('btn.continue'),
                    onPressed: _next,
                  ),
                  const SizedBox(height: 8),
                  AppTextButton(
                    key: const Key('onb-login'),
                    label: '${ref.t('auth.haveAccount')} ${ref.t('btn.login')}',
                    onPressed: () => context.push('/login'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
