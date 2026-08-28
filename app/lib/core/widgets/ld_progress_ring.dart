import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

enum LdRingSize {
  s(64, 8),
  m(96, 10),
  l(128, 12),
  xl(168, 14);

  const LdRingSize(this.diameter, this.stroke);
  final double diameter;
  final double stroke;
}

/// The circular progress primitive behind every macro and goal display
/// (docs/04 §8.3).
///
/// Going over target is information, not an error: the arc continues past
/// 100 % in a lighter tint of the same hue rather than capping silently.
class LdProgressRing extends StatelessWidget {
  const LdProgressRing({
    required this.value,
    required this.target,
    required this.label,
    required this.color,
    super.key,
    this.unit = '',
    this.size = LdRingSize.m,
    this.showTarget = true,
    this.animate = true,
  });

  final double value;
  final double target;
  final String label;
  final String unit;
  final Color color;
  final LdRingSize size;
  final bool showTarget;
  final bool animate;

  double get _progress => target <= 0 ? 0 : value / target;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final pct = (_progress * 100).round();

    final valueStyle = switch (size) {
      LdRingSize.s => type.titleM,
      LdRingSize.m => type.titleL,
      LdRingSize.l => type.displayM,
      LdRingSize.xl => type.displayM,
    };

    final shouldAnimate = animate && !context.reduceMotion;

    return Semantics(
      label: '$label, ${_fmt(value)} of ${_fmt(target)} $unit, $pct percent',
      excludeSemantics: true,
      child: SizedBox(
        width: size.diameter,
        height: size.diameter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: shouldAnimate ? 0 : _progress, end: _progress),
          duration: shouldAnimate ? LdMotion.ring : Duration.zero,
          curve: Curves.easeOutQuart,
          builder: (context, progress, _) => CustomPaint(
            painter: _RingPainter(
              progress: progress,
              color: color,
              trackColor: c.border,
              overTargetColor: c.overTarget(color),
              strokeWidth: size.stroke,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(value),
                    style: valueStyle.copyWith(color: c.textPrimary),
                  ),
                  if (showTarget)
                    Text(
                      '/ ${_fmt(target)}',
                      style: type.bodyS.copyWith(color: c.textTertiary),
                    ),
                  const SizedBox(height: LdSpacing.s1),
                  Text(
                    label.toUpperCase(),
                    style: type.labelMono.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) => v >= 1000
      ? v.round().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        )
      : v.round().toString();
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.overTargetColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final Color overTargetColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;

    const start = -math.pi / 2;

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // The first full revolution.
    final firstSweep = math.min(progress, 1.0) * 2 * math.pi;
    canvas.drawArc(rect, start, firstSweep, false, arc);

    // Anything beyond target continues in a lighter tint of the same hue, so
    // "over" is legible at a glance without changing what the colour means.
    if (progress > 1.0) {
      final overflow = math.min(progress - 1.0, 1.0) * 2 * math.pi;
      final overPaint = Paint()
        ..color = overTargetColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, overflow, false, overPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.overTargetColor != overTargetColor ||
      old.strokeWidth != strokeWidth;
}
