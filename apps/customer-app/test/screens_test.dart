import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_customer/src/data/models.dart';
import 'package:jolay_customer/src/data/providers.dart';
import 'package:jolay_customer/src/screens/auth_screens.dart';
import 'package:jolay_customer/src/screens/legal_screen.dart';
import 'package:jolay_customer/src/screens/onboarding.dart';
import 'package:jolay_customer/src/screens/ride_screens.dart';
import 'package:jolay_customer/src/screens/support_screens.dart';

import 'helpers.dart';

void main() {
  legalAndSosTests();
  testWidgets('country picker rewrites the dial code of the phone field', (t) async {
    await t.pumpWidget(app(const SignUpScreen(), api: FakeApi({}), overrides: [localeProvider.overrideWith(() => _En())]));
    await t.enterText(find.byKey(const Key('signup-phone')), '+7 701 222 33 44');
    await t.tap(find.byKey(const Key('country-picker')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('country-Kyrgyzstan')));
    await t.pumpAndSettle();
    expect(find.text('+996 701 222 33 44'), findsOneWidget);
  });

  testWidgets('login validates input locally and does not call the API', (t) async {
    final api = FakeApi({});
    await t.pumpWidget(app(const LoginScreen(), api: api));
    await t.tap(find.text('Кіру').last);                         // default locale is Kazakh
    await t.pump();
    expect(find.text('Телефон нөмірін халықаралық форматта енгізіңіз'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('sign up: weak password, mismatched confirmation and missing terms are all rejected', (t) async {
    final api = FakeApi({});
    await t.pumpWidget(app(const SignUpScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.enterText(find.byKey(const Key('signup-name')), 'Aidar Bekov');
    await t.enterText(find.byKey(const Key('signup-phone')), '+7 701 222 33 44');
    await t.enterText(find.byKey(const Key('signup-password')), 'short');
    await t.enterText(find.byKey(const Key('signup-confirm')), 'different1');
    await t.ensureVisible(find.text('Sign up').last);
    await t.tap(find.text('Sign up').last);
    await t.pump();
    expect(find.text('At least 8 characters with a letter and a digit'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('You must accept the terms'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('sign up sends a normalised phone and the accepted terms, then continues to OTP', (t) async {
    final api = FakeApi({'POST /auth/register': {'phone': '+77012223344'}});
    await t.pumpWidget(app(const SignUpScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.enterText(find.byKey(const Key('signup-name')), 'Aidar Bekov');
    await t.enterText(find.byKey(const Key('signup-phone')), '8 701 222 33 44');
    await t.enterText(find.byKey(const Key('signup-password')), 'Secret123');
    await t.enterText(find.byKey(const Key('signup-confirm')), 'Secret123');
    await t.ensureVisible(find.byKey(const Key('signup-terms')));
    await t.tap(find.byKey(const Key('signup-terms')));
    await t.ensureVisible(find.text('Sign up').last);
    await t.tap(find.text('Sign up').last);
    await t.pump();
    final call = api.calls.singleWhere((c) => c.path == '/auth/register');
    final body = call.body as Map;
    expect(body['phone'], '+77012223344');
    expect(body['role'], 'CUSTOMER');
    expect(body['acceptTerms'], true);
  });

  testWidgets('language can be switched between kk, ru and en on the welcome screen', (t) async {
    await t.pumpWidget(app(const WelcomeScreen(), api: FakeApi({})));
    expect(find.text('Жүр, жеткіз, алға жыл.'), findsOneWidget);
    await t.tap(find.byKey(const Key('lang-ru')));
    await t.pump();
    expect(find.text('Езжай, доставляй, двигайся вперёд.'), findsOneWidget);
    await t.tap(find.byKey(const Key('lang-en')));
    await t.pump();
    expect(find.text('Ride, deliver, move forward.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('ride options show server-calculated prices and send category, payment and an idempotency key', (t) async {
    tallScreen(t);
    final est = {
      'distanceM': 7400, 'durationS': 960, 'routeSource': 'ESTIMATED',
      'categories': [
        {'code': 'ECONOMY', 'name': 'JOLAY Economy', 'description': 'Affordable', 'capacity': 4, 'etaSeconds': 180, 'available': true, 'fare': _fare('1340.00')},
        {'code': 'BUSINESS', 'name': 'JOLAY Business', 'description': 'Premium', 'capacity': 4, 'etaSeconds': null, 'available': false, 'fare': _fare('3200.00')},
      ],
    };
    final api = FakeApi({'POST /rides/estimate': est, 'POST /rides': rideJson(status: 'SEARCHING_DRIVER', paymentStatus: 'NONE', method: 'WALLET')});
    await t.pumpWidget(app(const RideOptionsScreen(), api: api, overrides: [
      localeProvider.overrideWith(() => _En()),
      draftProvider.overrideWith(() => _Draft()),
    ]));
    await t.pumpAndSettle();
    expect(find.text('JOLAY Economy'), findsOneWidget);
    expect(find.textContaining(RegExp(r'1[\s\u00A0\u202F]340')), findsOneWidget);                    // price comes from the backend response
    expect(find.text('No drivers nearby · 4 seats'), findsOneWidget);
    await t.tap(find.byKey(const Key('cat-BUSINESS')));
    await t.ensureVisible(find.byKey(const Key('pay-WALLET')));
    await t.tap(find.byKey(const Key('pay-WALLET')));
    await t.pump();
    await t.tap(find.byKey(const Key('confirm-ride')));
    await t.pump();
    final create = api.calls.firstWhere((c) => c.path == '/rides');
    final body = create.body as Map;
    expect(body['category'], 'BUSINESS');
    expect(body['paymentMethod'], 'WALLET');
    expect(body.containsKey('fare'), isFalse, reason: 'the client must never submit a price');
    expect(create.headers!['Idempotency-Key'], startsWith('ride-'));
  });

  testWidgets('ride creation errors are shown localized (active ride exists)', (t) async {
    final est = {'distanceM': 5000, 'durationS': 600, 'routeSource': 'ESTIMATED', 'categories': [{'code': 'ECONOMY', 'name': 'E', 'description': 'd', 'capacity': 4, 'etaSeconds': 60, 'available': true, 'fare': _fare('900.00')}]};
    final api = FakeApi({'POST /rides/estimate': est})..throwOn = ApiException(409, 'active_ride_exists', 'x');
    await t.pumpWidget(app(const RideOptionsScreen(), api: api, overrides: [localeProvider.overrideWith(() => _Ru()), draftProvider.overrideWith(() => _Draft())]));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-ride')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('У вас уже есть активная поездка'), findsOneWidget);
  });

  testWidgets('completed ride: unpaid card ride offers payment; paid ride does not; rating is submitted to the backend', (t) async {
    tallScreen(t);
    final unpaid = FakeApi({'GET /rides/r1': rideJson(paymentStatus: 'PENDING'), 'GET /rides/r1/fare': [{'base_fare': '300.00', 'distance_fare': '800.00', 'time_fare': '270.00', 'fees': '0.00', 'discount': '0.00', 'multiplier': '1.00', 'total': '1390.00'}], 'POST /rides/r1/rating': null});
    await t.pumpWidget(app(const RideTrackScreen(rideId: 'r1'), api: unpaid, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.byKey(const Key('pay-now')), findsOneWidget);
    expect(find.text('Payment pending'), findsOneWidget);
    expect(find.textContaining(RegExp(r'1[\s\u00A0\u202F]390')), findsWidgets);
    await t.ensureVisible(find.byKey(const Key('star-5')));
    await t.tap(find.byKey(const Key('star-5')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('submit-rating')));
    await t.tap(find.byKey(const Key('submit-rating')));
    await t.pump();
    final rating = unpaid.calls.firstWhere((c) => c.path == '/rides/r1/rating').body as Map;
    expect(rating['stars'], 5);
    await t.pumpWidget(const SizedBox());

    final paid = FakeApi({'GET /rides/r1': rideJson(paymentStatus: 'PAID', method: 'CASH'), 'GET /rides/r1/fare': <dynamic>[]});
    await t.pumpWidget(app(const RideTrackScreen(rideId: 'r1'), api: paid, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.byKey(const Key('pay-now')), findsNothing);
    expect(find.text('Paid'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('searching screen offers cancel and talks to the backend', (t) async {
    final api = FakeApi({'GET /rides/r1': rideJson(status: 'SEARCHING_DRIVER', paymentStatus: 'NONE'), 'POST /rides/r1/cancel': rideJson(status: 'CANCELLED', paymentStatus: 'NONE')});
    await t.pumpWidget(app(const RideTrackScreen(rideId: 'r1'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.text('Finding your driver…'), findsOneWidget);
    await t.tap(find.byKey(const Key('cancel-search')));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Cancel ride'));
    await t.pump(const Duration(milliseconds: 400));
    expect(api.calls.any((c) => c.method == 'POST' && c.path == '/rides/r1/cancel'), isTrue);
    await t.pumpWidget(const SizedBox());   // dispose: stops the polling timer and animations
  });
}


void legalAndSosTests() {
  testWidgets('legal screen says "not published" instead of inventing text', (t) async {
    final api = FakeApi({'GET /catalog/legal/TERMS': ApiException(404, 'legal_not_published', 'x')});
    await t.pumpWidget(app(const LegalScreen(type: 'TERMS'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.byKey(const Key('legal-missing')), findsOneWidget);
    expect(find.text('This document has not been published yet.'), findsOneWidget);
    expect(api.calls.single.path, '/catalog/legal/TERMS');
  });

  testWidgets('legal screen shows the published text and version', (t) async {
    final api = FakeApi({'GET /catalog/legal/PRIVACY': {'type': 'PRIVACY', 'locale': 'ru', 'version': 3, 'body': 'Текст политики'}});
    await t.pumpWidget(app(const LegalScreen(type: 'PRIVACY'), api: api, overrides: [localeProvider.overrideWith(() => _Ru())]));
    await t.pump(); await t.pump();
    expect(find.text('Текст политики'), findsOneWidget);
    expect(find.text('Версия 3'), findsOneWidget);
  });

  testWidgets('emergency contacts: list, add with a normalised phone, and remove', (t) async {
    final api = FakeApi({
      'GET /customers/me/emergency-contacts': [{'id': 'c1', 'name': 'Mom', 'phone': '+77011112233'}],
      'POST /customers/me/emergency-contacts': {'id': 'c2', 'name': 'Dad', 'phone': '+77011112244'},
      'DELETE /customers/me/emergency-contacts/c1': null,
    });
    await t.pumpWidget(app(const EmergencyContactsScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.text('Mom'), findsOneWidget);
    await t.tap(find.byKey(const Key('contact-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('contact-name')), 'Dad');
    await t.enterText(find.byKey(const Key('contact-phone')), '8 701 111 22 44');
    await t.tap(find.byKey(const Key('contact-save')));
    await t.pumpAndSettle();
    final post = api.calls.firstWhere((c) => c.method == 'POST');
    expect(post.body, {'name': 'Dad', 'phone': '+77011112244'});
    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    expect(api.calls.any((c) => c.method == 'DELETE' && c.path == '/customers/me/emergency-contacts/c1'), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('referral screen shows the code, copies it, and says when the programme is off; sign-up sends the code', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final api = FakeApi({'GET /customers/me/referral': {'code': 'JABCD234', 'enabled': false, 'invited': 2, 'rewarded': 1, 'earned': 1000, 'referrerBonus': 1000, 'refereeBonus': 1000}});
    await t.pumpWidget(app(const ReferralScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.text('JABCD234'), findsOneWidget);
    expect(find.byKey(const Key('referral-off')), findsOneWidget);
    await t.tap(find.byKey(const Key('referral-copy')));
    await t.pump(const Duration(milliseconds: 300));
    expect(copied, 'JABCD234');
    await t.pumpWidget(const SizedBox());

    final api2 = FakeApi({'POST /auth/register': {'phone': '+77012223344'}});
    await t.pumpWidget(app(const SignUpScreen(), api: api2, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.enterText(find.byKey(const Key('signup-name')), 'Aidar Bekov');
    await t.enterText(find.byKey(const Key('signup-phone')), '8 701 222 33 44');
    await t.enterText(find.byKey(const Key('signup-password')), 'Secret123');
    await t.enterText(find.byKey(const Key('signup-confirm')), 'Secret123');
    await t.ensureVisible(find.byKey(const Key('signup-referral')));
    await t.enterText(find.byKey(const Key('signup-referral')), 'JABCD234');
    await t.ensureVisible(find.byKey(const Key('signup-terms')));
    await t.tap(find.byKey(const Key('signup-terms')));
    await t.ensureVisible(find.text('Sign up').last);
    await t.tap(find.text('Sign up').last);
    await t.pump();
    expect((api2.calls.singleWhere((c) => c.path == '/auth/register').body as Map)['referralCode'], 'JABCD234');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sharing a trip creates a link and copies it to the clipboard', (t) async {
    tallScreen(t);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final api = FakeApi({'GET /rides/r1': rideJson(status: 'DRIVER_ARRIVING', paymentStatus: 'NONE'), 'POST /rides/r1/share': {'token': 'abc', 'url': 'https://api.jolay.kz/api/v1/catalog/trip/abc'}});
    await t.pumpWidget(app(const RideTrackScreen(rideId: 'r1'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    await t.tap(find.byKey(const Key('share-trip')));
    await t.pump(const Duration(milliseconds: 400));
    expect(copied, 'https://api.jolay.kz/api/v1/catalog/trip/abc');
    expect(find.text('Link copied — send it to someone you trust'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('SOS during a ride notifies JOLAY support with the position and does not claim anything else', (t) async {
    tallScreen(t);
    final api = FakeApi({'GET /rides/r1': rideJson(status: 'DRIVER_ARRIVING', paymentStatus: 'NONE'), 'POST /incidents': {'id': 'i1', 'status': 'OPEN', 'duplicate': false}});
    await t.pumpWidget(app(const RideTrackScreen(rideId: 'r1'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    await t.tap(find.byKey(const Key('sos')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Emergency help'), findsOneWidget);
    await t.tap(find.byKey(const Key('sos-notify')));
    await t.pump(const Duration(milliseconds: 400));
    final call = api.calls.firstWhere((c) => c.path == '/incidents');
    final body = call.body as Map;
    expect(body['type'], 'SOS');
    expect((body['point'] as Map)['lat'], 43.2335);   // falls back to the pickup point when the driver position is unknown
    expect(find.text('Support has been notified. If you are in danger, call 112.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

Map<String, dynamic> _fare(String total) => {'baseFare': '300.00', 'distanceFare': '800.00', 'timeFare': '240.00', 'fees': '0.00', 'discount': '0.00', 'multiplier': '1.00', 'total': total};

class _En extends LocaleController { @override Locale build() => const Locale('en'); }
class _Ru extends LocaleController { @override Locale build() => const Locale('ru'); }
class _Draft extends DraftController {
  @override
  Draft build() => const Draft(pickup: Place('Dostyk Plaza', 'Dostyk Plaza', 43.2335, 76.9567), dropoff: Place('Mega', 'Mega Alma-Ata', 43.2025, 76.9066));
}
