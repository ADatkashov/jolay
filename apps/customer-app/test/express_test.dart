import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_customer/src/data/models.dart';
import 'package:jolay_customer/src/data/providers.dart';
import 'package:jolay_customer/src/screens/express_screens.dart';
import 'package:jolay_core/jolay_core.dart';

import 'helpers.dart';

class _En extends LocaleController {
  @override
  Locale build() => const Locale('en');
}

class _Draft extends DraftController {
  @override
  Draft build() => const Draft(
    pickup: Place('Dostyk Plaza', 'Dostyk Plaza', 43.2335, 76.9567),
  );
}

Map<String, dynamic> delivery({
  String status = 'SEARCHING_COURIER',
  bool code = true,
  int? rating,
  String payStatus = 'NONE',
}) => {
  'id': 'd1',
  'trackingNumber': 'JLABCD2345',
  'status': status,
  'sizeClass': 'SMALL',
  'weightKg': 1.0,
  'parcelDescription': 'Documents',
  'pickupAddress': 'Dostyk Plaza',
  'pickup': {'lat': 43.2335, 'lng': 76.9567},
  'dropoffAddress': 'Mega Alma-Ata',
  'dropoff': {'lat': 43.2025, 'lng': 76.9066},
  'recipientName': 'Dana Sadykova',
  'fee': '900.00',
  'paymentMethod': 'CASH',
  'paymentStatus': payStatus,
  if (code) 'handoverCode': '4821',
  'rating': ?rating,
  if (status == 'COURIER_ASSIGNED')
    'courier': {
      'name': 'Ahmed Khan',
      'phone': '+77012223344',
      'rating': 4.8,
      'vehicle': 'Toyota Camry',
      'plate': 'A1KZ',
      'lat': 43.23,
      'lng': 76.95,
    },
};

void main() {
  testWidgets(
    'express form calculates the fee on the server, sends normalised phones and never sends a price',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'GET /geo/places': [
          {
            'id': 'p',
            'name': 'Mega Alma-Ata',
            'address': 'Rozybakieva 247A',
            'lat': 43.2025,
            'lng': 76.9066,
          },
        ],
        'POST /deliveries/estimate': {
          'distanceM': 7400,
          'durationS': 900,
          'routeSource': 'ESTIMATED',
          'fee': {
            'base': '500',
            'distance': '300',
            'weight': '0',
            'total': '900.00',
            'currency': 'KZT',
          },
          'courierAvailable': true,
        },
        'POST /deliveries': delivery(),
      });
      await t.pumpWidget(
        app(
          const ExpressCreateScreen(),
          api: api,
          overrides: [
            localeProvider.overrideWith(() => _En()),
            draftProvider.overrideWith(() => _Draft()),
          ],
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('to-card')));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byKey(const Key('place-search')), 'Mega');
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Mega Alma-Ata').last);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('quote')), findsOneWidget);
      expect(find.textContaining(RegExp(r'900')), findsWidgets);
      await t.enterText(find.byKey(const Key('desc')), 'Documents');
      await t.enterText(find.byKey(const Key('s-name')), 'Aidar Bekov');
      await t.enterText(find.byKey(const Key('s-phone')), '+7 701 111 00 01');
      await t.enterText(find.byKey(const Key('r-name')), 'Dana Sadykova');
      await t.enterText(find.byKey(const Key('r-phone')), '8 701 222 33 44');
      await t.ensureVisible(find.byKey(const Key('express-order')));
      await t.tap(find.byKey(const Key('express-order')));
      await t.pump();
      final create = api.calls.firstWhere(
        (c) => c.method == 'POST' && c.path == '/deliveries',
      );
      final body = create.body as Map;
      expect((body['recipient'] as Map)['phone'], '+77012223344');
      expect(body['sizeClass'], 'SMALL');
      expect(
        body.containsKey('fee'),
        isFalse,
        reason: 'the client never submits a price',
      );
      expect(create.headers!['Idempotency-Key'], startsWith('express-'));
    },
  );

  testWidgets(
    'tracking shows the handover code and courier while active and offers cancel',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'GET /deliveries/d1': delivery(status: 'COURIER_ASSIGNED'),
        'POST /deliveries/d1/cancel': delivery(
          status: 'CANCELLED',
          code: false,
        ),
      });
      await t.pumpWidget(
        app(
          const ExpressTrackScreen(id: 'd1'),
          api: api,
          overrides: [localeProvider.overrideWith(() => _En())],
        ),
      );
      await t.pump();
      await t.pump();
      expect(find.text('Courier is heading to pick up'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('Ahmed Khan'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('express-cancel')));
      await t.tap(find.byKey(const Key('express-cancel')));
      await t.pump();
      expect(
        api.calls.any(
          (c) => c.method == 'POST' && c.path == '/deliveries/d1/cancel',
        ),
        isTrue,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a delivered order hides the code and lets the customer rate the courier',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'GET /deliveries/d1': delivery(
          status: 'DELIVERED',
          code: false,
          payStatus: 'PAID',
        ),
        'POST /deliveries/d1/rating': null,
      });
      await t.pumpWidget(
        app(
          const ExpressTrackScreen(id: 'd1'),
          api: api,
          overrides: [localeProvider.overrideWith(() => _En())],
        ),
      );
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('handover-code')), findsNothing);
      expect(find.text('Delivered'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('dstar-5')));
      await t.tap(find.byKey(const Key('dstar-5')));
      await t.pump();
      await t.tap(find.byKey(const Key('express-rate')));
      await t.pump();
      expect(
        (api.calls.firstWhere((c) => c.path == '/deliveries/d1/rating').body
            as Map)['stars'],
        5,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
