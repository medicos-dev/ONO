import 'dart:async';
import 'package:zego_express_engine/zego_express_engine.dart';
import 'package:permission_handler/permission_handler.dart';

/// Singleton Voice Service for Zego Cloud Voice Chat
/// Handles engine lifecycle, room management, and microphone control
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  ZegoExpressEngine? _engine;
  bool _isEngineInitialized = false;
  bool _isEngineCreated = false;
  bool _isInRoom = false;
  bool _isMicMuted = true;
  String? _currentRoomID;
  String? _currentStreamID;
  static StreamController<bool>? _micStateController;
  static bool _isMicrophoneOn = false;

  static Stream<bool> get micStateStream {
    _micStateController ??= StreamController<bool>.broadcast();
    return _micStateController!.stream;
  }

  static bool get isMicrophoneOn => _isMicrophoneOn;

  /// Initialize Zego Engine once at app startup
  /// Must be called before any other voice operations
  static Future<void> initialize({
    required int appId,
    required String appSign,
  }) async {
    final instance = VoiceService();
    await instance.init(appId, appSign);
  }

  Future<bool> init(int appID, String appSign) async {
    if (_isEngineInitialized && _engine != null && _isEngineCreated) {
      return true;
    }

    try {
      final profile = ZegoEngineProfile(
        appID,
        ZegoScenario.General,
        appSign: appSign,
      );

      await ZegoExpressEngine.createEngineWithProfile(profile);

      _engine = ZegoExpressEngine.instance;
      
      if (_engine == null) {
        _isEngineCreated = false;
        return false;
      }
      
      _isEngineCreated = true;

      _engine!.setAudioRouteToSpeaker(true);

      ZegoExpressEngine.onRoomStreamUpdate = (
        String roomID,
        ZegoUpdateType updateType,
        List<ZegoStream> streamList,
        Map<String, dynamic> extendedData,
      ) {
        for (final stream in streamList) {
          if (updateType == ZegoUpdateType.Add) {
            _engine?.startPlayingStream(stream.streamID);
          } else if (updateType == ZegoUpdateType.Delete) {
            _engine?.stopPlayingStream(stream.streamID);
          }
        }
      };

      _isEngineInitialized = true;
      _isEngineCreated = true;
      return true;
    } catch (e) {
      _isEngineInitialized = false;
      _isEngineCreated = false;
      _engine = null;
      return false;
    }
  }

  bool get isEngineInitialized => _isEngineInitialized && _isEngineCreated && _engine != null;

  bool get isInRoom => _isInRoom;

  bool get isMicMuted => _isMicMuted;

  /// Join voice room using game room code
  static Future<bool> joinRoom(String roomID, String userID, String userName) async {
    final instance = VoiceService();
    return instance.joinVoiceRoom(roomID, userID, userName);
  }

  Future<bool> joinVoiceRoom(String roomID, String userID, String userName) async {
    if (!_isEngineCreated || _engine == null) {
      return false;
    }

    final permissionStatus = await Permission.microphone.request();
    if (!permissionStatus.isGranted) {
      return false;
    }

    try {
      if (_isInRoom && _currentRoomID != null) {
        await logoutRoom();
      }

      // Sanitize roomID for Zego (alphanumeric only, max 64 chars)
      final raw = roomID.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final sanitizedRoomID = raw.isNotEmpty
          ? (raw.length > 64 ? raw.substring(0, 64) : raw)
          : null;
      
      if (sanitizedRoomID == null) {
        return false;
      }

      _currentRoomID = sanitizedRoomID;

      final user = ZegoUser(userID, userName);
      final roomConfig = ZegoRoomConfig.defaultConfig();
      await _engine!.loginRoom(sanitizedRoomID, user, config: roomConfig);

      _currentStreamID = userID;
      await _engine!.startPublishingStream(_currentStreamID!);

      await _engine!.mutePublishStreamAudio(true);
      _isMicMuted = true;
      _isMicrophoneOn = false;
      _micStateController?.add(false);

      _isInRoom = true;
      return true;
    } catch (e) {
      _isInRoom = false;
      _currentRoomID = null;
      _currentStreamID = null;
      return false;
    }
  }

  /// Leave voice room and stop publishing
  static Future<void> leaveRoom() async {
    final instance = VoiceService();
    await instance.logoutRoom();
  }

  Future<void> logoutRoom() async {
    if (!isEngineInitialized || !_isInRoom) {
      return;
    }

    try {
      if (_currentStreamID != null) {
        await _engine!.stopPublishingStream();
        _currentStreamID = null;
      }

      if (_currentRoomID != null) {
        await _engine!.logoutRoom(_currentRoomID!);
      }
    } catch (e) {
    }

    _isInRoom = false;
    _currentRoomID = null;
    _isMicMuted = true;
    _isMicrophoneOn = false;
    _micStateController?.add(false);
  }

  /// Start speaking (push-to-talk)
  static Future<void> startSpeaking() async {
    final instance = VoiceService();
    await instance.toggleMic(true);
  }

  /// Stop speaking (push-to-talk)
  static Future<void> stopSpeaking() async {
    final instance = VoiceService();
    await instance.toggleMic(false);
  }

  Future<bool> toggleMic(bool isOn) async {
    if (!isEngineInitialized || !_isInRoom) {
      return false;
    }

    final permissionStatus = await Permission.microphone.status;
    if (!permissionStatus.isGranted) {
      final requested = await Permission.microphone.request();
      if (!requested.isGranted) {
        return false;
      }
    }

    try {
      await _engine!.mutePublishStreamAudio(!isOn);
      _isMicMuted = !isOn;
      _isMicrophoneOn = isOn;
      _micStateController?.add(isOn);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Destroy engine (only called on app termination)
  static Future<void> dispose() async {
    final instance = VoiceService();
    await instance.destroyEngine();
  }

  Future<void> destroyEngine() async {
    if (!isEngineInitialized) {
      return;
    }

    try {
      if (_isInRoom) {
        await logoutRoom();
      }

      ZegoExpressEngine.destroyEngine();
      _engine = null;
      _isEngineInitialized = false;
      _isEngineCreated = false;
      _micStateController?.close();
      _micStateController = null;
    } catch (e) {
    }
  }
}
