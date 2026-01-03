import 'dart:async';
import 'package:flutter/material.dart';

/// Podium screen showing winners in order (1st, 2nd, 3rd...)
/// 20-second countdown with Exit button, triggers cleanup when done
class PodiumScreen extends StatefulWidget {
  final List<String> winners;
  final VoidCallback onExit;
  final VoidCallback onCleanup;

  const PodiumScreen({
    super.key,
    required this.winners,
    required this.onExit,
    required this.onCleanup,
  });

  @override
  State<PodiumScreen> createState() => _PodiumScreenState();
}

class _PodiumScreenState extends State<PodiumScreen> {
  int _countdown = 20;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
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
    super.dispose();
  }

  String _getPlaceEmoji(int place) {
    switch (place) {
      case 0: return '🥇';
      case 1: return '🥈';
      case 2: return '🥉';
      default: return '🏅';
    }
  }

  String _getPlaceText(int place) {
    switch (place) {
      case 0: return '1st Place';
      case 1: return '2nd Place';
      case 2: return '3rd Place';
      default: return '${place + 1}th Place';
    }
  }

  Color _getPlaceColor(int place) {
    switch (place) {
      case 0: return const Color(0xFFFFD700); // Gold
      case 1: return const Color(0xFFC0C0C0); // Silver
      case 2: return const Color(0xFFCD7F32); // Bronze
      default: return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF16213E),
            Color(0xFF0F3460),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Trophy icon
            const Text('🏆', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 16),
            // Title
            const Text(
              'GAME OVER!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 32),
            // Winners list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: widget.winners.length,
                itemBuilder: (context, index) {
                  final winner = widget.winners[index];
                  final color = _getPlaceColor(index);
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _getPlaceEmoji(index),
                            style: const TextStyle(fontSize: 40),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getPlaceText(index),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  winner,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
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
                        Color(0xFFE94560),
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
                        backgroundColor: const Color(0xFFE94560),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
