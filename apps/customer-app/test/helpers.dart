import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_customer/src/data/providers.dart';

/// Records every request and answers from a path -> response map. No network is ever touched.
class FakeApi extends ApiClient {
  final Map<String, Object?> responses;
  final List<({String method, String path, Object? body, Map<String, String>? headers})> calls = [];
  Object? throwOn;
  FakeApi(this.responses);

  @override
  Future<dynamic> request(String method, String path, {Object? body, Map<String, dynamic>? query, Map<String, String>? headers, bool auth = true, bool retry = true}) async {
    calls.add((method: method, path: path, body: body, headers: headers));
    if (throwOn != null && method == 'POST' && path == '/rides') throw throwOn!;
    final r = responses['$method $path'] ?? responses[path];
    if (r is Function) return r();
    return r;
  }
}

Widget app(Widget child, {FakeApi? api, List<Override> overrides = const [], Locale? locale}) => ProviderScope(
      overrides: [
        requiredRoleProvider.overrideWithValue('CUSTOMER'),
        if (api != null) apiProvider.overrideWithValue(api),
        realtimeEventsProvider.overrideWith((ref) => const Stream<RealtimeEvent>.empty()),
        ...overrides,
      ],
      child: Consumer(builder: (c, ref, _) => MaterialApp(
        theme: jolayTheme(), locale: ref.watch(localeProvider), supportedLocales: supportedLocales,
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: child,
      )),
    );

Map<String, dynamic> rideJson({String status = 'COMPLETED', String paymentStatus = 'PAID', String method = 'CARD', int? rating}) => {
      'id': 'r1', 'status': status, 'category': 'ECONOMY', 'pickupAddress': 'Dostyk Plaza', 'dropoffAddress': 'Mega Alma-Ata',
      'pickup': {'lat': 43.2335, 'lng': 76.9567}, 'dropoff': {'lat': 43.2025, 'lng': 76.9066}, 'distanceM': 7400, 'durationS': 960,
      'estimatedFare': '1340.00', 'finalFare': '1390.00', 'paymentMethod': method, 'paymentStatus': paymentStatus, 'cancellationFee': '0',
      'driver': {'name': 'Ahmed Khan', 'vehicle': 'Toyota Camry', 'color': 'White', 'plate': 'A1234KZ', 'rating': '4.8'}, 'rating': rating, 'createdAt': '2026-11-04T10:30:00Z',
    };

/// Phone-sized tall surface so stacked layouts are fully on screen during tests.
void tallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}
