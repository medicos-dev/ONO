import 'package:flutter/material.dart';
import '../models/card.dart';
import '../widgets/uno_card_widget.dart';

class CardFlyAnimation extends StatefulWidget {
  final UnoCard card;
  final Offset startPosition;
  final Offset endPosition;
  final VoidCallback? onComplete;
  final Duration duration;

  const CardFlyAnimation({
    super.key,
    required this.card,
    required this.startPosition,
    required this.endPosition,
    this.onComplete,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  State<CardFlyAnimation> createState() => _CardFlyAnimationState();
}

class _CardFlyAnimationState extends State<CardFlyAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    final curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _positionAnimation = Tween<Offset>(
      begin: widget.startPosition,
      end: widget.endPosition,
    ).animate(curvedAnimation);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.3,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 0.9)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 0.3,
      ),
    ]).animate(curvedAnimation);

    _controller.forward().then((_) {
      widget.onComplete?.call();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAnimating && _controller.isCompleted) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx,
          top: _positionAnimation.value.dy,
          child: IgnorePointer(
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: UnoCardWidget(
                card: widget.card,
                width: 80,
                height: 120,
              ),
            ),
          ),
        );
      },
    );
  }
}
