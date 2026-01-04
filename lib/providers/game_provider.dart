import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/uno_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../logic/game_logic.dart';
import '../services/supabase_uno_service.dart';
import '../services/message_types.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Main game state provider handling both Host and Client logic
class GameProvider extends ChangeNotifier {
  final SupabaseUnoService _networkService = SupabaseUnoService();
  final String _myPlayerId = const Uuid().v4();

  GameState? _gameState;
  String _myName = '';
  bool _isHost = false;
  bool _gameStarted =
      false; // Track if game has officially started (prevents lobby reversion)
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _error;
  bool _hasDrawnCard = false;
  UnoCard? _lastDrawnCard;
  int _lastStateSequence = 0;
  bool _showWinnerAnimation = false;
  String? _winnerAnimationName;
  bool _isWinnerAnimationForMe = false;
  bool _wasKickedAsWinner = false;
  bool _kicked = false; // Flag to indicate if player was kicked/room closed
  bool _showWildAnimation = false; // Trigger for wild card celebration

  // JOIN_REQUEST retry logic for clients
  Timer? _joinRetryTimer;
  bool _hasReceivedGameState = false;

  // UNO call animation state
  bool _showUnoCallAnimation = false;
  String? _unoCallerName;
  bool _hasCalledUno = false; // Tracks if player already called UNO this round

  // Flag-based handshake state (Host)
  final Set<String> _ackReceivedFrom = {}; // Track which players sent ACK_READY
  bool _waitingForAcks = false;

  Timer? _prepareGameRetryTimer;

  // Flag-based handshake state (Joiner)
  bool _isPreparingGame = false; // Set when PREPARE_GAME received

  // Sequential Sync Progress (Joiner)
  bool _hasReceivedPlayers = false;
  bool _hasReceivedDeck = false;
  bool _hasReceivedHand = false;
  bool _isGameLive = false;

  Timer? _syncStepTimeoutTimer;

  // Temporary storage for sequential sync (Joiner)
  List<Player>? _tempPlayers;
  List<UnoCard>? _tempDeck;
  List<UnoCard>? _tempMyHand;
  UnoCard? _tempStarterCard;

  // Full State Snapshot (Host)
  final Set<String> _snapshotAckReceived = {};

  // Logic: Valid UNO Calls (Host)
  final Set<String> _playersWhoCalledUno = {};

  Timer? _snapshotRetryTimer;

  // Reliable Sync Handshake & Chunking
  String? _snapshotPart1;
  Timer? _readyToReceiveRetryTimer;
  final Set<String> _pendingSnapshotReceivers =
      {}; // Host: Logic to track who needs snapshot

  Timer? _multiThrowClearTimer; // 10s timer for clearing center stack
  Timer? _gameEndTimer; // 20s timer for auto-kick after winner

  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _errorSubscription;
  Timer? _syncTimer;
  StreamSubscription? _presenceSubscription;

  // Animation Hygiene Timers
  Timer? _unoCallAnimationTimer;
  Timer? _unoCallStateTimer;
  Timer? _localUnoCooldownTimer;

  // Getters
  GameState? get gameState => _gameState;
  String get myPlayerId => _myPlayerId;
  String get myName => _myName;
  bool get isHost =>
      _isHost ||
      (_gameState?.hostId != null && _gameState!.hostId == _myPlayerId);
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get error => _error;
  bool get hasDrawnCard => _hasDrawnCard;
  UnoCard? get lastDrawnCard => _lastDrawnCard;
  bool get showWinnerAnimation => _showWinnerAnimation;
  String? get winnerAnimationName => _winnerAnimationName;
  bool get isWinnerAnimationForMe => _isWinnerAnimationForMe;
  bool get wasKickedAsWinner => _wasKickedAsWinner;
  bool get showWildAnimation => _showWildAnimation;
  bool get showUnoCallAnimation => _showUnoCallAnimation;
  String? get unoCallerName => _unoCallerName;
  bool get canCallUno => myPlayer?.hasUno == true && !_hasCalledUno;
  bool get isPreparingGame => _isPreparingGame; // For greedy navigation
  /// True when joiner is waiting for first state from Host
  bool get isSyncing => !_isHost && _isConnected && !_hasReceivedGameState;

  // Sequential sync progress getters (for Lobby UI)
  bool get hasReceivedPlayers => _hasReceivedPlayers;
  bool get hasReceivedDeck => _hasReceivedDeck;
  bool get hasReceivedHand => _hasReceivedHand;
  bool get isGameLive => _isGameLive;

  /// Cancel all sync timers (call when data-driven navigation succeeds)
  void cancelAllSyncTimers() {
    debugPrint('DEBUG: Cancelling all sync timers');
    _syncStepTimeoutTimer?.cancel();
    _readyToReceiveRetryTimer?.cancel();
    _snapshotRetryTimer?.cancel();
    _prepareGameRetryTimer?.cancel();
    _joinRetryTimer?.cancel();
  }

  /// Get my player object from the game state
  Player? get myPlayer => _gameState?.getPlayerById(_myPlayerId);

  /// Get my cards directly (SSOT shortcut)
  List<UnoCard> get myCards => myPlayer?.hand ?? [];

