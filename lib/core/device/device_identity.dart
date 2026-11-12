import 'package:shared_preferences/shared_preferences.dart';

/// Identificador de esta instalación. Se guarda en el celular y vuelve a
/// nacer si se borran los datos o se reinstala (el almacenamiento local se va).
///
/// No usa Build.ID: en Android ese valor es la etiqueta del sistema
/// (por ejemplo TP1A.220624.014) y es igual en todos los equipos del mismo
/// modelo con la misma actualización.
class DeviceIdentity {
  static const _key = 'install_id_v1';

  /// Ids viejos `and-<Build.ID>`. Chocan entre celulares del mismo modelo.
  static bool isLegacyBuildId(String id) => id.startsWith('and-');

  /// Mismo formato que [resetInstallId].
  static String newInstallId() {
    final now = DateTime.now();
    return 'reset-${now.microsecondsSinceEpoch}-${now.millisecondsSinceEpoch % 9973}';
  }

  static Future<String> getInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null &&
        saved.length >= 6 &&
        !isLegacyBuildId(saved)) {
      return saved;
    }

    final fresh = newInstallId();
    await prefs.setString(_key, fresh);
    return fresh;
  }

  /// Nuevo install_id (app como recién instalada).
  static Future<String> resetInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    final fresh = newInstallId();
    await prefs.setString(_key, fresh);
    return fresh;
  }
}
