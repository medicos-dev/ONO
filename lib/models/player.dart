import 'package:uuid/uuid.dart';
import 'uno_card.dart';

/// Represents a player in the UNO game
class Player {
  final String id;
  final String name;
  final List<UnoCard> hand;
  final bool isHost;

  Player({
    String? id,
    required this.name,
    List<UnoCard>? hand,
    this.isHost = false,
  }) : id = id ?? const Uuid().v4(),
       hand = hand ?? [];

  /// Create a copy with optional new values
  Player copyWith({
    String? id,
    String? name,
    List<UnoCard>? hand,
    bool? isHost,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      hand: hand ?? List.from(this.hand),
      isHost: isHost ?? this.isHost,
    );
  }

  /// Add a card to the player's hand
  Player addCard(UnoCard card) {
    return copyWith(hand: [...hand, card]);
  }

  /// Add multiple cards to the player's hand
  Player addCards(List<UnoCard> cards) {
    return copyWith(hand: [...hand, ...cards]);
  }

  /// Remove a card from the player's hand by ID
  Player removeCard(String cardId) {
    return copyWith(hand: hand.where((c) => c.id != cardId).toList());
  }

  /// Check if player has exactly one card (UNO condition)
  bool get hasUno => hand.length == 1;

  /// Check if player has won (no cards left)
  bool get hasWon => hand.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hand': hand.map((c) => c.toJson()).toList(),
      'isHost': isHost,
    };
  }

  // Factory for DB Row (room_players)
  factory Player.fromDbRow(Map<String, dynamic> row) {
    return Player(
      id: row['player_id'] as String,
      name: row['player_name'] as String? ?? 'Unknown',
      hand:
          (row['cards'] as List?)
              ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      isHost: false, // Calculated separately
    );
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'Unknown',
      hand:
          (json['hand'] as List?)
              ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      isHost: json['isHost'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'Player($name, ${hand.length} cards)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Player && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Compact JSON with short keys for network optimization
  Map<String, dynamic> toCompactJson() {
    return {
      'i': id,
      'n': name,
      'h': hand.map((c) => c.toCompactJson()).toList(),
      'o': isHost,
    };
  }

  factory Player.fromCompactJson(Map<String, dynamic> json) {
    return Player(
      id: json['i'] as String? ?? const Uuid().v4(),
      name: json['n'] as String? ?? 'Unknown',
      hand:
          (json['h'] as List?)
              ?.map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      isHost: json['o'] as bool? ?? false,
    );
  }
}
