import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jolay_core/jolay_core.dart';

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final c = RealtimeClient(ref.read(apiProvider).tokens);
  ref.onDispose(c.stop);
  return c;
});

final eventsProvider = StreamProvider<RealtimeEvent>((ref) {
  final rt = ref.watch(realtimeProvider);
  rt.start();
  return rt.events;
});

/// 404 `driver_not_registered` is a legitimate state (profile not created yet), so it is returned as null.
final driverMeProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try { return await ref.read(apiProvider).get('/drivers/me') as Map<String, dynamic>; }
  on ApiException catch (e) { if (e.code == 'driver_not_registered') return null; rethrow; }
});

final earningsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, p) async =>
    await ref.read(apiProvider).get('/drivers/earnings', query: {'period': p}) as Map<String, dynamic>);

final historyProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    ((await ref.read(apiProvider).get('/drivers/rides/history')) as List).cast<Map<String, dynamic>>());

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    await ref.read(apiProvider).get('/wallet') as Map<String, dynamic>);

/// Streams the driver's position to the backend while online. Positions are validated server-side
/// (offline/unapproved/suspended drivers and impossible jumps are rejected).
class LocationPublisher {
  final ApiClient api;
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _last;
  LocationPublisher(this.api);

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<void> start() async {
    await stop();
    try { _last = await Geolocator.getCurrentPosition(); await _push(); } catch (_) {}
    _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((p) => _last = p, onError: (_) {});
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _push());
  }

  Future<void> _push() async {
    final p = _last;
    if (p == null) return;
    try {
      await api.post('/drivers/location', body: {'point': {'lat': p.latitude, 'lng': p.longitude}, 'heading': p.heading.isNaN || p.heading < 0 ? 0 : p.heading.clamp(0, 360), 'speedKmh': (p.speed.isNaN || p.speed < 0 ? 0 : p.speed * 3.6).clamp(0, 250)});
    } catch (_) {/* transient: next tick retries */}
  }

  Position? get last => _last;

  Future<void> stop() async { await _sub?.cancel(); _timer?.cancel(); _sub = null; _timer = null; }
}

final locationPublisherProvider = Provider<LocationPublisher>((ref) {
  final p = LocationPublisher(ref.read(apiProvider));
  ref.onDispose(p.stop);
  return p;
});
