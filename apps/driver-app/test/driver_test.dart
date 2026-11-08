import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_driver/src/data.dart';
import 'package:jolay_driver/src/home.dart';
import 'package:jolay_driver/src/payouts.dart';

class FakeApi extends ApiClient {
  final Map<String, Object?> responses;
  final calls = <String>[];
  FakeApi(this.responses);
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool auth = true,
    bool retry = true,
  }) async {
    calls.add('$method $path');
    final r = responses['$method $path'];
    if (r is ApiException) throw r;
    return r;
  }
}

class _En extends LocaleController {
  @override
  Locale build() => const Locale('en');
}

Widget app(Widget child, FakeApi api, [List<Override> extra = const []]) =>
    ProviderScope(
      overrides: [
        requiredRoleProvider.overrideWithValue('DRIVER'),
        apiProvider.overrideWithValue(api),
        localeProvider.overrideWith(() => _En()),
        eventsProvider.overrideWith(
          (ref) => const Stream<RealtimeEvent>.empty(),
        ),
        ...extra,
      ],
      child: Consumer(
        builder: (c, ref, _) => MaterialApp(
          theme: jolayTheme(),
          locale: ref.watch(localeProvider),
          supportedLocales: supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        ),
      ),
    );

void main() {
  testWidgets('a driver without a profile is sent to vehicle registration', (
    t,
  ) async {
    final api = FakeApi({
      'GET /drivers/me': ApiException(404, 'driver_not_registered', 'x'),
    });
    await t.pumpWidget(app(const DriverGate(), api));
    await t.pump();
    await t.pump();
    expect(find.text('Register your vehicle'), findsOneWidget);
  });

  testWidgets(
    'an unapproved driver sees the review screen and cannot reach the work screen',
    (t) async {
      final api = FakeApi({
        'GET /drivers/me': {
          'verification': 'PENDING',
          'availability': 'OFFLINE',
        },
        'GET /drivers/documents': <dynamic>[],
      });
      await t.pumpWidget(app(const DriverGate(), api));
      await t.pump();
      await t.pump();
      expect(find.text('Account under review'), findsOneWidget);
      expect(find.byKey(const Key('online-switch')), findsNothing);
    },
  );

  testWidgets(
    'vehicle registration validates and posts the vehicle to the backend',
    (t) async {
      t.view.physicalSize = const Size(800, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'POST /drivers/register': <String, dynamic>{},
        'GET /drivers/me': null,
      });
      await t.pumpWidget(app(const VehicleRegistration(), api));
      await t.tap(find.text('Continue'));
      await t.pump();
      expect(
        api.calls.where((c) => c.contains('/drivers/register')),
        isEmpty,
      ); // empty form is rejected locally
      await t.enterText(find.byKey(const Key('v-brand')), 'Toyota');
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(1), 'Camry');
      await t.enterText(fields.at(2), '2020');
      await t.enterText(fields.at(3), 'White');
      await t.enterText(fields.at(4), '123ABC02');
      await t.tap(find.text('Continue'));
      await t.pump();
      expect(api.calls, contains('POST /drivers/register'));
    },
  );

  testWidgets('earnings come from the backend and are shown formatted', (
    t,
  ) async {
    final api = FakeApi({
      'GET /drivers/earnings': {
        'trips': 3,
        'gross': '5000.00',
        'commission': '750.00',
        'net': '4250.00',
        'period': 'today',
      },
      'GET /wallet': {'balance': '-750.00', 'currency': 'KZT'},
    });
    await t.pumpWidget(app(const Scaffold(body: EarningsTab()), api));
    await t.pump();
    await t.pump();
    expect(find.textContaining(RegExp(r'4[\s  ]250')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
    'payout request validates locally and posts amount and destination; history shows backend status',
    (t) async {
      t.view.physicalSize = const Size(800, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'GET /wallet': {'balance': '8200.00', 'currency': 'KZT'},
        'GET /drivers/payouts': [
          {
            'id': 'p1',
            'amount': '5000.00',
            'status': 'PAID',
            'destination': '****1234',
            'created_at': '2026-11-04T10:30:00Z',
          },
        ],
        'POST /drivers/payouts': {'id': 'p2', 'status': 'REQUESTED'},
      });
      await t.pumpWidget(app(const PayoutsScreen(), api));
      await t.pump();
      await t.pump();
      expect(find.text('Paid'), findsOneWidget);
      await t.tap(find.byKey(const Key('payout-submit')));
      await t.pump();
      expect(
        api.calls.where((c) => c == 'POST /drivers/payouts'),
        isEmpty,
        reason: 'invalid form is not sent',
      );
      await t.enterText(find.byKey(const Key('payout-amount')), '5000');
      await t.enterText(
        find.byKey(const Key('payout-destination')),
        'KZ12 3456 7890 1234',
      );
      await t.tap(find.byKey(const Key('payout-submit')));
      await t.pump();
      expect(api.calls, contains('POST /drivers/payouts'));
    },
  );

  testWidgets(
    'profile switch tells the backend whether this driver accepts parcel deliveries',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final api = FakeApi({
        'GET /drivers/me': {
          'verification': 'APPROVED',
          'availability': 'OFFLINE',
          'accepts_delivery': false,
          'rating_avg': '5.0',
          'rating_count': 0,
        },
        'PUT /drivers/delivery': {'acceptsDelivery': true},
      });
      await t.pumpWidget(app(const Scaffold(body: DriverProfile()), api));
      await t.pump();
      await t.pump();
      final sw = find.byKey(const Key('accept-deliveries'));
      await t.ensureVisible(sw);
      await t.tap(sw);
      await t.pump();
      expect(api.calls, contains('PUT /drivers/delivery'));
    },
  );

  testWidgets(
    'a store order paid in cash tells the courier how much to collect; prepaid ones show nothing',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      Map<String, dynamic> d({String? cash}) => {
        'id': 'd1',
        'trackingNumber': 'JLABCD2345',
        'status': 'COURIER_ASSIGNED',
        'pickupAddress': 'Nan Bistro',
        'dropoffAddress': 'Home',
        'senderName': 'Nan Bistro',
        'recipientName': 'Aidar',
        'parcelDescription': 'Order S1',
        'weightKg': 3.0,
        'courierEarnings': '720.00',
        'pickup': {'lat': 43.23, 'lng': 76.95},
        'dropoff': {'lat': 43.2, 'lng': 76.9},
        'cashToCollect': ?cash,
      };
      await t.pumpWidget(
        app(
          Scaffold(
            body: ActiveDeliveryCard(
              delivery: d(cash: '5900.00'),
              busy: false,
              onAct: (_) async {},
              onRefresh: () async {},
            ),
          ),
          FakeApi({}),
        ),
      );
      await t.pump();
      expect(find.byKey(const Key('cash-to-collect')), findsOneWidget);
      expect(find.text('Collect cash from the customer'), findsOneWidget);
      await t.pumpWidget(
        app(
          Scaffold(
            body: ActiveDeliveryCard(
              delivery: d(),
              busy: false,
              onAct: (_) async {},
              onRefresh: () async {},
            ),
          ),
          FakeApi({}),
        ),
      );
      await t.pump();
      expect(find.byKey(const Key('cash-to-collect')), findsNothing);
    },
  );

  testWidgets(
    'a cash trip with a promo tells the driver the reduced amount to collect; without a promo nothing extra is shown',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      Map<String, dynamic> ride({String discount = '0'}) => {
        'id': 'r1',
        'status': 'DRIVER_ARRIVED',
        'customerName': 'Aidar',
        'estimatedFare': '1340.00',
        'paymentMethod': 'CASH',
        'promoDiscount': discount,
        'payable': '1240.00',
        'pickupAddress': 'A',
        'dropoffAddress': 'B',
        'pickup': {'lat': 43.23, 'lng': 76.95},
        'dropoff': {'lat': 43.2, 'lng': 76.9},
      };
      await t.pumpWidget(
        app(
          Scaffold(
            body: ActiveTripCard(
              ride: ride(discount: '100.00'),
              busy: false,
              onAct: (_) async {},
            ),
          ),
          FakeApi({}),
        ),
      );
      await t.pump();
      expect(find.byKey(const Key('promo-cash')), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'1[\s\u00A0\u202F]240')),
        findsOneWidget,
      );
      await t.pumpWidget(
        app(
          Scaffold(
            body: ActiveTripCard(
              ride: ride(),
              busy: false,
              onAct: (_) async {},
            ),
          ),
          FakeApi({}),
        ),
      );
      await t.pump();
      expect(find.byKey(const Key('promo-cash')), findsNothing);
    },
  );
}
