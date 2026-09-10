import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identificador estable del celular (sobrevive al cerrar sesión).
class DeviceIdentity {
  static const _key = 'install_id_v1';

  static Future<String> getInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.length >= 6) return saved;

    String generated;
    try {
      final plugin = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final info = await plugin.androidInfo;
        generated = 'and-${info.id}';
      } else if (!kIsWeb && Platform.isIOS) {
        final info = await plugin.iosInfo;
        generated = 'ios-${info.identifierForVendor ?? DateTime.now().microsecondsSinceEpoch}';
      } else {
        generated = 'web-${DateTime.now().microsecondsSinceEpoch}';
      }
    } catch (_) {
      generated = 'dev-${DateTime.now().microsecondsSinceEpoch}';
    }

    await prefs.setString(_key, generated);
    return generated;
  }

  /// Nuevo install_id (app como recién instalada).
  static Future<String> resetInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    final fresh =
        'reset-${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch % 9973}';
    await prefs.setString(_key, fresh);
    return fresh;
  }
}
