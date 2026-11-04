import 'package:flutter/material.dart';

import 'theme.dart';

/// JOLAY wordmark: black text with a yellow road-dot.
class JolayLogo extends StatelessWidget {
  final double size;
  final Color color;
  const JolayLogo({super.key, this.size = 40, this.color = JolayColors.midnight});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('JOLAY', style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: size * 0.04, color: color, height: 1)),
        Padding(padding: EdgeInsets.only(left: size * 0.06, bottom: size * 0.08),
            child: Container(width: size * 0.18, height: size * 0.18, decoration: BoxDecoration(color: color == JolayColors.midnight ? JolayColors.yellow : JolayColors.midnight, shape: BoxShape.circle))),
      ]);
}

/// Primary yellow CTA with built-in busy state.
class JolayButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool secondary;
  const JolayButton({super.key, required this.label, this.onPressed, this.busy = false, this.secondary = false});
  @override
  Widget build(BuildContext context) {
    final child = busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label);
    final cb = busy ? null : onPressed;
    return secondary ? OutlinedButton(onPressed: cb, child: child) : FilledButton(onPressed: cb, child: child);
  }
}

class JolayCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const JolayCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(JolayRadius.md), onTap: onTap, child: Padding(padding: padding, child: child)));
}

/// Inline error banner (with retry) for failed loads.
class ErrorView extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, required this.retryLabel, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: JolayColors.textSecondary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)), child: Text(retryLabel))],
        ])),
      );
}

/// Original JOLAY illustration: a stylised city skyline with a yellow taxi, drawn in code (no third-party assets).
class CityTaxiIllustration extends StatelessWidget {
  final bool dark;
  const CityTaxiIllustration({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CityPainter(dark), size: Size.infinite);
}

class _CityPainter extends CustomPainter {
  final bool dark;
  _CityPainter(this.dark);
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final bld = Paint()..color = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E6E1);
    final bld2 = Paint()..color = dark ? const Color(0xFF3A3A3A) : const Color(0xFFD5D5CF);
    final heights = [.50, .72, .42, .86, .58, .66, .38];
    final bw = w / heights.length;
    for (var i = 0; i < heights.length; i++) {
      final r = Rect.fromLTWH(i * bw + 4, h * .78 - h * heights[i] * .7, bw - 8, h * heights[i] * .7);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), i.isEven ? bld : bld2);
      final win = Paint()..color = dark ? JolayColors.yellow.withValues(alpha: .55) : Colors.white.withValues(alpha: .8);
      for (var y = r.top + 12; y < r.bottom - 12; y += 18) { c.drawRect(Rect.fromLTWH(r.left + 8, y, 6, 8), win); c.drawRect(Rect.fromLTWH(r.right - 14, y, 6, 8), win); }
    }
    c.drawRect(Rect.fromLTWH(0, h * .78, w, h * .22), Paint()..color = JolayColors.midnight);
    final dash = Paint()..color = JolayColors.yellow..strokeWidth = 3;
    for (var x = 0.0; x < w; x += 40) { c.drawLine(Offset(x, h * .89), Offset(x + 20, h * .89), dash); }
    // taxi
    final tx = w * .30, ty = h * .62, tw = w * .40, th = h * .13;
    final body = Paint()..color = JolayColors.yellow;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tw, th), const Radius.circular(14)), body);
    final cabin = Path()..moveTo(tx + tw * .22, ty)..lineTo(tx + tw * .32, ty - th * .62)..lineTo(tx + tw * .70, ty - th * .62)..lineTo(tx + tw * .82, ty)..close();
    c.drawPath(cabin, body);
    final glass = Paint()..color = JolayColors.midnight.withValues(alpha: .85);
    c.drawPath(Path()..moveTo(tx + tw * .27, ty - 2)..lineTo(tx + tw * .35, ty - th * .5)..lineTo(tx + tw * .67, ty - th * .5)..lineTo(tx + tw * .76, ty - 2)..close(), glass);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tx + tw * .42, ty - th * .78, tw * .16, th * .16), const Radius.circular(3)), Paint()..color = JolayColors.midnight);
    for (final wx in [tx + tw * .22, tx + tw * .78]) {
      c.drawCircle(Offset(wx, ty + th), th * .30, Paint()..color = JolayColors.midnight);
      c.drawCircle(Offset(wx, ty + th), th * .12, Paint()..color = Colors.white);
    }
  }
  @override
  bool shouldRepaint(covariant _CityPainter o) => o.dark != dark;
}
