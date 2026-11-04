import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jolay_core/jolay_core.dart';

import 'models.dart';

/// Almaty city centre: used only when GPS is unavailable and the user has not picked a pickup manually.
const almatyCenter = Place('Almaty', '', 43.2389, 76.8897);

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final c = RealtimeClient(ref.read(apiProvider).tokens);
  ref.onDispose(c.stop);
  return c;
});

final realtimeEventsProvider = StreamProvider<RealtimeEvent>((ref) {
  final rt = ref.watch(realtimeProvider);
  rt.start();
  return rt.events;
});

enum LocationState { granted, denied, deniedForever, serviceOff }

/// Wraps geolocator permission handling. Location is only requested after the user has read the explanation screen.
class LocationService {
  static Future<LocationState> status() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationState.serviceOff;
    final p = await Geolocator.checkPermission();
    return switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => LocationState.granted,
      LocationPermission.deniedForever => LocationState.deniedForever,
      _ => LocationState.denied,
    };
  }

  static Future<LocationState> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationState.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => LocationState.granted,
      LocationPermission.deniedForever => LocationState.deniedForever,
      _ => LocationState.denied,
    };
  }

  static Future<Place?> current() async {
    if (await status() != LocationState.granted) return null;
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
      return Place('', '', p.latitude, p.longitude);
    } catch (_) { return null; }
  }
}

class Draft {
  final Place? pickup, dropoff;
  const Draft({this.pickup, this.dropoff});
  Draft copy({Place? pickup, Place? dropoff}) => Draft(pickup: pickup ?? this.pickup, dropoff: dropoff ?? this.dropoff);
}

class DraftController extends Notifier<Draft> {
  @override
  Draft build() => const Draft();
  void setPickup(Place p) => state = state.copy(pickup: p);
  void setDropoff(Place p) => state = state.copy(dropoff: p);
  void clear() => state = const Draft();
}

final draftProvider = NotifierProvider<DraftController, Draft>(DraftController.new);

final activeRideProvider = FutureProvider.autoDispose<Ride?>((ref) async {
  final j = await ref.read(apiProvider).get('/rides/active');
  return j == null || (j is String && j.isEmpty) ? null : Ride.fromJson(j as Map<String, dynamic>);
});

final historyProvider = FutureProvider.autoDispose.family<List<Ride>, String>((ref, tab) async {
  final j = await ref.read(apiProvider).get('/rides/history', query: {'tab': tab}) as List;
  return j.map((e) => Ride.fromJson(e as Map<String, dynamic>)).toList();
});

final savedAddressesProvider = FutureProvider.autoDispose<List<Place>>((ref) async {
  final j = await ref.read(apiProvider).get('/customers/me/addresses') as List;
  return j.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
});

final recentDestinationsProvider = FutureProvider.autoDispose<List<Place>>((ref) async {
  final j = await ref.read(apiProvider).get('/customers/me/recent-destinations') as List;
  return j.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
});

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final bal = await ref.read(apiProvider).get('/wallet') as Map<String, dynamic>;
  final tx = await ref.read(apiProvider).get('/wallet/transactions') as List;
  return {'balance': bal['balance'], 'transactions': tx};
});

final ticketsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final j = await ref.read(apiProvider).get('/support/tickets') as List;
  return j.cast<Map<String, dynamic>>();
});
