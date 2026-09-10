import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'user_json';
  static const _familyKey = 'family_json';
  static const _baseUrlKey = 'api_base_url';
  static const _deviceIdKey = 'device_id';
  static const _permissionsKey = 'permissions_ready';
  static const _pendingInviteKey = 'pending_invite';
  static const _boundNameKey = 'bound_user_name';
  static const _boundRoleKey = 'bound_user_role';
  static const _setupDoneKey = 'setup_checklist_done';
  static const _termsAcceptedKey = 'terms_accepted_v1';

  Future<SharedPreferences> get _p async => SharedPreferences.getInstance();

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> user,
    Map<String, dynamic>? family,
  }) async {
    final p = await _p;
    await p.setString(_accessKey, accessToken);
    await p.setString(_refreshKey, refreshToken);
    await p.setString(_userKey, jsonEncode(user));
    if (family != null) {
      await p.setString(_familyKey, jsonEncode(family));
    }
    final name = user['name'] as String?;
    final role = user['role'] as String?;
    if (name != null) await p.setString(_boundNameKey, name);
    if (role != null) await p.setString(_boundRoleKey, role);
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final p = await _p;
    await p.setString(_userKey, jsonEncode(user));
    final name = user['name'] as String?;
    final role = user['role'] as String?;
    if (name != null) await p.setString(_boundNameKey, name);
    if (role != null) await p.setString(_boundRoleKey, role);
  }

  Future<void> saveFamily(Map<String, dynamic>? family) async {
    final p = await _p;
    if (family == null) {
      await p.remove(_familyKey);
    } else {
      await p.setString(_familyKey, jsonEncode(family));
    }
  }

  Future<String?> get accessToken async => (await _p).getString(_accessKey);
  Future<String?> get refreshToken async => (await _p).getString(_refreshKey);

  Future<Map<String, dynamic>?> get user async {
    final raw = (await _p).getString(_userKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<Map<String, dynamic>?> get family async {
    final raw = (await _p).getString(_familyKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> setBaseUrl(String url) async {
    await (await _p).setString(_baseUrlKey, url);
  }

  Future<String?> get baseUrl async => (await _p).getString(_baseUrlKey);

  Future<void> setDeviceId(String id) async {
    await (await _p).setString(_deviceIdKey, id);
  }

  Future<String?> get deviceId async => (await _p).getString(_deviceIdKey);

  Future<void> setPermissionsReady(bool value) async {
    await (await _p).setBool(_permissionsKey, value);
  }

  Future<bool> get permissionsReady async =>
      (await _p).getBool(_permissionsKey) ?? false;

  Future<void> setPendingInvite(String? token) async {
    final p = await _p;
    if (token == null || token.isEmpty) {
      await p.remove(_pendingInviteKey);
    } else {
      await p.setString(_pendingInviteKey, token);
    }
  }

  Future<String?> get pendingInvite async =>
      (await _p).getString(_pendingInviteKey);

  Future<String?> get boundUserName async =>
      (await _p).getString(_boundNameKey);

  Future<String?> get boundUserRole async =>
      (await _p).getString(_boundRoleKey);

  Future<void> setSetupChecklistDone(bool value) async {
    await (await _p).setBool(_setupDoneKey, value);
  }

  /// null = instalación anterior a esta función (no forzar checklist).
  Future<bool?> get setupChecklistDoneFlag async =>
      (await _p).getBool(_setupDoneKey);

  Future<bool> get setupChecklistDone async =>
      (await _p).getBool(_setupDoneKey) ?? true;

  Future<void> setTermsAccepted(bool value) async {
    await (await _p).setBool(_termsAcceptedKey, value);
  }

  Future<bool> get termsAccepted async =>
      (await _p).getBool(_termsAcceptedKey) ?? false;

  /// Cierra sesión pero NO borra la identidad del celular (un celular = una persona).
  Future<void> clearSession() async {
    final p = await _p;
    await p.remove(_accessKey);
    await p.remove(_refreshKey);
    await p.remove(_userKey);
    await p.remove(_familyKey);
    await p.remove(_permissionsKey);
    await p.remove(_pendingInviteKey);
    await p.remove(_setupDoneKey);
    // device_id, bound_* y termsAccepted se conservan
  }

  /// Borra identidad local (como app recién instalada). Conserva URL del servidor.
  Future<void> clearAllLocal({bool keepBaseUrl = true}) async {
    final p = await _p;
    final url = keepBaseUrl ? p.getString(_baseUrlKey) : null;
    await p.clear();
    if (url != null && url.isNotEmpty) {
      await p.setString(_baseUrlKey, url);
    }
  }

  Future<void> clearBoundIdentity() async {
    final p = await _p;
    await p.remove(_boundNameKey);
    await p.remove(_boundRoleKey);
    await p.remove(_deviceIdKey);
  }

  Future<void> setBoundIdentity({String? name, String? role}) async {
    final p = await _p;
    if (name != null && name.isNotEmpty) {
      await p.setString(_boundNameKey, name);
    }
    if (role != null && role.isNotEmpty) {
      await p.setString(_boundRoleKey, role);
    }
  }

  @Deprecated('Usar clearSession para no romper un-celular-un-rol')
  Future<void> clear() => clearSession();
}
