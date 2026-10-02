import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';

/// Circular adherence meter.
///
/// Drawn with `CustomPainter` rather than a progress widget so the track and
/// the arc can share a single blurred-free paint pass — this sits inside a
/// scrolling `ListView` and a shader here would be wasted GPU work.
class AdherenceRing extends StatelessWidget {
  const AdherenceRing({super.key, required this.value, this.size = 82});

  /// 0.0 – 1.0
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Clamp once here so the label and the arc can never disagree — an
    // unclamped label reading "180%" beside a full arc is a correctness bug.
    final fraction = value.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: fraction,
          track: DocMeColors.inkDark.withValues(alpha: 0.12),
          arc: DocMeColors.mint,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(fraction * 100).round()}%',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'adherence',
                style: TextStyle(fontSize: 9, color: DocMeColors.inkDarkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.arc,
  });

  final double value;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.095;
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [arc, Color.lerp(arc, DocMeColors.sky, 0.55)!, arc],
        stops: const [0.0, 0.75, 1.0],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(Rect.fromCircle(center: centre, radius: radius));

    canvas.drawCircle(centre, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.arc != arc || old.track != track;
}