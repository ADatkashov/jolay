import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jolay_core/jolay_core.dart';

import 'screens/auth_screens.dart';
import 'screens/express_screens.dart';
import 'screens/legal_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding.dart';
import 'screens/ride_screens.dart';
import 'screens/shell.dart';
import 'screens/shop_screens.dart';
import 'screens/support_screens.dart';

/// Re-evaluates redirects whenever the auth status changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  const publicPaths = {
    '/splash',
    '/welcome',
    '/signup',
    '/otp',
    '/login',
    '/forgot',
    '/reset',
    '/legal/TERMS',
    '/legal/PRIVACY',
  };
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authProvider).status;
      final loc = state.matchedLocation;
      if (status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }
      // '/splash' is in publicPaths, but once the session check says "signed out" the splash must be left too,
      // otherwise a fresh install stays on the splash forever.
      if (status == AuthStatus.signedOut &&
          (loc == '/splash' || !publicPaths.contains(loc))) {
        return '/welcome';
      }
      if (status == AuthStatus.signedIn &&
          publicPaths.contains(loc) &&
          !loc.startsWith('/legal')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, s) => OtpScreen(phone: s.extra as String),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotScreen()),
      GoRoute(
        path: '/reset',
        builder: (_, s) => ResetScreen(identifier: s.extra as String),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Shell()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(path: '/shops', builder: (_, _) => const ShopsScreen()),
      GoRoute(
        path: '/store/:id',
        builder: (_, s) => StoreScreen(storeId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/shop-order/:id',
        builder: (_, s) => ShopOrderScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/express/new',
        builder: (_, _) => const ExpressCreateScreen(),
      ),
      GoRoute(
        path: '/express/:id',
        builder: (_, s) => ExpressTrackScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ride/destination',
        builder: (_, _) => const DestinationScreen(),
      ),
      GoRoute(
        path: '/ride/options',
        builder: (_, _) => const RideOptionsScreen(),
      ),
      GoRoute(
        path: '/ride/:id',
        builder: (_, s) => RideTrackScreen(rideId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/legal/:type',
        builder: (_, s) => LegalScreen(type: s.pathParameters['type']!),
      ),
      GoRoute(path: '/invite', builder: (_, _) => const ReferralScreen()),
      GoRoute(
        path: '/contacts',
        builder: (_, _) => const EmergencyContactsScreen(),
      ),
      GoRoute(path: '/support', builder: (_, _) => const SupportListScreen()),
      GoRoute(
        path: '/support/:id',
        builder: (_, s) => SupportChatScreen(
          ticketId: s.pathParameters['id']!,
          subject: s.extra as String? ?? '',
        ),
      ),
    ],
  );
});
