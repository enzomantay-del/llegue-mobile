import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  /// Preferí la URL guardada en el celular (Servidor).
  /// Si no hay, usa la IP local de la PC. Con hosting, pegá https://….onrender.com una vez.
  static const defaultBaseUrl = 'https://llegue-api.onrender.com';
  static const lanFallbackUrl = 'http://192.168.0.111:8787';
  static const _timeout = Duration(seconds: 25);

  String baseUrl;
  String? accessToken;

  Uri _u(String path) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'content-type': 'application/json'};
    if (auth && accessToken != null) {
      h['authorization'] = 'Bearer $accessToken';
    }
    return h;
  }

  Future<http.Response> _send(Future<http.Response> future) async {
    try {
      return await future.timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        'No pudimos conectar. Revisá tu conexión a internet e intentá de nuevo.',
      );
    } on ApiException {
      rethrow;
    } on http.ClientException catch (_) {
      throw ApiException(
        'No pudimos conectar. Revisá tu conexión a internet e intentá de nuevo.',
      );
    } catch (_) {
      throw ApiException(
        'No pudimos conectar. Revisá tu conexión a internet e intentá de nuevo.',
      );
    }
  }

  Future<http.Response> _postJson(String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    Future<http.Response> once(String root) {
      final base = root.replaceAll(RegExp(r'/$'), '');
      return http.post(
        Uri.parse('$base$path'),
        headers: _headers(auth: auth),
        body: jsonEncode(body),
      );
    }

    try {
      return await _send(once(baseUrl));
    } on ApiException {
      // Si falla el túnel/público, probá la red local de la PC.
      if (baseUrl != lanFallbackUrl && baseUrl != defaultBaseUrl) {
        rethrow;
      }
      final alt = baseUrl == defaultBaseUrl ? lanFallbackUrl : defaultBaseUrl;
      try {
        final res = await _send(once(alt));
        baseUrl = alt;
        return res;
      } on ApiException {
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> _json(
    http.Response res, {
    String fallback = 'Algo falló. Probá de nuevo.',
  }) async {
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }
    if (res.statusCode >= 400) {
      throw ApiException(body['error'] as String? ?? fallback);
    }
    return body;
  }

  Future<Map<String, dynamic>> requestOtp(String phone) async {
    final res = await _postJson('/auth/request-otp', {'phone': phone});
    return _json(res);
  }

  Future<Map<String, dynamic>> requestEmailOtp(String email) async {
    final res = await _send(http.post(
      _u('/auth/request-email-otp'),
      headers: _headers(),
      body: jsonEncode({'email': email}),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> registerTitular({
    required String name,
    String? birthDate,
    required String email,
    required String emailCode,
    required String phone,
    required String phoneCode,
    required String installId,
    String platform = 'android',
  }) async {
    final res = await _send(http.post(
      _u('/auth/register-titular'),
      headers: _headers(),
      body: jsonEncode({
        'name': name,
        if (birthDate != null) 'birthDate': birthDate,
        'email': email,
        'emailCode': emailCode,
        'phone': phone,
        'phoneCode': phoneCode,
        'installId': installId,
        'platform': platform,
      }),
    ));
    return _json(res, fallback: 'No pudimos crear la cuenta.');
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
    String? name,
    required String installId,
    String platform = 'android',
  }) async {
    final res = await _send(http.post(
      _u('/auth/verify-otp'),
      headers: _headers(),
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'installId': installId,
        'platform': platform,
        if (name != null) 'name': name,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> loginWithPin({
    required String inviteTokenOrCode,
    required String pin,
    required String installId,
    String platform = 'android',
  }) async {
    final res = await _send(http.post(
      _u('/auth/login-with-pin'),
      headers: _headers(),
      body: jsonEncode({
        'inviteTokenOrCode': inviteTokenOrCode,
        'pin': pin,
        'installId': installId,
        'platform': platform,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> lookupInstall(String installId) async {
    final res = await _send(http.get(
      _u('/devices/lookup?installId=${Uri.encodeComponent(installId)}'),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _send(
      http.get(_u('/auth/me'), headers: _headers(auth: true)),
    );
    return _json(res);
  }

  Future<Map<String, dynamic>> getAccountProfile() async {
    final res = await _send(
      http.get(_u('/account/profile'), headers: _headers(auth: true)),
    );
    return _json(res);
  }

  Future<Map<String, dynamic>> updateAccountProfile(
    Map<String, dynamic> body,
  ) async {
    final res = await _send(http.patch(
      _u('/account/profile'),
      headers: _headers(auth: true),
      body: jsonEncode(body),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> createFamily({
    required String name,
    required String relationshipLabel,
    required String displayName,
    required String installId,
    String platform = 'android',
  }) async {
    final res = await _send(http.post(
      _u('/families'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'name': name,
        'relationshipLabel': relationshipLabel,
        'displayName': displayName,
        'installId': installId,
        'platform': platform,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> createInvitation({
    required String name,
    required String role,
    String? pin,
    String? publicBaseUrl,
  }) async {
    final res = await _send(http.post(
      _u('/invitations'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'name': name,
        'role': role,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
        if (publicBaseUrl != null && publicBaseUrl.isNotEmpty)
          'publicBaseUrl': publicBaseUrl,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> getInvitation(String token) async {
    final res = await _send(http.get(_u('/invitations/$token')));
    return _json(res);
  }

  Future<Map<String, dynamic>> acceptInvitation(
    String token, {
    String? pin,
    required String installId,
    String platform = 'android',
  }) async {
    final res = await _send(http.post(
      _u('/invitations/$token/accept'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'installId': installId,
        'platform': platform,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> registerDevice({
    required String platform,
    required String installId,
    String? pushToken,
  }) async {
    final res = await _send(http.post(
      _u('/devices/register'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'platform': platform,
        'installId': installId,
        if (pushToken != null) 'pushToken': pushToken,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> patchPermissions({
    required String locationPermission,
    required String notificationsPermission,
    String? deviceId,
    bool? locationOk,
  }) async {
    final res = await _send(http.patch(
      _u('/devices/me/permissions'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'locationPermission': locationPermission,
        'notificationsPermission': notificationsPermission,
        if (deviceId != null) 'deviceId': deviceId,
        if (locationOk != null) 'locationOk': locationOk,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> reportBattery({
    required int batteryLevel,
    String? deviceId,
  }) async {
    final res = await _send(http.patch(
      _u('/devices/me/battery'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'batteryLevel': batteryLevel,
        if (deviceId != null) 'deviceId': deviceId,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> reportPresence({
    required String state,
    String? deviceId,
    bool immediate = false,
  }) async {
    final res = await _send(http.patch(
      _u('/devices/me/presence'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'state': state,
        'immediate': immediate,
        if (deviceId != null) 'deviceId': deviceId,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> familyStatus() async {
    final res = await _send(http.get(
      _u('/family/status'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> listPlaces({bool includePending = false}) async {
    final q = includePending ? '?includePending=1' : '';
    final res = await _send(http.get(
      _u('/places$q'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> createPlace({
    required String name,
    required double lat,
    required double lng,
    String type = 'favorite',
    int radiusM = 60,
  }) async {
    final res = await _send(http.post(
      _u('/places'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'name': name,
        'lat': lat,
        'lng': lng,
        'type': type,
        'radiusM': radiusM,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> suggestPlace({
    required String name,
    required double lat,
    required double lng,
  }) async {
    final res = await _send(http.post(
      _u('/places/suggest'),
      headers: _headers(auth: true),
      body: jsonEncode({'name': name, 'lat': lat, 'lng': lng}),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> approvePlace(String placeId) async {
    final res = await _send(http.post(
      _u('/places/$placeId/approve'),
      headers: _headers(auth: true),
      body: '{}',
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> deletePlace(String placeId) async {
    final res = await _send(http.delete(
      _u('/places/$placeId'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> updatePlace({
    required String placeId,
    required String name,
    required double lat,
    required double lng,
    String type = 'favorite',
    int radiusM = 60,
  }) async {
    final res = await _send(http.patch(
      _u('/places/$placeId'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'name': name,
        'lat': lat,
        'lng': lng,
        'type': type,
        'radiusM': radiusM,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> listRoutines({String? kidId}) async {
    final q = kidId != null ? '?kidId=$kidId' : '';
    final res = await _send(http.get(
      _u('/routines$q'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> createRoutine({
    required String kidId,
    required String placeId,
    required String label,
    required List<int> daysOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final res = await _send(http.post(
      _u('/routines'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'kidId': kidId,
        'placeId': placeId,
        'label': label,
        'daysOfWeek': daysOfWeek,
        'startTime': startTime,
        'endTime': endTime,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> deleteRoutine(String routineId) async {
    final res = await _send(http.delete(
      _u('/routines/$routineId'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> updateRoutine({
    required String routineId,
    required String kidId,
    required String placeId,
    required String label,
    required List<int> daysOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final res = await _send(http.patch(
      _u('/routines/$routineId'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'kidId': kidId,
        'placeId': placeId,
        'label': label,
        'daysOfWeek': daysOfWeek,
        'startTime': startTime,
        'endTime': endTime,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> getAlertPrefs() async {
    final res = await _send(http.get(
      _u('/alert-prefs'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> putAlertPrefs(Map<String, bool> prefs) async {
    final res = await _send(http.put(
      _u('/alert-prefs'),
      headers: _headers(auth: true),
      body: jsonEncode({'prefs': prefs}),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> activeTrip({String? kidId}) async {
    final q = kidId != null ? '?kidId=$kidId' : '';
    final res = await _send(http.get(
      _u('/trips/active$q'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> startTrip({
    String? kidId,
    String? destinationPlaceId,
    String? expectedReturnAt,
    String? kind,
    bool? forceNotify,
  }) async {
    final res = await _send(http.post(
      _u('/trips'),
      headers: _headers(auth: true),
      body: jsonEncode({
        if (kidId != null) 'kidId': kidId,
        if (destinationPlaceId != null) 'destinationPlaceId': destinationPlaceId,
        if (expectedReturnAt != null) 'expectedReturnAt': expectedReturnAt,
        if (kind != null) 'kind': kind,
        if (forceNotify != null) 'forceNotify': forceNotify,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> patchTrip(
    String tripId, {
    String? action,
    String? destinationPlaceId,
    String? expectedReturnAt,
    bool clearDestination = false,
  }) async {
    final res = await _send(http.patch(
      _u('/trips/$tripId'),
      headers: _headers(auth: true),
      body: jsonEncode({
        if (action != null) 'action': action,
        if (clearDestination) 'destinationPlaceId': null,
        if (!clearDestination && destinationPlaceId != null)
          'destinationPlaceId': destinationPlaceId,
        if (expectedReturnAt != null) 'expectedReturnAt': expectedReturnAt,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> postEvent({
    required String type,
    String? kidId,
    String? placeId,
    String? tripId,
    Map<String, dynamic>? payload,
    bool? forceNotify,
  }) async {
    final res = await _send(http.post(
      _u('/events'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'type': type,
        if (kidId != null) 'kidId': kidId,
        if (placeId != null) 'placeId': placeId,
        if (tripId != null) 'tripId': tripId,
        if (payload != null) 'payload': payload,
        if (forceNotify != null) 'forceNotify': forceNotify,
      }),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> listEvents({String? kidId}) async {
    final q = kidId != null ? '?kidId=$kidId' : '';
    final res = await _send(http.get(
      _u('/events$q'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<Map<String, dynamic>> listMyNotifications() async {
    final res = await _send(http.get(
      _u('/notifications/me'),
      headers: _headers(auth: true),
    ));
    return _json(res);
  }

  Future<bool> ping() async {
    try {
      final res = await _send(http.get(_u('/health')));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
