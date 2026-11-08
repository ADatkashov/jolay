// Demo entrypoint: runs the real driver app UI against an in-memory fake backend (no network, no login).
//   flutter build web -t lib/main_demo.dart ; open index.html?state=offer   (idle · offline · offer · trip · delivery · pending)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'main.dart';
import 'src/data.dart';
import 'src/demo/demo_api.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        requiredRoleProvider.overrideWithValue('DRIVER'),
        apiProvider.overrideWithValue(
          DemoDriverApi(Uri.base.queryParameters['state'] ?? 'idle'),
        ),
        eventsProvider.overrideWith(
          (ref) => const Stream<RealtimeEvent>.empty(),
        ),
      ],
      child: const JolayDriverApp(),
    ),
  );
}
