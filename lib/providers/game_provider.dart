import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/uno_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../logic/game_logic.dart';
import '../services/peer_network_service.dart';
import '../services/message_types.dart';

/// Main game state provider handling both Host and Client logic
class GameProvider extends ChangeNotifier {
  final PeerNetworkService _networkService = PeerNetworkService();
  final String _myPlayerId = const Uuid().v4();
  
  GameState? _gameState;
  String _myName = '';
  bool _isHost = false;
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
  

  
  // JOIN_REQUEST retry logic for clients
  Timer? _joinRetryTimer;
  bool _hasReceivedGameState = false;
  
  // UNO call animation state
  bool _showUnoCallAnimation = false;
  String? _unoCallerName;
  bool _hasCalledUno = false;  // Tracks if player already called UNO this round
  

  
  // Flag-based handshake state (Host)
  final Set<String> _ackReceivedFrom = {};  // Track which players sent ACK_READY
  bool _waitingForAcks = false;

  Timer? _prepareGameRetryTimer;
  
  // Flag-based handshake state (Joiner)
  bool _isPreparingGame = false;  // Set when PREPARE_GAME received
  
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

  Timer? _snapshotRetryTimer;
  
  // Reliable Sync Handshake & Chunking
  String? _snapshotPart1;
  Timer? _readyToReceiveRetryTimer;
  final Set<String> _pendingSnapshotReceivers = {}; // Host: Logic to track who needs snapshot
  
  Timer? _multiThrowClearTimer; // 10s timer for clearing center stack
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _errorSubscription;
  Timer? _syncTimer;

  // Getters
  GameState? get gameState => _gameState;
  String get myPlayerId => _myPlayerId;
  String get myName => _myName;
  bool get isHost => _isHost;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get error => _error;
  bool get hasDrawnCard => _hasDrawnCard;
  UnoCard? get lastDrawnCard => _lastDrawnCard;
  bool get showWinnerAnimation => _showWinnerAnimation;
  String? get winnerAnimationName => _winnerAnimationName;
  bool get isWinnerAnimationForMe => _isWinnerAnimationForMe;
  bool get wasKickedAsWinner => _wasKickedAsWinner;
  bool get showUnoCallAnimation => _showUnoCallAnimation;
  String? get unoCallerName => _unoCallerName;
  bool get canCallUno => myPlayer?.hasUno == true && !_hasCalledUno;
  bool get isPreparingGame => _isPreparingGame;  // For greedy navigation
  
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
  
