// Demo entrypoint: runs the real customer app UI against an in-memory fake backend (no network, no login).
//   flutter run -t lib/main_demo.dart            (or: flutter build web -t lib/main_demo.dart)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'main.dart';
import 'src/data/providers.dart';
import 'src/demo/demo_api.dart';

void main() {
  runApp(ProviderScope(
    overrides: [
      requiredRoleProvider.overrideWithValue('CUSTOMER'),
      apiProvider.overrideWithValue(DemoApi()),
      realtimeEventsProvider.overrideWith((ref) => const Stream<RealtimeEvent>.empty()),
    ],
    child: const JolayCustomerApp(),
  ));
}
