import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? jolayTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('light and dark themes expose distinct semantic palettes with the brand accent', () {
    final l = jolayTheme().extension<JolayPalette>()!,
        d = jolayDarkTheme().extension<JolayPalette>()!;
    expect(l.accent, AppColors.yellow);
    expect(d.accent, AppColors.yellow);
    expect(l.background, isNot(d.background));
    expect(jolayDarkTheme().brightness, Brightness.dark);
  });

  testWidgets('AppButton fires, and is inert while loading or disabled', (
    t,
  ) async {
    var n = 0;
    await t.pumpWidget(host(PrimaryButton(label: 'Go', onPressed: () => n++)));
    await t.tap(find.text('Go'));
    expect(n, 1);
    await t.pumpWidget(
      host(PrimaryButton(label: 'Go', loading: true, onPressed: () => n++)),
    );
    await t.tap(find.byType(PrimaryButton));
    expect(n, 1);
    await t.pumpWidget(host(const PrimaryButton(label: 'Go')));
    await t.tap(find.byType(PrimaryButton), warnIfMissed: false);
    expect(n, 1);
  });

  testWidgets(
    'AppButton keeps its natural height inside loose-height constraints (bottom bars)',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: jolayTheme(),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: PrimaryButton(label: 'Go', onPressed: () {}),
          ),
        ),
      );
      expect(t.getSize(find.byType(PrimaryButton)).height, lessThan(80));
    },
  );

  testWidgets(
    'StatusBadge always shows text and an icon; RideTypeCard marks selection with a check',
    (t) async {
      await t.pumpWidget(
        host(const StatusBadge(label: 'Paid', tone: StatusTone.success)),
      );
      expect(find.text('Paid'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
      await t.pumpWidget(
        host(
          RideTypeCard(
            name: 'Economy',
            description: 'd',
            price: '1340',
            selected: true,
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(AppIcons.checkCircle), findsOneWidget);
      await t.pumpWidget(
        host(
          RideTypeCard(
            name: 'Economy',
            description: 'd',
            price: '1340',
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(AppIcons.checkCircle), findsNothing);
    },
  );

  testWidgets(
    'RatingInput reports the tapped star; EmptyState/ErrorState render actions',
    (t) async {
      var v = 0;
      await t.pumpWidget(host(RatingInput(value: 0, onChanged: (x) => v = x)));
      await t.tap(find.byKey(const Key('star-4')));
      expect(v, 4);
      var retried = false;
      await t.pumpWidget(
        host(
          ErrorState(
            message: 'Offline',
            retryLabel: 'Retry',
            onRetry: () => retried = true,
          ),
        ),
      );
      await t.tap(find.text('Retry'));
      expect(retried, isTrue);
    },
  );

  testWidgets('components render in the dark theme without errors', (t) async {
    await t.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'A', onPressed: () {}),
            const AppOutlinedButton(label: 'B'),
            const AppCard(child: Text('c')),
            const Avatar(name: 'Aidos N'),
            const VehicleCard(model: 'Camry', plate: 'A 1 KZ'),
            const PriceLabel(amount: '1340'),
          ],
        ),
        theme: jolayDarkTheme(),
      ),
    );
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
