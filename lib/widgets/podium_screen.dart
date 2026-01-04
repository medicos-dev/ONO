import 'dart:async';
import 'package:flutter/material.dart';

/// Winner celebration screen - shows single winner with animated celebration
/// 20-second countdown with Exit button, triggers cleanup when done
class PodiumScreen extends StatefulWidget {
  final String winnerName;
  final bool isMe; // Whether the current player is the winner
  final VoidCallback onExit;
  final VoidCallback onCleanup;

  const PodiumScreen({
    super.key,
    required this.winnerName,
    this.isMe = false,
    required this.onExit,
    required this.onCleanup,
  });

  @override
  State<PodiumScreen> createState() => _PodiumScreenState();
}

class _PodiumScreenState extends State<PodiumScreen>
    with TickerProviderStateMixin {
  int _countdown = 20;
  Timer? _timer;
  late AnimationController _trophyController;
  late AnimationController _confettiController;
  late AnimationController _scaleController;
  late Animation<double> _trophyAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _setupAnimations();
  }

  void _setupAnimations() {
    // Trophy bounce animation
    _trophyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _trophyAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(
        parent: _trophyController,
        curve: Curves.easeInOut,
      ),
    );

    // Scale animation for entrance
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _scaleController.forward();

    // Confetti animation
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        widget.onCleanup();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _trophyController.dispose();
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: widget.isMe
              ? [
                  const Color(0xFFFFD700).withValues(alpha: 0.3),
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E),
                ]
              : [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E),
                  const Color(0xFF0F3460),
                ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            
            // Animated Trophy
            AnimatedBuilder(
              animation: _trophyAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _trophyAnimation.value),
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFFFD700).withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: const Text(
                        '🏆',
                        style: TextStyle(fontSize: 120),
                      ),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // Game Over Title
            ScaleTransition(
              scale: _scaleAnimation,
              child: const Text(
                'GAME OVER!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                  shadows: [
                    Shadow(
                      color: Color(0xFFFFD700),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Winner Card
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFFD700).withValues(alpha: 0.2),
                      const Color(0xFFFFD700).withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFFFD700),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Winner Label
                    Text(
                      widget.isMe ? 'YOU WON!' : 'WINNER',
                      style: TextStyle(
                        color: const Color(0xFFFFD700),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Winner Name
                    Text(
                      widget.winnerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Celebration Emoji
                    const Text(
                      '🎉',
                      style: TextStyle(fontSize: 48),
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Countdown timer
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Auto-returning to lobby in $_countdown seconds',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _countdown / 20,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFD700),
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Exit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _timer?.cancel();
                        widget.onExit();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 8,
                      ),
                      child: const Text(
                        'EXIT NOW',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
