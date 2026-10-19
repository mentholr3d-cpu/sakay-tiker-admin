import 'package:flutter/material.dart';

class MountainSilhouette extends StatelessWidget {
  final double height;

  const MountainSilhouette({super.key, this.height = 55});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MountainPainter(),
      ),
    );
  }
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Define 4 clear peaks with distinct base points
    final peaks = [
      _Peak(baseX: 0, peakX: w * 0.12, nextBaseX: w * 0.28, peakY: h * 0.15),
      _Peak(baseX: w * 0.28, peakX: w * 0.40, nextBaseX: w * 0.55, peakY: h * 0.35),
      _Peak(baseX: w * 0.55, peakX: w * 0.68, nextBaseX: w * 0.84, peakY: h * 0.08),
      _Peak(baseX: w * 0.84, peakX: w * 0.94, nextBaseX: w, peakY: h * 0.32),
    ];

    for (final peak in peaks) {
      // Left (lit) slope — lighter
      final leftSlope = Path()
        ..moveTo(peak.baseX, h)
        ..lineTo(peak.peakX, peak.peakY)
        ..lineTo(peak.peakX, h)
        ..close();
      canvas.drawPath(leftSlope, Paint()..color = Colors.white.withValues(alpha: 0.30));

      // Right (shadow) slope — darker
      final rightSlope = Path()
        ..moveTo(peak.peakX, peak.peakY)
        ..lineTo(peak.nextBaseX, h)
        ..lineTo(peak.peakX, h)
        ..close();
      canvas.drawPath(rightSlope, Paint()..color = Colors.white.withValues(alpha: 0.14));

      // Crisp ridge line at the very peak edges for definition
      final ridge = Path()
        ..moveTo(peak.baseX, h)
        ..lineTo(peak.peakX, peak.peakY)
        ..lineTo(peak.nextBaseX, h);
      canvas.drawPath(
        ridge,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Peak {
  final double baseX;
  final double peakX;
  final double nextBaseX;
  final double peakY;

  _Peak({required this.baseX, required this.peakX, required this.nextBaseX, required this.peakY});
}