import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import 'auth.dart';
import 'home.dart';

class _Refresh extends ChangeNotifier {
  _Refresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final driverRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _Refresh(ref);
  const pub = {'/splash', '/login', '/signup', '/otp'};
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(authProvider).status;
      final loc = state.matchedLocation;
      if (s == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
      if (s == AuthStatus.signedOut && !pub.contains(loc)) return '/login';
      if (s == AuthStatus.signedIn && pub.contains(loc)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const DriverSplash()),
      GoRoute(path: '/login', builder: (_, _) => const DriverLogin()),
      GoRoute(path: '/signup', builder: (_, _) => const DriverSignUp()),
      GoRoute(
        path: '/otp',
        builder: (_, s) => DriverOtp(phone: s.extra as String),
      ),
      GoRoute(path: '/home', builder: (_, _) => const DriverGate()),
    ],
  );
});
