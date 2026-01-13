import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'fire_burst_painter.dart';
import 'confetti_painter.dart' show ConfettiPainter, ConfettiParticle;
import '../theme/app_theme.dart';

class WildCardAnimation extends StatefulWidget {
  final VoidCallback? onComplete;
  final Widget child;

  const WildCardAnimation({
    super.key,
    this.onComplete,
    required this.child,
  });

  @override
  State<WildCardAnimation> createState() => _WildCardAnimationState();
}

class _WildCardAnimationState extends State<WildCardAnimation>
    with TickerProviderStateMixin {
  late AnimationController _fireController;
  late AnimationController _confettiController;
  late AnimationController _pulseController;
  late Animation<double> _fireAnimation;
  late Animation<double> _confettiAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _fireController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _confettiController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat(reverse: true);

    _fireAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fireController, curve: Curves.easeOut),
    );

    _confettiAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _confettiController, curve: Curves.easeOut),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fireController.forward();
    _confettiController.forward().then((_) {
      widget.onComplete?.call();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _fireController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  List<ConfettiParticle> _generateParticles() {
    final random = math.Random();
    final particles = <ConfettiParticle>[];
    final colors = [
      AppTheme.neonRed,
      AppTheme.neonBlue,
      AppTheme.neonGreen,
      AppTheme.neonYellow,
      AppTheme.neonPurple,
    ];

    for (int i = 0; i < 30; i++) {
      particles.add(
        ConfettiParticle(
          startX: 0.5,
          startY: 0.5,
          velocityX: (random.nextDouble() - 0.5) * 2,
          velocityY: (random.nextDouble() - 0.5) * 2,
          color: colors[random.nextInt(colors.length)],
          size: 10 + random.nextDouble() * 15,
          opacity: 0.7 + random.nextDouble() * 0.3,
          rotationSpeed: (random.nextDouble() - 0.5) * 4,
          startTime: random.nextDouble() * 0.3,
        ),
      );
    }

    return particles;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonPurple.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        CustomPaint(
          painter: FireBurstPainter(_fireAnimation.value),
          size: Size.infinite,
        ),
        CustomPaint(
          painter: ConfettiPainter(_confettiAnimation.value, _generateParticles()),
          size: Size.infinite,
        ),
      ],
    );
  }
}