  /// Check if it's my turn
  bool get isMyTurn {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) {
      return false;
    }
    return _gameState!.currentPlayer?.id == _myPlayerId;
  }

  /// Get list of other players
  List<Player> get opponents {
    if (_gameState == null) return [];
    return _gameState!.players.where((p) => p.id != _myPlayerId).toList();
  }

  /// Reset all local state for a fresh start
  void reset() {
    _syncTimer?.cancel();
    _joinRetryTimer?.cancel();
    _prepareGameRetryTimer?.cancel();
    _snapshotRetryTimer?.cancel();
    _readyToReceiveRetryTimer?.cancel();
    _multiThrowClearTimer?.cancel();
    _gameEndTimer?.cancel();
    _unoCallAnimationTimer?.cancel();
    _unoCallStateTimer?.cancel();
    _localUnoCooldownTimer?.cancel();

    _gameState = null;
    _error = null;
    _isConnected = false;
    _isConnecting = false;
    _gameStarted = false;
    _hasDrawnCard = false;
    _lastDrawnCard = null;
    _lastStateSequence = 0;
    _showWinnerAnimation = false;
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    _wasKickedAsWinner = false;
    _kicked = false;
    _hasReceivedGameState = false;
    _hasCalledUno = false;
    _unoCallerName = null;
    _showUnoCallAnimation = false;
    _ackReceivedFrom.clear();
    _waitingForAcks = false;

    // Reset sync flags
    _hasReceivedPlayers = false;
    _hasReceivedDeck = false;
    _hasReceivedHand = false;
    _isGameLive = false;

    notifyListeners();
  }

  /// Create a new room as host
  Future<bool> createRoom(String playerName, String roomCode) async {
    reset(); // Clear previous state
    _myName = playerName;
    _isHost = true;
    _isConnecting = true;
    notifyListeners();

    debugPrint('DEBUG: Host creating room $roomCode as $playerName');

    final success = await _networkService.connect(
      roomId: roomCode,
      playerName: playerName,
      playerId: _myPlayerId,
      isHost: true,
    );

    // ... rest of createRoom ...

    if (success) {
      _isConnected = true;
      _setupListeners();
      WakelockPlus.enable(); // Keep screen on during game

      // Create initial lobby state
      final host = Player(id: _myPlayerId, name: playerName, isHost: true);

      _gameState = GameState.lobby(
        hostId: _myPlayerId,
        roomCode: roomCode,
        host: host,
      );

      // Start periodic sync broadcasts (10 seconds)
      _startSyncTimer();

      // Broadcast initial state immediately
      debugPrint('DEBUG: Host broadcasting initial GAME_STATE');
      _broadcastGameState();
    } else {
      _error = 'Failed to create room';
    }

    _isConnecting = false;
    notifyListeners();
    return success;
  }

  /// Join an existing room as client
  Future<bool> joinRoom(String playerName, String roomCode) async {
    reset(); // Clear previous state
    _myName = playerName;
    _isHost = false;
    _isConnecting = true;
    notifyListeners();

    debugPrint('DEBUG: Client joining room $roomCode as $playerName');

    final success = await _networkService.connect(
      roomId: roomCode,
      playerName: playerName,
      playerId: _myPlayerId,
      isHost: false,
    );

    if (success) {
      _isConnected = true;
      _setupListeners();
      WakelockPlus.enable(); // Keep screen on during game

      // Send initial JOIN_REQUEST
      _sendJoinRequest();

      // Start retry timer - resend JOIN_REQUEST after 3 seconds if no GAME_STATE received
      _startJoinRetryTimer();
    } else {
      _error = 'Failed to join room';
    }

    _isConnecting = false;
    notifyListeners();
    return success;
  }

  void _sendJoinRequest() {
    debugPrint('DEBUG: Client sending JOIN_REQUEST for $_myName');
    _networkService.send(
      type: MessageType.joinRequest,
      payload: {'playerId': _myPlayerId, 'playerName': _myName},
    );

    // ROBUST JOIN: Also write to DB so Host sees us even if Broadcast misses
    _networkService.joinViaDb(_myPlayerId, _myName);
  }

  void _startJoinRetryTimer() {
    _joinRetryTimer?.cancel();
    // Debounce: Only retry every 3 seconds
    _joinRetryTimer = Timer(const Duration(seconds: 3), () {
      if (!_hasReceivedGameState && _isConnected && !_isHost) {
        debugPrint(
          'DEBUG: Client retrying JOIN_REQUEST (no GAME_STATE received after 3s)',
        );
        _sendJoinRequest();

        // Set up another retry in 3 more seconds
        _joinRetryTimer = Timer(const Duration(seconds: 3), () {
          if (!_hasReceivedGameState && _isConnected && !_isHost) {
            debugPrint('DEBUG: Client second retry JOIN_REQUEST');
            _sendJoinRequest();
          }
        });
      }
    });
  }

  StreamSubscription? _playersSubscription;

  void _setupListeners() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _playersSubscription?.cancel();

    _messageSubscription = _networkService.messageStream.listen(_onMessage);
    _connectionSubscription = _networkService.connectionStream.listen(
      _onConnectionChange,
    );
    _errorSubscription = _networkService.errorStream.listen(_onError);

    // Listen to relational players stream
    _playersSubscription = _networkService.playersStream.listen(
      _onPlayersUpdate,
    );
  }

  /// Handle updates from the room_players table
  void _onPlayersUpdate(List<Map<String, dynamic>> rows) {
    if (_gameState == null) return; // Wait for initial state

    // Guard: Reject empty player lists to prevent UI flicker
    if (rows.isEmpty) {
      debugPrint('DEBUG: Ignoring empty player update.');
      return;
    }

    // Use hostId from current state if available to identify host
    final hostId = _gameState?.hostId;

    final newPlayers =
        rows.map((row) {
          final p = Player.fromDbRow(row);
          // Correctly set isHost if we know the hostId
          // If hostId is null, we might default to false, but that's better than guessing
          return p.copyWith(isHost: hostId != null && p.id == hostId);
        }).toList();

    debugPrint(
      'DEBUG: Relational Players Update: ${newPlayers.length} players. Host=$hostId (Current: ${_gameState?.players.length ?? 0})',
    );

    // CRITICAL: In lobby phase, always accept player updates (don't block on count)
    // This ensures host sees new players joining immediately
    final currentCount = _gameState?.players.length ?? 0;
    if (_gameState?.phase == GamePhase.lobby) {
      // In lobby, always update to show new players
      _gameState = _gameState!.copyWith(players: newPlayers);
      debugPrint(
        'Provider: UI Update triggered (LOBBY). Players: ${_gameState!.players.length}',
      );
      notifyListeners();
    } else if (rows.length >= currentCount) {
      // In playing phase, only update if count increases or stays same
      _gameState = _gameState!.copyWith(players: newPlayers);
      debugPrint(
        'Provider: UI Update triggered. Players: ${_gameState!.players.length}',
      );
      notifyListeners();
    } else {
      debugPrint(
        'DEBUG: Ignoring player shrink from $currentCount to ${rows.length} (not in lobby).',
      );
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    // Sync every 10 seconds (safety net)
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isHost && _gameState != null) {
        if (_gameState!.phase != GamePhase.lobby) {
          debugPrint('DEBUG: Host periodic sync broadcast');
          _broadcastGameState();
        }
      }
    });
  }

  void _onMessage(GameMessage message) {
    debugPrint('DEBUG: Received message type: ${message.type}');

    // 0. Filter by targetId if present
    // If a message is targeted to someone else, ignore it
    if (message.payload.containsKey('targetId')) {
      final targetId = message.payload['targetId'];
      if (targetId != _myPlayerId) {
        return;
      }
    }

    switch (message.type) {
      case MessageType.joinRequest:
        _handleJoinRequest(message);
        break;
      case MessageType.gameState:
        _handleGameState(message);
        break;
      case MessageType.moveAttempt:
        _handleMoveAttempt(message);
        break;
      case MessageType.drawRequest:
        _handleDrawRequest(message);
        break;
      case MessageType.passTurn:
        _handlePassTurn(message);
        break;
      case MessageType.startGame:
        if (_isHost) _startGame();
        break;
      case MessageType.playerResign:
        _handlePlayerResign(message);
        break;
      case MessageType.syncRequest:
        if (_isHost) {
          debugPrint('DEBUG: Host received SYNC_REQUEST, broadcasting state');
          _broadcastGameState();
        }
        break;
      case MessageType.playerLeft:
        _handlePlayerLeft(message);
        break;

      case MessageType.winnerKicked:
        _handleWinnerKicked(message);
        break;
      case 'd': // DONE feedback
        _handleSnapshotDone(message);
        break;
      case MessageType.unoCall:
        _handleUnoCall(message);
        break;
      case MessageType.prepareGame:
        _handlePrepareGame(message);
        break;
      case MessageType.ackReady:
        _handleAckReady(message);
        break;
      case MessageType.setPlayers:
        _handleSetPlayers(message);
        break;
      case MessageType.setDeck:
        _handleSetDeck(message);
        break;
      case MessageType.setHand:
        _handleSetHand(message);
        break;
      case MessageType.goLive:
        _handleGoLive(message);
        break;
      case MessageType.reqResend:
        _handleReqResend(message);
        break;

      // INIT_GAME_START is replaced by START_SIGNAL, removing old handler call
      case MessageType.gameSnapshot:
        _handleGameSnapshot(message);
        break;
      case MessageType.snapshotAck:
        _handleSnapshotAck(message);
        break;
      case MessageType.throwMultiple:
        _handleThrowMultiple(message);
        break;
      case MessageType.startSignal:
        _handleStartSignal(message);
        break;
      case MessageType.readyToReceive:
        _handleReadyToReceive(message);
        break;
      case MessageType.snapshotPart1:
        _handleSnapshotPart1(message);
        break;
      case MessageType.snapshotPart2:
        _handleSnapshotPart2(message);
        break;
      case MessageType.gameEnded:
        _handleGameEnded(message);
        break;
      case MessageType.wildColorChange:
        _handleWildColorChange(message);
        break;
      case MessageType.unoAnnounced:
        _handleUnoAnnounced(message);
        break;
      case MessageType.gameOverCelebration:
        _handleGameOverCelebration(message);
        break;
      case MessageType.hostLeft:
        _handleHostLeft(message);
        break;
      case MessageType.hostResigned:
        _handleHostResigned(message);
        break;
      case MessageType.newHostSelected:
        _handleNewHostSelected(message);
        break;
      case MessageType.heartbeat:
        // Heartbeat received
        break;
    }
  }

  void _onConnectionChange(bool connected) {
    _isConnected = connected;
    if (!connected && !_isHost) {
      // Client disconnected, request sync when reconnected
      _networkService.requestSync();
    }
    notifyListeners();
  }

  void _onError(String error) {
    if (error == 'ROOM_CLOSED') {
      // Only non-hosts should be kicked when room is closed
      // The Host themselves triggered the closure, they don't need to be kicked
      if (_isHost) {
        debugPrint('DEBUG: ROOM_CLOSED received but I am host. Ignoring.');
        return;
      }

      debugPrint('DEBUG: Host closed the room. Kicking self...');
      _kicked =
          true; // Use usage-specific flag if available, or just rely on error message
      leaveRoom();
      _error = 'Host closed the room';
      notifyListeners();
      return;
    }

    _error = error;
    notifyListeners();
    // Clear error after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (_error == error) {
        _error = null;
        notifyListeners();
      }
    });
  }

  // === HOST LOGIC ===

  void _handleJoinRequest(GameMessage message) {
    if (!_isHost || _gameState == null) {
      debugPrint('DEBUG: Ignoring JOIN_REQUEST (not host or no game state)');
      return;
    }
    if (_gameState!.phase != GamePhase.lobby) {
      debugPrint('DEBUG: Ignoring JOIN_REQUEST (game not in lobby phase)');
      return;
    }

    final playerId = message.payload['playerId'] as String;
    final playerName = message.payload['playerName'] as String;

    debugPrint(
      'DEBUG: Host received JOIN_REQUEST from $playerName ($playerId)',
    );

    // Check if player already exists
    if (_gameState!.getPlayerById(playerId) != null) {
      debugPrint('DEBUG: Player already in list, broadcasting current state');
      _broadcastGameState();
      return;
    }

    // Add new player
    final newPlayer = Player(id: playerId, name: playerName, isHost: false);

    _gameState = _gameState!.addPlayer(newPlayer);

    debugPrint(
      'DEBUG: Host added player $playerName, now ${_gameState!.players.length} players',
    );
    debugPrint(
      'DEBUG: Host broadcasting GAME_STATE after adding player (priority)',
    );

    // Immediately broadcast with priority
    _broadcastGameState();
    notifyListeners();
  }

  void _handleMoveAttempt(GameMessage message) {
    // Only host processes MOVE_ATTEMPT (both from clients and themselves)
    if (!_isHost || _gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;

    final playerId = message.senderId;
    final cardJson = message.payload['card'] as Map<String, dynamic>;

    // Support both compact and regular JSON
    final card =
        cardJson.containsKey('i')
            ? UnoCard.fromCompactJson(cardJson)
            : UnoCard.fromJson(cardJson);
    final chosenColor =
        message.payload['chosenColor'] != null
            ? UnoColor.fromJson(message.payload['chosenColor'] as String)
            : null;

    // Validate it's this player's turn
    if (_gameState!.currentPlayer?.id != playerId) {
      return;
    }

    // Validate move
    if (!GameLogic.isValidMove(
      card,
      _gameState!.topDiscard,
      _gameState!.activeColor,
    )) {
      return;
    }

    // Broadcast Wild Color Change Event BEFORE applying move (using sendEvent for immediate delivery)
    final wasWild = card.isWild;
    if (wasWild && chosenColor != null) {
      _networkService.sendEvent(
        MessageType.wildColorChange,
        {'color': chosenColor.index},
      );
    }

    // Apply move (host processes their own moves here too)
    final previousDiscardCount = _gameState!.discardPile.length;
    _gameState = GameLogic.applyCardEffect(
      state: _gameState!,
      card: card,
      playerId: playerId,
      chosenColor: chosenColor,
    );
    
    // DEBUG: Verify discard pile was updated
    final newDiscardCount = _gameState!.discardPile.length;
    debugPrint('DEBUG: Card played - Discard pile: $previousDiscardCount -> $newDiscardCount');
    if (newDiscardCount <= previousDiscardCount && _gameState!.phase == GamePhase.playing) {
      debugPrint('ERROR: Discard pile did not increase after playing card!');
    }

    _hasDrawnCard = false;
    _lastDrawnCard = null;

    // Check for UNO announcement (player has 1 card) - use sendEvent for immediate delivery
    final player = _gameState!.getPlayerById(playerId);
    if (player != null && player.hand.length == 1) {
      _networkService.sendEvent(
        MessageType.unoAnnounced,
        {'playerId': playerId, 'playerName': player.name},
      );
    }

    // Check for winner
    if (_gameState!.phase == GamePhase.finished) {
      _handleGameWon();
    }

    // Update DB and broadcast immediately (same as multi-card throwing)
    final ssotState = _generateSSOTState();
    _networkService.updateRemoteGameState(ssotState);
    
    // Use broadcastFullSnapshot for reliable updates (same as multi-card)
    // This ensures all clients receive the complete state including discard pile
    broadcastFullSnapshot(immediate: true);
    
    // CRITICAL: Host also needs to update UI immediately
    notifyListeners();
  }

  void _handleDrawRequest(GameMessage message) {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;

    final playerId = message.senderId;

    if (_gameState!.currentPlayer?.id != playerId) {
      return;
    }

    // Logic for Pending Draws (+2/+4)
    if (_gameState!.pendingDraws > 0) {
      final result = GameLogic.drawCard(_gameState!, playerId);

      // Decrement pending draws
      final newPending = _gameState!.pendingDraws - 1;

      // Update state
      _gameState = result.state.copyWith(pendingDraws: newPending);

      // If no more pending draws, AUTO PASS
      if (newPending == 0) {
        _gameState = GameLogic.passTurn(_gameState!);
      }

      // Update DB and broadcast (same as multi-card)
      _networkService.updateRemoteGameState(_generateSSOTState());
      broadcastFullSnapshot(immediate: true);
      
      // Host updates UI immediately
      notifyListeners();
      return;
    }

    // Normal Draw Logic
    final result = GameLogic.drawCard(_gameState!, playerId);
    _gameState = result.state;

    // Update DB and broadcast (same as multi-card)
    _networkService.updateRemoteGameState(_generateSSOTState());
    broadcastFullSnapshot(immediate: true);
    
    // Host updates UI immediately
    notifyListeners();
  }

  void _handlePassTurn(GameMessage message) {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;

    final playerId = message.senderId;

    if (_gameState!.currentPlayer?.id != playerId) {
      return;
    }

    _gameState = GameLogic.passTurn(_gameState!);
    
    // Update DB and broadcast (same as multi-card)
    _networkService.updateRemoteGameState(_generateSSOTState());
    broadcastFullSnapshot(immediate: true);
    
    // Host updates UI immediately
    notifyListeners();
  }

  void _handlePlayerResign(GameMessage message) {
    if (!_isHost || _gameState == null) return;

    final playerId = message.senderId;
    _kickPlayer(playerId);
  }

  void _handleGameWon() {
    // 1. Update DB status to 'finished' so all clients know game ended
    _networkService.updateRoomStatus('finished');

    // 2. Broadcast GAME_OVER_CELEBRATION event for synchronized animation (using sendEvent)
    _networkService.sendEvent(
      MessageType.gameOverCelebration,
      {
        'winnerId': _gameState!.winnerId,
        'winnerName': _gameState!.winnerName,
      },
    );

    // 3. Send GAME_OVER message to all clients (legacy support)
    _networkService.send(
      type: MessageType.gameOver,
      payload: {
        'winnerId': _gameState!.winnerId,
        'winnerName': _gameState!.winnerName,
      },
    );

    // 4. Show winner animation
    _showWinnerAnimation = true;
    _winnerAnimationName = _gameState?.winnerName ?? 'Unknown';
    _isWinnerAnimationForMe = _gameState?.winnerId == _myPlayerId;
    notifyListeners();

    // 5. Start 20s auto-kick timer (Host only)
    if (_isHost) {
      _gameEndTimer?.cancel();
      _gameEndTimer = Timer(const Duration(seconds: 20), () {
        debugPrint(
          'DEBUG: 20s game-end timer expired. Auto-kicking all players.',
        );
        _autoKickAllPlayers();
      });
    }
  }

  /// Auto-kick all players after 20s winner display (Host only)
  void _autoKickAllPlayers() {
    if (!_isHost || _gameState == null) return;

    // Broadcast GAME_ENDED to all clients
    _networkService.send(
      type: MessageType.gameEnded,
      payload: {'reason': 'Game Over - 20s timeout'},
    );

    // Delete the room
    _networkService.deleteRoom(_gameState!.roomCode);

    // Leave room ourselves
    leaveRoom();
  }

  /// Exit to menu (called by Exit button or auto-kick)
  Future<void> exitToMenu() async {
    _gameEndTimer?.cancel();

    if (_isHost && _gameState != null) {
      // Host: Delete room and leave
      await _networkService.deleteRoom(_gameState!.roomCode);
    }

    await leaveRoom();
  }

  /// Handle GAME_ENDED message (Client only - Host auto-kicks themselves)
  void _handleGameEnded(GameMessage message) {
    if (_isHost) return; // Host handles its own exit

    debugPrint('DEBUG: Received GAME_ENDED. Auto-leaving...');

    // Client: Just leave the room
    leaveRoom();
  }

  /// Handle UNO call from a player
  void _handleUnoCall(GameMessage message) {
    if (!_isHost) return;

    final senderName = message.senderName;

    // Update state with unoCaller
    _gameState = _gameState?.copyWith(unoCaller: senderName);
    _broadcastGameState();

    // Trigger animation locally for the Host
    _unoCallerName = senderName;
    _showUnoCallAnimation = true;

    // TRACKING: Mark player as safe from penalty
    // Note: In strict UNO, you must call BEFORE playing 2nd to last card.
    // We allow calling anytime before the next player takes their turn.
    // Since we check at end of turn, calling resets penalty status.
    _playersWhoCalledUno.add(message.senderId);

    notifyListeners();

    // Auto-hide local animation after 3s
    _unoCallAnimationTimer?.cancel();
    _unoCallAnimationTimer = Timer(const Duration(seconds: 3), () {
      _showUnoCallAnimation = false;
      notifyListeners();
    });

    // Clear UnoCaller from state after 3 seconds
    _unoCallStateTimer?.cancel();
    _unoCallStateTimer = Timer(const Duration(seconds: 3), () {
      if (_gameState?.unoCaller == senderName) {
        _gameState = _gameState?.copyWith(clearUnoCaller: true);
        _broadcastGameState();
      }
    });
  }

  /// Call UNO!
  void callUno() {
    if (_hasCalledUno) return; // Prevent spamming
    _hasCalledUno = true;

    // Reset local flag after some time
    _localUnoCooldownTimer?.cancel();
    _localUnoCooldownTimer = Timer(const Duration(seconds: 5), () {
      _hasCalledUno = false;
    });

    if (_isHost) {
      // Host: Broadcast UNO_ANNOUNCED event for synchronized animation
      _networkService.send(
        type: MessageType.unoAnnounced,
        payload: {'playerId': _myPlayerId, 'playerName': _myName},
      );

      // Update state
      _gameState = _gameState?.copyWith(unoCaller: _myName);
      _broadcastGameState();

      // Clear UnoCaller after 3 seconds
      Timer(const Duration(seconds: 3), () {
        if (_gameState?.unoCaller == _myName) {
          _gameState = _gameState?.copyWith(clearUnoCaller: true);
          _broadcastGameState();
        }
      });

      // Local animation trigger
      _unoCallerName = _myName;
      _showUnoCallAnimation = true;
      notifyListeners();
      Timer(const Duration(seconds: 3), () {
        _showUnoCallAnimation = false;
        notifyListeners();
      });
    } else {
      // Client sends request
      _networkService.send(type: MessageType.unoCall);
    }
  }

  /// Handle WILD_COLOR_CHANGE event (Client & Host)
  void _handleWildColorChange(GameMessage message) {
    final colorIndex = message.payload['color'] as int?;
    if (colorIndex != null && colorIndex >= 0 && colorIndex < UnoColor.values.length) {
      _showWildAnimation = true;
      notifyListeners();
      // Animation will be cleared by UI after showing
    }
  }

  /// Handle UNO_ANNOUNCED event (Client & Host)
  void _handleUnoAnnounced(GameMessage message) {
    final playerName = message.payload['playerName'] as String? ?? message.senderName;
    _unoCallerName = playerName;
    _showUnoCallAnimation = true;
    notifyListeners();
    
    // Auto-hide after 3 seconds
    _unoCallAnimationTimer?.cancel();
    _unoCallAnimationTimer = Timer(const Duration(seconds: 3), () {
      _showUnoCallAnimation = false;
      notifyListeners();
    });
  }

  /// Handle GAME_OVER_CELEBRATION event (Client & Host)
  void _handleGameOverCelebration(GameMessage message) {
    final winnerId = message.payload['winnerId'] as String?;
    final winnerName = message.payload['winnerName'] as String? ?? 'Unknown';
    
    _showWinnerAnimation = true;
    _winnerAnimationName = winnerName;
    _isWinnerAnimationForMe = winnerId == _myPlayerId;
    notifyListeners();
  }

  /// Handle HOST_LEFT event - Host left, kick all players
  void _handleHostLeft(GameMessage message) {
    debugPrint('HOST_LEFT: Host left the room, kicking all players...');
    
    // Set error to trigger navigation
    _error = 'HOST_LEFT';
    _kicked = true;
    notifyListeners();
    
    // Leave room immediately
    leaveRoom();
  }

  /// Handle HOST_RESIGNED event - Host resigned, new host will be selected
  void _handleHostResigned(GameMessage message) {
    // This is informational, actual host migration happens in _handleNewHostSelected
    debugPrint('HOST_RESIGNED: Host resigned, waiting for new host selection...');
  }

  /// Handle NEW_HOST_SELECTED event - Update host and show notification
  void _handleNewHostSelected(GameMessage message) {
    final newHostId = message.payload['newHostId'] as String?;
    final newHostName = message.payload['newHostName'] as String? ?? 'Unknown';
    
    if (newHostId == null) return;

    debugPrint('NEW_HOST_SELECTED: New host is $newHostName ($newHostId)');

    // Update game state with new host
    if (_gameState != null) {
      _gameState = _gameState!.copyWith(hostId: newHostId);
      
      // Update players to reflect new host
      final updatedPlayers = _gameState!.players.map((p) {
        return p.copyWith(isHost: p.id == newHostId);
      }).toList();
      _gameState = _gameState!.copyWith(players: updatedPlayers);

      // If I am the new host, update local flag
      if (newHostId == _myPlayerId) {
        _isHost = true;
        debugPrint('I am now the new host!');
      }

      notifyListeners();
    }

    // Store notification for UI to show toast
    _error = 'NEW_HOST_SELECTED:$newHostName';
    notifyListeners();
    
    // Clear error after a moment
    Future.delayed(const Duration(seconds: 1), () {
      if (_error == 'NEW_HOST_SELECTED:$newHostName') {
        _error = null;
        notifyListeners();
      }
    });
  }

  /// Throw multiple cards at once (for multi-card selection)
  void throwMultipleCards(List<String> cardIds, {UnoColor? chosenColor}) {
    if (cardIds.isEmpty || _gameState == null) return;
    if (!isMyTurn) return;

    // Send THROW_MULTIPLE message
    _networkService.send(
      type: MessageType.throwMultiple,
      payload: {
        'cardIds': cardIds,
        if (chosenColor != null) 'chosenColor': chosenColor.index,
      },
    );

    // If we're the host, handle it locally too
    if (_isHost) {
      _handleThrowMultiple(
        GameMessage(
          type: MessageType.throwMultiple,
          senderId: _myPlayerId,
          senderName: _myName,
          payload: {
            'cardIds': cardIds,
            if (chosenColor != null) 'chosenColor': chosenColor.index,
          },
        ),
      );
    }
  }

  /// Start the game (host only)
  void startGame() {
    // Use getter to verify authority (handles desync)
    if (!isHost || _gameState == null) return;
    if (_gameState!.players.length < 2) {
      _error = 'Need at least 2 players to start';
      notifyListeners();
      return;
    }

    _startGame();
  }

  Future<void> _startGame() async {
    // Re-sync local flag in case we are host via ID match
    _isHost = true;

    if (_gameState == null) return;

    debugPrint('DEBUG: Host starting game (Atomic Init)...');

    // Step A: Calculate Local State First (DO NOT touch global _gameState yet)
    var localState = _gameState!.copyWith();

    // Initialize game logic (Generate Deck & Deal)
    localState = GameLogic.initializeGame(localState);

    // Step B: Validate
    // User Request: Ensure deck is 108 cards (Uno standard)
    if (localState.drawPile.isEmpty) {
      debugPrint('CRITICAL ERROR: Deck generation failed (Empty)! Aborting.');
      return;
    }

    // Warn if not 108 (might be custom deck logic, but log it)
    if (localState.drawPile.length +
            localState.players.fold(0, (sum, p) => sum + p.hand.length) !=
        108) {
      debugPrint(
        'WARNING: Total cards in game is not 108. Proceeding with caution.',
      );
    }

    // Verify all players have 7 cards
    if (!localState.players.every((p) => p.hand.length == 7)) {
      debugPrint(
        'CRITICAL ERROR: Hand dealing failed (Not 7 cards)! Aborting.',
      );
      return;
    }

    // Prepare state for DB (Force Playing Status)
    localState = localState.copyWith(phase: GamePhase.playing);

    // Step C: Push to DB (Wait for completion)
    debugPrint('DEBUG: Host pushing FULL ATOMIC STATE to Supabase DB...');
    // Use SSOT format to ensure hands are included
    final ssotState = _generateSSOTStateFromState(localState);
    await _networkService.startRemoteGame(ssotState);

    // Step D: Only AFTER DB write, update local state
    _gameState = localState;
    _gameStarted = true;

    debugPrint(
      'DEBUG: Atomic Init Success. Local State Updated. Broadcasting...',
    );

    // Flag-based handshake: Send PREPARE_GAME and wait for ACK_READY
    _waitingForAcks = true;
    _ackReceivedFrom.clear();

    // Trigger UI update
    notifyListeners();

    debugPrint('DEBUG: Sending PREPARE_GAME to all clients');
    _sendPrepareGame();

    // After 500ms, use the new Full State Snapshot approach
    _prepareGameRetryTimer?.cancel();
    _prepareGameRetryTimer = Timer(const Duration(milliseconds: 500), () {
      if (_waitingForAcks) {
        debugPrint('DEBUG: Using Full State Snapshot approach');
        _waitingForAcks = false;

        // Use the new snapshot architecture
        broadcastFullSnapshot(immediate: true);
      }
    });
  }

  /// Send PREPARE_GAME message
  void _sendPrepareGame() {
    _networkService.send(
      type: MessageType.prepareGame,
      payload: {'playerCount': _gameState!.players.length},
    );
  }

  /// Handle PREPARE_GAME message (Joiner only)
  void _handlePrepareGame(GameMessage message) {
    if (_isHost) return; // Host ignores this

    debugPrint(
      'DEBUG: Received PREPARE_GAME - setting isPreparingGame=true, sending ACK_READY',
    );

    // Set flag for greedy navigation (shows loading overlay)
    _isPreparingGame = true;
    notifyListeners();

    // Send ACK_READY back to host
    _networkService.send(
      type: MessageType.ackReady,
      payload: {'playerId': _myPlayerId},
    );
  }

  /// Handle ACK_READY message (Host only)
  void _handleAckReady(GameMessage message) {
    if (!_isHost) return; // Joiner ignores this
    if (!_waitingForAcks) return; // Not in handshake phase

    final playerId = message.payload['playerId'] as String? ?? message.senderId;
    debugPrint('DEBUG: Received ACK_READY from $playerId');

    _ackReceivedFrom.add(playerId);

    // Once we receive first ACK, wait 1 second then start sequential sync
    if (_ackReceivedFrom.length == 1) {
      debugPrint(
        'DEBUG: First ACK received - starting sequential data sync in 1s',
      );
      _prepareGameRetryTimer?.cancel();

      Timer(const Duration(milliseconds: 1000), () {
        if (_waitingForAcks) {
          _waitingForAcks = false;
          _sendSequentialGameData();
        }
      });
    }
  }

  /// Send game data in sequential steps with delays (Host only)
  void _sendSequentialGameData() {
    if (_gameState == null) return;

    debugPrint('DEBUG: Starting sequential data sync...');

    // Step 1: Send players (after 0ms)
    debugPrint('DEBUG: Step 1 - Sending SET_PLAYERS');
    _networkService.send(
      type: MessageType.setPlayers,
      payload: {
        'players': _gameState!.players.map((p) => p.toCompactJson()).toList(),
        'hostId': _gameState!.hostId,
        'roomCode': _gameState!.roomCode,
      },
    );

    // Step 2: Send deck chunk (after 1000ms)
    Timer(const Duration(milliseconds: 1000), () {
      if (_gameState == null) return;
      debugPrint('DEBUG: Step 2 - Sending SET_DECK');

      // Send only first 20 cards of draw pile to keep it small
      final deckChunk = _gameState!.drawPile.take(20).toList();
      _networkService.send(
        type: MessageType.setDeck,
        payload: {
          'deckChunk': deckChunk.map((c) => c.toCompactJson()).toList(),
          'totalDeckSize': _gameState!.drawPile.length,
        },
      );
    });

    // Step 3: Send each player's hand (after 2000ms)
    Timer(const Duration(milliseconds: 2000), () {
      if (_gameState == null) return;
      debugPrint('DEBUG: Step 3 - Sending SET_HAND for each player');

      // Send hands to each player (they'll filter by target)
      for (final player in _gameState!.players) {
        _networkService.send(
          type: MessageType.setHand,
          payload: {
            'targetPlayerId': player.id,
            'cards': player.hand.map((c) => c.toCompactJson()).toList(),
          },
        );
      }
    });

    // Step 4: Send GO_LIVE trigger (after 3500ms)
    Timer(const Duration(milliseconds: 3500), () {
      if (_gameState == null) return;
      debugPrint('DEBUG: Step 4 - Sending GO_LIVE');

      final starterCard =
          _gameState!.discardPile.isNotEmpty
              ? _gameState!.discardPile.last
              : null;

      _networkService.send(
        type: MessageType.goLive,
        payload: {
          'starterCard': starterCard?.toCompactJson(),
          'currentPlayerIndex': _gameState!.currentPlayerIndex,
          'isClockwise': _gameState!.isClockwise,
        },
      );

      // Resume heartbeats after sync complete
      // _networkService.resumeHeartbeats(); // Removed for P2P
    });

    notifyListeners();
  }

  // === SEQUENTIAL SYNC HANDLERS (Joiner) ===

  void _handleSetPlayers(GameMessage message) {
    if (_isHost) return; // Host ignores

    debugPrint('DEBUG: Received SET_PLAYERS');

    try {
      final playersJson = message.payload['players'] as List;
      _tempPlayers =
          playersJson
              .map((p) => Player.fromCompactJson(p as Map<String, dynamic>))
              .toList();
      _hasReceivedPlayers = true;

      // Start timeout for next step
      _startSyncStepTimeout('DECK');

      debugPrint('DEBUG: Parsed ${_tempPlayers!.length} players');
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG: Error parsing SET_PLAYERS: $e');
    }
  }

  void _handleSetDeck(GameMessage message) {
    if (_isHost) return;

    debugPrint('DEBUG: Received SET_DECK');

    try {
      final deckJson = message.payload['deckChunk'] as List;
      _tempDeck =
          deckJson
              .map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList();
      _hasReceivedDeck = true;

      // Start timeout for next step
      _startSyncStepTimeout('HAND');

      debugPrint('DEBUG: Parsed ${_tempDeck!.length} deck cards');
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG: Error parsing SET_DECK: $e');
    }
  }

  void _handleSetHand(GameMessage message) {
    if (_isHost) return;

    final targetId = message.payload['targetPlayerId'] as String?;
    if (targetId != _myPlayerId) return; // Not for me

    debugPrint('DEBUG: Received SET_HAND for me!');

    try {
      final cardsJson = message.payload['cards'] as List;
      _tempMyHand =
          cardsJson
              .map((c) => UnoCard.fromCompactJson(c as Map<String, dynamic>))
              .toList();
      _hasReceivedHand = true;

      // Start timeout for final step
      _startSyncStepTimeout('LIVE');

      debugPrint('DEBUG: Parsed ${_tempMyHand!.length} cards in my hand');
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG: Error parsing SET_HAND: $e');
    }
  }

  void _handleGoLive(GameMessage message) {
    if (_isHost) return;

    debugPrint('DEBUG: Received GO_LIVE - assembling game state!');

    try {
      // Parse starter card
      final starterCardJson = message.payload['starterCard'];
      if (starterCardJson != null) {
        _tempStarterCard = UnoCard.fromCompactJson(
          starterCardJson as Map<String, dynamic>,
        );
      }

      final currentPlayerIndex =
          message.payload['currentPlayerIndex'] as int? ?? 0;
      final isClockwise = message.payload['isClockwise'] as bool? ?? true;

      // Assemble the full game state from pieces
      if (_tempPlayers != null) {
        // Find my player and update their hand
        final updatedPlayers =
            _tempPlayers!.map((p) {
              if (p.id == _myPlayerId && _tempMyHand != null) {
                return p.copyWith(hand: _tempMyHand);
              }
              return p;
            }).toList();

        _gameState = GameState(
          drawPile: _tempDeck ?? [],
          discardPile: _tempStarterCard != null ? [_tempStarterCard!] : [],
          players: updatedPlayers,
          currentPlayerIndex: currentPlayerIndex,
          isClockwise: isClockwise,
          phase: GamePhase.playing, // NOW WE'RE PLAYING!
          hostId:
              updatedPlayers
                  .firstWhere(
                    (p) => p.isHost,
                    orElse: () => updatedPlayers.first,
                  )
                  .id,
          roomCode: _gameState?.roomCode ?? '',
        );

        _isGameLive = true;
        _isPreparingGame = false; // Clear the loading state
        _syncStepTimeoutTimer?.cancel();

        debugPrint('DEBUG: Game state assembled! Phase: ${_gameState!.phase}');
        notifyListeners();
      } else {
        debugPrint('DEBUG: GO_LIVE received but missing player data!');
      }
    } catch (e) {
      debugPrint('DEBUG: Error handling GO_LIVE: $e');
    }
  }

  void _handleReqResend(GameMessage message) {
    if (!_isHost) return; // Only host responds

    final step = message.payload['step'] as String?;
    final requesterId = message.senderId;

    debugPrint('DEBUG: Received REQ_RESEND for step: $step from $requesterId');

    if (_gameState == null) return;

    switch (step) {
      case 'PLAYERS':
        _networkService.send(
          type: MessageType.setPlayers,
          payload: {
            'players':
                _gameState!.players.map((p) => p.toCompactJson()).toList(),
            'hostId': _gameState!.hostId,
            'roomCode': _gameState!.roomCode,
          },
        );
        break;
      case 'DECK':
        final deckChunk = _gameState!.drawPile.take(20).toList();
        _networkService.send(
          type: MessageType.setDeck,
          payload: {
            'deckChunk': deckChunk.map((c) => c.toCompactJson()).toList(),
            'totalDeckSize': _gameState!.drawPile.length,
          },
        );
        break;
      case 'HAND':
        // Resend hand for the requester
        final player = _gameState!.getPlayerById(requesterId);
        if (player != null) {
          _networkService.send(
            type: MessageType.setHand,
            payload: {
              'targetPlayerId': player.id,
              'cards': player.hand.map((c) => c.toCompactJson()).toList(),
            },
          );
        }
        break;
      case 'LIVE':
        final starterCard =
            _gameState!.discardPile.isNotEmpty
                ? _gameState!.discardPile.last
                : null;
        _networkService.send(
          type: MessageType.goLive,
          payload: {
            'starterCard': starterCard?.toCompactJson(),
            'currentPlayerIndex': _gameState!.currentPlayerIndex,
            'isClockwise': _gameState!.isClockwise,
          },
        );
        break;
    }
  }

  /// Start a 5-second timeout for a sync step
  void _startSyncStepTimeout(String nextStep) {
    _syncStepTimeoutTimer?.cancel();

    _syncStepTimeoutTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('DEBUG: Sync step timeout - requesting resend of $nextStep');
      _networkService.send(
        type: MessageType.reqResend,
        payload: {'step': nextStep},
      );

      // Set up another timeout
      _startSyncStepTimeout(nextStep);
    });
  }

  // === RELIABLE SYNC & SNAPSHOT ARCHITECTURE ===

  /// 1. Broadcasts START_SIGNAL to initiate reliable sync
  /// Replaces the old blast-all approach
  void broadcastFullSnapshot({bool immediate = false}) {
    if (!_isHost || _gameState == null) return;

    // Reset ACK tracking
    _snapshotAckReceived.clear();
    _snapshotRetryTimer?.cancel();

    // Clear pending receivers
    _pendingSnapshotReceivers.clear();

    // Step A: Send START_SIGNAL to all players
    // This tells them to stop, show loading, and ask for data
    debugPrint('HOST: Broadcasting START_SIGNAL');
    _networkService.send(
      type: MessageType.startSignal,
      payload: {'playerCount': _gameState!.players.length},
    );
  }

  /// Step B (Joiner): Received START_SIGNAL
  void _handleStartSignal(GameMessage message) {
    // 1. Reset sync state & Show loading UI
    _isGameLive = false;
    _hasReceivedPlayers = false; // Using existing flags to trigger UI
    _isPreparingGame = true; // Show loading spinner
    _snapshotPart1 = null; // Clear any partial buffer

    notifyListeners();

    debugPrint(
      'JOINER: Received START_SIGNAL - Sending READY_TO_RECEIVE (Retry Loop Started)',
    );

    // 2. Start Retry Loop: Send READY_TO_RECEIVE every 3s until we get snapshot
    _readyToReceiveRetryTimer?.cancel();
    _sendReadyToReceive();

    _readyToReceiveRetryTimer = Timer.periodic(const Duration(seconds: 8), (
      timer,
    ) {
      if (_isGameLive) {
        timer.cancel();
      } else {
        debugPrint('JOINER: Retry sending READY_TO_RECEIVE...');
        _sendReadyToReceive();
      }
    });
  }

  void _sendReadyToReceive() {
    _networkService.send(
      type: MessageType.readyToReceive,
      payload: {'playerId': _myPlayerId},
    );
  }

  /// Step C (Host): Received READY_TO_RECEIVE
  void _handleReadyToReceive(GameMessage message) {
    if (!_isHost) return;
    final playerId = message.senderId;
    debugPrint('HOST: Received READY_TO_RECEIVE from $playerId');

    // Relaxed Timing: Wait 1000ms before sending chunks to prevent burst
    Future.delayed(const Duration(milliseconds: 1000), () {
      _sendChunkedSnapshotToPlayer(playerId);
    });
  }

  /// Helper: Send snapshot (chunked if needed) to specific player
  void _sendChunkedSnapshotToPlayer(String playerId) {
    if (_gameState == null) return;

    // 1. Prepare Data
    final snapshotData = {
      'state': _gameState!.toCompactJson(),
      'stateSeq': ++_lastStateSequence,
    };

    final jsonString = jsonEncode(snapshotData);

    // 2. Check size and send
    if (jsonString.length > 1000) {
      // Split into 2 parts
      final mid = jsonString.length ~/ 2;
      final part1 = jsonString.substring(0, mid);
      final part2 = jsonString.substring(mid);

      debugPrint(
        'HOST: Sending CHUNKED snapshot to $playerId (Len: ${jsonString.length})',
      );

      // Send Part 1
      _networkService.send(
        type: MessageType.snapshotPart1,
        payload: {
          'data': part1,
          'targetId': playerId, // Filter by targetId
        },
      );

      // Small delay to ensure order
      Future.delayed(const Duration(milliseconds: 50), () {
        _networkService.send(
          type: MessageType.snapshotPart2,
          payload: {'data': part2, 'targetId': playerId},
        );
      });
    } else {
      // Send as single message
      debugPrint('HOST: Sending normal snapshot to $playerId');
      _networkService.send(
        type: MessageType.gameSnapshot,
        payload: {...snapshotData, 'targetId': playerId},
      );
    }
  }

  /// Joiner: Handle Part 1
  void _handleSnapshotPart1(GameMessage message) {
    debugPrint('JOINER: Received SNAPSHOT_PART_1');
    _snapshotPart1 = message.payload['data'];
  }

  /// Joiner: Handle Part 2
  void _handleSnapshotPart2(GameMessage message) {
    debugPrint('JOINER: Received SNAPSHOT_PART_2');
    final part2 = message.payload['data'];

    if (_snapshotPart1 != null && part2 != null) {
      final fullJson = _snapshotPart1! + part2;
      _snapshotPart1 = null; // Clear buffer

      try {
        final data = jsonDecode(fullJson);
        // Reuse existing logic
        _applySnapshotData(data);
      } catch (e) {
        debugPrint('ERROR: Failed to reassemble snapshot chunks: $e');
      }
    }
  }

  /// Handle GAME_SNAPSHOT (Joiner)
  void _handleGameSnapshot(GameMessage message) {
    _applySnapshotData(message.payload);
  }

  void _applySnapshotData(Map<String, dynamic> payload) {
    if (_isHost) return;

    // Stop the retry loop!
    _readyToReceiveRetryTimer?.cancel();

    debugPrint('DEBUG: Processing Full Game Snapshot');

    try {
      final stateSeq = payload['stateSeq'] as int? ?? 0;
      final stateJson = payload['state'] as Map<String, dynamic>;

      // Parse the full state
      final newState = GameState.fromCompactJson(stateJson);

      debugPrint(
        'DEBUG: Parsed snapshot (seq=$stateSeq, phase=${newState.phase}, players=${newState.players.length})',
      );

      // Update game state
      _gameState = newState;
      _lastStateSequence = stateSeq;

      // Mark sync complete
      _hasReceivedPlayers = true;
      _hasReceivedDeck = true;
      _hasReceivedHand = true;
      _isGameLive = true;
      _isPreparingGame = false;
      _syncStepTimeoutTimer?.cancel();

      // Send ACK back to host
      _networkService.send(
        type: MessageType.snapshotAck,
        payload: {'playerId': _myPlayerId},
      );

      // Feedback Loop: Send 'd' (Done) to stop host retries
      _networkService.send(
        type: 'd', // Special short type
        payload: {'id': _myPlayerId},
      );

      debugPrint(
        'DEBUG: Snapshot applied! Deck: ${newState.drawPile.length}, Phase: ${newState.phase}',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG: Error parsing snapshot data: $e');
    }
  }

  /// Handle SNAPSHOT_ACK (Host)
  void _handleSnapshotAck(GameMessage message) {
    if (!_isHost) return;

    final playerId = message.payload['playerId'] as String? ?? message.senderId;
    debugPrint('DEBUG: Received SNAPSHOT_ACK from $playerId');

    _snapshotAckReceived.add(playerId);

    // Check if all joiners ACKed
    final expectedAcks = _gameState!.players.where((p) => !p.isHost).length;
    if (_snapshotAckReceived.length >= expectedAcks) {
      debugPrint('DEBUG: All snapshot ACKs received!');

      _snapshotRetryTimer?.cancel();
    }
  }

  /// Handle 'd' (Done) message
  void _handleSnapshotDone(GameMessage message) {
    if (!_isHost) return;
    final playerId = message.payload['id'];
    debugPrint('HOST: Received DONE (d) from $playerId - Stopping retries');
    _pendingSnapshotReceivers.remove(playerId);
  }

  /// Handle THROW_MULTIPLE (Host processes multi-card play)
  void _handleThrowMultiple(GameMessage message) {
    if (!_isHost) return;

    final playerId = message.senderId;
    final cardIds = (message.payload['cardIds'] as List?)?.cast<String>() ?? [];
    // Note: chosenColor is not used for multi-throw as last card's color becomes active

    debugPrint(
      'DEBUG: THROW_MULTIPLE from $playerId with ${cardIds.length} cards',
    );

    if (cardIds.isEmpty || _gameState == null) return;

    // Validate it's this player's turn
    if (_gameState!.currentPlayer?.id != playerId) {
      debugPrint('DEBUG: Not this player\'s turn');
      return;
    }

    // Find the player
    final playerIndex = _gameState!.getPlayerIndex(playerId);
    if (playerIndex == -1) return;

    final player = _gameState!.players[playerIndex];

    // Get all the cards being played
    final cardsToPlay = <UnoCard>[];
    for (final cardId in cardIds) {
      final card = player.hand.firstWhere(
        (c) => c.id == cardId,
        orElse: () => player.hand.first,
      );
      if (card.id == cardId) {
        cardsToPlay.add(card);
      }
    }

    if (cardsToPlay.length != cardIds.length) {
      debugPrint('DEBUG: Not all cards found in player hand');
      return;
    }

    final firstCard = cardsToPlay.first;

    // RULE: Wild cards are restricted to single play only
    if (firstCard.isWild) {
      debugPrint('DEBUG: Wild cards cannot be multi-thrown');
      return;
    }

    // RULE: All cards must have the SAME VALUE (not color)
    final allSameValue = cardsToPlay.every((c) => c.value == firstCard.value);
    if (!allSameValue) {
      debugPrint('DEBUG: Cards must all have the same value for multi-throw');
      return;
    }

    // RULE: First card must be playable on discard pile
    final topDiscard =
        _gameState!.discardPile.isNotEmpty
            ? _gameState!.discardPile.last
            : null;
    final activeColor = _gameState!.activeColor;
    if (!GameLogic.isValidMove(firstCard, topDiscard, activeColor)) {
      debugPrint('DEBUG: First card is not playable');
      return;
    }

    // Check UNO penalty BEFORE removing cards
    // Note: UNO call tracking would need to be added to Player model
    // For now, we skip this check - UNO penalty is enforced elsewhere

    // Process the throw: Remove all cards from hand
    var updatedPlayer = player;
    for (final card in cardsToPlay) {
      updatedPlayer = updatedPlayer.removeCard(card.id);
    }

    // Add only the last card to discard pile (its color becomes active)
    final lastCard = cardsToPlay.last;
    List<UnoCard> newDiscardPile = [..._gameState!.discardPile, lastCard];

    // Update players list
    List<Player> updatedPlayers = List.from(_gameState!.players);
    updatedPlayers[playerIndex] = updatedPlayer;

    // Calculate stacking effects based on card value
    final cardCount = cardsToPlay.length;
    int playersToSkip = 0;
    int cardsToDraw = 0;
    bool shouldFlipDirection = false;

    if (firstCard.type == UnoCardType.skip) {
      // Skip N players
      playersToSkip = cardCount;
      debugPrint(
        'DEBUG: Stacking $cardCount Skip cards - skipping $playersToSkip players',
      );
    } else if (firstCard.type == UnoCardType.drawTwo) {
      // Draw 2 × N cards
      cardsToDraw = 2 * cardCount;
      playersToSkip = 1; // Next player also skipped after drawing
      debugPrint(
        'DEBUG: Stacking $cardCount Draw2 cards - next player draws $cardsToDraw',
      );
    } else if (firstCard.type == UnoCardType.reverse) {
      // Flip direction N times (odd = change, even = no change)
      shouldFlipDirection = cardCount.isOdd;
      debugPrint(
        'DEBUG: Stacking $cardCount Reverse cards - direction ${shouldFlipDirection ? "flips" : "unchanged"}',
      );
    }

    // Apply direction change
    bool newDirection = _gameState!.isClockwise;
    if (shouldFlipDirection) {
      newDirection = !newDirection;
    }

    // Check for winner
    if (updatedPlayer.hasWon) {
      _gameState = _gameState!.copyWith(
        players: updatedPlayers,
        discardPile: newDiscardPile,
        phase: GamePhase.finished,
        winnerId: playerId,
        winnerName: player.name,
        activeColor: lastCard.color,
      );
    } else {
      // UNO PENALTY CHECK (Catching "Forgot to say UNO")
      // Logic: If you end your turn with 1 card and DID NOT call UNO -> Draw 2 cards.
      if (updatedPlayer.hand.length == 1) {
        if (!_playersWhoCalledUno.contains(playerId)) {
          debugPrint('UNO PENALTY: Player $playerId forgot to say UNO!');

          // Draw 2 cards immediately
          var drawPile = List<UnoCard>.from(_gameState!.drawPile);
          var penaltyPlayer = updatedPlayer;

          for (int i = 0; i < 2 && drawPile.isNotEmpty; i++) {
            final drawnCard = drawPile.removeLast();
            penaltyPlayer = penaltyPlayer.addCard(drawnCard);
          }

          updatedPlayers[playerIndex] = penaltyPlayer;
          _gameState = _gameState!.copyWith(drawPile: drawPile);

          // Notify everyone of the shame
          _networkService.send(
            type: MessageType.notification,
            payload: {'message': '${player.name} forgot UNO! Drawn 2 cards.'},
          );
        } else {
          // They called it - safe!
          debugPrint('UNO CHECK: Player $playerId called UNO correctly.');
        }
      }
      // If hand > 1, you are safe (and shouldn't have called UNO anyway)
      // Note: If you called UNO but have >1 cards now (e.g. played wrong card?), clear the safety.
      if (updatedPlayer.hand.length != 1) {
        _playersWhoCalledUno.remove(playerId);
      }

      // Calculate next player index with skip stacking
      int nextIndex = playerIndex;
      for (int i = 0; i <= playersToSkip; i++) {
        nextIndex = GameLogic.getNextPlayerIndex(
          nextIndex,
          _gameState!.players.length,
          newDirection,
        );
      }

      // Apply draw penalty to next player (for Draw 2 stacking)
      if (cardsToDraw > 0) {
        final nextPlayer = updatedPlayers[nextIndex];
        var penalizedPlayer = nextPlayer;
        var drawPile = List<UnoCard>.from(_gameState!.drawPile);

        for (int i = 0; i < cardsToDraw && drawPile.isNotEmpty; i++) {
          final drawnCard = drawPile.removeLast();
          penalizedPlayer = penalizedPlayer.addCard(drawnCard);
        }

        updatedPlayers[nextIndex] = penalizedPlayer;
        _gameState = _gameState!.copyWith(drawPile: drawPile);
        debugPrint('DEBUG: Player ${nextPlayer.name} drew $cardsToDraw cards');
      }

      _gameState = _gameState!.copyWith(
        players: updatedPlayers,
        discardPile: newDiscardPile,
        currentPlayerIndex: nextIndex,
        activeColor: lastCard.color,
        isClockwise: newDirection,
        activeMultiThrowStack: cardsToPlay, // Set visual stack
      );

      // Start 10s Timer to clear the visual stack
      _multiThrowClearTimer?.cancel();
      _multiThrowClearTimer = Timer(const Duration(seconds: 10), () {
        if (_gameState != null) {
          debugPrint('HOST: Clearing multi-throw stack visualization');
          _gameState = _gameState!.copyWith(clearMultiThrowStack: true);
          broadcastFullSnapshot(immediate: true); // Update clients
        }
      });
    }

    // Broadcast immediately so everyone sees the animation
    broadcastFullSnapshot(immediate: true);

    debugPrint(
      'DEBUG: Multi-throw processed (${cardsToPlay.length} cards), broadcasting snapshot',
    );
    notifyListeners();
  }

  void _broadcastGameState() {
    if (_gameState == null) return;

    // SYNC PROTECTION: Never broadcast empty/invalid state
    // BUT: Allow empty hands during initial game start (cards are being dealt)
    if (_gameState!.drawPile.isEmpty &&
        _gameState!.players.any((p) => p.hand.isEmpty) &&
        _gameState!.phase == GamePhase.playing &&
        _gameStarted) {
      // Only block if game is actually playing and we have no cards
      // During initial deal, hands might be empty temporarily
      debugPrint('CRITICAL: Attempted to broadcast EMPTY state. Aborting.');
      return;
    }

    // CRITICAL: Explicit check - if game has started, ALWAYS force playing phase
    // This prevents ANY lobby reversion regardless of state mutations
    if (_gameStarted && _gameState!.phase != GamePhase.playing) {
      debugPrint(
        'DEBUG: CRITICAL - Game started but phase is ${_gameState!.phase}. Forcing to playing.',
      );
      _gameState = _gameState!.copyWith(phase: GamePhase.playing);
    }

    // Handshake complete - cancel any pending PREPARE_GAME retries
    _prepareGameRetryTimer?.cancel();
    _waitingForAcks = false;

    // Increment sequence number for this state update
    _lastStateSequence++;

    // Use compact JSON for reduced payload
    final payload = _gameState!.toCompactJson();
    
    // CRITICAL: Verify hands are in players array before adding hands map
    final handCounts = _gameState!.players.map((p) => '${p.name}:${p.hand.length}').join(', ');
    debugPrint(
      'DEBUG: Broadcasting state - Players: ${_gameState!.players.length}, Hands: $handCounts, DrawPile: ${_gameState!.drawPile.length}, DiscardPile: ${_gameState!.discardPile.length}',
    );
    
    // CRITICAL: Verify discard pile is not empty in playing phase
    if (_gameState!.discardPile.isEmpty && _gameState!.phase == GamePhase.playing && _gameStarted) {
      debugPrint('WARNING: Discard pile is empty in playing phase!');
    }
    
    // CRITICAL: Verify draw pile is not empty
    if (_gameState!.drawPile.isEmpty && _gameState!.phase == GamePhase.playing && _gameStarted) {
      debugPrint('WARNING: Draw pile is empty in playing phase!');
    }
    
    // CRITICAL: Add hands map for SSOT (even in compact format)
    // This ensures hands are available even if players array parsing fails
    final Map<String, dynamic> hands = {};
    for (final p in _gameState!.players) {
      hands[p.id.toString()] = p.hand.map((c) => c.toJson()).toList();
      if (p.hand.isEmpty && _gameState!.phase == GamePhase.playing && _gameStarted) {
        debugPrint('WARNING: Player ${p.name} has empty hand in playing phase!');
      }
    }
    payload['hands'] = hands;
    
    // Explicitly inject current_turn_id for robust client sync
    payload['current_turn_id'] = _gameState!.currentPlayer?.id;

    // CRITICAL: Explicitly inject phase to prevent flicker
    if (_gameStarted) {
      payload['h'] =
          GamePhase.playing.index; // 'h' is the compact key for phase
      payload['phase'] =
          GamePhase.playing.name; // Redundant safety for regular JSON parsers
    }
    // CRITICAL: Inject sequence number for discard pile keying
    payload['stateSeq'] = _lastStateSequence;
    payload['sequenceNumber'] = _lastStateSequence; // Redundant for compatibility
    payload['compact'] = true;

    _networkService.send(
      type: MessageType.gameState,
      payload: payload,
      sequenceNumber: _lastStateSequence,
    );

    debugPrint(
      'DEBUG: GAME_STATE broadcast complete (seq=$_lastStateSequence)',
    );
  }

  void _kickPlayer(String playerId) {
    if (!_isHost || _gameState == null) return;

    _gameState = _gameState!.removePlayer(playerId);

    _networkService.send(
      type: MessageType.winnerKicked,
      payload: {'kickedPlayerId': playerId},
    );

    if (_gameState!.players.length < 2) {
      _gameState = _gameState!.copyWith(phase: GamePhase.lobby);
    } else if (_gameState!.phase == GamePhase.finished) {
      _gameState = _gameState!.copyWith(
        phase: GamePhase.playing,
        winnerId: null,
        winnerName: null,
      );
    }

    _broadcastGameState();
    notifyListeners();
  }

  /// Kick winner after animation
  void kickWinnerAndContinue() {
    if (!_isHost || _gameState == null) return;

    final winnerId = _gameState!.winnerId;
    if (winnerId != null) {
      _kickPlayer(winnerId);
    }

    _showWinnerAnimation = false;
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    notifyListeners();
  }

  // === CLIENT LOGIC ===

  void _handleGameState(GameMessage message) {
    // Host now also processes broadcasts to ensure synchronized updates
    // This ensures host sees discard pile updates at the same time as clients

    try {
      final stateSeq = message.payload['stateSeq'] as int? ?? 0;

      // Gap Detection: If we missed messages, request full resync
      if (_hasReceivedGameState && stateSeq > _lastStateSequence + 1) {
        debugPrint(
          'DEBUG: Gap detected! Expected ${_lastStateSequence + 1}, got $stateSeq. Requesting resync...',
        );
        _networkService.send(type: MessageType.syncRequest);
        // Continue processing this state anyway (it's still valid)
      }

      // Only accept newer or equal states (host processes their own broadcasts)
      // For host: Allow processing their own broadcasts to sync UI
      // For client: Only accept newer states
      if (!_isHost && stateSeq < _lastStateSequence) {
        debugPrint('DEBUG: Ignoring older state (seq=$stateSeq < $_lastStateSequence)');
        return;
      }
      
      // Update sequence (host may process same sequence from their own broadcast)
      if (stateSeq > _lastStateSequence) {
        _lastStateSequence = stateSeq;
      }

      // FIX: Handle flattened state (from Supabase optimization) vs nested state (direct)
      final rawState = message.payload['state'];
      final stateJson =
          rawState is Map
              ? rawState
              : message.payload; // Fallback to using payload as state

      final isCompact = message.payload['compact'] as bool? ?? false;
      
      // DEBUG: Log what we're receiving
      final stateMap = stateJson as Map<String, dynamic>;
      final discardCount = (stateMap['x'] as List?)?.length ?? (stateMap['discardPile'] as List?)?.length ?? 0;
      final drawCount = (stateMap['d'] as List?)?.length ?? (stateMap['drawPile'] as List?)?.length ?? 0;
      debugPrint('DEBUG: Parsing state - discardPile: $discardCount, drawPile: $drawCount (compact: $isCompact)');

      var newState =
          isCompact
              ? GameState.fromCompactJson(Map<String, dynamic>.from(stateJson))
              : GameState.fromJson(Map<String, dynamic>.from(stateJson));

      debugPrint(
        'DEBUG: Client received GAME_STATE (seq=$stateSeq, phase=${newState.phase}, players=${newState.players.length})',
      );

      // CRITICAL: Check if status from DB indicates game started
      // The Host updates DB status to 'playing' but phase may still be 'lobby' in JSON
      final status = message.payload['status'] as String?;

      // Prevent Lobby Flicker: If we are already playing, or DB says playing, FORCE playing.
      if (status == 'playing' ||
          (_gameState?.phase == GamePhase.playing &&
              newState.phase == GamePhase.lobby)) {
        if (newState.phase == GamePhase.lobby) {
          newState = newState.copyWith(phase: GamePhase.playing);
        }
      }

      // CRITICAL: Turn Sync via ID
      // If host sent current_turn_id, allow it to override the index
      final currentTurnId = message.payload['current_turn_id'] as String?;
      if (currentTurnId != null) {
        final playerIndex = newState.getPlayerIndex(currentTurnId);
        if (playerIndex != -1 && playerIndex != newState.currentPlayerIndex) {
          debugPrint(
            'DEBUG: Fixing turn sync. Host says turn is $currentTurnId (index $playerIndex)',
          );
          newState = newState.copyWith(currentPlayerIndex: playerIndex);
        }
      }

      // EXPLICIT HAND PARSING (SSOT Safety)
      // Check for hands in both the payload directly and nested game_state
      try {
        // First check payload directly (for compact format broadcasts)
        final handsMap = message.payload['hands'] as Map<String, dynamic>?;
        
        // If not found, check nested game_state (for DB format)
        final rawGameState = message.payload['game_state'] as Map<String, dynamic>?;
        final finalHandsMap = handsMap ?? rawGameState?['hands'] as Map<String, dynamic>?;
        
        if (finalHandsMap != null && finalHandsMap.isNotEmpty) {
          // Update all players' hands from SSOT
          // CRITICAL: Don't clear local hand if incoming hand is empty (preserve existing)
          final updatedPlayers = newState.players.map((p) {
            final playerHandList = finalHandsMap[p.id.toString()] as List<dynamic>?;
            if (playerHandList != null && playerHandList.isNotEmpty) {
              // Only update if incoming hand is not empty
              final playerCards = playerHandList
                  .map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
                  .toList();
              return p.copyWith(hand: playerCards);
            } else if (playerHandList != null && playerHandList.isEmpty) {
              // Incoming hand is empty - preserve local hand if it exists
              final localPlayer = _gameState?.getPlayerById(p.id);
              if (localPlayer != null && localPlayer.hand.isNotEmpty) {
                debugPrint('DEBUG: Preserving local hand for ${p.name} (incoming was empty)');
                return p.copyWith(hand: localPlayer.hand);
              }
            }
            return p;
          }).toList();

          newState = newState.copyWith(players: updatedPlayers);
          debugPrint(
            'DEBUG: Patched hands from SSOT. My hand: ${newState.getPlayerById(_myPlayerId)?.hand.length ?? 0} cards',
          );
        } else {
          // If no hands map, preserve local hands if incoming is empty
          final myLocalHand = _gameState?.getPlayerById(_myPlayerId)?.hand ?? [];
          final myIncomingHand = newState.getPlayerById(_myPlayerId)?.hand ?? [];
          
          if (myIncomingHand.isEmpty && myLocalHand.isNotEmpty) {
            debugPrint('DEBUG: Preserving local hand (no hands map, incoming empty)');
            final updatedPlayers = newState.players.map((p) {
              if (p.id == _myPlayerId) {
                return p.copyWith(hand: myLocalHand);
              }
              return p;
            }).toList();
            newState = newState.copyWith(players: updatedPlayers);
          }
          
          final myHandSize = newState.getPlayerById(_myPlayerId)?.hand.length ?? 0;
          debugPrint(
            'DEBUG: No hands map found, using hands from players array. My hand: $myHandSize cards',
          );
          if (myHandSize == 0 && _gameState?.phase == GamePhase.playing && _gameStarted) {
            debugPrint('WARNING: My hand is empty but game is playing!');
          }
        }
      } catch (e) {
        debugPrint('DEBUG: Failed to parse hands: $e');
      }

      // CRITICAL FIX: Merge Logic for Players & HostId
      // 1. If payload has no players (common in relational schema), keep existing players
      if (newState.players.isEmpty && _gameState?.players.isNotEmpty == true) {
        debugPrint('WARNING: Received empty players array, preserving existing players');
        newState = newState.copyWith(players: _gameState!.players);
      }

      // 2. Guard: Don't shrink player list unexpectedly (stream hiccup protection)
      // BUT: In lobby phase, always accept the new player count from host (for proper sync)
      final currentCount = _gameState?.players.length ?? 0;
      if (newState.players.length < currentCount &&
          currentCount > 0 &&
          newState.phase == GamePhase.lobby &&
          !_isHost) {
        // Only ignore if we're a client and the count shrinks unexpectedly
        // This prevents clients from seeing wrong player counts during lobby
        debugPrint(
          'DEBUG: Ignoring game state with smaller player count ($currentCount -> ${newState.players.length}) in lobby.',
        );
        // Still update other fields, but preserve players
        newState = newState.copyWith(players: _gameState!.players);
      } else if (newState.players.length > currentCount || 
                 (newState.phase == GamePhase.lobby && newState.players.length == currentCount && newState.players.isNotEmpty)) {
        // Accept new players if count increases or if we're in lobby and have valid players
        // This ensures clients see all players in lobby
        debugPrint('DEBUG: Accepting player update: ${currentCount} -> ${newState.players.length}');
      }

      // 2. Ensure hostId is preserved/updated
      // Check if we have hostId in payload (injected by service)
      final payloadHostId = message.payload['hostId'] as String?;
      if (payloadHostId != null && payloadHostId.isNotEmpty) {
        newState = newState.copyWith(hostId: payloadHostId);
      } else if (newState.hostId.isEmpty &&
          _gameState?.hostId.isNotEmpty == true) {
        newState = newState.copyWith(hostId: _gameState!.hostId);
      }

      // 3. Re-apply isHost flag to players based on effective hostId
      if (newState.hostId.isNotEmpty) {
        final updatedPlayers =
            newState.players
                .map((p) => p.copyWith(isHost: p.id == newState.hostId))
                .toList();
        newState = newState.copyWith(players: updatedPlayers);
      }

      // Mark that we received a game state - stop retry timer
      if (!_hasReceivedGameState) {
        _hasReceivedGameState = true;
        _joinRetryTimer?.cancel();
        debugPrint('DEBUG: Client successfully synced with host!');
      }

      // Clear isPreparingGame when we receive a playing phase state
      if (newState.phase == GamePhase.playing) {
        _isPreparingGame = false;
        debugPrint('DEBUG: Game state received - clearing isPreparingGame');
      }

      // CRITICAL: Only preserve discardPile/drawPile if we're in lobby phase or if the new state is clearly wrong
      // In playing phase, always trust the new state (it should have the correct discard pile)
      // Only preserve if we're transitioning from lobby to playing and the new state is missing data
      if (newState.phase == GamePhase.playing && 
          _gameState?.phase == GamePhase.lobby &&
          newState.discardPile.isEmpty && 
          _gameState?.discardPile.isNotEmpty == true) {
        debugPrint('WARNING: Transitioning to playing with empty discard pile, preserving existing');
        newState = newState.copyWith(discardPile: _gameState!.discardPile);
      }
      
      // For draw pile, only preserve if transitioning from lobby
      if (newState.phase == GamePhase.playing && 
          _gameState?.phase == GamePhase.lobby &&
          newState.drawPile.isEmpty && 
          _gameState?.drawPile.isNotEmpty == true) {
        debugPrint('WARNING: Transitioning to playing with empty draw pile, preserving existing');
        newState = newState.copyWith(drawPile: _gameState!.drawPile);
      }

      _gameState = newState;

      // Auto-hide UNO animation after 3s if it was triggered by state
      if (_gameState?.unoCaller != null) {
        _unoCallerName = _gameState!.unoCaller;
        _showUnoCallAnimation = true;
        // Hide after 3 seconds
        _unoCallAnimationTimer?.cancel();
        _unoCallAnimationTimer = Timer(const Duration(seconds: 3), () {
          _showUnoCallAnimation = false;
          notifyListeners();
        });
      }

      // Check for Wild Card Animation
      if (newState.lastPlayedCard != null &&
          newState.lastPlayedCard?.id != _gameState?.lastPlayedCard?.id) {
        final card = newState.lastPlayedCard!;
        if (card.isWild) {
          _showWildAnimation = true;
        }
      }

      // Check for Game Over (Phase Finished)
      if (newState.phase == GamePhase.finished &&
          _gameState?.phase != GamePhase.finished) {
        // Game Over! Transition to Podium handled by UI listening to phase
        debugPrint('DEBUG: Game Over! Winners: ${newState.winners}');
      }

      _hasDrawnCard = false;
      _lastDrawnCard = null;

      debugPrint(
        'Provider: UI Update triggered (GAME_STATE). Players: ${_gameState!.players.length}, isHost: $isHost',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('DEBUG: Error parsing game state: $e');
    }
  }

  void _handleWinnerKicked(GameMessage message) {
    final kickedPlayerId = message.payload['kickedPlayerId'] as String?;

    if (kickedPlayerId == _myPlayerId) {
      _wasKickedAsWinner = true;
      _showWinnerAnimation = false;
      notifyListeners();
    }

    _showWinnerAnimation = false;
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    notifyListeners();
  }

  void dismissWinnerAnimation() {
    _showWinnerAnimation = false;
    notifyListeners();
  }

  void clearWildAnimation() {
    _showWildAnimation = false;
    notifyListeners();
  }

  /// Helper to delete room after podium screen
  Future<void> declareWinnerAndCleanup() async {
    if (_isHost && _gameState != null) {
      await _networkService.declareWinnerAndCleanup(_gameState!.roomCode);
    }
  }

  /// Clean up room when Host leaves lobby
  /// Always delete the room - no auto-deletion based on player count
  /// This ensures joiners get ROOM_CLOSED and are kicked properly
  Future<void> cleanupRoom() async {
    if (!_isHost || _gameState == null) return;

    _gameEndTimer?.cancel();

    debugPrint('Host leaving lobby - resetting status and deleting room ${_gameState!.roomCode}');
    
    // Reset status to 'lobby' before deleting (helps with cleanup)
    await _networkService.updateRoomStatus('lobby');
    
    await _networkService.deleteRoom(_gameState!.roomCode);
    // Note: Don't call leaveRoom() here to avoid recursion
  }

  /// Resign from the current game
  /// Returns cards to the deck, notifies others, and leaves the room
  Future<void> resignGame() async {
    if (_gameState == null) return;

    debugPrint('Resigning/Leavning game...');

    // If game is live (playing), return my cards to the deck
    if (_gameState!.phase == GamePhase.playing && !_isHost) {
      // Only non-hosts "resign" in the gameplay sense.
      // Hosts leaving usually kills the room or requires host migration (not implemented yet).

      // Send message that we are leaving, causing Host to handle card cleanup
      _networkService.send(
        type: MessageType.playerLeft,
        payload: {
          'playerId': _myPlayerId,
          'playerName': _myName,
          'reason': 'resigned',
        },
      );
    }
    // If Host leaves mid-game, we currently just leave (which might pause the game for others unless we delete)
    // For now, we rely on standard leaveRoom logic.

    await leaveRoom();
  }

  /// Handle a player leaving the game (Logic run by Host)
  void _handlePlayerLeft(GameMessage message) {
    if (!_isHost || _gameState == null) return;

    final playerId = message.payload['playerId'] as String?;
    final playerName =
        message.payload['playerName'] as String? ?? 'Unknown Player';

    if (playerId == null) return;

    debugPrint('Reviewing player departure: $playerName ($playerId)');

    // 1. Find the player
    final playerIndex = _gameState!.players.indexWhere((p) => p.id == playerId);
    if (playerIndex == -1) return;

    final player = _gameState!.players[playerIndex];

    // 2. Return cards to deck if game is playing
    if (_gameState!.phase == GamePhase.playing) {
      // Return hand to deck
      _gameState!.drawPile.addAll(player.hand);
      _gameState!.drawPile.shuffle(); // Shuffle deck to mix them in

      debugPrint(
        'Returned ${player.hand.length} cards from $playerName to deck.',
      );
    }

    // 3. Remove player from list
    _gameState!.players.removeAt(playerIndex);

    // 4. Update current turn index if needed
    if (_gameState!.currentPlayerIndex >= _gameState!.players.length) {
      _gameState = _gameState!.copyWith(currentPlayerIndex: 0);
    }
    // If the player who left was before the current turn, shift index back
    else if (playerIndex < _gameState!.currentPlayerIndex) {
      _gameState = _gameState!.copyWith(
        currentPlayerIndex: _gameState!.currentPlayerIndex - 1,
      );
    }

    // 5. Broadcast update and notification
    _broadcastGameState();

    // Send toast notification command to all clients
    _networkService.send(
      type:
          MessageType
              .gameGap, // Reusing an existing type or generic one since 'notification' is missing
      payload: {
        'message': '$playerName has resigned.',
        'type': 'info',
        'isNotification': true, // Flag to handle it as notification
      },
    );
  }

  /// Generate Single Source of Truth state for DB
  Map<String, dynamic> _generateSSOTState() {
    if (_gameState == null) return {};
    return _generateSSOTStateFromState(_gameState!);
  }

  /// Generate SSOT state from a given GameState (helper for initialization)
  Map<String, dynamic> _generateSSOTStateFromState(GameState state) {
    // Use compact JSON for consistency with broadcasts
    final stateJson = state.toCompactJson();
    final Map<String, dynamic> hands = {};

    // Extract hands for SSOT (always include, even if empty, for consistency)
    for (final p in state.players) {
      hands[p.id.toString()] = p.hand.map((c) => c.toJson()).toList();
    }

    // Add hands map to compact JSON
    stateJson['hands'] = hands;
    
    // Ensure hands are also in players array (compact format uses 'h' key)
    // This is already done by toCompactJson(), but we verify it's there
    
    return stateJson;
  }

  /// Play a card
  void playCard(UnoCard card, {UnoColor? chosenColor}) {
    if (_gameState == null || !isMyTurn) return;

    if (!GameLogic.isValidMove(
      card,
      _gameState!.topDiscard,
      _gameState!.activeColor,
    )) {
      _error = 'Invalid move';
      notifyListeners();
      return;
    }

    // Both Host and Client send MOVE_ATTEMPT for synchronized updates
    // Host processes their own MOVE_ATTEMPT in _handleMoveAttempt
    _networkService.send(
      type: MessageType.moveAttempt,
      payload: {
        'card': card.toCompactJson(),
        if (chosenColor != null) 'chosenColor': chosenColor.toJson(),
      },
    );
  }

  /// Draw a card
  void drawCard() {
    if (_gameState == null || !isMyTurn || _hasDrawnCard) return;

    // Both Host and Client send DRAW_REQUEST for synchronized updates
    _networkService.send(type: MessageType.drawRequest);
    _hasDrawnCard = true;
    notifyListeners();
  }

  /// Pass turn
  void passTurn() {
    if (_gameState == null || !isMyTurn) return;

    // Both Host and Client send PASS_TURN for synchronized updates
    _networkService.send(type: MessageType.passTurn);
    _hasDrawnCard = false;
    _lastDrawnCard = null;
  }

  /// Resign from the game
  Future<void> resign() async {
    if (_gameState == null) return;

    if (_isHost) {
      // Host resigning: Select new host randomly and notify all players
      _handleHostResignation();
    } else {
      _networkService.send(type: MessageType.playerResign);
      await leaveRoom();
    }
  }

  /// Handle host resignation - select new host randomly
  void _handleHostResignation() {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.players.length <= 1) {
      // Only host left, just leave
      leaveRoom();
      return;
    }

    // Get remaining players (excluding current host)
    final remainingPlayers = _gameState!.players
        .where((p) => p.id != _myPlayerId)
        .toList();
    
    if (remainingPlayers.isEmpty) {
      leaveRoom();
      return;
    }

    // Randomly select new host
    final random = DateTime.now().millisecondsSinceEpoch % remainingPlayers.length;
    final newHost = remainingPlayers[random];

    debugPrint('Host resigning: Selecting ${newHost.name} as new host');

    // Update game state with new host
    _gameState = _gameState!.copyWith(hostId: newHost.id);
    
    // Update players to reflect new host
    final updatedPlayers = _gameState!.players.map((p) {
      return p.copyWith(isHost: p.id == newHost.id);
    }).toList();
    _gameState = _gameState!.copyWith(players: updatedPlayers);

    // Return host's cards to deck if game is playing
    if (_gameState!.phase == GamePhase.playing) {
      final hostPlayer = _gameState!.getPlayerById(_myPlayerId);
      if (hostPlayer != null) {
        _gameState!.drawPile.addAll(hostPlayer.hand);
        _gameState!.drawPile.shuffle();
      }
    }

    // Remove host from players list
    _gameState = _gameState!.removePlayer(_myPlayerId);

    // Update current turn index if needed
    if (_gameState!.currentPlayerIndex >= _gameState!.players.length) {
      _gameState = _gameState!.copyWith(currentPlayerIndex: 0);
    }

    // Broadcast host resignation event
    _networkService.send(
      type: MessageType.hostResigned,
      payload: {
        'oldHostId': _myPlayerId,
        'oldHostName': _myName,
        'newHostId': newHost.id,
        'newHostName': newHost.name,
      },
    );

    // Broadcast new host selected notification
    _networkService.send(
      type: MessageType.newHostSelected,
      payload: {
        'newHostId': newHost.id,
        'newHostName': newHost.name,
      },
    );

    // Broadcast updated game state
    _networkService.updateRemoteGameState(_generateSSOTState());
    _broadcastGameState();

    // Host leaves after migration
    leaveRoom();
  }

  /// Check if a card can be played
  bool canPlayCard(UnoCard card) {
    if (_gameState == null || !isMyTurn) return false;
    return GameLogic.isValidMove(
      card,
      _gameState!.topDiscard,
      _gameState!.activeColor,
    );
  }

  /// Leave the current room
  Future<void> leaveRoom() async {
    debugPrint(
      'GameProvider: leaveRoom called! StackTrace: ${StackTrace.current}',
    ); // Added StackTrace

    // If Host leaves (not resigning), kick all players and delete room
    if (_isHost && _gameState != null) {
      debugPrint('HOST: Leaving room - kicking all players and deleting room...');
      
      // 1. Broadcast HOST_LEFT to kick all players (ephemeral broadcast)
      try {
        await _networkService.send(
          type: MessageType.hostLeft,
          payload: {
            'hostId': _myPlayerId,
            'hostName': _myName,
          },
        );
        debugPrint('HOST: HOST_LEFT broadcast sent');
      } catch (e) {
        debugPrint('HOST: Failed to send HOST_LEFT broadcast: $e');
      }

      // 2. Wait for broadcast to be sent
      await Future.delayed(const Duration(milliseconds: 1000));

      // 3. Reset status and delete room from DB (CRITICAL: Must delete before leaving)
      _gameEndTimer?.cancel();
      final roomCode = _gameState!.roomCode;
      debugPrint('HOST: Resetting status and deleting room $roomCode from backend...');
      
      // Reset status to 'lobby' before deleting (helps with cleanup)
      await _networkService.updateRoomStatus('lobby');
      
      await _networkService.deleteRoom(roomCode);
      debugPrint('HOST: Room deleted successfully');
      
      // 4. Set error flag for host to trigger navigation in UI
      _error = 'HOST_LEFT'; // Same flag as clients receive
    } else {
      // CLIENT LOGIC:
      // Always remove self from DB
      await _networkService.removeSelfFromRoom();

      // Clients just leave, never delete.
    }

    if (_kicked) {
      _error = 'The host has closed the room.';
    } else if (_error == null && !_isHost) {
      // Only clear error for clients if not already set
      _error = null;
    }

    _syncTimer?.cancel();
    _joinRetryTimer?.cancel();
    WakelockPlus.disable(); // Allow screen to turn off
    await _networkService.disconnect();
    _gameState = null;
    _isHost = false;
    _gameStarted = false;
    _isConnected = false;
    _hasDrawnCard = false;
    _lastDrawnCard = null;
    _lastStateSequence = 0;
    _hasReceivedGameState = false;
    _showWinnerAnimation = false;
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    // _kicked = false; // Keep kicked true until next join? No, reset it on join.
    // _error is kept so UI can show it
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint('GameProvider: dispose called!'); // Log
    _syncTimer?.cancel();
    _joinRetryTimer?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _playersSubscription?.cancel(); // Cancel new subscription
    _presenceSubscription?.cancel();
    _networkService.dispose();
    super.dispose();
  }
}
