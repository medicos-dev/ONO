import 'uno_card.dart';
import 'player.dart';

/// Game phases
enum GamePhase {
  lobby, // Waiting for players
  playing, // Game in progress
  finished; // Game over

  String toJson() => name;

  static GamePhase fromJson(String json) {
    return GamePhase.values.firstWhere((e) => e.name == json);
  }
}

/// Complete game state that gets synchronized between Host and Clients
class GameState {
  final List<UnoCard> drawPile;
  final List<UnoCard> discardPile;
  final List<Player> players;
  final int currentPlayerIndex;
  final bool isClockwise;
  final UnoColor?
  activeColor; // For wild cards, overrides discard pile top color
  final GamePhase phase;
  final String? winnerId;
  final String? winnerName;
  final String hostId;
  final String roomCode;
  final List<UnoCard>?
  activeMultiThrowStack; // Visual synchronization for multi-card throws

  // Advanced game mechanics
  final List<String> winners; // Ordered list of winner names (1st, 2nd, 3rd...)
  final int pendingDraws; // Tracks +2/+4 draws remaining
  final UnoCard? lastPlayedCard; // For wild card animation trigger
  final String? unoCaller; // Name of player who called UNO (for animation sync)

  GameState({
    this.drawPile = const [],
    this.discardPile = const [],
    this.players = const [],
    this.currentPlayerIndex = 0,
    this.isClockwise = true,
    this.activeColor,
    this.activeMultiThrowStack,
    this.phase = GamePhase.lobby,
    this.winnerId,
    this.winnerName,
    required this.hostId,
    required this.roomCode,
    this.winners = const [],
    this.pendingDraws = 0,
    this.lastPlayedCard,
    this.unoCaller,
  });

  /// Create initial lobby state
  factory GameState.lobby({
    required String hostId,
    required String roomCode,
    required Player host,
  }) {
    return GameState(
      hostId: hostId,
      roomCode: roomCode,
      players: [host],
      phase: GamePhase.lobby,
      unoCaller: null,
    );
  }

  /// Create a copy with optional new values
  GameState copyWith({
    List<UnoCard>? drawPile,
    List<UnoCard>? discardPile,
    List<Player>? players,
    int? currentPlayerIndex,
    bool? isClockwise,
    UnoColor? activeColor,
    bool clearActiveColor = false,
    List<UnoCard>? activeMultiThrowStack,
    bool clearMultiThrowStack = false,
    GamePhase? phase,
    String? winnerId,
    String? winnerName,
    String? hostId,
    String? roomCode,
    List<String>? winners,
    int? pendingDraws,
    UnoCard? lastPlayedCard,
    bool clearLastPlayedCard = false,
    String? unoCaller,
    bool clearUnoCaller = false,
  }) {
    return GameState(
      drawPile: drawPile ?? this.drawPile,
      discardPile: discardPile ?? this.discardPile,
      players: players ?? this.players,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      isClockwise: isClockwise ?? this.isClockwise,
      activeColor: clearActiveColor ? null : (activeColor ?? this.activeColor),
      activeMultiThrowStack:
          clearMultiThrowStack
              ? null
              : (activeMultiThrowStack ?? this.activeMultiThrowStack),
      phase: phase ?? this.phase,
      winnerId: winnerId ?? this.winnerId,
      winnerName: winnerName ?? this.winnerName,
      hostId: hostId ?? this.hostId,
      roomCode: roomCode ?? this.roomCode,
      winners: winners ?? this.winners,
      pendingDraws: pendingDraws ?? this.pendingDraws,
      lastPlayedCard:
          clearLastPlayedCard ? null : (lastPlayedCard ?? this.lastPlayedCard),
      unoCaller: clearUnoCaller ? null : (unoCaller ?? this.unoCaller),
    );
  }

  /// Get the current player
  Player? get currentPlayer {
    if (players.isEmpty || currentPlayerIndex >= players.length) return null;
    return players[currentPlayerIndex];
  }

  /// Get the top card of the discard pile
  UnoCard? get topDiscard {
    if (discardPile.isEmpty) return null;
    return discardPile.last;
  }

  /// Get the effective color (considers wild card color choice)
  UnoColor? get effectiveColor {
    if (activeColor != null) return activeColor;
    return topDiscard?.color;
  }

