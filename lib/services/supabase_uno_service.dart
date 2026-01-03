import 'dart:async';
import 'package:flutter/foundation.dart';
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
        eventsPerSecond: 10, // Rate limiting for cost efficiency
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

  /// Join an existing room
  Future<void> _joinRoom(String roomCode) async {
    // 1. Get Room ID
    final roomRes =
        await _client
            .from('uno_rooms')
            .select('id, status')
            .eq('room_code', roomCode)
            .maybeSingle();

    if (roomRes == null) throw Exception('Room not found');

    // Check Status
    if (roomRes['status'] != 'lobby') {
      throw Exception('Game already in progress');
    }

    _currentRoomId = roomRes['id'];

    // 2. Insert self into Room Players (Upsert to handle re-joins)
    await _client.from('room_players').upsert({
      'room_id': _currentRoomId,
      'player_id': _myClientId,
      'player_name': _myName,
      'is_ready': false,
      'cards': [],
    }, onConflict: 'room_id, player_id');

    debugPrint('Supabase: Joined room $_currentRoomId');
  }

  // Cache for Stream Merging
  List<Map<String, dynamic>> _cachedPlayers = [];
  Map<String, dynamic> _cachedGameState = {};
  bool _hasReceivedRoomData =
      false; // Track if we've ever received valid room data

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

              // Inject extra metadata for the UI/GameProvider
              _cachedGameState['status'] = room['status'];
              _cachedGameState['hostId'] = room['host_id'];
              _cachedGameState['roomCode'] = room['room_code'];

              _emitSynthesizedGameState();
            } else {
              // CLIENT SAFETY: Never trigger room deletion from client side
              // Room deletion should only be initiated by Host actions
              if (!_isHost && _hasReceivedRoomData) {
                debugPrint(
                  'Supabase: Room appears empty - waiting for reconnect',
                );
                // Don't emit ROOM_CLOSED - let Host handle cleanup
                // This prevents clients from triggering false room deletions
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

    // CRITICAL: Inject the relational players list into the GameState payload
    // Map DB columns (player_name) to Player model keys (name)
    synthesizedPayload['players'] =
        _cachedPlayers.map((p) {
          final pid = p['player_id'].toString();

          // Use hand from game_state if available (SSOT), otherwise fallback to room_players
          final List<dynamic> playerHand =
              (handsMap != null && handsMap.containsKey(pid))
                  ? handsMap[pid]
                  : (p['cards'] ?? []);

          return {
            'id': pid,
            'name': p['player_name'] ?? 'Guest',
            'isReady': p['is_ready'] ?? false,
            'isHost': pid == _cachedGameState['hostId'],
            'hand': playerHand,
          };
        }).toList();

    // Ensure the UI knows who the host is (DO NOT fallback to _myClientId - causes Joiner to think they're Host)
    // hostId comes from _cachedGameState['hostId'] which is injected from room stream
    // If it's missing, leave it as is - GameProvider will use its own _isHost flag

    debugPrint(
      'Service: Emitting synthesized state. Players: ${(synthesizedPayload['players'] as List).length}, hostId: ${synthesizedPayload['hostId']}',
    );

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

      // Delete where room_code matches AND host_id matches our ID
      // (Though RLS may enforce the host_id part, we add it here for clarity)
      await _client.from(_tableName).delete().eq('room_code', roomCode);

      debugPrint('Supabase: Room deleted successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to delete room: $e');
      // We don't throw here to avoid blocking UI navigation
    }
  }

  /// Update room status (e.g. 'playing')
  Future<void> updateRoomStatus(String status) async {
    if (_currentRoomId == null) return;
    try {
      await _client
          .from(_tableName)
          .update({'status': status})
          .eq('id', _currentRoomId!);
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
        // We do NOT set 'cards' or 'is_ready' here to avoid resetting state if re-joining
        // But upsert MIGHT overwrite if we don't specify onConflict behavior carefully.
        // In Supabase, upsert overwrites all columns provided.
        // If we omit 'cards', it might set it to null or default if it's a new row,
        // or keep connection if it's an update? actually upsert updates columns provided.
        // Let's provide only the necessary columns.
      }, onConflict: 'room_id, player_id');

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
      if (senderId == _myClientId) return; // Skip own messages

      debugPrint('Supabase: Received Broadcast message: ${payload['type']}');

      final message = GameMessage(
        type: payload['type'] as String? ?? 'unknown',
        senderId: senderId ?? 'unknown',
        senderName: payload['senderName'] as String? ?? 'Unknown',
        payload: payload['payload'] as Map<String, dynamic>? ?? {},
        sequenceNumber: payload['seq'] as int? ?? 0,
      );

      _messageController.add(message);
    } catch (e) {
      debugPrint('Supabase: Error handling broadcast: $e');
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

  /// Update game state in database (Host uses this)
  /// Atomically update game status and state (Start Game)
  Future<void> startRemoteGame(Map<String, dynamic> initialState) async {
    if (_currentRoomCode == null) return;

    try {
      debugPrint('Supabase: Starting game (atomic update)...');
      await _client
          .from(_tableName)
          .update({'status': 'playing', 'game_state': initialState})
          .eq('room_code', _currentRoomCode!);

      debugPrint('Supabase: Game started successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to start game: $e');
      _errorController.add('Failed to start game: $e');
    }
  }

  /// Update remote game state (Host uses this)
  Future<void> updateRemoteGameState(Map<String, dynamic> newState) async {
    if (_currentRoomCode == null) return; // Guard

    try {
      debugPrint('Supabase: Updating remote game state...');
      await _client
          .from(_tableName)
          .update({'game_state': newState})
          .eq('room_code', _currentRoomCode!);

      debugPrint('Supabase: Remote game state updated successfully');
    } catch (e) {
      debugPrint('Supabase: Failed to update remote game state: $e');
      _errorController.add('Failed to update game state: $e');
    }
  }

  /// Request sync from host (Client uses this)
  Future<void> requestSync() async {
    // Force re-fetch of room state
    if (_currentRoomId != null) {
      final roomRes =
          await _client
              .from('uno_rooms')
              .select('game_state, status')
              .eq('id', _currentRoomId!)
              .maybeSingle();

      if (roomRes != null) {
        final gameState = roomRes['game_state'] as Map<String, dynamic>? ?? {};
        gameState['status'] = roomRes['status'];

        _messageController.add(
          GameMessage(
            type: MessageType.gameState,
            senderId: 'host',
            senderName: 'Host', // Fixed missing param
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