  /// Check if it's my turn
  bool get isMyTurn {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) return false;
    return _gameState!.currentPlayer?.id == _myPlayerId;
  }
  
  /// Get list of other players
  List<Player> get opponents {
    if (_gameState == null) return [];
    return _gameState!.players.where((p) => p.id != _myPlayerId).toList();
  }

  /// Create a new room as host
  Future<bool> createRoom(String playerName, String roomCode) async {
    _myName = playerName;
    _isHost = true;
    _isConnecting = true;
    _error = null;
    _wasKickedAsWinner = false;
    _hasReceivedGameState = true; // Host doesn't need to receive
    notifyListeners();
    
    debugPrint('DEBUG: Host creating room $roomCode as $playerName');
    
    final success = await _networkService.connect(
      roomId: roomCode,
      playerName: playerName,
      playerId: _myPlayerId,
      isHost: true,
    );
    
    if (success) {
      _isConnected = true;
      _setupListeners();
      
      // Create initial lobby state
      final host = Player(
        id: _myPlayerId,
        name: playerName,
        isHost: true,
      );
      
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
    _myName = playerName;
    _isHost = false;
    _isConnecting = true;
    _error = null;
    _wasKickedAsWinner = false;
    _hasReceivedGameState = false;
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
      payload: {
        'playerId': _myPlayerId,
        'playerName': _myName,
      },
    );
  }

  void _startJoinRetryTimer() {
    _joinRetryTimer?.cancel();
    // Debounce: Only retry every 3 seconds
    _joinRetryTimer = Timer(const Duration(seconds: 3), () {
      if (!_hasReceivedGameState && _isConnected && !_isHost) {
        debugPrint('DEBUG: Client retrying JOIN_REQUEST (no GAME_STATE received after 3s)');
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

  void _setupListeners() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    
    _messageSubscription = _networkService.messageStream.listen(_onMessage);
    _connectionSubscription = _networkService.connectionStream.listen(_onConnectionChange);
    _errorSubscription = _networkService.errorStream.listen(_onError);
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
    
    debugPrint('DEBUG: Host received JOIN_REQUEST from $playerName ($playerId)');
    
    // Check if player already exists
    if (_gameState!.getPlayerById(playerId) != null) {
      debugPrint('DEBUG: Player already in list, broadcasting current state');
      _broadcastGameState();
      return;
    }
    
    // Add new player
    final newPlayer = Player(
      id: playerId,
      name: playerName,
      isHost: false,
    );
    
    
    _gameState = _gameState!.addPlayer(newPlayer);
    
    debugPrint('DEBUG: Host added player $playerName, now ${_gameState!.players.length} players');
    debugPrint('DEBUG: Host broadcasting GAME_STATE after adding player (priority)');
    
    // Immediately broadcast with priority
    _broadcastGameState();
    notifyListeners();
  }

  void _handleMoveAttempt(GameMessage message) {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;
    
    final playerId = message.senderId;
    final cardJson = message.payload['card'] as Map<String, dynamic>;
    
    // Support both compact and regular JSON
    final card = cardJson.containsKey('i') 
        ? UnoCard.fromCompactJson(cardJson)
        : UnoCard.fromJson(cardJson);
    final chosenColor = message.payload['chosenColor'] != null
        ? UnoColor.fromJson(message.payload['chosenColor'] as String)
        : null;
    
    // Validate it's this player's turn
    if (_gameState!.currentPlayer?.id != playerId) {
      return;
    }
    
    // Validate move
    if (!GameLogic.isValidMove(card, _gameState!.topDiscard, _gameState!.activeColor)) {
      return;
    }
    
    // Apply move
    _gameState = GameLogic.applyCardEffect(
      state: _gameState!,
      card: card,
      playerId: playerId,
      chosenColor: chosenColor,
    );
    
    // Check for winner
    if (_gameState!.phase == GamePhase.finished) {
      _handleGameWon();
    }
    
    _broadcastGameState();
    notifyListeners();
  }

  void _handleDrawRequest(GameMessage message) {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.phase != GamePhase.playing) return;
    
    final playerId = message.senderId;
    
    if (_gameState!.currentPlayer?.id != playerId) {
      return;
    }
    
    final result = GameLogic.drawCard(_gameState!, playerId);
    _gameState = result.state;
    
    _broadcastGameState();
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
    _broadcastGameState();
    notifyListeners();
  }

  void _handlePlayerResign(GameMessage message) {
    if (!_isHost || _gameState == null) return;
    
    final playerId = message.senderId;
    _kickPlayer(playerId);
  }

  void _handleGameWon() {
    _networkService.send(
      type: MessageType.gameOver,
      payload: {
        'winnerId': _gameState!.winnerId,
        'winnerName': _gameState!.winnerName,
      },
    );
    
    _showWinnerAnimation = true;
    _winnerAnimationName = _gameState!.winnerName;
    _isWinnerAnimationForMe = _gameState!.winnerId == _myPlayerId;
    notifyListeners();
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
      _handleThrowMultiple(GameMessage(
        type: MessageType.throwMultiple,
        senderId: _myPlayerId,
        senderName: _myName,
        payload: {
          'cardIds': cardIds,
          if (chosenColor != null) 'chosenColor': chosenColor.index,
        },
      ));
    }
  }

  /// Start the game (host only)
  void startGame() {
    if (!_isHost || _gameState == null) return;
    if (_gameState!.players.length < 2) {
      _error = 'Need at least 2 players to start';
      notifyListeners();
      return;
    }
    
    _startGame();
  }

  void _startGame() {
    if (!_isHost || _gameState == null) return;
    
    debugPrint('DEBUG: Host starting game with ${_gameState!.players.length} players');
    
    // CRITICAL: Kill periodic sync timer permanently
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('DEBUG: Periodic sync timer KILLED');
    
    // Initialize game (batched - one GAME_STATE with all cards dealt)
    _gameState = GameLogic.initializeGame(_gameState!);
    
    // Flag-based handshake: Send PREPARE_GAME and wait for ACK_READY
    _waitingForAcks = true;
    _ackReceivedFrom.clear();
    
    debugPrint('DEBUG: Sending PREPARE_GAME to all clients');
    _sendPrepareGame();
    
    // After 2 seconds, use the new Full State Snapshot approach
    _prepareGameRetryTimer?.cancel();
    _prepareGameRetryTimer = Timer(const Duration(seconds: 2), () {
      if (_waitingForAcks) {
        debugPrint('DEBUG: Using Full State Snapshot approach');
        _waitingForAcks = false;
        
        // Use the new snapshot architecture
        broadcastFullSnapshot(immediate: true);
        
        // Resume heartbeats after snapshot is sent
        // _networkService.resumeHeartbeats(); // Removed for P2P
      }
    });
    
    notifyListeners();
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
    if (_isHost) return;  // Host ignores this
    
    debugPrint('DEBUG: Received PREPARE_GAME - setting isPreparingGame=true, sending ACK_READY');
    
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
    if (!_isHost) return;  // Joiner ignores this
    if (!_waitingForAcks) return;  // Not in handshake phase
    
    final playerId = message.payload['playerId'] as String? ?? message.senderId;
    debugPrint('DEBUG: Received ACK_READY from $playerId');
    
    _ackReceivedFrom.add(playerId);
    
    // Once we receive first ACK, wait 1 second then start sequential sync
    if (_ackReceivedFrom.length == 1) {
      debugPrint('DEBUG: First ACK received - starting sequential data sync in 1s');
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
      
      final starterCard = _gameState!.discardPile.isNotEmpty 
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
    if (_isHost) return;  // Host ignores
    
    debugPrint('DEBUG: Received SET_PLAYERS');
    
    try {
      final playersJson = message.payload['players'] as List;
      _tempPlayers = playersJson
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
      _tempDeck = deckJson
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
    if (targetId != _myPlayerId) return;  // Not for me
    
    debugPrint('DEBUG: Received SET_HAND for me!');
    
    try {
      final cardsJson = message.payload['cards'] as List;
      _tempMyHand = cardsJson
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
        _tempStarterCard = UnoCard.fromCompactJson(starterCardJson as Map<String, dynamic>);
      }
      
      final currentPlayerIndex = message.payload['currentPlayerIndex'] as int? ?? 0;
      final isClockwise = message.payload['isClockwise'] as bool? ?? true;
      
      // Assemble the full game state from pieces
      if (_tempPlayers != null) {
        // Find my player and update their hand
        final updatedPlayers = _tempPlayers!.map((p) {
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
          phase: GamePhase.playing,  // NOW WE'RE PLAYING!
          hostId: updatedPlayers.firstWhere((p) => p.isHost, orElse: () => updatedPlayers.first).id,
          roomCode: _gameState?.roomCode ?? '',
        );
        
        _isGameLive = true;
        _isPreparingGame = false;  // Clear the loading state
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
    if (!_isHost) return;  // Only host responds
    
    final step = message.payload['step'] as String?;
    final requesterId = message.senderId;
    
    debugPrint('DEBUG: Received REQ_RESEND for step: $step from $requesterId');
    
    if (_gameState == null) return;
    
    switch (step) {
      case 'PLAYERS':
        _networkService.send(
          type: MessageType.setPlayers,
          payload: {
            'players': _gameState!.players.map((p) => p.toCompactJson()).toList(),
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
        final starterCard = _gameState!.discardPile.isNotEmpty 
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
    _isPreparingGame = true;     // Show loading spinner
    _snapshotPart1 = null;       // Clear any partial buffer
    
    notifyListeners();
    
    debugPrint('JOINER: Received START_SIGNAL - Sending READY_TO_RECEIVE (Retry Loop Started)');
    
    // 2. Start Retry Loop: Send READY_TO_RECEIVE every 3s until we get snapshot
    _readyToReceiveRetryTimer?.cancel();
    _sendReadyToReceive();
    
    _readyToReceiveRetryTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
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
      
      debugPrint('HOST: Sending CHUNKED snapshot to $playerId (Len: ${jsonString.length})');
      
      // Send Part 1
      _networkService.send(
        type: MessageType.snapshotPart1,
        payload: {
          'data': part1, 
          'targetId': playerId // Filter by targetId
        },
      );
      
      // Small delay to ensure order
      Future.delayed(const Duration(milliseconds: 50), () {
        _networkService.send(
          type: MessageType.snapshotPart2,
          payload: {
             'data': part2,
             'targetId': playerId
          },
        );
      });
      
    } else {
      // Send as single message
      debugPrint('HOST: Sending normal snapshot to $playerId');
      _networkService.send(
        type: MessageType.gameSnapshot,
        payload: {
          ...snapshotData,
          'targetId': playerId
        }, 
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
      
      debugPrint('DEBUG: Parsed snapshot (seq=$stateSeq, phase=${newState.phase}, players=${newState.players.length})');
      
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
      
      debugPrint('DEBUG: Snapshot applied! Deck: ${newState.drawPile.length}, Phase: ${newState.phase}');
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
    
    debugPrint('DEBUG: THROW_MULTIPLE from $playerId with ${cardIds.length} cards');
    
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
      final card = player.hand.firstWhere((c) => c.id == cardId, orElse: () => player.hand.first);
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
    final topDiscard = _gameState!.discardPile.isNotEmpty ? _gameState!.discardPile.last : null;
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
      debugPrint('DEBUG: Stacking $cardCount Skip cards - skipping $playersToSkip players');
    } else if (firstCard.type == UnoCardType.drawTwo) {
      // Draw 2 × N cards
      cardsToDraw = 2 * cardCount;
      playersToSkip = 1;  // Next player also skipped after drawing
      debugPrint('DEBUG: Stacking $cardCount Draw2 cards - next player draws $cardsToDraw');
    } else if (firstCard.type == UnoCardType.reverse) {
      // Flip direction N times (odd = change, even = no change)
      shouldFlipDirection = cardCount.isOdd;
      debugPrint('DEBUG: Stacking $cardCount Reverse cards - direction ${shouldFlipDirection ? "flips" : "unchanged"}');
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
        isClockwise: newDirection,
      );
    } else {
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
    
    debugPrint('DEBUG: Multi-throw processed (${cardsToPlay.length} cards), broadcasting snapshot');
    notifyListeners();
  }

  void _broadcastGameState() {
    if (_gameState == null) return;
    
    // Handshake complete - cancel any pending PREPARE_GAME retries
    _prepareGameRetryTimer?.cancel();
    _waitingForAcks = false;
    
    _lastStateSequence++;
    
    // Use compact JSON for reduced payload
    _networkService.send(
      type: MessageType.gameState,
      payload: {
        'state': _gameState!.toCompactJson(),
        'stateSeq': _lastStateSequence,
        'compact': true,
      },
    );
    
    debugPrint('DEBUG: GAME_STATE broadcast complete (seq=$_lastStateSequence)');
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
    // Host ignores (uses local state)
    if (_isHost) return;
    
    try {
      final stateSeq = message.payload['stateSeq'] as int? ?? 0;
      
      // Only accept newer states
      if (stateSeq < _lastStateSequence) return;
      
      _lastStateSequence = stateSeq;
      
      final stateJson = message.payload['state'] as Map<String, dynamic>;
      final isCompact = message.payload['compact'] as bool? ?? false;
      
      final newState = isCompact 
          ? GameState.fromCompactJson(stateJson)
          : GameState.fromJson(stateJson);
      
      debugPrint('DEBUG: Client received GAME_STATE (seq=$stateSeq, phase=${newState.phase}, players=${newState.players.length})');
      
      // Mark that we received a game state - stop retry timer
      if (!_hasReceivedGameState) {
        _hasReceivedGameState = true;
        _joinRetryTimer?.cancel();
        debugPrint('DEBUG: Client successfully synced with host!');
      }
      
      // Clear isPreparingGame when we receive a playing phase state
      if (newState.phase == GamePhase.playing && _isPreparingGame) {
        _isPreparingGame = false;
        debugPrint('DEBUG: Game state received - clearing isPreparingGame');
      }
      
      // Check for winner animation
      if (newState.phase == GamePhase.finished && 
          _gameState?.phase != GamePhase.finished) {
        _showWinnerAnimation = true;
        _winnerAnimationName = newState.winnerName;
        _isWinnerAnimationForMe = newState.winnerId == _myPlayerId;
      }
      
      _gameState = newState;
      _hasDrawnCard = false;
      _lastDrawnCard = null;
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
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    notifyListeners();
  }

  /// Handle incoming UNO call from any player
  void _handleUnoCall(GameMessage message) {
    final callerName = message.payload['playerName'] as String? ?? message.senderName;
    
    debugPrint('DEBUG: UNO called by $callerName!');
    
    // Show UNO animation to all players
    _showUnoCallAnimation = true;
    _unoCallerName = callerName;
    notifyListeners();
    
    // Auto-dismiss animation after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      dismissUnoAnimation();
    });
  }

  /// Call UNO (player with 1 card calls this)
  void callUno() {
    if (!canCallUno) return;
    
    debugPrint('DEBUG: Calling UNO!');
    
    _hasCalledUno = true;
    
    // Broadcast UNO call to all players
    _networkService.send(
      type: MessageType.unoCall,
      payload: {
        'playerId': _myPlayerId,
        'playerName': _myName,
      },
    );
    
    // Also show animation locally
    _showUnoCallAnimation = true;
    _unoCallerName = _myName;
    notifyListeners();
    
    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      dismissUnoAnimation();
    });
  }

  /// Dismiss UNO call animation
  void dismissUnoAnimation() {
    _showUnoCallAnimation = false;
    _unoCallerName = null;
    notifyListeners();
  }

  /// Play a card
  void playCard(UnoCard card, {UnoColor? chosenColor}) {
    if (_gameState == null || !isMyTurn) return;
    
    if (!GameLogic.isValidMove(card, _gameState!.topDiscard, _gameState!.activeColor)) {
      _error = 'Invalid move';
      notifyListeners();
      return;
    }
    
    if (_isHost) {
      _gameState = GameLogic.applyCardEffect(
        state: _gameState!,
        card: card,
        playerId: _myPlayerId,
        chosenColor: chosenColor,
      );
      _hasDrawnCard = false;
      _lastDrawnCard = null;
      
      if (_gameState!.phase == GamePhase.finished) {
        _handleGameWon();
      }
      
      _broadcastGameState();
      notifyListeners();
    } else {
      _networkService.send(
        type: MessageType.moveAttempt,
        payload: {
          'card': card.toCompactJson(),
          if (chosenColor != null) 'chosenColor': chosenColor.toJson(),
        },
      );
    }
  }

  /// Draw a card
  void drawCard() {
    if (_gameState == null || !isMyTurn || _hasDrawnCard) return;
    
    if (_isHost) {
      final result = GameLogic.drawCard(_gameState!, _myPlayerId);
      _gameState = result.state;
      _lastDrawnCard = result.drawnCard;
      _hasDrawnCard = true;
      _broadcastGameState();
      notifyListeners();
    } else {
      _networkService.send(type: MessageType.drawRequest);
      _hasDrawnCard = true;
      notifyListeners();
    }
  }

  /// Pass turn
  void passTurn() {
    if (_gameState == null || !isMyTurn) return;
    
    if (_isHost) {
      _gameState = GameLogic.passTurn(_gameState!);
      _hasDrawnCard = false;
      _lastDrawnCard = null;
      _broadcastGameState();
      notifyListeners();
    } else {
      _networkService.send(type: MessageType.passTurn);
      _hasDrawnCard = false;
      _lastDrawnCard = null;
    }
  }

  /// Resign from the game
  void resign() {
    if (_gameState == null) return;
    
    if (_isHost) {
      _kickPlayer(_myPlayerId);
      if (_gameState!.players.isEmpty) {
        leaveRoom();
      }
    } else {
      _networkService.send(type: MessageType.playerResign);
      leaveRoom();
    }
  }

  /// Check if a card can be played
  bool canPlayCard(UnoCard card) {
    if (_gameState == null || !isMyTurn) return false;
    return GameLogic.isValidMove(card, _gameState!.topDiscard, _gameState!.activeColor);
  }

  /// Leave the current room
  void leaveRoom() {
    _syncTimer?.cancel();
    _joinRetryTimer?.cancel();
    _networkService.disconnect();
    _gameState = null;
    _isHost = false;
    _isConnected = false;
    _hasDrawnCard = false;
    _lastDrawnCard = null;
    _lastStateSequence = 0;
    _hasReceivedGameState = false;
    _showWinnerAnimation = false;
    _winnerAnimationName = null;
    _isWinnerAnimationForMe = false;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _joinRetryTimer?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _networkService.dispose();
    super.dispose();
  }
}
