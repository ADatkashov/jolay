import 'package:jolay_core/jolay_core.dart';

/// Token store that always holds a session, so the app boots straight into the signed-in state.
class _DemoTokens extends TokenStore {
  @override
  Future<TokenPair?> read() async => const TokenPair('demo', 'demo');
  @override
  Future<void> write(TokenPair t) async {}
  @override
  Future<void> clear() async {}
}

/// In-memory stand-in for the JOLAY backend with fixed Almaty sample data. Used only by `main_demo.dart`.
class DemoApi extends ApiClient {
  DemoApi() : super(tokens: _DemoTokens());

  static const _driver = {
    'name': 'Ахмед Хан',
    'vehicle': 'Toyota Camry',
    'color': 'Белый',
    'plate': 'A 123 KZ',
    'rating': '4.9',
    'phone': '+77011234567',
    'lat': 43.2410,
    'lng': 76.9300,
  };

  static Map<String, dynamic> _ride(
    String id,
    String status,
    String from,
    String to,
    String fare,
    String when, {
    bool driver = true,
    int? rating,
    String payStatus = 'PAID',
  }) => {
    'id': id,
    'status': status,
    'category': 'ECONOMY',
    'pickupAddress': from,
    'dropoffAddress': to,
    'pickup': {'lat': 43.2565, 'lng': 76.9285},
    'dropoff': {'lat': 43.2025, 'lng': 76.8930},
    'distanceM': 7400,
    'durationS': 960,
    'estimatedFare': fare,
    'finalFare': status == 'COMPLETED' ? fare : null,
    'paymentMethod': 'CARD',
    'paymentStatus': payStatus,
    'cancellationFee': '0',
    'driver': driver ? _driver : null,
    'driverEtaSeconds': 240,
    'rating': rating,
    'createdAt': when,
  };

  static final _active = _ride(
    'r-active',
    'DRIVER_ARRIVING',
    'пр. Достык, 180',
    'ТРЦ Mega Alma-Ata',
    '1340.00',
    '2026-11-06T09:40:00Z',
    payStatus: 'PENDING',
  );
  static final _done = [
    _ride(
      'r1',
      'COMPLETED',
      'Dostyk Plaza',
      'Аэропорт Алматы',
      '4200.00',
      '2026-11-04T10:30:00Z',
      rating: 5,
    ),
    _ride(
      'r2',
      'COMPLETED',
      'Парк Горького',
      'Мега Парк',
      '1590.00',
      '2026-11-02T18:05:00Z',
      rating: 5,
    ),
    _ride(
      'r3',
      'COMPLETED',
      'Алматы Тауэр',
      'Медеу',
      '2350.00',
      '2026-10-29T08:12:00Z',
      rating: 4,
    ),
  ];
  static final _cancelled = [
    _ride(
      'r4',
      'CANCELLED',
      'Сайран',
      'Артур-центр',
      '980.00',
      '2026-10-27T21:00:00Z',
      driver: false,
    ),
  ];

