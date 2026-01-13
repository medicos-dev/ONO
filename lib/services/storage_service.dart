import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _playerIdKey = 'player_id';
  static const String _playerNameKey = 'player_name';
  static const String _roomCodeKey = 'room_code';

  static Future<String?> getPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playerIdKey);
  }

  static Future<void> savePlayerId(String playerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerIdKey, playerId);
  }

  static Future<String?> getPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playerNameKey);
  }

  static Future<void> savePlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerNameKey, name);
  }

  static Future<String?> getRoomCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roomCodeKey);
  }

  static Future<void> saveRoomCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomCodeKey, code);
  }

  static Future<void> clearRoomCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roomCodeKey);
  }
}
