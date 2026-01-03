import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/uno_card.dart';
import 'uno_card_widget.dart';

/// Horseshoe/Fan-shaped history view of played cards
/// Triggered by tapping the discard pile
/// Uses polar coordinate layout for "Dealer's Grip" spread
class HorseshoeHistoryOverlay extends StatefulWidget {
  final List<UnoCard> playedCards;
  final VoidCallback onDismiss;

  const HorseshoeHistoryOverlay({
    super.key,
    required this.playedCards,
    required this.onDismiss,
  });

  @override
  State<HorseshoeHistoryOverlay> createState() =>
      _HorseshoeHistoryOverlayState();
}

class _HorseshoeHistoryOverlayState extends State<HorseshoeHistoryOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    // Auto-dismiss after 10 seconds
    _autoDismissTimer = Timer(const Duration(seconds: 10), () {
      _dismiss();
    });
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.playedCards;
    final cardCount = cards.length;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: _dismiss,
        child: Stack(
          children: [
            // Blur background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            // Title - wrapped to remove any inherited text decoration
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: DefaultTextStyle(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: Column(
                    children: [
                      const Text(
                        '📜 Card History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap anywhere to close • Auto-closes in 10s',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Horseshoe card layout
            Center(
              child: SizedBox(
                height: 400,
                width: MediaQuery.of(context).size.width,
                child:
                    cardCount == 0
                        ? Center(
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              decoration: TextDecoration.none,
                            ),
                            child: Text(
                              'No cards played yet',
                              style: TextStyle(
                                color: Colors.white70,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        )
                        : _buildHorseshoeCards(cards),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorseshoeCards(List<UnoCard> cards) {
    // Show last 15 cards max for performance
    final displayCards =
        cards.length > 15 ? cards.sublist(cards.length - 15) : cards;
    final count = displayCards.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Center point: bottom-center of the viewing area
        final centerX = constraints.maxWidth / 2;
        final centerY =
            constraints.maxHeight * 0.85; // Moved down for crescent at bottom

        // Radius for the arc (adaptive to screen width, limited for mobile)
        final radius = min(constraints.maxWidth * 0.35, 150.0);

        // Max angular spread: ~60° total (-30° to +30°)
        const maxAngleDegrees = 30.0;
        const maxAngle = maxAngleDegrees * pi / 180; // Convert to radians

        return Stack(
          clipBehavior: Clip.none,
          children: List.generate(count, (index) {
            // Normalize index to -1 to +1 range
            final normalizedIndex =
                count == 1 ? 0.0 : (index / (count - 1)) * 2 - 1; // -1 to 1

            // Angle in radians (-maxAngle to +maxAngle)
            final angle = normalizedIndex * maxAngle;

            // Polar coordinate formula:
            // x = centerX + radius * sin(angle) -> spread horizontally
            // y = centerY - radius * cos(angle) -> arc upward
            final x =
                centerX +
                radius * sin(angle) * 2.5; // Multiply for wider spread
            final y = centerY - radius * cos(angle) * 0.6; // Flatter arc

            // Card rotation follows the hand curve (matches angle direction)
            // Rotation: -20° for leftmost, 0° for center, +20° for rightmost
            final rotationDegrees = normalizedIndex * 20.0;
            final rotation = rotationDegrees * pi / 180;

            // Scale: newest (last) cards are slightly larger and on top
            final scale = 0.65 + (index / count) * 0.35;

            final card = displayCards[index];

            // Card dimensions for centering
            const cardWidth = 50.0;
            const cardHeight = 75.0;

            return Positioned(
              left: x - (cardWidth * scale) / 2,
              top: y - (cardHeight * scale) / 2,
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scale: scale,
                  child: DefaultTextStyle(
                    style: const TextStyle(decoration: TextDecoration.none),
                    child: UnoCardWidget(
                      card: card,
                      isPlayable: false,
                      size: UnoCardSize.small,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Show the horseshoe history as an overlay
void showHorseshoeHistory(BuildContext context, List<UnoCard> playedCards) {
  late OverlayEntry overlay;

  overlay = OverlayEntry(
    builder:
        (context) => HorseshoeHistoryOverlay(
          playedCards: playedCards,
          onDismiss: () => overlay.remove(),
        ),
  );

  Overlay.of(context).insert(overlay);
}
