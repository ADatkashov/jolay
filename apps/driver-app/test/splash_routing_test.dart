import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_driver/src/auth.dart';
import 'package:jolay_driver/src/router.dart';

/// Empty in-memory token storage: the real secure-storage plugin never answers under the fake-async test clock.
class _EmptyTokens extends TokenStore {
  @override
  Future<TokenPair?> read() async => null;
  @override
  Future<void> write(TokenPair t) async {}
  @override
  Future<void> clear() async {}
}

class _NoNetworkApi extends ApiClient {
  _NoNetworkApi() : super(tokens: _EmptyTokens());
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool auth = true,
    bool retry = true,
  }) async => null;
}

class _En extends LocaleController {
  @override
  Locale build() => const Locale('en');
}

/// A fresh install has no stored session: the splash must hand over to the login screen instead
/// of staying on the splash forever (regression: `/splash` counted as a public path for signed-out
/// users, so the redirect never fired and the app looked frozen).
void main() {
  testWidgets('signed-out driver leaves the splash for the login screen', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          requiredRoleProvider.overrideWithValue('DRIVER'),
          apiProvider.overrideWithValue(_NoNetworkApi()),
          localeProvider.overrideWith(() => _En()),
        ],
        child: Consumer(
          builder: (c, ref, _) => MaterialApp.router(
            theme: jolayTheme(),
            locale: ref.watch(localeProvider),
            supportedLocales: supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: ref.watch(driverRouterProvider),
          ),
        ),
      ),
    );
    expect(find.byType(DriverSplash), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1200));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(DriverSplash), findsNothing);
    expect(find.byType(DriverLogin), findsOneWidget);
  });
}
