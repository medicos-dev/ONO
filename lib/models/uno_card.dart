import 'package:uuid/uuid.dart';

/// UNO card colors
enum UnoColor {
  red,
  blue,
  green,
  yellow,
  black; // For wild cards

  String toJson() => name;

  static UnoColor fromJson(String json) {
    return UnoColor.values.firstWhere((e) => e.name == json);
  }

  /// Get the display color for UI
  int get colorValue {
    switch (this) {
      case UnoColor.red:
        return 0xFFE53935;
      case UnoColor.blue:
        return 0xFF1E88E5;
      case UnoColor.green:
        return 0xFF43A047;
      case UnoColor.yellow:
        return 0xFFFDD835;
      case UnoColor.black:
        return 0xFF212121;
    }
  }
}

/// UNO card types
enum UnoCardType {
  number,
  skip,
  reverse,
  drawTwo,
  wild,
  wildDrawFour;

  String toJson() => name;

  static UnoCardType fromJson(String json) {
    return UnoCardType.values.firstWhere((e) => e.name == json);
  }
}

/// Represents a single UNO card
class UnoCard {
  final String id;
  final UnoColor color;
  final String value;
  final UnoCardType type;

  UnoCard({
    String? id,
    required this.color,
    required this.value,
    required this.type,
  }) : id = id ?? const Uuid().v4();

  /// Create a copy with optional new values
  UnoCard copyWith({
    String? id,
    UnoColor? color,
    String? value,
    UnoCardType? type,
  }) {
    return UnoCard(
      id: id ?? this.id,
      color: color ?? this.color,
      value: value ?? this.value,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'color': color.toJson(),
      'value': value,
      'type': type.toJson(),
    };
  }

  factory UnoCard.fromJson(Map<String, dynamic> json) {
    return UnoCard(
      id: json['id'] as String,
      color: UnoColor.fromJson(json['color'] as String),
      value: json['value'] as String,
      type: UnoCardType.fromJson(json['type'] as String),
    );
  }

  /// Display name for the card
  String get displayName {
    switch (type) {
      case UnoCardType.number:
        return value;
      case UnoCardType.skip:
        return '⊘';
      case UnoCardType.reverse:
        return '⟲';
      case UnoCardType.drawTwo:
        return '+2';
      case UnoCardType.wild:
        return 'W';
      case UnoCardType.wildDrawFour:
        return '+4';
    }
  }

  /// Check if this is a wild card
  bool get isWild => type == UnoCardType.wild || type == UnoCardType.wildDrawFour;

  @override
  String toString() => 'UnoCard($color $displayName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnoCard &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Compact JSON with short keys for network optimization
  Map<String, dynamic> toCompactJson() {
    return {
      'i': id,
      'c': color.index,  // Use index instead of name for color
      'v': value,
      't': type.index,   // Use index instead of name for type
    };
  }

  factory UnoCard.fromCompactJson(Map<String, dynamic> json) {
    return UnoCard(
      id: json['i'] as String,
      color: UnoColor.values[json['c'] as int],
      value: json['v'] as String,
      type: UnoCardType.values[json['t'] as int],
    );
  }
}
