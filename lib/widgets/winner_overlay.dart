import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/app_theme.dart';
import 'confetti_painter.dart';
import 'dart:math' as math;

class WinnerOverlay extends StatefulWidget {
  final String winnerName;
  final VoidCallback onExitGame;
  final VoidCallback onReturnHome;

  const WinnerOverlay({
    super.key,
    required this.winnerName,
    required this.onExitGame,
    required this.onReturnHome,
  });

  @override
  State<WinnerOverlay> createState() => _WinnerOverlayState();
}

class _WinnerOverlayState extends State<WinnerOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _confettiController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _confettiAnimation;
  Timer? _autoCloseTimer;
  List<ConfettiParticle> _confettiParticles = [];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _confettiController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _confettiAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _confettiController, curve: Curves.easeOut),
    );

    _confettiParticles = _generateParticles();
    _fadeController.forward();
    _confettiController.forward();

    _autoCloseTimer = Timer(const Duration(seconds: 10), () {
      widget.onReturnHome();
    });
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

    for (int i = 0; i < 50; i++) {
      particles.add(
        ConfettiParticle(
          startX: 0.5,
          startY: 0.5,
          velocityX: (random.nextDouble() - 0.5) * 2.5,
          velocityY: (random.nextDouble() - 0.5) * 2.5,
          color: colors[random.nextInt(colors.length)],
          size: 8 + random.nextDouble() * 12,
          opacity: 0.8 + random.nextDouble() * 0.2,
          rotationSpeed: (random.nextDouble() - 0.5) * 6,
          startTime: random.nextDouble() * 0.3,
        ),
      );
    }

    return particles;
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _fadeAnimation,
          _pulseAnimation,
          _confettiAnimation,
        ]),
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: ConfettiPainter(
                      _confettiAnimation.value,
                      _confettiParticles,
                    ),
                    size: Size.infinite,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppTheme.neonYellow.withOpacity(0.3),
                                AppTheme.neonYellow.withOpacity(0.1),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.neonYellow.withOpacity(0.6),
                                blurRadius: 40,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.emoji_events,
                            size: 80,
                            color: AppTheme.neonYellow,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'WINNER!',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: AppTheme.neonYellow,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: AppTheme.neonYellow.withOpacity(0.8),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.winnerName,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: widget.onExitGame,
                            icon: const Icon(Icons.exit_to_app),
                            label: const Text('EXIT GAME'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: widget.onReturnHome,
                            icon: const Icon(Icons.home),
                            label: const Text('HOME'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
