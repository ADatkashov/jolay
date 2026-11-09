import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// Pure-Flutter map marker visuals (no map-package dependency). Wrap in the map library's marker type in the app.

/// Shared map styling decisions so both apps render the map identically.
abstract final class JolayMapStyle {
  /// Dark map from the light 2GIS raster tiles: luminance is inverted and compressed (land ≈ #232323, roads ≈ #161616,
  /// labels ≈ light grey) and the hue is rotated back so the water stays blue and parks stay green instead of
  /// turning orange/pink. Wrap each tile with `ColorFiltered(colorFilter: JolayMapStyle.darkTiles, ...)`.
  static const ColorFilter darkTiles = ColorFilter.matrix(<double>[
    // R
    0.4936, -1.2298, -0.1238, 0, 241.3,
    // G
    -0.3664, -0.3698, -0.1238, 0, 241.3,
    // B
    -0.3664, -1.2298, 0.7362, 0, 241.3,
    // A
    0, 0, 0, 1, 0,
  ]);

  /// Route line: a dark casing keeps the yellow core readable on both light and dark tiles.
  static Color routeCasing(bool dark) =>
      dark ? const Color(0xFF0B0B0B) : AppColors.midnight;
  static const Color routeCore = AppColors.yellow;
  static const double routeCasingWidth = 9;
  static const double routeCoreWidth = 4.5;

  /// Padding so the camera frames content in the *visible* part of the map when a bottom sheet of [sheetHeight] covers it.
  static EdgeInsets framing({
    double sheetHeight = 0,
    double top = 96,
    double side = 48,
  }) => EdgeInsets.fromLTRB(side, top, side, sheetHeight + 32);
}

/// "You are here": yellow dot, white ring and a slow pulse (static under reduced motion). Reads on light and dark maps.
class UserLocationDot extends StatefulWidget {
  final double size;
  const UserLocationDot({super.key, this.size = 56});
  @override
  State<UserLocationDot> createState() => _UserDotState();
}

class _UserDotState extends State<UserLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = context.reduceMotion ? .0 : _c.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * (.35 + .65 * t),
                height: widget.size * (.35 + .65 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.yellow.withValues(
                    alpha: .38 * (1 - t) + (context.reduceMotion ? .2 : 0),
                  ),
                ),
              ),
              Container(
                width: widget.size * .34,
                height: widget.size * .34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.yellow,
                  border: Border.all(color: AppColors.white, width: 3),
                  boxShadow: AppElevation.floating,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Pickup (white circle) and drop-off (yellow square flag): shape differs, not only colour. A white halo keeps both
/// visible on dark tiles.
class RoutePin extends StatelessWidget {
  final bool dropoff;
  final double size;
  const RoutePin({super.key, this.dropoff = false, this.size = 40});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: size * .5,
          height: size * .5,
          decoration: BoxDecoration(
            color: dropoff ? AppColors.yellow : AppColors.white,
            shape: dropoff ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: dropoff ? BorderRadius.circular(5) : null,
            border: Border.all(color: AppColors.midnight, width: 4),
            boxShadow: [
              const BoxShadow(color: Color(0x66000000), blurRadius: 8),
              BoxShadow(
                color: AppColors.white.withValues(alpha: .9),
                spreadRadius: 1.5,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The driver's car on the map.
class CarMarker extends StatelessWidget {
  final double size;
  const CarMarker({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.yellow,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.midnight, width: 3),
        boxShadow: [
          const BoxShadow(color: Color(0x66000000), blurRadius: 10),
          BoxShadow(
            color: AppColors.white.withValues(alpha: .85),
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: const Icon(AppIcons.car, size: 22, color: AppColors.midnight),
    ),
  );
}

/// Round floating control that sits on a map (recenter, zoom …).
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: p.surface,
            shape: BoxShape.circle,
            boxShadow: AppElevation.floating,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, size: AppIconSize.lg, color: p.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
