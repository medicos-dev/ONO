import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:peerdart/peerdart.dart';
import 'message_types.dart';

/// WebRTC P2P Network Service for ONO Card Game
/// Supports HOST mode (server) and CLIENT mode (joiner)
class PeerNetworkService {

  Peer? _peer;
  DataConnection? _hostConnection;           // CLIENT only: connection to host
  final List<DataConnection> _clients = [];  // HOST only: all client connections
  
  bool _isHost = false;
  String? _roomId;
  String? _playerId;
  String? _playerName;
  int _sequenceNumber = 0;
  
  // Voice support
  bool _isVoiceEnabled = false;
  
  // Stream controllers (same interface as HackChatService)
  final StreamController<GameMessage> _messageController = StreamController<GameMessage>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  /// Stream of game messages
  Stream<GameMessage> get messageStream => _messageController.stream;
  
  /// Stream of connection status
  Stream<bool> get connectionStream => _connectionController.stream;
  
  /// Stream of errors
  Stream<String> get errorStream => _errorController.stream;
  
  /// Whether we're currently connected
  bool get isConnected => _peer != null && (_isHost ? true : _hostConnection != null);
  
  /// Current room ID
  String? get roomId => _roomId;
  
  /// Current player name
  String? get playerName => _playerName;
  
  /// Current player ID
  String? get playerId => _playerId;
  
  /// Whether voice chat is enabled
  bool get isVoiceEnabled => _isVoiceEnabled;
  
  /// Toggle voice chat (stub for future implementation)
  Future<void> toggleVoice(bool enable) async {
    _isVoiceEnabled = enable;
    debugPrint('P2P: Voice chat toggled to $enable');
    // Future: Initialize local media stream requesting audio: true
  }
  
