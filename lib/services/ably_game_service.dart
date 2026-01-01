import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'message_types.dart';

/// Cost-optimized Ably Game Service using 1-letter JSON protocol
/// Protocol: t=type, v=value, n=sequenceNumber
class AblyGameService {
  static String get _apiKey => dotenv.env['ABLY_API_KEY'] ?? '';
  
  ably.Realtime? _realtime;
  ably.RealtimeChannel? _channel;
  String? _myClientId;
  String? _myName;
  bool _isHost = false;
  
  // Streams
  final StreamController<GameMessage> _messageController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  final StreamController<String> _errorController = StreamController.broadcast();
  final StreamController<PresenceEvent> _presenceController = StreamController.broadcast();
  
  Stream<GameMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;

  /// Connect to Ably and join the room channel
  Future<bool> connect({
    required String roomId,
    required String playerName,
    required String playerId,
    required bool isHost,
  }) async {
    _myClientId = playerId;
    _myName = playerName;
    _isHost = isHost;
    
    try {
      debugPrint('Ably: Connecting to room $roomId as ${isHost ? "HOST" : "CLIENT"}');
      
      // Initialize Ably with clientId for presence
      final clientOptions = ably.ClientOptions(
        key: _apiKey,
        clientId: playerId,
      );
      
      _realtime = ably.Realtime(options: clientOptions);
      
      // Listen for connection state changes
      _realtime!.connection.on().listen((stateChange) {
        debugPrint('Ably: Connection state: ${stateChange.current}');
        if (stateChange.current == ably.ConnectionState.connected) {
          _connectionController.add(true);
        } else if (stateChange.current == ably.ConnectionState.failed ||
                   stateChange.current == ably.ConnectionState.disconnected) {
          _connectionController.add(false);
        }
      });
      
      // Get channel
      final channelName = 'ono_room_$roomId';
      _channel = _realtime!.channels.get(channelName);
      
      // Subscribe to messages
      _channel!.subscribe().listen((ably.Message message) {
        _handleIncomingMessage(message);
      });
      
      // Subscribe to presence
      _channel!.presence.subscribe().listen((ably.PresenceMessage presenceMessage) {
        _handlePresence(presenceMessage);
      });
      
      // Enter presence with player data
      await _channel!.presence.enter({
        'name': playerName,
        'isHost': isHost,
      });
      
      debugPrint('Ably: Connected and entered presence');
      return true;
      
    } catch (e) {
      debugPrint('Ably: Connection failed: $e');
      _errorController.add('Connection failed: $e');
      return false;
    }
  }

