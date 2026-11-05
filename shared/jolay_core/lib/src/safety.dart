import 'api.dart';

/// Sends an SOS to JOLAY support. The backend links the active ride and counterpart, and notifies staff in real time.
/// This never replaces calling emergency services (112); the apps offer both.
Future<void> reportSos(ApiClient api, {double? lat, double? lng}) async {
  await api.post('/incidents', body: {'type': 'SOS', if (lat != null && lng != null) 'point': {'lat': lat, 'lng': lng}});
}
