import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../models/card.dart';
import '../widgets/uno_card_widget.dart';
import '../theme/app_theme.dart';

class DiscardPileHistoryOverlay extends StatefulWidget {
  final List<UnoCard> discardPile;

  const DiscardPileHistoryOverlay({
    super.key,
    required this.discardPile,
  });

  @override
  State<DiscardPileHistoryOverlay> createState() => _DiscardPileHistoryOverlayState();
}

class _DiscardPileHistoryOverlayState extends State<DiscardPileHistoryOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();

    _autoCloseTimer = Timer(const Duration(seconds: 10), () {
      _closeOverlay();
    });
  }

  void _closeOverlay() {
    _autoCloseTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastSixCards = widget.discardPile.length > 6
        ? widget.discardPile.sublist(widget.discardPile.length - 6)
        : widget.discardPile;
    final reversedCards = lastSixCards.reversed.toList();

    return GestureDetector(
      onTap: _closeOverlay,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 400),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.neonBlue,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonBlue.withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Discard Pile History',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: AppTheme.neonBlue,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            if (reversedCards.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'No cards discarded yet',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: reversedCards.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final card = entry.value;
                                  final rotation = (index % 2 == 0 ? 1 : -1) * 5.0;
                                  
                                  return Transform.rotate(
                                    angle: rotation * 3.14159 / 180,
                                    child: UnoCardWidget(
                                      card: card,
                                      width: 70,
                                      height: 105,
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap outside to close',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
