import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_customer/src/data/models.dart';
import 'package:jolay_customer/src/data/providers.dart';
import 'package:jolay_customer/src/screens/shop_screens.dart';
import 'package:jolay_core/jolay_core.dart';

import 'helpers.dart';

class _En extends LocaleController { @override Locale build() => const Locale('en'); }
class _Draft extends DraftController { @override Draft build() => const Draft(pickup: Place('Dostyk Plaza', 'Dostyk Plaza', 43.2335, 76.9567)); }

const _menu = {
  'id': 's1', 'name': 'Plov House', 'category': 'FOOD', 'accepting_orders': true,
  'products': [{'id': 'p1', 'name': 'Plov', 'description': 'Beef', 'section': 'Hot', 'price': '2500.00'}],
};

void main() {
  testWidgets('shops list shows stores near the pickup and the category filter reloads', (t) async {
    tallScreen(t);
    final api = FakeApi({
      'GET /stores': [{'id': 's1', 'name': 'Plov House', 'category': 'FOOD', 'prep_minutes': 15, 'distance_m': 1200}],
      'GET /store-orders': <dynamic>[],
    });
    await t.pumpWidget(app(const ShopsScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En()), draftProvider.overrideWith(() => _Draft())]));
    await t.pump(); await t.pump();
    expect(find.text('Plov House'), findsOneWidget);
    await t.tap(find.byKey(const Key('cat-GROCERY')));
    await t.pump(); await t.pump();
    expect(api.calls.where((c) => c.path == '/stores').length, 2);
  });

  testWidgets('menu: adding items fills the cart, one store per cart', (t) async {
    tallScreen(t);
    final api = FakeApi({'GET /stores/s1/menu': _menu});
    await t.pumpWidget(app(const StoreScreen(storeId: 's1'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    await t.tap(find.byKey(const Key('plus-p1')));
    await t.tap(find.byKey(const Key('plus-p1')));
    await t.pump();
    expect(find.byKey(const Key('view-cart')), findsOneWidget);
    expect(find.textContaining('· 2 ·'), findsOneWidget);
    await t.tap(find.byKey(const Key('minus-p1')));
    await t.pump();
    expect(find.textContaining('· 1 ·'), findsOneWidget);
  });

  testWidgets('checkout shows the server quote, sends no price and uses an idempotency key', (t) async {
    tallScreen(t);
    final api = FakeApi({
      'POST /store-orders/estimate': {'itemsTotal': '5000.00', 'deliveryFee': '900.00', 'total': '5900.00', 'distanceM': 1200, 'currency': 'KZT'},
      'POST /store-orders': {'id': 'o1', 'number': 'S-1', 'status': 'PLACED', 'storeName': 'Plov House', 'items': <dynamic>[], 'deliveryFee': '900.00', 'total': '5900.00'},
      'GET /store-orders/o1': {'id': 'o1', 'number': 'S-1', 'status': 'PLACED', 'storeName': 'Plov House', 'items': <dynamic>[], 'deliveryFee': '900.00', 'total': '5900.00'},
    });
    await t.pumpWidget(app(const CheckoutScreen(), api: api, overrides: [localeProvider.overrideWith(() => _En()), draftProvider.overrideWith(() => _Draft()), cartProvider.overrideWith(() => _SeededCart())]));
    await t.pump(); await t.pump(); await t.pump();
    expect(find.byKey(const Key('shop-quote')), findsOneWidget);
    expect(find.textContaining('5'), findsWidgets);
    final est = api.calls.firstWhere((c) => c.path == '/store-orders/estimate').body as Map;
    expect(est.containsKey('price') || est.containsKey('total'), isFalse);
    expect((est['items'] as List).single, {'productId': 'p1', 'quantity': 2});
    expect(est['paymentMethod'], 'WALLET');
    expect(find.text('Paid from your wallet. The money is held until the order is delivered.'), findsOneWidget);

    await t.tap(find.byKey(const Key('pay-CASH')));
    await t.pump();
    expect(find.text('You pay the courier on delivery. Large orders have a limit.'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(0), 'Aidar Bekov');
    await t.enterText(find.byType(TextFormField).at(1), '+7 701 111 00 01');
    await t.ensureVisible(find.byKey(const Key('place-order')));
    await t.tap(find.byKey(const Key('place-order')));
    await t.pump(); await t.pump();
    final placed = api.calls.firstWhere((c) => c.method == 'POST' && c.path == '/store-orders');
    expect((placed.body as Map)['paymentMethod'], 'CASH');
    expect(placed.headers?['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('order tracking shows status, handover code and a cancel button only while PLACED', (t) async {
    tallScreen(t);
    Map<String, dynamic> order(String s) => {'id': 'o1', 'number': 'S-1', 'status': s, 'storeName': 'Plov House', 'deliveryFee': '900.00', 'total': '5900.00',
      'items': [{'name': 'Plov', 'unit_price': '2500.00', 'quantity': 2}],
      if (s == 'READY') 'delivery': {'status': 'SEARCHING_COURIER', 'handoverCode': '4821'}};
    final api = FakeApi({'GET /store-orders/o1': order('PLACED')});
    await t.pumpWidget(app(const ShopOrderScreen(id: 'o1'), api: api, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.text('Waiting for the store'), findsOneWidget);
    expect(find.byKey(const Key('shop-cancel')), findsOneWidget);
    expect(find.byKey(const Key('shop-code')), findsNothing);
    await t.pumpWidget(const SizedBox());
    final api2 = FakeApi({'GET /store-orders/o1': order('READY')});
    await t.pumpWidget(app(const ShopOrderScreen(id: 'o1'), api: api2, overrides: [localeProvider.overrideWith(() => _En())]));
    await t.pump(); await t.pump();
    expect(find.byKey(const Key('shop-code')), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    expect(find.byKey(const Key('shop-cancel')), findsNothing);
  });
}

class _SeededCart extends CartController {
  @override
  Cart build() => const Cart(storeId: 's1', storeName: 'Plov House', lines: [CartLine('p1', 'Plov', '2500.00', 2)]);
}