  /// Warm up the Render server to prevent cold-start delays
  Future<void> _warmUpServer() async {
    final url = Uri.parse('https://ono-x1v9.onrender.com/');
    debugPrint('P2P: Warming up server at $url...');
    
    // Fire and forget 3 pings with delay
    for (int i = 0; i < 3; i++) {
      try {
        // Simple GET request to trigger load balancer
        await http.get(url).timeout(const Duration(seconds: 2));
        debugPrint('P2P: Wake-up ping ${i+1} sent');
      } catch (_) {
        // Ignore errors, we just want to hit the endpoint
      }
      if (i < 2) await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// Connect to a room (creates as HOST or joins as CLIENT)
  Future<bool> connect({
    required String roomId,
    required String playerName,
    required String playerId,
    required bool isHost,
  }) async {
    try {
      await disconnect();
      
      // Start server warm-up (fire and forget to not block UI, but we await briefly if needed)
      // Actually, we should await it partially or run it in parallel if we want speed.
      // But user requested: "In the connect method... add a Warm-up phase"
      // Since Render can take 30s, we shouldn't block the WHOLE time, but the pings are fast.
      await _warmUpServer();
      
      // Wait briefly for PeerJS server to release the old ID
      await Future.delayed(const Duration(milliseconds: 500));
      
      _roomId = roomId;
      _playerName = playerName;
      _playerId = playerId;
      _isHost = isHost;
      _sequenceNumber = 0;
      
      if (isHost) {
        return await _connectAsHost(roomId);
      } else {
        return await _connectAsClient(roomId);
      }
    } catch (e) {
      debugPrint('P2P: Connection error: $e');
      _errorController.add('Connection failed: $e');
      return false;
    }
  }

  /// HOST MODE: Create peer with room ID and listen for connections
  Future<bool> _connectAsHost(String roomId) async {
    final completer = Completer<bool>();
    
    final peerId = 'ono_$roomId';
    debugPrint('HOST: Creating peer with ID: $peerId');
    
    _peer = Peer(
      id: peerId,
      options: PeerOptions(
        debug: LogLevel.All,
        host: 'ono-x1v9.onrender.com',
        port: 443,
        secure: true,
        path: '/',
        key: 'peerjs',
        config: {
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun2.l.google.com:19302'},
            {'urls': 'stun:stun3.l.google.com:19302'},
            {'urls': 'stun:stun4.l.google.com:19302'},
          ],
          'sdpSemantics': 'unified-plan',
        },
      ),
    );
    
    // Handle peer open (ready to receive connections)
    _peer!.on<String>('open').listen((id) {
      debugPrint('HOST: Peer ready with ID: $id');
      _connectionController.add(true);
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    });
    
    // Handle incoming connections
    _peer!.on<DataConnection>('connection').listen((conn) {
      debugPrint('HOST: New client connecting: ${conn.peer}');
      _handleNewClient(conn);
    });
    
    // Handle peer errors
    _peer!.on('error').listen((error) {
      debugPrint('HOST: Peer error: $error');
      _errorController.add('Peer error: $error');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    
    // Handle peer close
    _peer!.on('close').listen((_) {
      debugPrint('HOST: Peer closed');
      _connectionController.add(false);
    });
    
    // Timeout after 15 seconds (increased for public server latency)
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('HOST: Connection timeout waiting for OPEN event');
        _errorController.add('Connection timeout');
        return false;
      },
    );
  }

  /// CLIENT MODE: Create peer and connect to host
  Future<bool> _connectAsClient(String roomId) async {
    final completer = Completer<bool>();
    
    debugPrint('CLIENT: Creating peer and connecting to host: ono_$roomId');
    
    _peer = Peer(
      options: PeerOptions(
        debug: LogLevel.All,
        host: 'ono-x1v9.onrender.com',
        port: 443,
        secure: true,
        path: '/',
        key: 'peerjs',
        config: {
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun2.l.google.com:19302'},
            {'urls': 'stun:stun3.l.google.com:19302'},
            {'urls': 'stun:stun4.l.google.com:19302'},
          ],
          'sdpSemantics': 'unified-plan',
        },
      ),
    );
    
    // Handle peer open
    _peer!.on<String>('open').listen((id) {
      debugPrint('CLIENT: Peer ready with ID: $id');
      
      // Now connect to host
      _hostConnection = _peer!.connect('ono_$roomId');
      
      // Handle connection open
      _hostConnection!.on('open').listen((_) {
        debugPrint('CLIENT: Connected to host!');
        _connectionController.add(true);
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      });
      
      // Handle incoming data from host
      _hostConnection!.on<dynamic>('data').listen((data) {
        _handleIncomingData(data);
      });
      
      // Handle connection close
      _hostConnection!.on('close').listen((_) {
        debugPrint('CLIENT: Disconnected from host');
        _connectionController.add(false);
        _errorController.add('Host disconnected');
      });
      
      // Handle connection error
      _hostConnection!.on('error').listen((error) {
        debugPrint('CLIENT: Connection error: $error');
        _errorController.add('Connection error: $error');
      });
    });
    
    // Handle peer errors
    _peer!.on('error').listen((error) {
      debugPrint('CLIENT: Peer error: $error');
      _errorController.add('Peer error: $error');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    
    // Timeout after 15 seconds (increased for public server latency)
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('CLIENT: Connection timeout waiting for OPEN/CONNECTION');
        _errorController.add('Connection timeout');
        return false;
      },
    );
  }

  /// Handle new client connection (HOST only)
  void _handleNewClient(DataConnection conn) {
    // Setup data listener
    conn.on<dynamic>('data').listen((data) {
      _handleIncomingData(data);
    });
    
    // Handle client disconnect
    conn.on('close').listen((_) {
      debugPrint('HOST: Client disconnected: ${conn.peer}');
      _clients.remove(conn);
    });
    
    // Handle connection errors
    conn.on('error').listen((error) {
      debugPrint('HOST: Client connection error: $error');
    });
    
    // Wait for connection to open before adding to list
    conn.on('open').listen((_) {
      debugPrint('HOST: Client connection ready: ${conn.peer}');
      _clients.add(conn);
    });
    
    // If already open, add immediately
    if (conn.open) {
      _clients.add(conn);
    }
  }

