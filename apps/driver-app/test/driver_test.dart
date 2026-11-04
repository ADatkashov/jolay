import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_driver/src/data.dart';
import 'package:jolay_driver/src/home.dart';

class FakeApi extends ApiClient {
  final Map<String, Object?> responses;
  final calls = <String>[];
  FakeApi(this.responses);
  @override
  Future<dynamic> request(String method, String path, {Object? body, Map<String, dynamic>? query, Map<String, String>? headers, bool auth = true, bool retry = true}) async {
    calls.add('$method $path');
    final r = responses['$method $path'];
    if (r is ApiException) throw r;
    return r;
  }
}

class _En extends LocaleController { @override Locale build() => const Locale('en'); }

Widget app(Widget child, FakeApi api, [List<Override> extra = const []]) => ProviderScope(
      overrides: [requiredRoleProvider.overrideWithValue('DRIVER'), apiProvider.overrideWithValue(api), localeProvider.overrideWith(() => _En()), eventsProvider.overrideWith((ref) => const Stream<RealtimeEvent>.empty()), ...extra],
      child: Consumer(builder: (c, ref, _) => MaterialApp(theme: jolayTheme(), locale: ref.watch(localeProvider), supportedLocales: supportedLocales,
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate], home: child)),
    );

void main() {
  testWidgets('a driver without a profile is sent to vehicle registration', (t) async {
    final api = FakeApi({'GET /drivers/me': ApiException(404, 'driver_not_registered', 'x')});
    await t.pumpWidget(app(const DriverGate(), api));
    await t.pump(); await t.pump();
    expect(find.text('Register your vehicle'), findsOneWidget);
  });

  testWidgets('an unapproved driver sees the review screen and cannot reach the work screen', (t) async {
    final api = FakeApi({'GET /drivers/me': {'verification': 'PENDING', 'availability': 'OFFLINE'}, 'GET /drivers/documents': <dynamic>[]});
    await t.pumpWidget(app(const DriverGate(), api));
    await t.pump(); await t.pump();
    expect(find.text('Account under review'), findsOneWidget);
    expect(find.byKey(const Key('online-switch')), findsNothing);
  });

  testWidgets('vehicle registration validates and posts the vehicle to the backend', (t) async {
    t.view.physicalSize = const Size(800, 1800); t.view.devicePixelRatio = 1.0; addTearDown(t.view.reset);
    final api = FakeApi({'POST /drivers/register': <String, dynamic>{}, 'GET /drivers/me': null});
    await t.pumpWidget(app(const VehicleRegistration(), api));
    await t.tap(find.text('Continue'));
    await t.pump();
    expect(api.calls.where((c) => c.contains('/drivers/register')), isEmpty);   // empty form is rejected locally
    await t.enterText(find.byKey(const Key('v-brand')), 'Toyota');
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(1), 'Camry'); await t.enterText(fields.at(2), '2020'); await t.enterText(fields.at(3), 'White'); await t.enterText(fields.at(4), '123ABC02');
    await t.tap(find.text('Continue'));
    await t.pump();
    expect(api.calls, contains('POST /drivers/register'));
  });

  testWidgets('earnings come from the backend and are shown formatted', (t) async {
    final api = FakeApi({'GET /drivers/earnings': {'trips': 3, 'gross': '5000.00', 'commission': '750.00', 'net': '4250.00', 'period': 'today'}, 'GET /wallet': {'balance': '-750.00', 'currency': 'KZT'}});
    await t.pumpWidget(app(const Scaffold(body: EarningsTab()), api));
    await t.pump(); await t.pump();
    expect(find.textContaining(RegExp(r'4[\s  ]250')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
