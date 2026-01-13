import 'package:flutter/material.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';

class PlayerAvatar extends StatelessWidget {
  final Player player;
  final bool isActive;
  final bool showCardCount;
  final double size;

  const PlayerAvatar({
    super.key,
    required this.player,
    this.isActive = false,
    this.showCardCount = true,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.darkSurface,
        border: Border.all(
          color: isActive ? AppTheme.neonBlue : AppTheme.neonPurple,
          width: isActive ? 3 : 2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppTheme.neonBlue.withOpacity(0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            player.initials,
            style: TextStyle(
              fontFamily: 'SourGummy',
              fontSize: size * 0.35,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          if (player.isHost)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppTheme.neonYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star,
                  size: 12,
                  color: AppTheme.darkBackground,
                ),
              ),
            ),
          if (showCardCount && player.cardCount > 0)
            Positioned(
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.neonRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${player.cardCount}',
                  style: const TextStyle(
                    fontFamily: 'SourGummy',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