  /// Find a player by ID
  Player? getPlayerById(String id) {
    try {
      return players.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get the index of a player by ID
  int getPlayerIndex(String id) {
    return players.indexWhere((p) => p.id == id);
  }

  /// Add a player to the game
  GameState addPlayer(Player player) {
    return copyWith(players: [...players, player]);
  }

  /// Remove a player from the game
  GameState removePlayer(String playerId) {
    final newPlayers = players.where((p) => p.id != playerId).toList();
    int newIndex = currentPlayerIndex;
    if (newIndex >= newPlayers.length && newPlayers.isNotEmpty) {
      newIndex = 0;
    }
    return copyWith(players: newPlayers, currentPlayerIndex: newIndex);
  }

  /// Update a specific player
  GameState updatePlayer(Player updatedPlayer) {
    return copyWith(
      players:
          players.map((p) {
            return p.id == updatedPlayer.id ? updatedPlayer : p;
          }).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'drawPile': drawPile.map((c) => c.toJson()).toList(),
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'players': players.map((p) => p.toJson()).toList(),
      'currentPlayerIndex': currentPlayerIndex,
      'isClockwise': isClockwise,
      'activeColor': activeColor?.toJson(),
      'activeMultiThrowStack':
          activeMultiThrowStack?.map((c) => c.toJson()).toList(),
      'phase': phase.toJson(),
      'winnerId': winnerId,
      'winnerName': winnerName,
      'hostId': hostId,
      'roomCode': roomCode,
      'winners': winners,
      'pendingDraws': pendingDraws,
      'lastPlayedCard': lastPlayedCard?.toJson(),
      'unoCaller': unoCaller,
    };
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      drawPile:
          (json['drawPile'] as List?)
              ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      discardPile:
          (json['discardPile'] as List?)
              ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      players:
          (json['players'] as List?)
              ?.map((p) => Player.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      isClockwise: json['isClockwise'] as bool? ?? true,
      activeColor:
          json['activeColor'] != null
              ? UnoColor.fromJson(json['activeColor'] as String)
              : null,
      activeMultiThrowStack:
          (json['activeMultiThrowStack'] as List?)
              ?.map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
              .toList(),
      phase:
          json['phase'] != null
              ? GamePhase.fromJson(json['phase'] as String)
              : GamePhase.lobby,
      winnerId: json['winnerId'] as String?,
      winnerName: json['winnerName'] as String?,
      hostId: json['hostId'] as String? ?? '',
      roomCode: json['roomCode'] as String? ?? '',
      winners: (json['winners'] as List?)?.cast<String>() ?? [],
      pendingDraws: json['pendingDraws'] as int? ?? 0,
      lastPlayedCard:
          json['lastPlayedCard'] != null
              ? UnoCard.fromJson(json['lastPlayedCard'] as Map<String, dynamic>)
              : null,
      unoCaller: json['unoCaller'] as String?,
    );
  }

  /// Compact JSON with short keys for network optimization
  /// Keys: d=drawPile, x=discardPile, p=players, c=currentPlayerIndex,
  /// w=isClockwise, a=activeColor, m=activeMultiThrowStack, h=phase, i=winnerId, n=winnerName,
  /// o=hostId, r=roomCode, W=winners, D=pendingDraws, L=lastPlayedCard
  Map<String, dynamic> toCompactJson() {
    return {
      'd': drawPile.map((c) => c.toCompactJson()).toList(),
      'x': discardPile.map((c) => c.toCompactJson()).toList(),
      'p': players.map((p) => p.toCompactJson()).toList(),
      'c': currentPlayerIndex,
      'w': isClockwise,
      if (activeColor != null) 'a': activeColor!.index,
      if (activeMultiThrowStack != null)
        'm': activeMultiThrowStack!.map((c) => c.toCompactJson()).toList(),
      'h': phase.index,
      if (winnerId != null) 'i': winnerId,
      if (winnerName != null) 'n': winnerName,
      'o': hostId,
      'r': roomCode,
      if (winners.isNotEmpty) 'W': winners,
      if (pendingDraws > 0) 'D': pendingDraws,
      if (lastPlayedCard != null) 'L': lastPlayedCard!.toCompactJson(),
    };
  }

  factory GameState.fromCompactJson(Map<String, dynamic> json) {
    return GameState(
      drawPile:
          (json['d'] as List?)
              ?.map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      discardPile:
          (json['x'] as List?)
              ?.map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      players:
          (json['p'] as List?)
              ?.map((p) => Player.fromCompactJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      currentPlayerIndex: json['c'] as int? ?? 0,
      isClockwise: json['w'] as bool? ?? true,
      activeColor: json['a'] != null ? UnoColor.values[json['a'] as int] : null,
      activeMultiThrowStack:
          (json['m'] as List?)
              ?.map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList(),
      phase:
          json['h'] != null
              ? GamePhase.values[json['h'] as int]
              : GamePhase.lobby,
      winnerId: json['i'] as String?,
      winnerName: json['n'] as String?,
      hostId: json['o'] as String? ?? '',
      roomCode: json['r'] as String? ?? '',
      winners: (json['W'] as List?)?.cast<String>() ?? [],
      pendingDraws: json['D'] as int? ?? 0,
      lastPlayedCard:
          json['L'] != null
              ? UnoCard.fromCompactJson(json['L'] as Map<String, dynamic>)
              : null,
    );
  }

  @override
  String toString() =>
      'GameState(phase: $phase, players: ${players.length}, turn: $currentPlayerIndex)';
}
