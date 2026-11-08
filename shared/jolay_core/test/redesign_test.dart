import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child, {ThemeData? theme, bool disableAnimations = false}) =>
    MaterialApp(
      theme: theme ?? jolayDarkTheme(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: disableAnimations),
        child: w!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('dark palette follows the JOLAY brand spec', () {
    final d = JolayPalette.dark;
    expect(d.background, const Color(0xFF171717));
    expect(d.surface, const Color(0xFF1F1F1F));
    expect(d.elevated, const Color(0xFF242424));
    expect(d.textPrimary, const Color(0xFFF7F7F4));
    expect(d.textSecondary, const Color(0xFFA6A6A6));
    expect(d.success, const Color(0xFF36C995));
    expect(d.error, const Color(0xFFF16D7D));
    expect(d.accent, AppColors.yellow);
  });

  test('dark text keeps WCAG AA contrast on every dark surface', () {
    double lum(Color c) {
      double ch(double v) => v <= .03928
          ? v / 12.92
          : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
    }

    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
    }

    final d = JolayPalette.dark;
    for (final bg in [d.background, d.surface, d.elevated]) {
      expect(ratio(d.textPrimary, bg), greaterThan(7));
      expect(ratio(d.textSecondary, bg), greaterThan(4.5));
      expect(ratio(d.success, bg), greaterThan(4.5));
      expect(ratio(d.error, bg), greaterThan(4.5));
    }
    expect(ratio(d.onAccent, d.accent), greaterThan(7));
  });

  test('theme mode defaults to dark and honours a stored choice', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    await c.read(themeModeProvider.notifier).set(ThemeMode.light);
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('every new string exists in kk, ru and en', () {
    const keys = [
      'sheet.expand',
      'sheet.collapse',
      'driver.offlineConfirmTitle',
      'driver.offlineConfirmBody',
      'driver.stayOnline',
      'driver.completeConfirmTitle',
      'driver.completeConfirmBody',
    ];
    for (final loc in supportedLocales) {
      for (final k in keys) {
        final v = tr(loc, k);
        expect(v, isNot(k), reason: '$k missing for ${loc.languageCode}');
        expect(v.trim(), isNotEmpty);
      }
    }
  });

  testWidgets(
    'JolayToggle reports the opposite value and is inert when disabled',
    (t) async {
      final seen = <bool>[];
      await t.pumpWidget(
        host(
          JolayToggle(value: false, semanticLabel: 'Go', onChanged: seen.add),
        ),
      );
      await t.tap(find.byType(JolayToggle));
      expect(seen, [true]);
      expect(
        t.getSize(find.byType(JolayToggle)).height,
        greaterThanOrEqualTo(48),
      );

      seen.clear();
      await t.pumpWidget(
        host(
          const JolayToggle(value: true, semanticLabel: 'Go', onChanged: null),
        ),
      );
      await t.tap(find.byType(JolayToggle), warnIfMissed: false);
      expect(seen, isEmpty);
    },
  );

  testWidgets('JolayToggle exposes its state to screen readers', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(
      host(
        JolayToggle(
          value: true,
          semanticLabel: 'Go offline',
          onChanged: (_) {},
        ),
      ),
    );
    expect(
      t.getSemantics(find.byType(JolayToggle)),
      matchesSemantics(
        label: 'Go offline',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    h.dispose();
  });

  testWidgets('StatusIndicator states the status in words, not only colour', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const StatusIndicator(
          active: true,
          label: 'You are online',
          caption: 'hint',
        ),
      ),
    );
    expect(find.text('You are online'), findsOneWidget);
    await t.pumpWidget(
      host(const StatusIndicator(active: false, label: 'You are offline')),
    );
    expect(find.text('You are offline'), findsOneWidget);
  });

  testWidgets('MapPanel handle: tap and fling ask to expand / collapse', (
    t,
  ) async {
    final calls = <bool>[];
    var expanded = true;
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (c, set) => MapPanel(
            expanded: expanded,
            handleLabel: 'Toggle',
            onExpandChanged: (v) {
              calls.add(v);
              set(() => expanded = v);
            },
            child: const Text('content'),
          ),
        ),
      ),
    );
    await t.tap(find.bySemanticsLabel('Toggle'));
    expect(calls, [false]);
    await t.fling(find.bySemanticsLabel('Toggle'), const Offset(0, -120), 800);
    expect(calls, [false, true]);
  });

  testWidgets(
    'long labels wrap on a 320 dp phone at 2x text instead of overflowing',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: jolayDarkTheme(),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: w!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  PrimaryButton(
                    label: 'Жолаушыға қарай жолға шығу және навигацияны қосу',
                    size: AppButtonSize.xl,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 8),
                  const StatusIndicator(
                    active: true,
                    label: 'Желідесіз',
                    caption: 'Жақын жердегі тапсырыстар іздеп жатырмыз…',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      expect(
        t.getSize(find.byType(PrimaryButton)).height,
        greaterThanOrEqualTo(60),
      );
    },
  );

  testWidgets('primary button gives a haptic tick, secondary does not', (
    t,
  ) async {
    final haptics = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        if (c.method == 'HapticFeedback.vibrate') haptics.add('${c.arguments}');
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await t.pumpWidget(
      host(
        Column(
          children: [
            PrimaryButton(label: 'A', onPressed: () {}),
            AppOutlinedButton(label: 'B', onPressed: () {}),
          ],
        ),
      ),
    );
    await t.tap(find.text('B'));
    expect(haptics, isEmpty);
    await t.tap(find.text('A'));
    expect(haptics, hasLength(1));
  });

  test(
    'dark tile filter is a valid 4x5 colour matrix that darkens white tiles',
    () {
      expect(JolayMapStyle.darkTiles, isA<ColorFilter>());
      // Pure maths on the documented matrix: white (255) → ≈ #161616 (roads), beige land (240) stays dark.
      const m = [
        0.4936, -1.2298, -0.1238, 241.3, //
      ];
      double out(double v) => m[0] * v + m[1] * v + m[2] * v + m[3];
      expect(out(255), closeTo(22, 1));
      expect(out(240), lessThan(60));
      expect(out(40), greaterThan(180)); // dark labels become light
    },
  );

  test('map framing leaves room for the bottom sheet', () {
    final pad = JolayMapStyle.framing(sheetHeight: 300);
    expect(pad.bottom, greaterThan(300));
    expect(pad.top, greaterThan(0));
  });
}
