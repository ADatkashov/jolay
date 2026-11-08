import 'package:jolay_core/jolay_core.dart';

class _DemoTokens extends TokenStore {
  @override
  Future<TokenPair?> read() async => const TokenPair('demo', 'demo');
  @override
  Future<void> write(TokenPair t) async {}
  @override
  Future<void> clear() async {}
}

/// In-memory stand-in for the JOLAY backend with fixed Almaty sample data. Used only by `main_demo.dart`.
/// [state] picks what the driver is doing: idle · offline · offer · trip · delivery · pending.
class DemoDriverApi extends ApiClient {
  final String state;
  DemoDriverApi(this.state) : super(tokens: _DemoTokens());

  static const _pickup = {'lat': 43.2565, 'lng': 76.9285};
  static const _drop = {'lat': 43.2025, 'lng': 76.8930};

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
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (path == '/customers/me') {
      return {
        'id': 'd1',
        'fullName': 'Ерлан Сейтов',
        'phone': '+77015550123',
        'email': null,
        'roles': ['DRIVER'],
        'locale': 'ru',
      };
    }
    if (path == '/drivers/me') {
      return {
        'verification': state == 'pending' ? 'PENDING' : 'APPROVED',
        'availability': state == 'offline' ? 'OFFLINE' : 'ONLINE',
        'accepts_delivery': true,
        'rating_avg': '4.92',
        'rating_count': 318,
        'todayEarnings': '18400.00',
        'vehicle': {
          'brand': 'Toyota',
          'model': 'Camry',
          'year': 2021,
          'color': 'Белый',
          'plate': 'A 123 KZ',
          'category': 'COMFORT',
        },
      };
    }
    if (path == '/drivers/documents') {
      return [
        {'type': 'ID_CARD', 'status': 'APPROVED'},
        {'type': 'DRIVER_LICENSE', 'status': 'PENDING'},
        {'type': 'PHOTO', 'status': 'PENDING'},
      ];
    }
    if (path == '/drivers/earnings') {
      return switch (query?['period']) {
        'week' => {
          'trips': 41,
          'gross': '112500.00',
          'commission': '16875.00',
          'net': '95625.00',
          'period': 'week',
        },
        'month' => {
          'trips': 168,
          'gross': '455000.00',
          'commission': '68250.00',
          'net': '386750.00',
          'period': 'month',
        },
        _ => {
          'trips': 9,
          'gross': '21600.00',
          'commission': '3240.00',
          'net': '18360.00',
          'period': 'today',
        },
      };
    }
    if (path == '/wallet') return {'balance': '42300.00', 'currency': 'KZT'};
    if (path == '/drivers/payouts') {
      return [
        {
          'id': 'p1',
          'amount': '30000.00',
          'status': 'PAID',
          'destination': '****1234',
          'created_at': '2026-11-02T10:30:00Z',
        },
        {
          'id': 'p2',
          'amount': '15000.00',
          'status': 'REQUESTED',
          'destination': '****1234',
          'created_at': '2026-11-06T08:00:00Z',
        },
      ];
    }
    if (path == '/drivers/rides/history') {
      return [
        {
          'createdAt': '2026-11-06T08:12:00Z',
          'pickupAddress': 'Dostyk Plaza',
          'dropoffAddress': 'Аэропорт Алматы',
          'finalFare': '4200.00',
        },
        {
          'createdAt': '2026-11-06T06:40:00Z',
          'pickupAddress': 'Парк Горького',
          'dropoffAddress': 'Мега Парк',
          'finalFare': '1590.00',
        },
        {
          'createdAt': '2026-11-05T21:05:00Z',
          'pickupAddress': 'Алматы Тауэр',
          'dropoffAddress': 'Медеу',
          'finalFare': '2350.00',
        },
      ];
    }
    if (path == '/drivers/rides/active') {
      if (state != 'trip') return null;
      return {
        'id': 'r1',
        'status': 'DRIVER_ARRIVING',
        'customerName': 'Айдос Нурланов',
        'customerPhone': '+77012345678',
        'estimatedFare': '1340.00',
        'paymentMethod': 'CASH',
        'promoDiscount': '100.00',
        'payable': '1240.00',
        'pickupAddress': 'пр. Достык, 180',
        'dropoffAddress': 'ТРЦ Mega Alma-Ata',
        'pickup': _pickup,
        'dropoff': _drop,
      };
    }
    if (path == '/drivers/deliveries/active') {
      if (state != 'delivery') return null;
      return {
        'id': 'd1',
        'trackingNumber': 'JLABCD2345',
        'status': 'COURIER_ASSIGNED',
        'pickupAddress': 'Almaty Grill, ул. Розыбакиева 12',
        'dropoffAddress': 'мкр. Самал-2, 58',
        'senderName': 'Almaty Grill',
        'recipientName': 'Айдос',
        'parcelDescription': 'Заказ S-1042',
        'weightKg': 3.0,
        'courierEarnings': '720.00',
        'pickup': _pickup,
        'dropoff': _drop,
        'cashToCollect': '5900.00',
      };
    }
    if (path == '/drivers/offers') {
      if (state != 'offer') return null;
      return {
        'offer_id': 'o1',
        'seconds_left': 11,
        'pickup_distance_m': 1400,
        'eta_s': 240,
        'expected_earnings': '1980.00',
        'pickup_address': 'пр. Достык, 180',
        'dropoff_address': 'Аэропорт Алматы, ул. Майлина 2',
        'est_distance_m': 18400,
        'est_duration_s': 1620,
        'payment_method': 'CARD',
        'category_code': 'COMFORT',
      };
    }
    if (path == '/drivers/delivery-offers') return null;
    return method == 'GET' ? <dynamic>[] : <String, dynamic>{};
  }
}