  void _handleIncomingMessage(ably.Message message) {
    if (message.data == null) return;
    
    try {
      final data = message.data as Map;
      final type = data['t'] as String?;  // 1-letter: type
      final value = data['v'];             // Value/payload
      final seq = data['n'] as int?;       // Sequence number
      final senderId = data['s'] as String?;
      final senderName = data['sn'] as String?;
      
      if (senderId == _myClientId) return; // Ignore own messages
      
      // Map 1-letter codes to full message types
      final fullType = _expandType(type ?? '');
      
      final gameMessage = GameMessage(
        type: fullType,
        senderId: senderId ?? '',
        senderName: senderName ?? 'Unknown',
        payload: value is Map ? Map<String, dynamic>.from(value) : {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        sequenceNumber: seq ?? 0,
      );
      
      _messageController.add(gameMessage);
      
    } catch (e) {
      debugPrint('Ably: Failed to parse message: $e');
    }
  }

  void _handlePresence(ably.PresenceMessage presenceMessage) {
    debugPrint('Ably: Presence event: ${presenceMessage.action} - ${presenceMessage.clientId}');
    
    final presenceEvent = PresenceEvent(
      action: presenceMessage.action,
      clientId: presenceMessage.clientId ?? '',
      data: presenceMessage.data is Map 
          ? Map<String, dynamic>.from(presenceMessage.data as Map)
          : {},
    );
    
    _presenceController.add(presenceEvent);
  }

  /// Send message using 1-letter protocol
  void send({required String type, Map<String, dynamic> payload = const {}, int? sequenceNumber}) {
    if (_channel == null) {
      debugPrint('Ably: Cannot send - channel not connected');
      return;
    }
    
    // Compress type to 1-letter code
    final shortType = _compressType(type);
    
    final message = {
      't': shortType,              // Type (1-letter)
      'v': payload,                // Value
      'n': sequenceNumber ?? 0,    // Sequence number
      's': _myClientId,            // Sender ID
      'sn': _myName,               // Sender Name
    };
    
    _channel!.publish(name: 'game', data: message);
  }

  /// Compress full type to 1-letter code (cost optimization)
  String _compressType(String type) {
    switch (type) {
      case MessageType.gameState: return 's';
      case MessageType.joinRequest: return 'j';
      case MessageType.joinAccepted: return 'ja';
      case MessageType.moveAttempt: return 'm';
      case MessageType.drawRequest: return 'd';
      case MessageType.passTurn: return 'p';
      case MessageType.startGame: return 'sg';
      case MessageType.playerJoined: return 'pj';
      case MessageType.playerLeft: return 'pl';
      case MessageType.playerResign: return 'pr';
      case MessageType.gameOver: return 'go';
      case MessageType.syncRequest: return 'r';
      case MessageType.heartbeat: return 'h';
      case MessageType.unoCall: return 'u';
      case MessageType.prepareGame: return 'pg';
      case MessageType.ackReady: return 'ar';
      case MessageType.setPlayers: return 'sp';
      case MessageType.setDeck: return 'sd';
      case MessageType.setHand: return 'sh';
      case MessageType.goLive: return 'gl';
      case MessageType.reqResend: return 'rr';
      case MessageType.startSignal: return 'ss';
      case MessageType.readyToReceive: return 'rtr';
      case MessageType.gameSnapshot: return 'gs';
      case MessageType.snapshotAck: return 'sa';
      case MessageType.snapshotPart1: return 's1';
      case MessageType.snapshotPart2: return 's2';
      case MessageType.throwMultiple: return 'tm';
      case MessageType.error: return 'e';
      default: return type.substring(0, 2).toLowerCase();
    }
  }

  /// Expand 1-letter code to full type
  String _expandType(String code) {
    switch (code) {
      case 's': return MessageType.gameState;
      case 'j': return MessageType.joinRequest;
      case 'ja': return MessageType.joinAccepted;
      case 'm': return MessageType.moveAttempt;
      case 'd': return MessageType.drawRequest;
      case 'p': return MessageType.passTurn;
      case 'sg': return MessageType.startGame;
      case 'pj': return MessageType.playerJoined;
      case 'pl': return MessageType.playerLeft;
      case 'pr': return MessageType.playerResign;
      case 'go': return MessageType.gameOver;
      case 'r': return MessageType.syncRequest;
      case 'h': return MessageType.heartbeat;
      case 'u': return MessageType.unoCall;
      case 'pg': return MessageType.prepareGame;
      case 'ar': return MessageType.ackReady;
      case 'sp': return MessageType.setPlayers;
      case 'sd': return MessageType.setDeck;
      case 'sh': return MessageType.setHand;
      case 'gl': return MessageType.goLive;
      case 'rr': return MessageType.reqResend;
      case 'ss': return MessageType.startSignal;
      case 'rtr': return MessageType.readyToReceive;
      case 'gs': return MessageType.gameSnapshot;
      case 'sa': return MessageType.snapshotAck;
      case 's1': return MessageType.snapshotPart1;
      case 's2': return MessageType.snapshotPart2;
      case 'tm': return MessageType.throwMultiple;
      case 'e': return MessageType.error;
      default: return code;
    }
  }

  /// Request sync from host
  void requestSync() {
    send(type: MessageType.syncRequest);
  }

  /// Get current presence members
  Future<List<PresenceEvent>> getPresenceMembers() async {
    if (_channel == null) return [];
    
    try {
      final members = await _channel!.presence.get();
      return members.map((m) => PresenceEvent(
        action: ably.PresenceAction.present,
        clientId: m.clientId ?? '',
        data: m.data is Map ? Map<String, dynamic>.from(m.data as Map) : {},
      )).toList();
    } catch (e) {
      debugPrint('Ably: Failed to get presence: $e');
      return [];
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel?.presence.leave();
      _realtime?.close();
    } catch (e) {
      debugPrint('Ably: Disconnect error: $e');
    }
    _channel = null;
    _realtime = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _connectionController.close();
    await _errorController.close();
    await _presenceController.close();
  }

  // Getters
  bool get isHost => _isHost;
  String? get myClientId => _myClientId;
}

/// Presence event wrapper
class PresenceEvent {
  final ably.PresenceAction? action;
  final String clientId;
  final Map<String, dynamic> data;

  PresenceEvent({
    required this.action,
    required this.clientId,
    required this.data,
  });

  String get playerName => data['name'] as String? ?? 'Unknown';
  bool get isHost => data['isHost'] as bool? ?? false;
}
