import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';
import 'package:latlong2/latlong.dart';

import '../data/models.dart';
import 'common.dart';

/// Map tiles are 2GIS, fetched through the JOLAY backend (the 2GIS key stays on the server). Override with --dart-define=TILE_URL=... if needed.
const tileUrl = String.fromEnvironment(
  'TILE_URL',
  defaultValue: '${ApiConfig.baseUrl}/api/v1/geo/tiles/{z}/{x}/{y}.png',
);

Marker pin(LatLng p, Widget child, {double size = 44}) =>
    Marker(point: p, width: size, height: size, child: child);

Marker pickupMarker(LatLng p) => pin(p, const RoutePin());
Marker dropoffMarker(LatLng p) => pin(p, const RoutePin(dropoff: true));
Marker carMarker(LatLng p) => pin(p, const CarMarker());
Marker userMarker(LatLng p) => pin(p, const UserLocationDot(), size: 56);

/// Base JOLAY map: calm tiles (inverted in dark mode), route line in Midnight with a yellow core, no rotation.
class JolayMap extends StatelessWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng> route;
  final MapController? controller;
  final void Function(LatLng)? onTap;
  final bool interactive;

  /// When set, the camera starts framed around these points (with [fitPadding]) instead of at [center]/[zoom].
  final List<LatLng>? fitPoints;
  final EdgeInsets fitPadding;
  const JolayMap({
    super.key,
    required this.center,
    this.zoom = 14,
    this.markers = const [],
    this.route = const [],
    this.controller,
    this.onTap,
    this.interactive = true,
    this.fitPoints,
    this.fitPadding = const EdgeInsets.all(48),
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        initialCameraFit: fitPoints == null || fitPoints!.length < 2
            ? null
            : CameraFit.coordinates(
                coordinates: fitPoints!,
                padding: fitPadding,
                maxZoom: 16,
              ),
        onTap: onTap == null ? null : (_, p) => onTap!(p),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'kz.jolay.customer',
          tileBuilder: dark ? darkModeTileBuilder : null,
        ),
        if (route.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 8,
                color: AppColors.midnight,
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
              Polyline(
                points: route,
                strokeWidth: 3.5,
                color: AppColors.yellow,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('© 2GIS'),
          ],
        ),
      ],
    );
  }
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
  bool _moving = false;

  Future<void> _confirm() async {
    final c = _center ?? widget.start;
    setState(() => _busy = true);
    try {
      final r =
          await ref
                  .read(apiProvider)
                  .get(
                    '/geo/reverse',
                    query: {'lat': c.latitude, 'lng': c.longitude},
                  )
              as Map<String, dynamic>;
      if (mounted) {
        Navigator.pop(
          context,
          Place(
            r['address'] as String,
            r['address'] as String,
            c.latitude,
            c.longitude,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showError(context, ref, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mc,
              options: MapOptions(
                initialCenter: widget.start,
                initialZoom: 16,
                onPositionChanged: (p, gesture) {
                  _center = p.center;
                  if (gesture != _moving) setState(() => _moving = gesture);
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: tileUrl,
                  userAgentPackageName: 'kz.jolay.customer',
                  tileBuilder: dark ? darkModeTileBuilder : null,
                ),
              ],
            ),
          ),
          // Fixed centre pin lifts while the map is being dragged.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 52),
                child: AnimatedSlide(
                  duration: context.motion(AppDurations.fast),
                  offset: Offset(0, _moving ? -.18 : 0),
                  child: const Icon(
                    AppIcons.pin,
                    size: 52,
                    color: AppColors.midnight,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: AppIconButton(
                  icon: AppIcons.back,
                  tooltip: ref.t('common.back'),
                  style: AppIconButtonStyle.floating,
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MapPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ref.t('ride.pinHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: ref.t('btn.continue'),
                    loading: _busy,
                    onPressed: _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
