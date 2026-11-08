import 'package:flutter/material.dart';

import 'tokens.dart';

/// App symbol: a yellow tile with a road-shaped "J" and a location dot. Drawn in code (no third-party assets).
class JolayMark extends StatelessWidget {
  final double size;
  final bool onDark;
  const JolayMark({super.key, this.size = 64, this.onDark = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'JOLAY',
    image: true,
    child: ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final u = s.width;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, u, u),
        Radius.circular(u * .28),
      ),
      Paint()..color = AppColors.yellow,
    );
    final ink = Paint()..color = AppColors.midnight;
    final stroke = Paint()
      ..color = AppColors.midnight
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * .13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final j = Path()
      ..moveTo(u * .62, u * .36)
      ..lineTo(u * .62, u * .58)
      ..cubicTo(u * .62, u * .74, u * .50, u * .80, u * .36, u * .76);
    c.drawPath(j, stroke);
    c.drawCircle(Offset(u * .62, u * .21), u * .075, ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// JOLAY wordmark with the yellow road-dot.
class JolayLogo extends StatelessWidget {
  final double size;
  final Color color;
  const JolayLogo({super.key, this.size = 40, this.color = AppColors.midnight});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'JOLAY',
    header: false,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'JOLAY',
            style: TextStyle(
              fontFamily: AppTypography.family,
              package: AppTypography.package,
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: size * .06,
              color: color,
              height: 1,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: size * .07, bottom: size * .06),
            child: Container(
              width: size * .17,
              height: size * .17,
              decoration: const BoxDecoration(
                color: AppColors.yellow,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

enum JolayScene { ride, order, send }

/// Original onboarding illustrations (code-drawn, brand colours only). Transparent background; fits its box.
class JolayIllustration extends StatelessWidget {
  final JolayScene scene;
  const JolayIllustration(this.scene, {super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _ScenePainter(scene, context.palette.isDark),
      size: Size.infinite,
    ),
  );
}

class _ScenePainter extends CustomPainter {
  final JolayScene scene;
  final bool dark;
  _ScenePainter(this.scene, this.dark);

  Paint _fill(Color c) => Paint()..color = c;
  Paint _line(Color c, double w, {bool round = true}) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas c, Size s) {
    final side = s.shortestSide;
    c.translate((s.width - side) / 2, (s.height - side) / 2);
    c.scale(side / 300);
    final ground = dark ? const Color(0xFF2A2A28) : const Color(0xFFEDEDE8);
    final ground2 = dark ? const Color(0xFF353532) : const Color(0xFFDDDDD6);
    final ink = dark ? AppColors.darkTextPrimary : AppColors.midnight;
    c.drawCircle(const Offset(150, 150), 138, _fill(ground));
    switch (scene) {
      case JolayScene.ride:
        _ride(c, ink, ground2);
      case JolayScene.order:
        _order(c, ink, ground2);
      case JolayScene.send:
        _send(c, ink, ground2);
    }
  }

  void _pin(Canvas c, Offset o, Color col, Color dot) {
    final path = Path()
      ..moveTo(o.dx, o.dy)
      ..cubicTo(o.dx - 22, o.dy - 24, o.dx - 18, o.dy - 52, o.dx, o.dy - 52)
      ..cubicTo(o.dx + 18, o.dy - 52, o.dx + 22, o.dy - 24, o.dx, o.dy)
      ..close();
    c.drawPath(path, _fill(col));
    c.drawCircle(Offset(o.dx, o.dy - 34), 7, _fill(dot));
  }

  void _ride(Canvas c, Color ink, Color g2) {
    // streets
    for (final r in const [
      Rect.fromLTWH(46, 88, 208, 14),
      Rect.fromLTWH(46, 176, 208, 14),
    ]) {
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(7)),
        _fill(g2),
      );
    }
    for (final r in const [
      Rect.fromLTWH(96, 50, 14, 200),
      Rect.fromLTWH(190, 50, 14, 200),
    ]) {
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(7)),
        _fill(g2),
      );
    }
    // route
    final route = Path()
      ..moveTo(103, 232)
      ..lineTo(103, 183)
      ..lineTo(197, 183)
      ..lineTo(197, 95)
      ..lineTo(150, 95);
    c.drawPath(route, _line(AppColors.midnight, 9));
    c.drawPath(route, _line(AppColors.yellow, 4));
    // origin
    c.drawCircle(const Offset(103, 232), 13, _fill(AppColors.white));
    c.drawCircle(const Offset(103, 232), 13, _line(AppColors.midnight, 4));
    _pin(c, const Offset(150, 95), AppColors.yellow, AppColors.midnight);
    // car
    c.save();
    c.translate(197, 150);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-17, -22, 34, 44),
        const Radius.circular(10),
      ),
      _fill(AppColors.midnight),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-12, -14, 24, 12),
        const Radius.circular(4),
      ),
      _fill(AppColors.yellow),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-12, 6, 24, 9),
        const Radius.circular(4),
      ),
      _fill(AppColors.yellow.withValues(alpha: .55)),
    );
    c.restore();
  }

  void _order(Canvas c, Color ink, Color g2) {
    // bag
    final bag = RRect.fromRectAndRadius(
      const Rect.fromLTWH(90, 112, 120, 112),
      const Radius.circular(20),
    );
    c.drawRRect(bag.shift(const Offset(0, 6)), _fill(g2));
    c.drawRRect(bag, _fill(AppColors.yellow));
    c.drawPath(
      Path()
        ..moveTo(120, 124)
        ..cubicTo(120, 84, 180, 84, 180, 124),
      _line(AppColors.midnight, 8),
    );
    c.drawCircle(const Offset(120, 134), 6, _fill(AppColors.midnight));
    c.drawCircle(const Offset(180, 134), 6, _fill(AppColors.midnight));
    // smile-ish handle label
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(128, 168, 44, 10),
        const Radius.circular(5),
      ),
      _fill(AppColors.midnight),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(138, 186, 24, 8),
        const Radius.circular(4),
      ),
      _fill(AppColors.midnight.withValues(alpha: .35)),
    );
    // floating cards
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(196, 70, 62, 38),
        const Radius.circular(10),
      ),
      _fill(AppColors.midnight),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(206, 82, 30, 7),
        const Radius.circular(3.5),
      ),
      _fill(AppColors.yellow),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(206, 94, 20, 6),
        const Radius.circular(3),
      ),
      _fill(AppColors.white.withValues(alpha: .5)),
    );
    c.drawCircle(const Offset(66, 96), 18, _fill(AppColors.white));
    c.drawCircle(const Offset(66, 96), 18, _line(AppColors.midnight, 4));
    c.drawPath(
      Path()
        ..moveTo(58, 96)
        ..lineTo(64, 102)
        ..lineTo(75, 90),
      _line(AppColors.midnight, 4.5),
    );
    // rider
    c.drawCircle(const Offset(224, 214), 12, _fill(AppColors.midnight));
    c.drawCircle(const Offset(224, 214), 5, _fill(AppColors.yellow));
    c.drawPath(
      Path()
        ..moveTo(206, 214)
        ..lineTo(166, 214),
      _line(AppColors.midnight, 5)..strokeCap = StrokeCap.round,
    );
  }

  void _send(Canvas c, Color ink, Color g2) {
    // parcel (front, top, side)
    final front = Path()
      ..moveTo(88, 138)
      ..lineTo(176, 138)
      ..lineTo(176, 222)
      ..lineTo(88, 222)
      ..close();
    final top = Path()
      ..moveTo(88, 138)
      ..lineTo(112, 112)
      ..lineTo(200, 112)
      ..lineTo(176, 138)
      ..close();
    final side = Path()
      ..moveTo(176, 138)
      ..lineTo(200, 112)
      ..lineTo(200, 196)
      ..lineTo(176, 222)
      ..close();
    c.drawPath(front, _fill(AppColors.yellow));
    c.drawPath(top, _fill(const Color(0xFFFBD772)));
    c.drawPath(side, _fill(const Color(0xFFD9A21E)));
    c.drawPath(
      Path()
        ..moveTo(124, 138)
        ..lineTo(140, 138)
        ..lineTo(140, 222)
        ..lineTo(124, 222)
        ..close(),
      _fill(AppColors.midnight),
    );
    c.drawPath(
      Path()
        ..moveTo(124, 138)
        ..lineTo(148, 112)
        ..lineTo(164, 112)
        ..lineTo(140, 138)
        ..close(),
      _fill(AppColors.midnight),
    );
    // speed lines
    for (final y in const [150.0, 172.0, 194.0]) {
      c.drawLine(
        Offset(40 + (y - 150) * .2, y),
        Offset(72 + (y - 150) * .2, y),
        _line(AppColors.midnight.withValues(alpha: .35), 5),
      );
    }
    // destination
    _pin(c, const Offset(232, 92), AppColors.midnight, AppColors.yellow);
    c.drawPath(
      Path()
        ..moveTo(206, 104)
        ..cubicTo(214, 128, 226, 96, 232, 100),
      _line(AppColors.midnight.withValues(alpha: .0), 1),
    );
    c.drawOval(const Rect.fromLTWH(216, 90, 32, 10), _fill(g2));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter o) =>
      o.scene != scene || o.dark != dark;
}

