import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'websocket_service.dart';

/// The player's chosen name — asked once by the first-launch intro, shown in
/// the home-menu greeting, and sent to the PC server so the player list reads
/// "Santosh" instead of a bare IP.
class PlayerProfile {
  PlayerProfile._();
  static final PlayerProfile instance = PlayerProfile._();

  static const _key = 'player_name';

  /// null = never set → the intro plays on next boot.
  final ValueNotifier<String?> name = ValueNotifier<String?>(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    name.value = prefs.getString(_key);
  }

  Future<void> save(String newName) async {
    name.value = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, newName);
    WebSocketService.instance.updatePlayerName(newName);
  }

  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
