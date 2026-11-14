import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'user_json';
  static const _familyKey = 'family_json';
  static const _userIdKey = 'user_id';
  static const _familyIdKey = 'family_id';
  static const _placesKey = 'places_json';
  static const _pendingPlacesKey = 'pending_places_json';
  static const _baseUrlKey = 'api_base_url';
  static const _deviceIdKey = 'device_id';
  static const _permissionsKey = 'permissions_ready';
  static const _pendingInviteKey = 'pending_invite';
  static const _boundNameKey = 'bound_user_name';
  static const _boundRoleKey = 'bound_user_role';
  static const _boundPhoneKey = 'bound_user_phone';
  static const _setupDoneKey = 'setup_checklist_done';
  static const _termsAcceptedKey = 'terms_accepted_v1';
  /// v2: la guía ahora incluye batería, hibernación y autostart.
  /// Quien ya vio la v1 vuelve a verla una vez.
  static const _keepAliveSeenKey = 'keep_alive_onboarding_seen_v2';
  static const _tripCreatorsKey = 'trip_creators_v1';
  static const _shownAlertsKey = 'shown_alert_ids_v1';
  static const _alertBaselineKey = 'alert_baseline_v1';
  static const _inflightAlertsKey = 'inflight_alert_ids_v1';
  static const _pendingEventsKey = 'pending_geofence_events_v1';
  static const _notificationsSinceKey = 'notifications_since_v1';

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
    await _writeUserIds(p, user: user, family: family);
    if (family != null) {
      await p.setString(_familyKey, jsonEncode(family));
    }
    final name = user['name'] as String?;
    final role = user['role'] as String?;
    final phone = user['phone'] as String?;
    if (name != null) await p.setString(_boundNameKey, name);
    if (role != null) await p.setString(_boundRoleKey, role);
    if (phone != null && phone.isNotEmpty) {
      await p.setString(_boundPhoneKey, phone);
    }
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final p = await _p;
    await p.setString(_userKey, jsonEncode(user));
    await _writeUserIds(p, user: user);
    final name = user['name'] as String?;
    final role = user['role'] as String?;
    final phone = user['phone'] as String?;
    if (name != null) await p.setString(_boundNameKey, name);
    if (role != null) await p.setString(_boundRoleKey, role);
    if (phone != null && phone.isNotEmpty) {
      await p.setString(_boundPhoneKey, phone);
    }
  }

  Future<void> saveFamily(Map<String, dynamic>? family) async {
    final p = await _p;
    if (family == null) {
      await p.remove(_familyKey);
      await p.remove(_familyIdKey);
    } else {
      await p.setString(_familyKey, jsonEncode(family));
      final id = family['id'] as String?;
      if (id != null && id.isNotEmpty) {
        await p.setString(_familyIdKey, id);
      }
    }
  }

  Future<void> savePlaces(
    List<Map<String, dynamic>> places, {
    List<Map<String, dynamic>>? pendingPlaces,
  }) async {
    final p = await _p;
    await p.setString(_placesKey, jsonEncode(places));
    if (pendingPlaces != null) {
      await p.setString(_pendingPlacesKey, jsonEncode(pendingPlaces));
    }
  }

  Future<String?> get accessToken async => (await _p).getString(_accessKey);
  Future<String?> get refreshToken async => (await _p).getString(_refreshKey);
  Future<String?> get userId async => (await _p).getString(_userIdKey);
  Future<String?> get familyId async => (await _p).getString(_familyIdKey);

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

  Future<List<Map<String, dynamic>>> get places async =>
      _decodeMapList((await _p).getString(_placesKey));

  Future<List<Map<String, dynamic>>> get pendingPlaces async =>
      _decodeMapList((await _p).getString(_pendingPlacesKey));

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

  Future<String?> get boundUserPhone async =>
      (await _p).getString(_boundPhoneKey);

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

  Future<void> setKeepAliveOnboardingSeen(bool value) async {
    await (await _p).setBool(_keepAliveSeenKey, value);
  }

  Future<bool> get keepAliveOnboardingSeen async =>
      (await _p).getBool(_keepAliveSeenKey) ?? false;

  Future<String?> get notificationsSince async {
    final p = await _p;
    await p.reload();
    return p.getString(_notificationsSinceKey);
  }

  Future<void> setNotificationsSince(String iso) async {
    await (await _p).setString(_notificationsSinceKey, iso);
  }

  Future<Set<String>> shownAlertIds() async {
    final p = await _p;
    await p.reload();
    return (p.getStringList(_shownAlertsKey) ?? const <String>[]).toSet();
  }

  Future<bool> hasAlertBaseline() async {
    final p = await _p;
    await p.reload();
    return p.getBool(_alertBaselineKey) ?? false;
  }

  Future<void> setAlertBaseline() async {
    await (await _p).setBool(_alertBaselineKey, true);
  }

  Future<void> markAlertShown(String id) => markAlertsShown([id]);

  Future<void> markAlertsShown(Iterable<String> ids) async {
    final incoming = ids.where((id) => id.isNotEmpty).toList();
    if (incoming.isEmpty) return;
    final p = await _p;
    await p.reload();
    final shown = (p.getStringList(_shownAlertsKey) ?? <String>[]).toList();
    for (final id in incoming) {
      if (!shown.contains(id)) shown.add(id);
    }
    final trimmed = shown.length > 400
        ? shown.sublist(shown.length - 400)
        : shown;
    await p.setStringList(_shownAlertsKey, trimmed);
    await _dropInflight(p, incoming.toSet());
  }

  /// Reserva el id unos segundos para que la pantalla y el servicio
  /// no muestren el mismo aviso a la vez. No lo marca como visto.
  Future<bool> tryClaimAlert(
    String id, {
    Duration hold = const Duration(seconds: 20),
  }) async {
    if (id.isEmpty) return false;
    final p = await _p;
    await p.reload();
    final shown = p.getStringList(_shownAlertsKey) ?? const <String>[];
    if (shown.contains(id)) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final inflight = _readInflight(p, now);
    if (inflight.containsKey(id)) return false;
    inflight[id] = now + hold.inMilliseconds;
    await p.setStringList(_inflightAlertsKey, _inflightRows(inflight));
    return true;
  }

  Map<String, int> _readInflight(SharedPreferences p, int nowMs) {
    final raw = p.getStringList(_inflightAlertsKey) ?? const <String>[];
    final out = <String, int>{};
    for (final row in raw) {
      final split = row.lastIndexOf('|');
      if (split <= 0) continue;
      final id = row.substring(0, split);
      final exp = int.tryParse(row.substring(split + 1)) ?? 0;
      if (id.isNotEmpty && exp > nowMs) out[id] = exp;
    }
    return out;
  }

  List<String> _inflightRows(Map<String, int> inflight) => [
        for (final entry in inflight.entries) '${entry.key}|${entry.value}',
      ];

  Future<void> _dropInflight(SharedPreferences p, Set<String> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final inflight = _readInflight(p, now);
    inflight.removeWhere((id, _) => ids.contains(id));
    await p.setStringList(_inflightAlertsKey, _inflightRows(inflight));
  }

  Future<List<Map<String, dynamic>>> pendingGeofenceEvents() async {
    final p = await _p;
    await p.reload();
    return _decodeMapList(p.getString(_pendingEventsKey));
  }

  Future<void> enqueuePendingGeofenceEvent(Map<String, dynamic> event) async {
    final all = await pendingGeofenceEvents();
    final key = _pendingEventKey(event);
    if (all.any((item) => _pendingEventKey(item) == key)) return;
    all.add(event);
    final trimmed = all.length > 30 ? all.sublist(all.length - 30) : all;
    await (await _p).setString(_pendingEventsKey, jsonEncode(trimmed));
  }

  Future<void> removePendingGeofenceEvent(Map<String, dynamic> event) async {
    final key = _pendingEventKey(event);
    final all = await pendingGeofenceEvents();
    all.removeWhere((item) => _pendingEventKey(item) == key);
    await (await _p).setString(_pendingEventsKey, jsonEncode(all));
  }

  String _pendingEventKey(Map<String, dynamic> event) =>
      '${event['type']}|${event['placeId']}|${event['createdAtMs']}';

  /// Cierra sesión pero NO borra la identidad del celular (un celular = una persona).
  Future<void> clearSession() async {
    final p = await _p;
    await p.remove(_accessKey);
    await p.remove(_refreshKey);
    await p.remove(_userKey);
    await p.remove(_familyKey);
    await p.remove(_userIdKey);
    await p.remove(_familyIdKey);
    await p.remove(_placesKey);
    await p.remove(_pendingPlacesKey);
    await p.remove(_permissionsKey);
    await p.remove(_pendingInviteKey);
    await p.remove(_setupDoneKey);
    await p.remove(_tripCreatorsKey);
    await p.remove(_pendingEventsKey);
    await p.remove(_notificationsSinceKey);
    // device_id, bound_*, termsAccepted, avisos ya mostrados y
    // keepAliveOnboardingSeen se conservan
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
    await p.remove(_boundPhoneKey);
    await p.remove(_deviceIdKey);
  }

  Future<void> setBoundIdentity({
    String? name,
    String? role,
    String? phone,
  }) async {
    final p = await _p;
    if (name != null && name.isNotEmpty) {
      await p.setString(_boundNameKey, name);
    }
    if (role != null && role.isNotEmpty) {
      await p.setString(_boundRoleKey, role);
    }
    if (phone != null && phone.isNotEmpty) {
      await p.setString(_boundPhoneKey, phone);
    }
  }

  Future<Map<String, dynamic>> _tripCreators() async {
    final raw = (await _p).getString(_tripCreatorsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTripCreator({
    required String tripId,
    required String createdById,
    required String createdByName,
    String? kidId,
  }) async {
    final all = await _tripCreators();
    final entry = {
      'createdById': createdById,
      'createdByName': createdByName,
      if (kidId != null) 'kidId': kidId,
    };
    all[tripId] = entry;
    if (kidId != null && kidId.isNotEmpty) {
      all['kid:$kidId'] = {...entry, 'tripId': tripId};
    }
    await (await _p).setString(_tripCreatorsKey, jsonEncode(all));
  }

  Future<Map<String, dynamic>?> tripCreator({
    String? tripId,
    String? kidId,
  }) async {
    final all = await _tripCreators();
    if (tripId != null && all[tripId] is Map) {
      return Map<String, dynamic>.from(all[tripId] as Map);
    }
    if (kidId != null && all['kid:$kidId'] is Map) {
      return Map<String, dynamic>.from(all['kid:$kidId'] as Map);
    }
    return null;
  }

  @Deprecated('Usar clearSession para no romper un-celular-un-rol')
  Future<void> clear() => clearSession();

  Future<void> _writeUserIds(
    SharedPreferences p, {
    required Map<String, dynamic> user,
    Map<String, dynamic>? family,
  }) async {
    final userId = user['id'] as String?;
    if (userId != null && userId.isNotEmpty) {
      await p.setString(_userIdKey, userId);
    }
    final familyId =
        (family?['id'] as String?) ?? (user['familyId'] as String?);
    if (familyId != null && familyId.isNotEmpty) {
      await p.setString(_familyIdKey, familyId);
    }
  }

  List<Map<String, dynamic>> _decodeMapList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
