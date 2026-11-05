import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Where a device push token comes from. The real implementation (Firebase Messaging, which needs the owner's
/// google-services.json / GoogleService-Info.plist) is supplied by overriding [pushTokenSourceProvider] in main().
abstract class PushTokenSource {
  /// Returns the token and platform name, or null when push is unavailable (permission denied, no Firebase config).
  Future<({String token, String platform})?> obtain();
}

/// MOCK: a random per-install token with platform "mock". The backend stores it like a real one; the dev push sender
/// writes messages for it into `push_outbox` instead of calling FCM. Replace with a Firebase-backed source for real delivery.
class MockPushTokenSource implements PushTokenSource {
  @override
  Future<({String token, String platform})?> obtain() async {
    final p = await SharedPreferences.getInstance();
    var t = p.getString('push_mock_token');
    if (t == null) {
      final r = Random.secure();
      t = 'mock-${List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await p.setString('push_mock_token', t);
    }
    return (token: t, platform: 'mock');
  }
}

final pushTokenSourceProvider = Provider<PushTokenSource>((ref) => MockPushTokenSource());

/// Registers this device with the backend. Best effort: push is never allowed to break sign-in.
Future<void> registerPushToken(ApiClient api, PushTokenSource source) async {
  try {
    final d = await source.obtain();
    if (d == null) return;
    await api.post('/notifications/devices', body: {'pushToken': d.token, 'platform': d.platform});
  } catch (_) {/* retried on the next sign-in / app start */}
}
