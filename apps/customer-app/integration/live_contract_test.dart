// Live contract test: the apps' REAL data layer (jolay_core ApiClient / AuthController / RealtimeClient and the customer app's providers and models)
// against a REAL running backend. It is what the fake-API widget tests cannot prove: that the JSON the server sends is what the apps parse.
//
// Not part of `flutter test` (it lives outside test/). Run it with scripts/live-contract-test.sh, or by hand:
//   LIVE_BACKEND_LOG=/path/to/backend.log flutter test --dart-define=JOLAY_API=http://127.0.0.1:8080 integration/live_contract_test.dart
// The backend must run with JOLAY_SMS_LOG_CODE=true (the OTP is read from its log) and a seeded admin (JOLAY_ADMIN_PHONE / JOLAY_ADMIN_PASSWORD).
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:jolay_customer/src/data/models.dart';
import 'package:jolay_customer/src/data/providers.dart';

class MemTokens extends TokenStore {
  TokenPair? _t;
  @override
  Future<TokenPair?> read() async => _t;
  @override
  Future<void> write(TokenPair t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}

final _log = Platform.environment['LIVE_BACKEND_LOG'];
final _adminPhone = Platform.environment['LIVE_ADMIN_PHONE'] ?? '+77000000000';
final _adminPassword = Platform.environment['LIVE_ADMIN_PASSWORD'] ?? 'ChangeMe12345';
final _rnd = Random();

String _newPhone() => '+7705${_rnd.nextInt(10000000).toString().padLeft(7, '0')}';

/// Reads the newest OTP sent to [phone] from the backend's development SMS log line:  [DEV SMS] to=+770****34 text=...123456...
Future<String> otpFor(String phone) async {
  final masked = '${phone.substring(0, 4)}****${phone.substring(phone.length - 2)}';
  for (var i = 0; i < 40; i++) {
    for (final line in File(_log!).readAsLinesSync().reversed) {
      if (!line.contains('[DEV SMS] to=$masked')) continue;
      final m = RegExp(r'(\d{6})').firstMatch(line.split('text=').last);
      if (m != null) return m.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('no OTP for $phone in $_log');
}

/// One signed-in person (customer, driver or admin) with their own in-memory session and Riverpod container, exactly as an app instance has.
class Actor {
  final ProviderContainer c;
  final ApiClient api;
  final String phone;
  Actor._(this.c, this.api, this.phone);

  factory Actor(String role, String phone) {
    final api = ApiClient(tokens: MemTokens());
    final c = ProviderContainer(overrides: [apiProvider.overrideWithValue(api), requiredRoleProvider.overrideWithValue(role)]);
    return Actor._(c, api, phone);
  }

  AuthController get auth => c.read(authProvider.notifier);

  static Future<Actor> signUp(String role, String name) async {
    final a = Actor(role, _newPhone());
    await a.auth.register(fullName: name, phone: a.phone, password: 'Secret123', locale: 'ru');
    await a.auth.verifyOtp(a.phone, await otpFor(a.phone));
    return a;
  }

  void dispose() => c.dispose();
}

Future<T> _read<T>(ProviderContainer c, FutureProvider<T> p) async {
  final sub = c.listen(p, (_, _) {});
  try { return await c.read(p.future); } finally { sub.close(); }
}

void expectKeys(Map<dynamic, dynamic> m, List<String> keys, String what) {
  for (final k in keys) {
    expect(m.containsKey(k), isTrue, reason: '$what: the app reads "$k" but the backend did not send it (got ${m.keys.toList()})');
  }
}

void main() {
  if (_log == null) {
    test('live contract (skipped: set LIVE_BACKEND_LOG and start a backend, see the header)', () {}, skip: 'LIVE_BACKEND_LOG not set');
    return;
  }

  late Actor admin, customer, driver;
  late String rideId;

  setUpAll(() async {
    admin = Actor('CUSTOMER', _adminPhone);
    // The seeded admin signs in with password (no OTP); it is not a customer, so use the raw API for its session.
    final r = await admin.api.post('/auth/login', auth: false, body: {'identifier': _adminPhone, 'password': _adminPassword}) as Map;
    await admin.api.tokens.write(TokenPair(r['accessToken'] as String, r['refreshToken'] as String));
    customer = await Actor.signUp('CUSTOMER', 'Live Customer');
    driver = await Actor.signUp('DRIVER', 'Live Driver');
  });

  tearDownAll(() { admin.dispose(); customer.dispose(); driver.dispose(); });

  test('sign-up / session: AuthController parses the real responses', () {
    final s = customer.c.read(authProvider);
    expect(s.status, AuthStatus.signedIn);
    expect(s.user!.roles, contains('CUSTOMER'));
    expect(s.user!.phone, customer.phone);
  });

  test('driver onboarding: vehicle registration, admin approval, online + location (driver app request shapes)', () async {
    final plate = 'L${_rnd.nextInt(900) + 100}KZ';
    await driver.api.post('/drivers/register', body: {'vehicle': {'brand': 'Toyota', 'model': 'Camry', 'year': 2020, 'color': 'White', 'plate': plate, 'category': 'ECONOMY'}});
    final me = await driver.api.get('/drivers/me') as Map;
    expectKeys(me, ['verification', 'availability'], 'GET /drivers/me');
    final driverId = driver.c.read(authProvider).user!.id;
    await admin.api.put('/admin/drivers/$driverId/verification', body: {'status': 'APPROVED'});
    await driver.api.put('/drivers/availability', body: {'online': true});
    await driver.api.post('/drivers/location', body: {'point': {'lat': 43.2340, 'lng': 76.9570}, 'heading': 90, 'speedKmh': 30});
  });

  test('customer reads: addresses, places search, recent destinations, wallet, referral, contacts, tickets all parse', () async {
    final saved = await customer.api.post('/customers/me/addresses', body: {'label': 'Home', 'address': 'Dostyk Plaza', 'point': {'lat': 43.2335, 'lng': 76.9567}}) as Map;
    expect(saved['id'], isNotNull);
    final addresses = await _read(customer.c, savedAddressesProvider);
    expect(addresses.single.address, 'Dostyk Plaza');

    final places = ((await customer.api.get('/geo/places', query: {'q': 'Dostyk', 'lat': 43.2, 'lng': 76.9})) as List).map((e) => Place.fromJson((e as Map).cast<String, dynamic>())).toList();
    expect(places, isNotEmpty);
    expect(await _read(customer.c, recentDestinationsProvider), isEmpty);

    final wallet = await _read(customer.c, walletProvider);
    expect(wallet.keys, isNotEmpty);
    final referral = await _read(customer.c, referralProvider);
    expectKeys(referral, ['code', 'enabled', 'invited', 'rewarded', 'earned'], 'GET /customers/me/referral');
    expect(await _read(customer.c, emergencyContactsProvider), isEmpty);
    await customer.api.post('/customers/me/emergency-contacts', body: {'name': 'Mom', 'phone': '+77011112233'});
    final contacts = await _read(customer.c, emergencyContactsProvider);
    expectKeys(contacts.single, ['id', 'name', 'phone'], 'emergency contacts');
    expect(await _read(customer.c, ticketsProvider), isEmpty);
    final ticket = await customer.api.post('/support/tickets', body: {'category': 'RIDE', 'subject': 'Live test', 'message': 'hello'}) as Map;
    expect(ticket['id'], isNotNull);
    final tickets = await _read(customer.c, ticketsProvider);
    expectKeys(tickets.single, ['id', 'subject', 'unread'], 'support tickets list');
    final legal = await customer.api.get('/catalog/legal/TERMS', query: {'lang': 'ru'}, auth: false).then<Object?>((v) => v, onError: (Object e) => e);
    expect(legal is Map || (legal is ApiException && legal.status == 404), isTrue, reason: 'legal text is either published or a clean 404, got $legal');
  });

  test('a full cash ride: estimate -> order -> offer -> accept (WebSocket event) -> trip -> complete -> receipt -> rating -> history', () async {
    final events = <RealtimeEvent>[];
    final rt = RealtimeClient(customer.api.tokens);
    final sub = rt.events.listen(events.add);
    await rt.start();
    addTearDown(() async { await sub.cancel(); rt.stop(); });

    // estimate, exactly as RideOptionsScreen does it
    final est = Estimate.fromJson(((await customer.api.post('/rides/estimate', headers: {'Accept-Language': 'ru'},
        body: {'pickup': {'lat': 43.2335, 'lng': 76.9567}, 'dropoff': {'lat': 43.2025, 'lng': 76.9066}})) as Map).cast<String, dynamic>());
    expect(est.categories, isNotEmpty);
    final economy = est.categories.firstWhere((c) => c.code == 'ECONOMY');
    expect(economy.available, isTrue, reason: 'the live driver is nearby');
    expect(double.parse(economy.fare.payable), greaterThan(0));

    // order, exactly as _confirm does it
    final created = Ride.fromJson(((await customer.api.post('/rides', headers: {'Idempotency-Key': 'live-${DateTime.now().microsecondsSinceEpoch}'}, body: {
      'pickup': {'point': {'lat': 43.2335, 'lng': 76.9567}, 'address': 'Dostyk Plaza'},
      'dropoff': {'point': {'lat': 43.2025, 'lng': 76.9066}, 'address': 'Mega Alma-Ata'},
      'category': 'ECONOMY', 'paymentMethod': 'CASH',
    })) as Map).cast<String, dynamic>());
    rideId = created.id;
    expect(created.status, 'SEARCHING_DRIVER');
    final active = await _read(customer.c, activeRideProvider);
    expect(active!.id, rideId);

    // share the trip (public view, no auth)
    final share = await customer.api.post('/rides/$rideId/share') as Map;
    final pub = await customer.api.get('/catalog/ride-share/${share['token']}', auth: false) as Map;
    expect(pub['active'], true);
    expect(pub.containsKey('phone'), isFalse);

    // the driver's screen: polling /drivers/offers as the driver app does
    final offer = await _until(() async { final o = await driver.api.get('/drivers/offers'); return o is Map ? o.cast<String, dynamic>() : null; });
    expectKeys(offer, ['offer_id', 'pickup_address', 'dropoff_address', 'expected_earnings', 'pickup_distance_m', 'payment_method', 'seconds_left'], 'GET /drivers/offers');
    await driver.api.post('/drivers/offers/${offer['offer_id']}/accept');

    // the customer is told over the WebSocket, and REST agrees
    await _until(() async => events.any((e) => e.type == 'DRIVER_ACCEPTED') ? true : null);
    final assigned = await _read(customer.c, activeRideProvider);
    expect(assigned!.status, 'DRIVER_ASSIGNED');
    expect(assigned.driver, isNotNull);
    expect(assigned.driver!.plate, isNotEmpty);

    // the driver's active trip as the driver app reads it
    final trip = await driver.api.get('/drivers/rides/active') as Map;
    expectKeys(trip, ['id', 'status', 'pickup', 'dropoff', 'pickupAddress', 'dropoffAddress', 'estimatedFare', 'paymentMethod', 'payable', 'promoDiscount', 'customerName'], 'GET /drivers/rides/active');

    await driver.api.post('/drivers/rides/$rideId/en-route');
    await _driveTo(driver.api, 43.2335, 76.9567);      // to the pickup
    await driver.api.post('/drivers/rides/$rideId/arrived');
    await driver.api.post('/drivers/rides/$rideId/start');
    await _driveTo(driver.api, 43.2025, 76.9066);      // the trip itself, in small steps like a real phone (the backend rejects GPS teleports)
    await driver.api.post('/drivers/rides/$rideId/complete');

    // the customer's receipt screen
    final done = Ride.fromJson(((await customer.api.get('/rides/$rideId')) as Map).cast<String, dynamic>());
    expect(done.status, 'COMPLETED');
    expect(done.paymentStatus, 'PAID');
    expect(double.parse(done.fare), greaterThan(0));
    final fare = ((await customer.api.get('/rides/$rideId/fare')) as List).cast<Map<String, dynamic>>().single;
    expectKeys(fare, ['base_fare', 'distance_fare', 'time_fare', 'fees', 'discount', 'multiplier', 'total'], 'GET /rides/{id}/fare (receipt)');
    expect(await _read(customer.c, activeRideProvider), isNull);

    await customer.api.post('/rides/$rideId/rating', body: {'stars': 5, 'tags': <String>[], 'comment': 'live'});
    final history = await _read(customer.c, historyProvider('completed'));
    expect(history.single.id, rideId);
    expect(history.single.rating, 5);

    // the driver's own lists
    final earnings = await driver.api.get('/drivers/earnings', query: {'period': 'today'}) as Map;
    expectKeys(earnings, ['trips', 'gross', 'commission', 'net'], 'GET /drivers/earnings');
    expect(earnings['trips'], 1);
    expectKeys(await driver.api.get('/wallet') as Map, ['balance'], 'GET /wallet (driver payouts screen)');
    final dHistory = (await driver.api.get('/drivers/rides/history') as List).cast<Map<String, dynamic>>();
    expect(dHistory.single['id'], rideId);

    // the public trip link keeps working after the trip but no longer shows the position
    final after = await customer.api.get('/catalog/ride-share/${share['token']}', auth: false) as Map;
    expect(after['status'], 'COMPLETED');
    expect(after.containsKey('driverLocation'), isFalse);
  });

  test('Express parcel: estimate -> order -> courier offer -> pickup -> handover code -> delivered -> public tracking', () async {
    // the courier is the same phone as the driver, parked where the previous ride ended (Mega Alma-Ata)
    await driver.api.put('/drivers/delivery', body: {'enabled': true});
    final est = await customer.api.post('/deliveries/estimate', body: {'pickup': {'lat': 43.2030, 'lng': 76.9070}, 'dropoff': {'lat': 43.2335, 'lng': 76.9567}, 'sizeClass': 'SMALL', 'weightKg': 2.0}) as Map;
    expectKeys(est, ['distanceM', 'fee', 'courierAvailable'], 'POST /deliveries/estimate');
    expectKeys(est['fee'] as Map, ['total'], 'POST /deliveries/estimate -> fee');

    final order = await customer.api.post('/deliveries', headers: {'Idempotency-Key': 'live-d-${DateTime.now().microsecondsSinceEpoch}'}, body: {
      'pickup': {'point': {'lat': 43.2030, 'lng': 76.9070}, 'address': 'Mega Alma-Ata'},
      'dropoff': {'point': {'lat': 43.2335, 'lng': 76.9567}, 'address': 'Dostyk Plaza'},
      'sizeClass': 'SMALL', 'weightKg': 2.0, 'description': 'Documents', 'paymentMethod': 'CASH',
      'sender': {'name': 'Live Customer', 'phone': customer.phone}, 'recipient': {'name': 'Aidar', 'phone': '+77011112244'},
    }) as Map;
    final id = order['id'] as String;

    final offer = await _until(() async { final o = await driver.api.get('/drivers/delivery-offers'); return o is Map ? o.cast<String, dynamic>() : null; });
    expectKeys(offer, ['offer_id', 'pickup_address', 'dropoff_address', 'expected_earnings', 'pickup_distance_m', 'payment_method', 'parcel_description', 'weight_kg'], 'GET /drivers/delivery-offers');
    await driver.api.post('/drivers/delivery-offers/${offer['offer_id']}/accept');

    final asDriver = await driver.api.get('/drivers/deliveries/active') as Map;
    expectKeys(asDriver, ['id', 'status', 'pickup', 'dropoff', 'pickupAddress', 'dropoffAddress', 'senderName', 'senderPhone', 'recipientName', 'recipientPhone', 'parcelDescription', 'weightKg', 'courierEarnings', 'trackingNumber'], 'GET /drivers/deliveries/active');
    expect(asDriver.containsKey('handoverCode'), isFalse, reason: 'the courier must never be sent the recipient code');

    final asCustomer = await customer.api.get('/deliveries/$id') as Map;
    expectKeys(asCustomer, ['courier', 'dropoff', 'dropoffAddress', 'fee', 'handoverCode', 'paymentMethod', 'paymentStatus', 'pickup', 'pickupAddress', 'recipientName', 'status', 'trackingNumber'], 'GET /deliveries/{id} (customer)');
    final code = asCustomer['handoverCode'] as String;
    expect(code, matches(r'^\d{4}$'));

    await _driveTo(driver.api, 43.2030, 76.9070);
    await driver.api.post('/drivers/deliveries/$id/picked-up');
    await _driveTo(driver.api, 43.2335, 76.9567);
    await expectLater(driver.api.post('/drivers/deliveries/$id/deliver', body: {'code': code == '0000' ? '1111' : '0000'}), throwsA(isA<ApiException>()), reason: 'a wrong handover code is refused');
    await driver.api.post('/drivers/deliveries/$id/deliver', body: {'code': code});

    final done = await customer.api.get('/deliveries/$id') as Map;
    expect(done['status'], 'DELIVERED');
    expect(done.containsKey('handoverCode') ? done['handoverCode'] : null, isNull, reason: 'the code is hidden once delivered');
    final pub = await customer.api.get('/catalog/track/${done['trackingNumber']}', auth: false) as Map;
    expect(pub['status'], 'DELIVERED');
    expect(pub.containsKey('phone'), isFalse);
    await customer.api.post('/deliveries/$id/rating', body: {'stars': 5});
  });

  test('wallet top-up through the sandbox gateway, then a wallet ride with a promo code, a peak window and a zone surcharge (all created by an admin)', () async {
    final top = await customer.api.post('/wallet/top-ups', body: {'amount': 5000}, headers: {'Idempotency-Key': 'live-t-${DateTime.now().microsecondsSinceEpoch}'}) as Map;
    expectKeys(top, ['id', 'checkoutUrl', 'amount'], 'POST /wallet/top-ups');
    expect(top['checkoutUrl'], contains('sandbox-checkout'));
    await customer.api.post('/payments/${top['id']}/sandbox-checkout');
    final wallet = await _read(customer.c, walletProvider);
    expect(double.parse(wallet['balance'].toString()), 5000);

    final code = 'LIVE${_rnd.nextInt(100000)}';
    final promo = await admin.api.post('/admin/promos', body: {'code': code, 'kind': 'FIXED', 'value': 200, 'perUserLimit': 1, 'firstRideOnly': false, 'active': true}) as Map;
    final zone = await admin.api.post('/admin/pricing/zones', body: {'city': 'ALA', 'name': 'Live zone', 'lat': 43.2030, 'lng': 76.9070, 'radiusM': 300, 'surcharge': 600, 'appliesTo': 'PICKUP', 'active': true}) as Map;
    final window = await admin.api.post('/admin/pricing/peak-windows', body: {'city': 'ALA', 'label': 'Live rush', 'days': [1, 2, 3, 4, 5, 6, 7], 'start': '00:00', 'end': '23:59', 'multiplier': 1.2, 'active': true}) as Map;
    addTearDown(() async {
      await admin.api.delete('/admin/pricing/zones/${zone['id']}');
      await admin.api.delete('/admin/pricing/peak-windows/${window['id']}');
      await admin.api.put('/admin/promos/${promo['id']}', body: {'code': code, 'kind': 'FIXED', 'value': 200, 'perUserLimit': 1, 'firstRideOnly': false, 'active': false});
    });

    await _driveTo(driver.api, 43.2032, 76.9072);                       // the driver waits near the pickup (Mega) for the next order
    final body = {'pickup': {'lat': 43.2030, 'lng': 76.9070}, 'dropoff': {'lat': 43.2335, 'lng': 76.9567}, 'promoCode': code.toLowerCase()};
    final est = Estimate.fromJson(((await customer.api.post('/rides/estimate', body: body)) as Map).cast<String, dynamic>());
    final fare = est.categories.firstWhere((c) => c.code == 'ECONOMY').fare;
    expect(fare.multiplier, 1.2, reason: 'the peak window is in the estimate');
    expect(double.parse(fare.fees), greaterThanOrEqualTo(600), reason: 'the zone surcharge is in the fee line');
    expect(double.parse(fare.discount), 200);
    expect(double.parse(fare.payable), double.parse(fare.total) - 200);

    await expectLater(customer.api.post('/rides/estimate', body: {...body, 'promoCode': 'NOPE'}), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'promo_not_found')));

    final ride = Ride.fromJson(((await customer.api.post('/rides', headers: {'Idempotency-Key': 'live-w-${DateTime.now().microsecondsSinceEpoch}'}, body: {
      'pickup': {'point': {'lat': 43.2030, 'lng': 76.9070}, 'address': 'Mega Alma-Ata'}, 'dropoff': {'point': {'lat': 43.2335, 'lng': 76.9567}, 'address': 'Dostyk Plaza'},
      'category': 'ECONOMY', 'paymentMethod': 'WALLET', 'promoCode': code,
    })) as Map).cast<String, dynamic>());
    expect(ride.promoCode, code);
    expect(double.parse(ride.promoDiscount), 200);

    final offer = await _until(() async { final o = await driver.api.get('/drivers/offers'); return o is Map ? o.cast<String, dynamic>() : null; });
    await driver.api.post('/drivers/offers/${offer['offer_id']}/accept');
    await driver.api.post('/drivers/rides/${ride.id}/en-route');
    await _driveTo(driver.api, 43.2030, 76.9070);   // back to the pickup (the courier ended at Dostyk)
    await driver.api.post('/drivers/rides/${ride.id}/arrived');
    await driver.api.post('/drivers/rides/${ride.id}/start');
    await _driveTo(driver.api, 43.2335, 76.9567);
    await driver.api.post('/drivers/rides/${ride.id}/complete');

    final done = Ride.fromJson(((await customer.api.get('/rides/${ride.id}')) as Map).cast<String, dynamic>());
    expect(done.paymentStatus, 'PAID');
    expect(done.hasPromo, isTrue);
    final newBalance = double.parse((await _read(customer.c, walletProvider))['balance'].toString());
    expect(newBalance, closeTo(5000 - double.parse(done.payable), 0.01), reason: 'the wallet was charged fare - promo');
  });

  test('SOS with an emergency contact, referral code, profile update and logout behave on the real backend', () async {
    final who = await Actor.signUp('CUSTOMER', 'Live Logout');
    addTearDown(who.dispose);
    await who.api.post('/customers/me/emergency-contacts', body: {'name': 'Mom', 'phone': '+77011112233'});
    final sos = await who.api.post('/incidents', body: {'type': 'SOS', 'point': {'lat': 43.23, 'lng': 76.95}}) as Map;
    expect(sos['status'], 'OPEN');
    await who.auth.updateProfile(fullName: 'Live Customer Renamed', locale: 'kk');
    expect(who.c.read(authProvider).user!.fullName, 'Live Customer Renamed');
    await who.auth.logout();
    expect(who.c.read(authProvider).status, AuthStatus.signedOut);
    await expectLater(who.api.get('/rides/active'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
  });
}

/// Where the live driver currently is (updated by [_driveTo]); the backend rejects GPS teleports, so every move starts from here.
double _dLat = 43.2340, _dLng = 76.9570;

/// Posts positions along a straight line in steps of at most ~400 m, as a phone reporting every few seconds would.
Future<void> _driveTo(ApiClient api, double lat1, double lng1) async {
  final lat0 = _dLat, lng0 = _dLng;
  final metres = sqrt(pow((lat1 - lat0) * 111320, 2) + pow((lng1 - lng0) * 111320 * cos(lat0 * pi / 180), 2));
  final steps = max(1, (metres / 400).ceil());
  for (var i = 1; i <= steps; i++) {
    final f = i / steps;
    await api.post('/drivers/location', body: {'point': {'lat': lat0 + (lat1 - lat0) * f, 'lng': lng0 + (lng1 - lng0) * f}, 'heading': 200, 'speedKmh': 40});
    _dLat = lat0 + (lat1 - lat0) * f; _dLng = lng0 + (lng1 - lng0) * f;
  }
}

Future<T> _until<T>(Future<T?> Function() probe, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final v = await probe();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw TimeoutException('condition not met within $timeout');
}
