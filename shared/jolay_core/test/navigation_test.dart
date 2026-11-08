import 'package:flutter_test/flutter_test.dart';
import 'package:jolay_core/jolay_core.dart';

void main() {
  test('RideNavigation parses the route, the steps and tolerates gaps', () {
    final n = RideNavigation.fromJson({
      'leg': 'PICKUP',
      'distanceM': 1500,
      'durationS': 300,
      'source': '2GIS',
      'polyline': [
        [43.2335, 76.9567],
        [43.2340, 76.9570],
        ['bad'],
      ],
      'steps': [
        {'text': '', 'icon': 'start', 'distanceM': 10},
        {
          'text': 'Turn right',
          'icon': 'turn_right',
          'distanceM': 800.0,
          'lat': 43.2,
          'lng': 76.9,
        },
      ],
    });
    expect(n.isPickupLeg, isTrue);
    expect(n.isEstimated, isFalse);
    expect(n.points, [(43.2335, 76.9567), (43.2340, 76.9570)]);
    expect(n.steps.length, 2);
    expect(
      n.nextStep?.text,
      'Turn right',
      reason: 'the empty first step is skipped',
    );
    expect(n.nextStep?.distanceM, 800);

    final bare = RideNavigation.fromJson({});
    expect(bare.points, isEmpty);
    expect(bare.steps, isEmpty);
    expect(bare.isEstimated, isTrue);
    expect(bare.nextStep, isNull);
  });

  test('manoeuvre icons are picked by keyword', () {
    iconFor(String icon) =>
        NavStep(text: 't', icon: icon, distanceM: 0).iconData;
    expect(iconFor('turn_left'), isNot(iconFor('turn_right')));
    expect(iconFor('finish'), isNot(iconFor('turn_left')));
    expect(iconFor('unknown_thing'), iconFor(''));
  });
}
