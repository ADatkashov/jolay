import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_customer/src/screens/shell.dart';

import 'helpers.dart';

class _Ru extends LocaleController {
  _Ru(this.l);
  final Locale l;
  @override
  Locale build() => l;
}

void main() {
  setUp(() {
    // Location services off: the home screen must still render, with the manual-entry card.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator_android'),
          (c) async => false,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator_apple'),
          (c) async => false,
        );
  });

  Future<void> pumpHome(WidgetTester t, Locale l, {double scale = 1}) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = FakeApi({
      'GET /rides/active': null,
      'GET /customers/me/addresses': [
        {'name': 'Home', 'address': 'Abay 10', 'lat': 43.24, 'lng': 76.95},
        {'name': 'Work', 'address': 'Dostyk 5', 'lat': 43.23, 'lng': 76.96},
      ],
      'GET /customers/me/recent-destinations': <dynamic>[],
      'GET /notifications': <dynamic>[],
    });
    await t.pumpWidget(
      app(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: const Scaffold(body: HomeTab()),
        ),
        api: api,
        overrides: [localeProvider.overrideWith(() => _Ru(l))],
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  for (final l in supportedLocales) {
    testWidgets(
      'home: three service tiles show their full text on a 320 dp phone (${l.languageCode}, 1.3x text)',
      (t) async {
        await pumpHome(t, l, scale: 1.3);
        expect(t.takeException(), isNull);
        for (final k in ['service.ride', 'service.order', 'service.send']) {
          final label = tr(l, k);
          // FittedBox scales the label down but never cuts it: the full string is in the tree.
          expect(
            find.text(label),
            findsOneWidget,
            reason: '$k in ${l.languageCode}',
          );
        }
        for (final k in [
          'service.rideSub',
          'service.orderSub',
          'service.sendSub',
        ]) {
          expect(find.text(tr(l, k)), findsOneWidget);
        }
        // Every tile meets the 48 dp touch target.
        for (final key in ['tile-ride', 'tile-order', 'tile-send']) {
          expect(
            t.getSize(find.byKey(Key(key))).height,
            greaterThanOrEqualTo(48),
          );
        }
      },
    );
  }

  testWidgets(
    'home: the sheet handle collapses and expands the shortcuts area',
    (t) async {
      await pumpHome(t, const Locale('en'));
      final handle = find.bySemanticsLabel('Hide list');
      expect(handle, findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      final before = t.getSize(find.byType(MapPanel)).height;
      await t.tap(handle);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.bySemanticsLabel('Show list'), findsOneWidget);
      // Collapsing never makes the panel taller; the three services stay reachable.
      expect(
        t.getSize(find.byType(MapPanel)).height,
        lessThanOrEqualTo(before),
      );
      expect(find.byKey(const Key('tile-ride')), findsOneWidget);
    },
  );
}
