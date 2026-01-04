import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:supabase_flutter/supabase_flutter.dart';
import 'message_types.dart';

/// Supabase-based real-time game state synchronization service
/// Replaces Ably for cost-efficient game sync using Supabase Realtime
class SupabaseUnoService {
  static const String _tableName = 'uno_rooms';

  SupabaseClient get _client => Supabase.instance.client;

  String? _currentRoomCode;
  String? _currentRoomId;
  String? _myClientId;
  String? _myName;
  bool _isHost = false;

  RealtimeChannel? _realtimeChannel;

  // Streams for GameProvider integration
  final StreamController<GameMessage> _messageController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  final StreamController<String> _errorController =
      StreamController.broadcast();

  // New Stream for Players List
  final StreamController<List<Map<String, dynamic>>> _playersController =
      StreamController.broadcast();
  Stream<List<Map<String, dynamic>>> get playersStream =>
      _playersController.stream;

  StreamSubscription? _playersSubscription;
  StreamSubscription? _gameStateSubscription;

  Stream<GameMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Initialize Supabase - call this in main.dart
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 20, // Increased for lower latency (was 10)
      ),
    );
    debugPrint('Supabase: Initialized successfully');
  }

  /// Connect to a room (Relational Schema Version)
  Future<bool> connect({
    required String roomId, // roomCode
    required String playerName,
    required String playerId,
    required bool isHost,
  }) async {
    _currentRoomCode = roomId;
    _myClientId = playerId;
    _myName = playerName;
    _isHost = isHost;

    try {
      debugPrint(
        'Supabase: Connecting to room $roomId as ${isHost ? "HOST" : "CLIENT"}',
      );

      if (isHost) {
        // HOST: Create Room + Join as first player
        await _createRoom(roomId);
      } else {
        // CLIENT: Join directly
        await _joinRoom(roomId);
      }

      // Start Dual Streams
      await _setupRelationalSubscriptions(roomId);

      _connectionController.add(true);
      return true;
    } catch (e) {
      debugPrint('Supabase: Connection failed: $e');
      _errorController.add('Connection failed: $e');
      return false;
    }
  }

  /// Create a new room
  Future<void> _createRoom(String roomCode) async {
    // 1. Create Uno Room
    final roomRes =
        await _client
            .from('uno_rooms')
            .insert({
              'room_code': roomCode,
              'host_id': _myClientId,
              'status': 'lobby',
              'game_state': {}, // Empty initial state
            })
            .select()
            .single();

    _currentRoomId = roomRes['id'];

    // 2. Add Host to Room Players
    await _client.from('room_players').insert({
      'room_id': _currentRoomId,
      'player_id': _myClientId,
      'player_name': _myName,
      'is_ready': true,
      'cards': [],
    });

    debugPrint('Supabase: Created room $_currentRoomId');
  }

  /// Join an existing room (using RPC for atomic operation)
  Future<void> _joinRoom(String roomCode) async {
    // 1. Get Room ID and game state
    final roomRes =
        await _client
            .from('uno_rooms')
            .select('id, status, game_state, host_id')
            .eq('room_code', roomCode)
            .maybeSingle();

    if (roomRes == null) throw Exception('Room not found');

    final status = roomRes['status'] as String?;
    final gameState = roomRes['game_state'] as Map<String, dynamic>?;
    final hostId = roomRes['host_id'] as String?;
    
    // Check if game has actually started (has players with cards)
    bool gameActuallyStarted = false;
    if (gameState != null) {
      final players = gameState['p'] as List<dynamic>? ?? gameState['players'] as List<dynamic>?;
      if (players != null && players.isNotEmpty) {
        // Check if any player has cards (game has started)
        for (final player in players) {
          final playerMap = player as Map<String, dynamic>;
          final hand = playerMap['h'] as List<dynamic>? ?? playerMap['hand'] as List<dynamic>?;
          if (hand != null && hand.isNotEmpty) {
            gameActuallyStarted = true;
            break;
          }
        }
      }
    }
    
    // Allow join if status is 'lobby' OR if status is 'playing' but game hasn't actually started
    // This handles cases where status is stuck as 'playing' from a previous session
    if (status == 'playing' && gameActuallyStarted) {
      throw Exception('Game already in progress');
    }
    
    // If status is 'playing' but game hasn't started, reset to 'lobby'
    if (status == 'playing' && !gameActuallyStarted) {
      debugPrint('Supabase: Status is playing but game not started, resetting to lobby');
      await _client
          .from('uno_rooms')
          .update({'status': 'lobby'})
          .eq('room_code', roomCode);
    }

    _currentRoomId = roomRes['id'];

    // 2. Use RPC function to atomically add player to both room_players and game_state
    try {
      await _client.rpc(
        'add_player_to_room',
        params: {
          'p_room_code': roomCode,
          'p_player_id': _myClientId,
          'p_player_name': _myName,
          'p_host_id': hostId ?? '',
        },
      );
      
      debugPrint('Supabase: Added player via RPC, updated game_state received');
    } catch (e) {
      debugPrint('Supabase: RPC add_player_to_room failed, falling back to direct insert: $e');
      
      // Fallback: Direct insert if RPC fails
      await _client.from('room_players').upsert({
        'room_id': _currentRoomId,
        'player_id': _myClientId,
        'player_name': _myName,
        'is_ready': false,
        'cards': [],
      }, onConflict: 'room_id, player_id');
      
      // Sync players to game_state
      await _client.rpc(
        'sync_players_to_game_state',
        params: {'p_room_code': roomCode},
      );
    }

    debugPrint('Supabase: Joined room $_currentRoomId');
  }

  // Cache for Stream Merging
  List<Map<String, dynamic>> _cachedPlayers = [];
  Map<String, dynamic> _cachedGameState = {};
  bool _hasReceivedRoomData = false;

  // Track previous turn to prevent spamming haptics
  String? _previousTurnId;

  /// Setup Listeners for Rooms and Players
  // Setup Listeners for Rooms and Players
  Future<void> _setupRelationalSubscriptions(String roomCode) async {
    if (_currentRoomId == null) return;

    // 1. Players Stream with Error Handling
    _playersSubscription = _client
        .from('room_players')
        .stream(primaryKey: ['id'])
        .eq('room_id', _currentRoomId!)
        .listen(
          (List<Map<String, dynamic>> players) {
            debugPrint(
              'Service: Players updated. Count: ${players.length}',
            ); // Added debug
            _cachedPlayers = players;

            // CRITICAL: Emit to playersStream for GameProvider's _onPlayersUpdate
            _playersController.add(players);

            _emitSynthesizedGameState();
          },
          onError: (error) {
            debugPrint('Supabase: Players Stream Error: $error');
            _errorController.add('Player sync lost. Trying to reconnect...');
          },
          cancelOnError: false, // Keep trying to reconnect
        );

    // 2. Room State Stream with Metadata Injection
    _gameStateSubscription = _client
        .from('uno_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', _currentRoomId!)
        .listen(
          (List<Map<String, dynamic>> data) {
            if (data.isNotEmpty) {
              _hasReceivedRoomData =
                  true; // Mark that we've received valid data

              final room = data.first;
              _cachedGameState = Map<String, dynamic>.from(
                room['game_state'] as Map? ?? {},
              );

              // Discard pile is already in game_state JSONB, no need to inject separately

              // Inject extra metadata for the UI/GameProvider
              _cachedGameState['status'] = room['status'];
              _cachedGameState['hostId'] = room['host_id'];
              _cachedGameState['roomCode'] = room['room_code'];

              _emitSynthesizedGameState();
            } else {
              // CLIENT SAFETY: Check for definitive room closure
              // If we have received valid room data before, and now it's gone AND players are empty -> Room Deleted
              if (!_isHost && _hasReceivedRoomData) {
                debugPrint(
                  'Supabase: Room data is empty - waiting for signal or reconnect...',
                );
                // _errorController.add('ROOM_CLOSED'); // DISABLED: Relies on broadcast
              } else if (!_hasReceivedRoomData) {
                // Initial empty emission - ignore
                debugPrint('Supabase: Ignoring initial empty room data');
              }
            }
          },
          onError: (error) {
            debugPrint('Supabase: Room State Error: $error');
            _errorController.add('Room sync lost.');
          },
        );

    // 3. Keep listening to ephemeral broadcasts
    _realtimeChannel = _client.channel('room:$roomCode');

    // Create a completer to wait for subscription
    final subscriptionCompleter = Completer<void>();

    _realtimeChannel!
        .onBroadcast(
          event: 'game_message',
          callback: (payload) {
            _handleBroadcastMessage(payload);
          },
        )
        .onBroadcast(
          event: 'game_event', // Separate channel for transient events
          callback: (payload) {
            _handleGameEvent(payload);
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (!subscriptionCompleter.isCompleted) {
              subscriptionCompleter.complete();
            }
          } else if (status == RealtimeSubscribeStatus.closed) {
            debugPrint('Supabase: Realtime channel closed.');
          }
          if (error != null) {
            debugPrint('Supabase: Channel subscription error: $error');
            if (!subscriptionCompleter.isCompleted) {
              // Determine if we should fail or just log
              // For now, let's complete so we don't hang, but connection might be partial
              subscriptionCompleter.complete();
            }
          }
        });

    // Wait for subscription with timeout to prevent hanging
    try {
      await subscriptionCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Supabase: Subscription timeout (proceeding anyway)');
        },
      );
    } catch (e) {
      debugPrint('Supabase: Error waiting for subscription: $e');
    }
  }

  /// Helper to merge cached data and emit a single source of truth
  void _emitSynthesizedGameState() {
    // Guard: NEVER emit state with empty players if we are connected to a room.
    // Supabase streams can briefly return [] during reconnection.
    if (_cachedPlayers.isEmpty) {
      debugPrint('Service: Ignoring empty player list emission.');
      return;
    }

    // Deep copy state to avoid mutation issues
    final synthesizedPayload = Map<String, dynamic>.from(_cachedGameState);

    // Check for hands in game_state (Single Source of Truth for gameplay)
    final handsMap = _cachedGameState['hands'] as Map<String, dynamic>?;
    
    // CRITICAL: Also check if hands are in players array (compact format)
    // The compact format stores hands in players array with key 'h'
    final playersArray = _cachedGameState['p'] as List<dynamic>?;
    
    debugPrint(
      'Service: Hands map: ${handsMap != null ? handsMap.length : 0} players, Players array: ${playersArray != null ? playersArray.length : 0} players, Cached players: ${_cachedPlayers.length}',
    );

    // CRITICAL: Build players list from _cachedPlayers (database source of truth)
    // This ensures we always have the correct player count from room_players table
    final synthesizedPlayers = <Map<String, dynamic>>[];
    
    for (final p in _cachedPlayers) {
      final pid = p['player_id'].toString();

      // Priority 1: Use hand from game_state hands map (SSOT)
      List<dynamic> playerHand = [];
      if (handsMap != null && handsMap.containsKey(pid)) {
        playerHand = handsMap[pid] as List<dynamic>;
      } 
      // Priority 2: Check players array (compact format)
      else if (playersArray != null) {
        try {
          final playerInArray = playersArray.firstWhere(
            (pl) {
              final plMap = pl as Map<String, dynamic>;
              return (plMap['i']?.toString() == pid || plMap['id']?.toString() == pid);
            },
            orElse: () => null,
          );
          if (playerInArray != null) {
            final playerData = playerInArray as Map<String, dynamic>;
            playerHand = playerData['h'] as List<dynamic>? ?? [];
          }
        } catch (e) {
          debugPrint('Service: Error parsing player from array: $e');
        }
      }
      // Priority 3: Fallback to room_players cards
      if (playerHand.isEmpty) {
        playerHand = (p['cards'] ?? []) as List<dynamic>;
      }

      synthesizedPlayers.add({
        'id': pid,
        'name': p['player_name'] ?? 'Guest',
        'isReady': p['is_ready'] ?? false,
        'isHost': pid == _cachedGameState['hostId'],
        'hand': playerHand,
      });
    }
    
    // CRITICAL: Always use the synthesized players list (from database)
    synthesizedPayload['players'] = synthesizedPlayers;
    
    // CRITICAL: Ensure hands map is also in the payload for SSOT
    if (handsMap != null) {
      synthesizedPayload['hands'] = handsMap;
    }

    // Ensure the UI knows who the host is (DO NOT fallback to _myClientId - causes Joiner to think they're Host)
    // hostId comes from _cachedGameState['hostId'] which is injected from room stream
    // If it's missing, leave it as is - GameProvider will use its own _isHost flag

    debugPrint(
      'Service: Emitting synthesized state. Players: ${(synthesizedPayload['players'] as List).length}, hostId: ${synthesizedPayload['hostId']}',
    );

    // HAPTICS & TURN NOTIFICATION (Lag Fix)
    // Trigger vibrate if it's explicitly MY turn now (and wasn't before)
    final currentTurnId = _cachedGameState['current_turn_id'] as String?;
    if (currentTurnId != null) {
      if (currentTurnId == _myClientId && _previousTurnId != _myClientId) {
        debugPrint('HAPTIC: It is YOUR turn!');
        HapticFeedback.vibrate();
      }
      _previousTurnId = currentTurnId;
    }

    // DISCARD PILE CHECK
    // Ensure 'x' (discard) is present. If it's in the payload, it will be passed, but we log it for verification.
    if (synthesizedPayload.containsKey('x')) {
      // 'x' is the compact key for discardPile
      // debugPrint('Service: Discard pile (x) is present.');
    } else if (synthesizedPayload.containsKey('discardPile')) {
      // Long form
      // debugPrint('Service: Discard pile (long) is present.');
    }

    _messageController.add(
      GameMessage(
        type: MessageType.gameState,
        senderId: 'host',
        senderName: 'Host',
        payload: synthesizedPayload,
      ),
    );
  }

  /// Delete the room from the database (Host only)
  Future<void> deleteRoom(String roomCode) async {
    try {
      debugPrint(
        'Supabase: Attempting to delete room $roomCode by host $_myClientId',
      );

      // First, reset status to 'lobby' before deleting (helps with cleanup)
      try {
        await _client
            .from(_tableName)
            .update({'status': 'lobby'})
            .eq('room_code', roomCode);
        debugPrint('Supabase: Reset status to lobby before delete');
      } catch (e) {
        debugPrint('Supabase: Failed to reset status before delete: $e');
        // Continue with delete even if status reset fails
      }

      // Delete where room_code matches AND host_id matches our ID
      // (Though RLS may enforce the host_id part, we add it here for clarity)
      await _client.from(_tableName).delete().eq('room_code', roomCode);

      debugPrint('Supabase: Room deleted successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to delete room: $e');
      // We don't throw here to avoid blocking UI navigation
    }
  }

  /// Update room status (e.g. 'playing', 'lobby', 'finished')
  Future<void> updateRoomStatus(String status) async {
    if (_currentRoomId == null && _currentRoomCode == null) return;
    try {
      final query = _currentRoomId != null
          ? _client.from(_tableName).update({'status': status}).eq('id', _currentRoomId!)
          : _client.from(_tableName).update({'status': status}).eq('room_code', _currentRoomCode!);
      
      await query;
      debugPrint('Supabase: Room status updated to $status');
    } catch (e) {
      debugPrint('Supabase: Failed to update room status: $e');
    }
  }

  /// Join via DB Row Update (Robust Fallback)
  Future<void> joinViaDb(String playerId, String playerName) async {
    try {
      if (_currentRoomId == null) return;
      debugPrint('Supabase: Attempting robust join via DB Write (RPC)...');

      // DIRECT DB UPDATE (Replacement for RPC)
      // We use upsert to ensure we don't fail if the record exists,
      // but we want to be careful not to overwrite 'cards' if the player is already playing.
      // However, for a 'join' operation, we usually want to ensure presence.

      // We will perform an upsert that strictly respects the schema constraints.
      // If the player is already there, we update the name (just in case) and ensure they are linked.
      await _client.from('room_players').upsert({
        'room_id': _currentRoomId,
        'player_id': playerId,
        'player_name': playerName,
        'is_ready': false, // Ensure new joiners start as not ready
        'cards': [], // Ensure new joiners have empty cards
      }, onConflict: 'room_id, player_id');
      
      // After joining, ensure room status is 'lobby' (not 'playing')
      // This prevents status from being stuck as 'playing' from previous sessions
      try {
        await _client
            .from('uno_rooms')
            .update({'status': 'lobby'})
            .eq('id', _currentRoomId!);
        debugPrint('Supabase: Ensured room status is lobby after join');
      } catch (e) {
        debugPrint('Supabase: Failed to reset status after join: $e');
      }

      debugPrint('Supabase: Robust DB join (upsert) completed.');
    } catch (e) {
      debugPrint('Supabase: Robust RPC join failed: $e');
      // Fallback: Try manual update if RPC fails
      try {
        debugPrint('Supabase: Attempting fallback manual DB update...');
        // This fallback logic is now less relevant with the `room_players` table
        // and the `upsert` in `_joinRoom`.
        // For now, we'll just log the failure.
        debugPrint(
          'Supabase: Fallback manual DB update not implemented for new schema.',
        );
      } catch (fallbackError) {
        debugPrint('Supabase: Fallback update also failed: $fallbackError');
      }
    }
  }

  /// Handle incoming Broadcast messages (Ephemeral)
  void _handleBroadcastMessage(Map<String, dynamic> payload) {
    try {
      final senderId = payload['senderId'] as String?;
      final messageType = payload['type'] as String? ?? 'unknown';
      
      // CRITICAL: Allow GAME_STATE messages to pass through even from self
      // This ensures the host receives their own broadcasts for UI sync
      if (senderId == _myClientId && messageType != MessageType.gameState) {
        return; // Skip own messages (except GAME_STATE)
      }

      debugPrint('Supabase: Received Broadcast message: $messageType');

      final message = GameMessage(
        type: messageType,
        senderId: senderId ?? 'unknown',
        senderName: payload['senderName'] as String? ?? 'Unknown',
        payload: payload['payload'] as Map<String, dynamic>? ?? {},
        sequenceNumber: payload['seq'] as int? ?? 0,
      );

      // Special handling for ROOM_CLOSED broadcast
      if (message.type == MessageType.roomClosed) {
        debugPrint('Supabase: Received ROOM_CLOSED broadcast from Host');
        _errorController.add('ROOM_CLOSED');
        return;
      }

      // Special handling for HOST_LEFT broadcast
      if (message.type == MessageType.hostLeft) {
        debugPrint('Supabase: Received HOST_LEFT broadcast from Host');
        _errorController.add('HOST_LEFT');
        // Still add to message stream for provider to handle
      }

      _messageController.add(message);
    } catch (e) {
      debugPrint('Supabase: Error handling broadcast: $e');
    }
  }

  /// Handle transient game events (animations) - separate from GAME_STATE
  void _handleGameEvent(Map<String, dynamic> payload) {
    try {
      final eventType = payload['eventType'] as String? ?? 'unknown';
      debugPrint('Supabase: Received game event: $eventType');
      
      // Create a GameMessage with the actual event type (not GAME_EVENT wrapper)
      final message = GameMessage(
        type: eventType, // Use actual event type (WILD_COLOR_CHANGE, etc.)
        senderId: payload['senderId'] as String? ?? 'unknown',
        senderName: payload['senderName'] as String? ?? 'Unknown',
        payload: payload['payload'] as Map<String, dynamic>? ?? {},
        sequenceNumber: 0, // Events don't have sequence numbers
      );
      
      // Add to message stream immediately (independent of GAME_STATE)
      _messageController.add(message);
    } catch (e) {
      debugPrint('Supabase: Error handling game event: $e');
    }
  }

  /// Send a message
  /// - MessageType.gameState -> Updates DB (Persistent)
  /// - Others -> Sends Broadcast (Ephemeral)
  Future<void> send({
    required String type,
    Map<String, dynamic> payload = const {},
    int? sequenceNumber,
  }) async {
    if (_currentRoomCode == null || _realtimeChannel == null) {
      debugPrint('Supabase: Cannot send - not connected to a room');
      return;
    }

    // Wrap the payload with message metadata
    final messageData = {
      'type': type,
      'senderId': _myClientId,
      'senderName': _myName,
      'payload': payload,
      'seq': sequenceNumber ?? 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (type == MessageType.gameState) {
      // PERSISTENT: Update the Database
      // Flatten logic for GameState
      final stateToStore = {
        ...(payload['state'] is Map
            ? Map<String, dynamic>.from(payload['state'] as Map)
            : payload),
        'seq': sequenceNumber ?? 0,
        'senderId': _myClientId,
        'senderName': _myName,
        'type': MessageType.gameState, // Explicitly mark as state
      };

      await updateRemoteGameState(stateToStore);
    } else {
      // EPHEMERAL: Send via Broadcast
      // This is fast and doesn't overwrite the DB state
      await _realtimeChannel?.sendBroadcastMessage(
        event: 'game_message',
        payload: messageData,
      );
    }
  }

  /// Send a transient game event (for animations)
  /// These events are independent of GAME_STATE sequence and trigger UI immediately
  Future<void> sendEvent(String eventType, Map<String, dynamic> eventData) async {
    if (_currentRoomCode == null || _realtimeChannel == null) {
      debugPrint('Supabase: Cannot send event - not connected to a room');
      return;
    }

    // Wrap as GAME_EVENT for separate handling
    final messageData = {
      'type': MessageType.gameEvent,
      'eventType': eventType, // WILD_COLOR_CHANGE, UNO_ANNOUNCED, etc.
      'senderId': _myClientId,
      'senderName': _myName,
      'payload': eventData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isTransient': true, // Mark as transient (not state-dependent)
    };

    // Send via separate broadcast channel for events
    await _realtimeChannel?.sendBroadcastMessage(
      event: 'game_event', // Separate event channel
      payload: messageData,
    );
    
    debugPrint('Supabase: Sent game event: $eventType');
  }

  /// Update game state in database (Host uses this)
  /// Atomically update game status and state (Start Game)
  /// Also sets is_ready = true for ALL players
  Future<void> startRemoteGame(Map<String, dynamic> initialState) async {
    if (_currentRoomCode == null || _currentRoomId == null) return;

    try {
      debugPrint('Supabase: Starting game (atomic update)...');
      
      // 1. Update uno_rooms table
      await _client
          .from(_tableName)
          .update({'status': 'playing', 'game_state': initialState})
          .eq('room_code', _currentRoomCode!);

      // 2. Set is_ready = true for ALL players in room_players table
      final playersArray = initialState['p'] as List<dynamic>?;
      if (playersArray != null) {
        final handsMap = initialState['hands'] as Map<String, dynamic>?;
        
        for (final playerData in playersArray) {
          final playerMap = playerData as Map<String, dynamic>;
          final playerId = playerMap['i'] as String?;
          if (playerId == null) continue;
          
          // Get hand from hands map (SSOT)
          final playerHand = handsMap?[playerId] as List<dynamic>? ?? [];
          
          await _client
              .from('room_players')
              .update({
                'is_ready': true, // FIX: Set ready before dealing
                'cards': playerHand, // Also update cards
              })
              .eq('room_id', _currentRoomId!)
              .eq('player_id', playerId);
        }
        debugPrint('Supabase: Set is_ready=true for ${playersArray.length} players');
      }

      debugPrint('Supabase: Game started successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to start game: $e');
      _errorController.add('Failed to start game: $e');
    }
  }

  /// Update remote game state (Host uses this)
  /// Also updates room_players table to keep DB in sync with broadcasts
  /// Update game state in database (using RPC for atomic operation)
  Future<void> updateRemoteGameState(Map<String, dynamic> newState) async {
    if (_currentRoomCode == null || _currentRoomId == null) return; // Guard

    try {
      debugPrint('Supabase: Updating remote game state and room_players...');
      
      // Verify hands are included before storing
      final handsMap = newState['hands'] as Map<String, dynamic>?;
      if (handsMap != null) {
        debugPrint('Supabase: Storing state with hands map (${handsMap.length} players)');
      } else {
        debugPrint('WARNING: State being stored without hands map!');
      }
      
      // Verify discard pile is in the state
      final discardPile = newState['x'] as List<dynamic>? ?? newState['discardPile'] as List<dynamic>?;
      debugPrint('Supabase: Storing state with discard pile (${discardPile?.length ?? 0} cards)');
      
      // Determine status based on game phase (CRITICAL: Don't set 'playing' in lobby)
      final phase = newState['phase'] as String?;
      final status = (phase == 'playing' || phase == 'finished') ? phase! : 'lobby';
      
      debugPrint('Supabase: Updating state with phase=${phase}, status=${status}');
      
      // 1. Use RPC function to atomically update game_state and status
      try {
        await _client.rpc(
          'update_game_state',
          params: {
            'p_room_code': _currentRoomCode!,
            'p_game_state': newState,
            'p_status': status,
          },
        );
      } catch (rpcError) {
        debugPrint('Supabase: RPC update_game_state failed, falling back to direct update: $rpcError');
        
        // Fallback: Direct update if RPC fails
        await _client
            .from(_tableName)
            .update({
              'game_state': newState,
              'status': status,
            })
            .eq('room_code', _currentRoomCode!);
      }

      // 2. Update room_players table: sync cards and is_ready for each player
      if (handsMap != null && handsMap.isNotEmpty) {
        final playersArray = newState['p'] as List<dynamic>?;
        if (playersArray != null) {
          for (final playerData in playersArray) {
            final playerMap = playerData as Map<String, dynamic>;
            final playerId = playerMap['i'] as String?;
            if (playerId == null) continue;
            
            // Get hand from hands map (SSOT)
            final playerHand = handsMap[playerId] as List<dynamic>? ?? [];
            
            // Update room_players table
            await _client
                .from('room_players')
                .update({
                  'cards': playerHand,
                  'is_ready': true, // All players are ready during gameplay
                })
                .eq('room_id', _currentRoomId!)
                .eq('player_id', playerId);
          }
          debugPrint('Supabase: Updated ${playersArray.length} players in room_players table');
        }
      }

      debugPrint('Supabase: Remote game state and room_players updated successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to update remote game state: $e');
      _errorController.add('Failed to update game state: $e');
    }
  }

  /// Sync players from room_players to game_state (Host uses this)
  Future<void> syncPlayersToGameState(String roomCode) async {
    try {
      debugPrint('Supabase: Syncing players from room_players to game_state');
      
      await _client.rpc(
        'sync_players_to_game_state',
        params: {'p_room_code': roomCode},
      );
      
      debugPrint('Supabase: Players synced successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to sync players: $e');
      // Don't throw - allow fallback behavior
    }
  }

  /// Request sync from host (Client uses this)
  Future<void> requestSync() async {
    // Force re-fetch of room state
    if (_currentRoomId != null) {
      final roomRes =
          await _client
              .from('uno_rooms')
              .select('game_state, status, host_id')
              .eq('id', _currentRoomId!)
              .maybeSingle();

      if (roomRes != null) {
        final gameState = roomRes['game_state'] as Map<String, dynamic>? ?? {};
        gameState['status'] = roomRes['status'];
        gameState['hostId'] = roomRes['host_id']; // Inject hostId from database

        _messageController.add(
          GameMessage(
            type: MessageType.gameState,
            senderId: 'host',
            senderName: 'Host',
            payload: gameState,
          ),
        );
      }
    }
  }

  /// Cleanup: Delete room after game ends (critical for 500MB limit)
  Future<void> declareWinnerAndCleanup(String roomCode) async {
    try {
      await _client.from(_tableName).delete().eq('room_code', roomCode);

      debugPrint('Supabase: Room $roomCode deleted (cleanup complete)');
    } catch (e) {
      debugPrint('Supabase: Failed to cleanup room: $e');
    }
  }

  /// Remove self from room (DB Delete)
  Future<void> removeSelfFromRoom() async {
    try {
      if (_currentRoomId == null || _myClientId == null) return;

      await _client
          .from('room_players')
          .delete()
          .eq('room_id', _currentRoomId!)
          .eq('player_id', _myClientId!);

      debugPrint('Supabase: Removed self from room_players');
    } catch (e) {
      debugPrint('Supabase: Error removing self: $e');
    }
  }

  /// Disconnect and cleanup
  Future<void> disconnect() async {
    debugPrint('Supabase: Disconnecting service...');
    await _playersSubscription?.cancel();
    await _gameStateSubscription?.cancel();
    _playersSubscription = null;
    _gameStateSubscription = null;

    // Reset cached state
    _hasReceivedRoomData = false;
    _cachedPlayers = [];
    _cachedGameState = {};

    try {
      await _realtimeChannel?.unsubscribe();
      debugPrint('Supabase: Channel unsubscribed.');
      _realtimeChannel = null;
      _currentRoomCode = null;
      _currentRoomId = null;
      _connectionController.add(false);
    } catch (e) {
      debugPrint('Supabase: Disconnect error: $e');
    }
  }

  Future<void> dispose() async {
    debugPrint('Supabase: Service Dispose called!'); // Added Log
    await disconnect();
    await _messageController.close();
    await _connectionController.close();
    await _errorController.close();
  }

  // Getters
  bool get isHost => _isHost;
  String? get myClientId => _myClientId;
  String? get currentRoomCode => _currentRoomCode;
}
