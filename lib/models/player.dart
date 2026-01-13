import 'card.dart';

class Player {
  final String id;
  final String name;
  final String roomCode;
  final bool isHost;
  final bool isSpectator;
  final int? seatNumber;
  final List<UnoCard> hand;
  final DateTime lastSeen;

  Player({
    required this.id,
    required this.name,
    required this.roomCode,
    required this.isHost,
    this.isSpectator = false,
    this.seatNumber,
    required this.hand,
    required this.lastSeen,
  });

  int get cardCount => hand.length;
  
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length > 1 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roomCode': roomCode,
      'isHost': isHost,
      'isSpectator': isSpectator,
      'seatNumber': seatNumber,
      'hand': hand.map((c) => c.toJson()).toList(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      roomCode: json['roomCode'] as String,
      isHost: json['isHost'] as bool? ?? false,
      isSpectator: json['isSpectator'] as bool? ?? false,
      seatNumber: json['seatNumber'] as int?,
      hand: (json['hand'] as List<dynamic>?)
          ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }

  Player copyWith({
    String? id,
    String? name,
    String? roomCode,
    bool? isHost,
    bool? isSpectator,
    int? seatNumber,
    List<UnoCard>? hand,
    DateTime? lastSeen,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      roomCode: roomCode ?? this.roomCode,
      isHost: isHost ?? this.isHost,
      isSpectator: isSpectator ?? this.isSpectator,
      seatNumber: seatNumber ?? this.seatNumber,
      hand: hand ?? this.hand,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