  static const _places = [
    {
      'name': 'ТРЦ Mega Alma-Ata',
      'address': 'ул. Розыбакиева, 247',
      'lat': 43.2025,
      'lng': 76.8930,
    },
    {
      'name': 'Аэропорт Алматы',
      'address': 'ул. Майлина, 2',
      'lat': 43.3521,
      'lng': 77.0405,
    },
    {
      'name': 'Парк Первого Президента',
      'address': 'пр. Аль-Фараби',
      'lat': 43.2180,
      'lng': 76.9290,
    },
    {
      'name': 'Зелёный базар',
      'address': 'ул. Жибек Жолы, 53',
      'lat': 43.2603,
      'lng': 76.9529,
    },
  ];

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
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final r = _route(method, path, query);
    return r;
  }

  dynamic _route(String method, String path, Map<String, dynamic>? q) {
    if (path == '/customers/me') {
      return {
        'id': 'u1',
        'fullName': 'Айдос Нурланов',
        'phone': '+77012345678',
        'email': 'aidos@example.kz',
        'roles': ['CUSTOMER'],
        'locale': 'ru',
      };
    }
    if (path == '/rides/active') {
      return _active;
    }
    if (path == '/rides/history') {
      return switch (q?['tab']) {
        'completed' => _done,
        'ongoing' => [_active],
        _ => _cancelled,
      };
    }
    if (path == '/customers/me/addresses') {
      return [
        {
          'name': 'Дом',
          'address': 'мкр. Самал-2, 58',
          'lat': 43.2338,
          'lng': 76.9567,
        },
        {
          'name': 'Работа',
          'address': 'пр. Аль-Фараби, 77',
          'lat': 43.2182,
          'lng': 76.9288,
        },
      ];
    }
    if (path == '/customers/me/recent-destinations') {
      return _places.take(3).toList();
    }
    if (path == '/geo/places') {
      return _places;
    }
    if (path == '/geo/reverse') {
      return {
        'name': 'пр. Достык, 180',
        'address': 'Алматы',
        'lat': 43.2565,
        'lng': 76.9285,
      };
    }
    if (path == '/wallet') {
      return {'balance': '12500.00'};
    }
    if (path == '/wallet/transactions') {
      return [
        {
          'type': 'TOP_UP',
          'description': 'Пополнение картой',
          'amount': '10000.00',
          'created_at': '2026-11-05T12:00:00Z',
        },
        {
          'type': 'RIDE',
          'description': 'Поездка · Аэропорт Алматы',
          'amount': '-4200.00',
          'created_at': '2026-11-04T10:50:00Z',
        },
        {
          'type': 'RIDE',
          'description': 'Поездка · Мега Парк',
          'amount': '-1590.00',
          'created_at': '2026-11-02T18:25:00Z',
        },
        {
          'type': 'TOP_UP',
          'description': 'Пополнение картой',
          'amount': '5000.00',
          'created_at': '2026-10-30T09:00:00Z',
        },
      ];
    }
    if (path == '/support/tickets') {
      return [
        {
          'id': 't1',
          'subject': 'Не прошла оплата поездки',
          'status': 'OPEN',
          'created_at': '2026-11-05T15:00:00Z',
        },
      ];
    }
    if (path == '/rides/estimate') {
      return {
        'distanceM': 7400,
        'durationS': 960,
        'routeSource': 'DEMO',
        'categories': [
          _cat('ECONOMY', 'Эконом', 'Бюджетная поездка', 4, 240, '1340.00'),
          _cat('COMFORT', 'Комфорт', 'Просторный седан', 4, 300, '1890.00'),
          _cat('BUSINESS', 'Бизнес', 'Премиум-авто', 4, 420, '3120.00'),
          _cat('MINIVAN', 'Минивэн', 'До 6 пассажиров', 6, 540, '2650.00'),
        ],
      };
    }
    if (path.startsWith('/rides/') && path.endsWith('/fare')) {
      return {
        'baseFare': '500',
        'distanceFare': '640',
        'timeFare': '200',
        'fees': '0',
        'discount': '0',
        'total': '1340.00',
      };
    }
    if (path == '/rides/r-search') {
      return _ride(
        'r-search',
        'SEARCHING_DRIVER',
        'пр. Достык, 180',
        'ТРЦ Mega Alma-Ata',
        '1340.00',
        DateTime.now().toUtc().toIso8601String(),
        driver: false,
        payStatus: 'PENDING',
      );
    }
    if (path == '/rides/r-done') {
      return _ride(
        'r-done',
        'COMPLETED',
        'пр. Достык, 180',
        'ТРЦ Mega Alma-Ata',
        '1340.00',
        '2026-11-06T09:40:00Z',
        payStatus: 'PENDING',
      );
    }
    if (path.startsWith('/rides/')) {
      return _active;
    }
    if (path == '/notifications') {
      return [
        {
          'id': 'n1',
          'type': 'DRIVER_ARRIVED',
          'payload': {'rideId': 'r-active'},
          'read_at': null,
          'created_at': '2026-11-06T09:44:00Z',
        },
        {
          'id': 'n2',
          'type': 'DRIVER_ACCEPTED',
          'payload': {'rideId': 'r-active'},
          'read_at': null,
          'created_at': '2026-11-06T09:41:00Z',
        },
        {
          'id': 'n3',
          'type': 'RIDE_COMPLETED',
          'payload': {'rideId': 'r1'},
          'read_at': '2026-11-04T10:50:00Z',
          'created_at': '2026-11-04T10:48:00Z',
        },
        {
          'id': 'n4',
          'type': 'PAYMENT_STATUS_UPDATED',
          'payload': {},
          'read_at': '2026-11-04T10:50:00Z',
          'created_at': '2026-11-04T10:49:00Z',
        },
      ];
    }
    if (path == '/stores') {
      return [
            {
              'id': 's1',
              'name': 'Бургерная Almaty Grill',
              'category': 'FOOD',
              'prep_minutes': 20,
              'distance_m': 1200,
            },
            {
              'id': 's2',
              'name': 'Small Супермаркет',
              'category': 'GROCERY',
              'prep_minutes': 15,
              'distance_m': 800,
            },
            {
              'id': 's3',
              'name': 'Аптека Сади',
              'category': 'PHARMACY',
              'prep_minutes': 10,
              'distance_m': 1700,
            },
            {
              'id': 's4',
              'name': 'Dastarkhan Kitchen',
              'category': 'FOOD',
              'prep_minutes': 30,
              'distance_m': 2400,
            },
          ]
          .where(
            (s) => q?['category'] == null || s['category'] == q!['category'],
          )
          .toList();
    }
    if (path == '/store-orders') {
      return [];
    }
    if (path.startsWith('/stores/') && path.endsWith('/menu')) {
      return {
        'id': 's1',
        'name': 'Бургерная Almaty Grill',
        'accepting_orders': true,
        'products': [
          {
            'id': 'p1',
            'name': 'Классик бургер',
            'description': 'Говядина, чеддер, соус',
            'section': 'Бургеры',
            'price': '2200.00',
          },
          {
            'id': 'p2',
            'name': 'Чизбургер Double',
            'description': 'Две котлеты, двойной сыр',
            'section': 'Бургеры',
            'price': '2900.00',
          },
          {
            'id': 'p3',
            'name': 'Картофель фри',
            'description': 'Большая порция',
            'section': 'Закуски',
            'price': '900.00',
          },
          {
            'id': 'p4',
            'name': 'Лимонад домашний',
            'description': '0.5 л',
            'section': 'Напитки',
            'price': '800.00',
          },
        ],
      };
    }
    if (path.startsWith('/catalog/legal/')) {
      return {
        'title': 'Документ',
        'version': '1.0',
        'body': 'Демонстрационный текст документа JOLAY.',
      };
    }
    return method == 'GET' ? <dynamic>[] : <String, dynamic>{};
  }

  static Map<String, dynamic> _cat(
    String code,
    String name,
    String desc,
    int cap,
    int eta,
    String total,
  ) => {
    'code': code,
    'name': name,
    'description': desc,
    'capacity': cap,
    'etaSeconds': eta,
    'available': true,
    'fare': {
      'baseFare': '500',
      'distanceFare': '600',
      'timeFare': '200',
      'fees': '0',
      'discount': '0',
      'total': total,
    },
  };
}
