import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UnoCallOverlay extends StatefulWidget {
  final String playerName;

  const UnoCallOverlay({
    super.key,
    required this.playerName,
  });

  @override
  State<UnoCallOverlay> createState() => _UnoCallOverlayState();
}

class _UnoCallOverlayState extends State<UnoCallOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _controller.reverse().then((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: () {
          if (mounted && Navigator.canPop(context)) {
            _controller.reverse().then((_) {
              Navigator.of(context).pop();
            });
          }
        },
        child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.neonYellow,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonYellow.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'UNO!',
                        style: TextStyle(
                          fontFamily: 'SourGummy',
                          fontSize: 48 * _scaleAnimation.value,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonYellow,
                          shadows: [
                            Shadow(
                              color: AppTheme.neonYellow.withOpacity(0.8),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${widget.playerName} has only\none card left!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'SourGummy',
                          fontSize: 20,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }
}
