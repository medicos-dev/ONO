import 'package:flutter/material.dart';
import '../models/card.dart';

enum UnoCardSize { small, medium, large }

/// Widget to display a UNO card
class UnoCardWidget extends StatelessWidget {
  final UnoCard card;
  final bool isPlayable;
  final bool isSelected;
  final CardColor? activeColor;
  final UnoCardSize size;
  final double? width;
  final double? height;

  const UnoCardWidget({
    super.key,
    required this.card,
    this.isPlayable = false,
    this.isSelected = false,
    this.activeColor,
    this.size = UnoCardSize.medium,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final dimensions = _getDimensions();
    final effectiveColor = card.isWild && activeColor != null
        ? activeColor!
        : card.color;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      transform: Matrix4.identity()
        ..translate(0.0, isPlayable ? -10.0 : 0.0),
      child: Container(
        width: width ?? dimensions.width,
        height: height ?? dimensions.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(dimensions.borderRadius),
          gradient: _getCardGradient(effectiveColor),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFA4CD01)
                : isPlayable
                    ? const Color(0xFFFDD835)
                    : Colors.white.withOpacity(0.3),
            width: isSelected ? 3 : isPlayable ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isPlayable
                  ? const Color(0xFFFDD835).withOpacity(0.4)
                  : Colors.black.withOpacity(0.3),
              blurRadius: isPlayable ? 15 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (card.isWild) _buildWildBackground(dimensions),
            
            Padding(
              padding: EdgeInsets.all(dimensions.padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: _buildCornerText(dimensions.cornerFontSize),
                  ),
                  
                  Expanded(
                    child: Center(
                      child: _buildCenterContent(dimensions.centerFontSize),
                    ),
                  ),
                  
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.rotate(
                      angle: 3.14159,
                      child: _buildCornerText(dimensions.cornerFontSize),
                    ),
                  ),
                ],
              ),
            ),
            
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFA4CD01),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _CardDimensions _getDimensions() {
    if (width != null && height != null) {
      return _CardDimensions(
        width: width!,
        height: height!,
        borderRadius: 12,
        padding: 6,
        cornerFontSize: 12,
        centerFontSize: 24,
      );
    }
    
    switch (size) {
      case UnoCardSize.small:
        return const _CardDimensions(
          width: 50,
          height: 75,
          borderRadius: 8,
          padding: 4,
          cornerFontSize: 10,
          centerFontSize: 16,
        );
      case UnoCardSize.medium:
        return const _CardDimensions(
          width: 70,
          height: 105,
          borderRadius: 12,
          padding: 6,
          cornerFontSize: 12,
          centerFontSize: 24,
        );
      case UnoCardSize.large:
        return const _CardDimensions(
          width: 90,
          height: 135,
          borderRadius: 16,
          padding: 8,
          cornerFontSize: 14,
          centerFontSize: 32,
        );
    }
  }

  LinearGradient _getCardGradient(CardColor color) {
    switch (color) {
      case CardColor.red:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE53935), Color(0xFFC62828)],
        );
      case CardColor.blue:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
        );
      case CardColor.green:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
        );
      case CardColor.yellow:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDD835), Color(0xFFF9A825)],
        );
      case CardColor.wild:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF424242), Color(0xFF212121)],
        );
    }
  }

  Widget _buildWildBackground(_CardDimensions dimensions) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dimensions.borderRadius - 2),
        child: CustomPaint(
          painter: _WildCardPainter(),
        ),
      ),
    );
  }

  Widget _buildCornerText(double fontSize) {
    return Text(
      _getDisplayValue(),
      style: TextStyle(
        color: _getTextColor(),
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(
            color: Colors.black26,
            blurRadius: 2,
            offset: Offset(1, 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterContent(double fontSize) {
    switch (card.type) {
      case CardType.skip:
        return Icon(
          Icons.not_interested,
          size: fontSize * 1.5,
          color: _getTextColor(),
        );
      case CardType.reverse:
        return Icon(
          Icons.swap_horiz,
          size: fontSize * 1.5,
          color: _getTextColor(),
        );
      case CardType.drawTwo:
        return Text(
          '+2',
          style: TextStyle(
            color: _getTextColor(),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        );
      case CardType.wild:
        return _buildWildIcon(fontSize);
      case CardType.wildDrawFour:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildWildIcon(fontSize * 0.6),
            const SizedBox(height: 4),
            Text(
              '+4',
              style: TextStyle(
                color: _getTextColor(),
                fontSize: fontSize * 0.7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      case CardType.number:
        return Text(
          '${card.number}',
          style: TextStyle(
            color: _getTextColor(),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        );
    }
  }

  Widget _buildWildIcon(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WildIconPainter(),
      ),
    );
  }

  String _getDisplayValue() {
    switch (card.type) {
      case CardType.number:
        return '${card.number}';
      case CardType.skip:
        return '⊘';
      case CardType.reverse:
        return '⟲';
      case CardType.drawTwo:
        return '+2';
      case CardType.wild:
        return 'W';
      case CardType.wildDrawFour:
        return '+4';
    }
  }

  Color _getTextColor() {
    if (card.color == CardColor.yellow) {
      return Colors.black87;
    }
    return Colors.white;
  }
}

class _CardDimensions {
  final double width;
  final double height;
  final double borderRadius;
  final double padding;
  final double cornerFontSize;
  final double centerFontSize;

  const _CardDimensions({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.padding,
    required this.cornerFontSize,
    required this.centerFontSize,
  });
}

class _WildCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
      const Color(0xFFFDD835),
    ];

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    
    for (int i = 0; i < 4; i++) {
      final startAngle = (i * 3.14159 / 2) - 3.14159 / 4;
      path.reset();
      path.moveTo(center.dx, center.dy);
      path.arcTo(
        Rect.fromCenter(center: center, width: size.width * 2, height: size.height * 2),
        startAngle,
        3.14159 / 2,
        false,
      );
      path.close();
      
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i].withOpacity(0.3)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WildIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
      const Color(0xFFFDD835),
    ];

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (int i = 0; i < 4; i++) {
      final startAngle = (i * 3.14159 / 2) - 3.14159 / 2;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          3.14159 / 2,
          false,
        )
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