/// Compact skyline + taxi used on splash screens. Kept for backwards compatibility with earlier builds.
class CityTaxiIllustration extends StatelessWidget {
  final bool dark;
  const CityTaxiIllustration({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(painter: _CityPainter(dark), size: Size.infinite),
  );
}

class _CityPainter extends CustomPainter {
  final bool dark;
  _CityPainter(this.dark);
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final bld = Paint()
      ..color = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E6E1);
    final bld2 = Paint()
      ..color = dark ? const Color(0xFF3A3A3A) : const Color(0xFFD5D5CF);
    final heights = [.50, .72, .42, .86, .58, .66, .38];
    final bw = w / heights.length;
    for (var i = 0; i < heights.length; i++) {
      final r = Rect.fromLTWH(
        i * bw + 4,
        h * .78 - h * heights[i] * .7,
        bw - 8,
        h * heights[i] * .7,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        i.isEven ? bld : bld2,
      );
      final win = Paint()
        ..color = dark
            ? AppColors.yellow.withValues(alpha: .55)
            : Colors.white.withValues(alpha: .8);
      for (var y = r.top + 12; y < r.bottom - 12; y += 18) {
        c.drawRect(Rect.fromLTWH(r.left + 8, y, 6, 8), win);
        c.drawRect(Rect.fromLTWH(r.right - 14, y, 6, 8), win);
      }
    }
    c.drawRect(
      Rect.fromLTWH(0, h * .78, w, h * .22),
      Paint()..color = AppColors.midnight,
    );
    final dash = Paint()
      ..color = AppColors.yellow
      ..strokeWidth = 3;
    for (var x = 0.0; x < w; x += 40) {
      c.drawLine(Offset(x, h * .89), Offset(x + 20, h * .89), dash);
    }
    final tx = w * .30, ty = h * .62, tw = w * .40, th = h * .13;
    final body = Paint()..color = AppColors.yellow;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tx, ty, tw, th),
        const Radius.circular(14),
      ),
      body,
    );
    final cabin = Path()
      ..moveTo(tx + tw * .22, ty)
      ..lineTo(tx + tw * .32, ty - th * .62)
      ..lineTo(tx + tw * .70, ty - th * .62)
      ..lineTo(tx + tw * .82, ty)
      ..close();
    c.drawPath(cabin, body);
    final glass = Paint()..color = AppColors.midnight.withValues(alpha: .85);
    c.drawPath(
      Path()
        ..moveTo(tx + tw * .27, ty - 2)
        ..lineTo(tx + tw * .35, ty - th * .5)
        ..lineTo(tx + tw * .67, ty - th * .5)
        ..lineTo(tx + tw * .76, ty - 2)
        ..close(),
      glass,
    );
    for (final wx in [tx + tw * .22, tx + tw * .78]) {
      c.drawCircle(
        Offset(wx, ty + th),
        th * .30,
        Paint()..color = AppColors.midnight,
      );
      c.drawCircle(
        Offset(wx, ty + th),
        th * .12,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CityPainter o) => o.dark != dark;
}
