import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_customer/src/router.dart';
import 'package:jolay_customer/src/screens/onboarding.dart';

/// Empty in-memory token storage: the real secure-storage plugin never answers under the fake-async test clock.
class _EmptyTokens extends TokenStore {
  @override
  Future<TokenPair?> read() async => null;
  @override
  Future<void> write(TokenPair t) async {}
  @override
  Future<void> clear() async {}
}

class _NoSessionApi extends ApiClient {
  _NoSessionApi() : super(tokens: _EmptyTokens());
}

/// A fresh install has no stored session: the splash screen must hand over to the welcome screen
/// instead of staying on the splash forever (regression: `/splash` was treated as a public path
/// for signed-out users, so the redirect never fired and the app looked frozen).
void main() {
  testWidgets('signed-out user leaves the splash for the welcome screen', (
    t,
  ) async {
    final api = _NoSessionApi();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          requiredRoleProvider.overrideWithValue('CUSTOMER'),
          apiProvider.overrideWithValue(api),
        ],
        child: Consumer(
          builder: (c, ref, _) => MaterialApp.router(
            theme: jolayTheme(),
            supportedLocales: supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    expect(find.byType(SplashScreen), findsOneWidget);

    // The splash shows for ~1.2 s, then the router redirect takes over.
    await t.pump(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 600));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
