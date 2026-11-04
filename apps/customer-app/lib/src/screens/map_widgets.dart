import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';

import '../data/models.dart';
import 'common.dart';

/// Tile source is configurable (--dart-define=TILE_URL=...). The default OpenStreetMap server is for DEVELOPMENT only;
/// production must use a licensed provider (Mapbox / 2GIS / Google) — see docs/ARCHITECTURE.md.
const tileUrl = String.fromEnvironment('TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

Marker pin(LatLng p, IconData icon, Color color) => Marker(
      point: p, width: 44, height: 44,
      child: Icon(icon, color: color, size: 38, shadows: const [Shadow(color: Colors.black26, blurRadius: 6)]),
    );

class JolayMap extends StatelessWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng> route;
  final MapController? controller;
  final void Function(LatLng)? onTap;
  const JolayMap({super.key, required this.center, this.zoom = 14, this.markers = const [], this.route = const [], this.controller, this.onTap});

  @override
  Widget build(BuildContext context) => FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: center, initialZoom: zoom, onTap: onTap == null ? null : (_, p) => onTap!(p), interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
        children: [
          TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'kz.jolay.customer'),
          if (route.length > 1) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 4, color: JolayColors.midnight)]),
          MarkerLayer(markers: markers),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors (dev tiles)')]),
        ],
      );
}

/// Full-screen map with a fixed centre pin: the user moves the map and confirms the point. Reverse-geocodes via the backend.
class MapPickerScreen extends ConsumerStatefulWidget {
  final LatLng start;
  final String title;
  const MapPickerScreen({super.key, required this.start, required this.title});
  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerState();
}

class _MapPickerState extends ConsumerState<MapPickerScreen> {
  final _mc = MapController();
  LatLng? _center;
  bool _busy = false;

  Future<void> _confirm() async {
    final c = _center ?? widget.start;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).get('/geo/reverse', query: {'lat': c.latitude, 'lng': c.longitude}) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, Place(r['address'] as String, r['address'] as String, c.latitude, c.longitude));
    } catch (e) { if (mounted) { showError(context, ref, e); setState(() => _busy = false); } }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Stack(children: [
          FlutterMap(
            mapController: _mc,
            options: MapOptions(initialCenter: widget.start, initialZoom: 16, onPositionChanged: (p, _) => _center = p.center, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
            children: [TileLayer(urlTemplate: tileUrl, userAgentPackageName: 'kz.jolay.customer')],
          ),
          const Center(child: Padding(padding: EdgeInsets.only(bottom: 38), child: Icon(Icons.location_on, size: 44, color: JolayColors.midnight))),
          Positioned(left: 24, right: 24, bottom: 24, child: SafeArea(child: JolayButton(label: ref.t('btn.continue'), busy: _busy, onPressed: _confirm))),
        ]),
      );
}
