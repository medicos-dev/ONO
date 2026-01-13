import 'dart:math' as math;
import 'package:flutter/material.dart';

class ConfettiPainter extends CustomPainter {
  final double animationValue;
  final List<ConfettiParticle> particles;

  ConfettiPainter(this.animationValue, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final progress = (animationValue - particle.startTime).clamp(0.0, 1.0);
      if (progress <= 0) continue;

      final y = particle.startY + (particle.velocityY * progress * size.height);
      final x = particle.startX + (particle.velocityX * progress * size.width);

      if (y < 0 || y > size.height || x < 0 || x > size.width) continue;

      final opacity = (1.0 - progress) * particle.opacity;
      final paint = Paint()
        ..color = particle.color.withOpacity(opacity);

      final rotation = progress * math.pi * 2 * particle.rotationSpeed;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: particle.size,
          height: particle.size * 0.5,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class ConfettiParticle {
  final double startX;
  final double startY;
  final double velocityX;
  final double velocityY;
  final Color color;
  final double size;
  final double opacity;
  final double rotationSpeed;
  final double startTime;

  ConfettiParticle({
    required this.startX,
    required this.startY,
    required this.velocityX,
    required this.velocityY,
    required this.color,
    required this.size,
    required this.opacity,
    required this.rotationSpeed,
    required this.startTime,
  });
}