  /// Handle incoming data (both HOST and CLIENT)
  void _handleIncomingData(dynamic data) {
    try {
      final String jsonStr = data is String ? data : data.toString();
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      
      // Check if it's an ONO game message
      if (GameMessage.isOnoMessage(decoded)) {
        final message = GameMessage.fromJson(decoded);
        
        // Don't echo our own messages back
        if (message.senderId != _playerId) {
          _messageController.add(message);
        }
      }
    } catch (e) {
      debugPrint('P2P: Failed to parse message: $e');
    }
  }

  /// Disconnect from the current room
  Future<void> disconnect() async {
    debugPrint('P2P: Disconnecting...');
    
    // Close all client connections (HOST)
    for (final conn in _clients) {
      conn.close();
    }
    _clients.clear();
    
    // Close host connection (CLIENT)
    _hostConnection?.close();
    _hostConnection = null;
    
    // Destroy peer
    _peer?.dispose();
    _peer = null;
    
    _roomId = null;
    _playerName = null;
    _playerId = null;
    _sequenceNumber = 0;
    _isHost = false;
    
    _connectionController.add(false);
  }

  /// Send a game message with sequence number
  void sendMessage(GameMessage message) {
    if (_peer == null) return;
    
    try {
      _sequenceNumber++;
      final messageWithSeq = GameMessage(
        type: message.type,
        senderId: message.senderId,
        senderName: message.senderName,
        payload: message.payload,
        timestamp: message.timestamp,
        sequenceNumber: _sequenceNumber,
      );
      
      final messageJson = json.encode(messageWithSeq.toJson());
      
      if (_isHost) {
        // HOST: Broadcast to all clients
        _sendToAllClients(messageJson);
      } else {
        // CLIENT: Send to host
        _sendToHost(messageJson);
      }
    } catch (e) {
      debugPrint('P2P: Send failed: $e');
      _errorController.add('Send failed: $e');
    }
  }

  /// Send a raw game message with type and payload
  void send({
    required String type,
    Map<String, dynamic> payload = const {},
  }) {
    if (_playerId == null || _playerName == null) return;
    
    sendMessage(GameMessage(
      type: type,
      senderId: _playerId!,
      senderName: _playerName!,
      payload: payload,
    ));
  }

  /// Send snapshot immediately (no buffering needed for P2P)
  void sendSnapshot(Map<String, dynamic> snapshotData) {
    if (_playerId == null || _playerName == null) return;
    
    debugPrint('P2P: Sending snapshot immediately');
    
    sendMessage(GameMessage(
      type: MessageType.gameSnapshot,
      senderId: _playerId!,
      senderName: _playerName!,
      payload: snapshotData,
    ));
  }

  /// Send snapshot immediately (same as sendSnapshot for P2P)
  void sendSnapshotImmediate(Map<String, dynamic> snapshotData) {
    sendSnapshot(snapshotData);
  }

  /// Request sync from host (for clients)
  void requestSync() {
    send(type: MessageType.syncRequest);
  }

  /// Send data to all connected clients (HOST only)
  void _sendToAllClients(String data) {
    if (!_isHost) return;
    
    debugPrint('HOST: Broadcasting to ${_clients.length} clients');
    
    for (final conn in _clients) {
      if (conn.open) {
        try {
          conn.send(data);
        } catch (e) {
          debugPrint('HOST: Failed to send to client ${conn.peer}: $e');
        }
      }
    }
  }

  /// Send data to host (CLIENT only)
  void _sendToHost(String data) {
    if (_isHost || _hostConnection == null) return;
    
    if (_hostConnection!.open) {
      try {
        _hostConnection!.send(data);
      } catch (e) {
        debugPrint('CLIENT: Failed to send to host: $e');
      }
    }
  }

  /// STUB: Pause heartbeats (not needed for P2P, kept for compatibility)
  void pauseHeartbeats() {
    // No-op: P2P doesn't need heartbeats
  }

  /// STUB: Resume heartbeats (not needed for P2P, kept for compatibility)
  void resumeHeartbeats() {
    // No-op: P2P doesn't need heartbeats
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
    _errorController.close();
  }
}
