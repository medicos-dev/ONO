/// Message types for the game protocol
class MessageType {
  static const String gameState = 'GAME_STATE';
  static const String joinRequest = 'JOIN_REQUEST';
  static const String joinAccepted = 'JOIN_ACCEPTED';
  static const String moveAttempt = 'MOVE_ATTEMPT';
  static const String drawRequest = 'DRAW_REQUEST';
  static const String passTurn = 'PASS_TURN';
  static const String startGame = 'START_GAME';
  static const String playerJoined = 'PLAYER_JOINED';
  static const String playerLeft = 'PLAYER_LEFT';
  static const String playerResign = 'PLAYER_RESIGN';
  static const String winnerKicked = 'WINNER_KICKED';
  static const String gameOver = 'GAME_OVER';
  static const String syncRequest = 'SYNC_REQUEST';
  static const String heartbeat = 'HEARTBEAT';
  static const String unoCall = 'UNO_CALL'; // Player called UNO!
  static const String notification = 'NOTIFICATION'; // Generic notification
  static const String gameGap = 'GAME_GAP'; // Gap in game state sequence
  static const String prepareGame =
      'PREPARE_GAME'; // Host signals game is about to start
  static const String ackReady = 'ACK_READY'; // Joiner acknowledges ready

  // Sequential Sync Messages (Step-by-step state transfer)
  static const String setPlayers = 'SET_PLAYERS'; // Step 1: Player list
  static const String setDeck = 'SET_DECK'; // Step 2: Deck chunk
  static const String setHand = 'SET_HAND'; // Step 3: Player's hand
  static const String goLive = 'GO_LIVE'; // Step 4: Final trigger
  static const String reqResend = 'REQ_RESEND'; // Request re-send of a step

  // Full State Snapshot Architecture
  static const String initGameStart =
      'INIT_GAME_START'; // Tiny message to prepare UI
  static const String gameSnapshot = 'GAME_SNAPSHOT'; // Full compressed state
  static const String snapshotAck =
      'SNAPSHOT_ACK'; // Acknowledgement of snapshot

  // Reliable Handshake (3-step sync)
  static const String startSignal =
      'START_SIGNAL'; // Host -> Joiners: Game starting
  static const String readyToReceive =
      'READY_TO_RECEIVE'; // Joiner -> Host: Ready for snapshot

  // Snapshot Chunking (for large payloads)
  static const String snapshotPart1 = 'SNAPSHOT_PART_1'; // First chunk
  static const String snapshotPart2 = 'SNAPSHOT_PART_2'; // Second chunk

  // Multi-Card Play
  static const String throwMultiple =
      'THROW_MULTIPLE'; // Play multiple matching cards

  // Game End
  static const String gameEnded =
      'GAME_ENDED'; // Auto-kick after 20s winner display
  static const String roomClosed = 'ROOM_CLOSED';

  // Global Event System for Animations (Transient Events)
  static const String gameEvent = 'GAME_EVENT'; // Generic event wrapper for animations
  static const String wildColorChange =
      'WILD_COLOR_CHANGE'; // Wild card color selection animation
  static const String unoAnnounced =
      'UNO_ANNOUNCED'; // Player called UNO animation
  static const String gameOverCelebration =
      'GAME_OVER_CELEBRATION'; // Game end celebration animation

  // Host Management
  static const String hostLeft = 'HOST_LEFT'; // Host left - kick all players
  static const String hostResigned = 'HOST_RESIGNED'; // Host resigned - new host selected
  static const String newHostSelected = 'NEW_HOST_SELECTED'; // New host notification

  static const String error = 'ERROR';
}

/// A game message that gets sent over the network
class GameMessage {
  final String type;
  final String senderId;
  final String senderName;
  final Map<String, dynamic> payload;
  final int timestamp;
  final int sequenceNumber; // For ordering messages

  GameMessage({
    required this.type,
    required this.senderId,
    required this.senderName,
    this.payload = const {},
    int? timestamp,
    this.sequenceNumber = 0,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() {
    return {
      '_ono': true, // Marker to identify our messages
      'type': type,
      'senderId': senderId,
      'senderName': senderName,
      'payload': payload,
      'timestamp': timestamp,
      'seq': sequenceNumber,
    };
  }

  factory GameMessage.fromJson(Map<String, dynamic> json) {
    return GameMessage(
      type: json['type'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      timestamp: json['timestamp'] as int?,
      sequenceNumber: json['seq'] as int? ?? 0,
    );
  }

  /// Check if a JSON is a valid ONO game message
  static bool isOnoMessage(Map<String, dynamic> json) {
    return json['_ono'] == true && json.containsKey('type');
  }

  @override
  String toString() => 'GameMessage($type from $senderName)';
}
