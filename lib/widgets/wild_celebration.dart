import 'dart:math';
import 'package:flutter/material.dart';

/// Wild Card celebration animation with Fire and Confetti emojis
/// No Lottie - pure Flutter animation
class WildCelebration extends StatefulWidget {
  final VoidCallback? onComplete;

  const WildCelebration({super.key, this.onComplete});

  @override
  State<WildCelebration> createState() => _WildCelebrationState();
}

class _WildCelebrationState extends State<WildCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final Random _random = Random();

  static const List<String> _emojis = ['🔥', '🎉', '✨', '💥', '⭐', '🎊'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Generate 30 random particles
    _particles = List.generate(30, (_) => _generateParticle());

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  _Particle _generateParticle() {
    final angle = _random.nextDouble() * 2 * pi;
    final speed = 200 + _random.nextDouble() * 300;
    final emoji = _emojis[_random.nextInt(_emojis.length)];
    final size = 24.0 + _random.nextDouble() * 24;
    final rotationSpeed = (_random.nextDouble() - 0.5) * 4;
    
    return _Particle(
      emoji: emoji,
      dx: cos(angle) * speed,
      dy: sin(angle) * speed - 100, // Upward bias
      size: size,
      rotationSpeed: rotationSpeed,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final opacity = 1.0 - progress;

          return Stack(
            children: _particles.map((particle) {
              final x = particle.dx * progress;
              final y = particle.dy * progress + 50 * progress * progress; // Gravity
              final rotation = particle.rotationSpeed * progress * 2 * pi;
              final scale = 1.0 - progress * 0.3;

              return Positioned(
                left: MediaQuery.of(context).size.width / 2 + x - particle.size / 2,
                top: MediaQuery.of(context).size.height / 2 + y - particle.size / 2,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: rotation,
                    child: Transform.scale(
                      scale: scale.clamp(0.5, 1.0),
                      child: Text(
                        particle.emoji,
                        style: TextStyle(fontSize: particle.size),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _Particle {
  final String emoji;
  final double dx;
  final double dy;
  final double size;
  final double rotationSpeed;

  _Particle({
    required this.emoji,
    required this.dx,
    required this.dy,
    required this.size,
    required this.rotationSpeed,
  });
}

/// Show wild card celebration as an overlay
void showWildCelebration(BuildContext context) {
  late OverlayEntry overlay;
  
  overlay = OverlayEntry(
    builder: (context) => WildCelebration(
      onComplete: () => overlay.remove(),
    ),
  );

  Overlay.of(context).insert(overlay);
}
