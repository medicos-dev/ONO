import 'dart:math' as math;
import 'package:flutter/material.dart';

class FireBurstPainter extends CustomPainter {
  final double animationValue;

  FireBurstPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * animationValue;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;

    for (int i = 0; i < 12; i++) {
      final angle = (i * 2 * math.pi / 12) + (animationValue * math.pi * 2);
      final distance = radius * (0.5 + (animationValue * 0.5));
      final x = center.dx + math.cos(angle) * distance;
      final y = center.dy + math.sin(angle) * distance;

      final opacity = (1.0 - animationValue) * 0.8;
      paint.color = [
        Colors.red.withOpacity(opacity),
        Colors.orange.withOpacity(opacity),
        Colors.yellow.withOpacity(opacity),
      ][i % 3];

      canvas.drawCircle(
        Offset(x, y),
        radius * 0.15 * (1.0 - animationValue),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FireBurstPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
