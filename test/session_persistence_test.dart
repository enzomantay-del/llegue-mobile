import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/api/api_client.dart';
import 'package:llegue_mobile/core/notifications/local_alerts.dart';
import 'package:llegue_mobile/core/state/app_controller.dart';
import 'package:llegue_mobile/core/storage/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SilentAlerts extends LocalAlerts {
  @override
  Future<void> init() async {}

  @override
  Future<void> stopListeningOngoing() async {}

  @override
  Future<void> showListeningOngoing() async {}
}

class FakeApiClient extends ApiClient {
  Object? meError;
  Object? familyError;
  Object? refreshError;
  Map<String, dynamic> meBody = {};
  Map<String, dynamic> familyBody = {};
  int meCalls = 0;
  int familyCalls = 0;
  int refreshCalls = 0;
  bool failMeOnce = false;

  @override
  Future<Map<String, dynamic>> me() async {
    meCalls++;
    if (failMeOnce) {
      failMeOnce = false;
      throw ApiException('Sesión vencida.', statusCode: 401);
    }
    final err = meError;
    if (err != null) throw err;
    return meBody;
  }

  @override
  Future<Map<String, dynamic>> familyStatus() async {
    familyCalls++;
    final err = familyError;
    if (err != null) throw err;
    return familyBody;
  }

  @override
  Future<Map<String, dynamic>> refreshSession() async {
    refreshCalls++;
    final err = refreshError;
    if (err != null) throw err;
    accessToken = 'new-access';
    refreshToken = 'new-refresh';
    final user = meBody['user'] is Map
        ? Map<String, dynamic>.from(meBody['user'] as Map)
        : <String, dynamic>{};
    final cb = onTokensRefreshed;
    if (cb != null) {
      await cb(accessToken!, refreshToken!, user);
    }
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'user': user,
    };
  }

  @override
  Future<Map<String, dynamic>> lookupInstall(String installId) async {
    return {'bound': false};
  }
}

Map<String, dynamic> _user({String familyId = 'f1'}) => {
  'id': 'u1',
  'name': 'Enzo',
  'role': 'admin_adult',
  'familyId': familyId,
};

Map<String, dynamic> _family() => {'id': 'f1', 'name': 'Casa'};

List<Map<String, dynamic>> _places() => [
  {'id': 'p1', 'name': 'Casa', 'type': 'home', 'lat': -27.0, 'lng': -55.0},
];

String _jwt({required DateTime exp}) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'sub': 'u1',
        'exp': exp.toUtc().millisecondsSinceEpoch ~/ 1000,
      }),
    ),
  );
  return '${header.replaceAll('=', '')}.${payload.replaceAll('=', '')}.sig';
}

Future<AppController> _controllerWithSavedSession({
  required FakeApiClient api,
  String? accessToken,
  String refreshToken = 'refresh-1',
}) async {
  final store = SessionStore();
  await store.saveAuth(
    accessToken: accessToken ?? 'access-1',
    refreshToken: refreshToken,
    user: _user(),
    family: _family(),
  );
  await store.savePlaces(_places(), pendingPlaces: []);
  await store.setPermissionsReady(true);
  await store.setKeepAliveOnboardingSeen(true);
  await store.setSetupChecklistDone(true);

  final app = AppController(api: api, store: store, alerts: SilentAlerts());
  await app.restorePersistedSession();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SharedPreferences guarda token, refresh, userId y familyId', () async {
    final store = SessionStore();
    await store.saveAuth(
      accessToken: 'a',
      refreshToken: 'r',
      user: _user(),
      family: _family(),
    );
    await store.savePlaces(_places());

    expect(await store.accessToken, 'a');
    expect(await store.refreshToken, 'r');
    expect(await store.userId, 'u1');
    expect(await store.familyId, 'f1');
    expect((await store.places).single['name'], 'Casa');

    await store.clearSession();
    expect(await store.accessToken, isNull);
    expect(await store.refreshToken, isNull);
    expect(await store.userId, isNull);
    expect(await store.familyId, isNull);
    expect(await store.places, isEmpty);
  });

  test(
    'logout explícito borra sesión; matar el proceso no (restore)',
    () async {
      final api = FakeApiClient()
        ..meError = ApiException('No pudimos conectar.');
      final app = await _controllerWithSavedSession(api: api);

      expect(app.isLoggedIn, isTrue);
      expect(app.hasFamily, isTrue);
      expect(app.places, isNotEmpty);

      final store = app.store;
      expect(await store.accessToken, isNotNull);
      expect(await store.familyId, 'f1');

      await app.logout();
      expect(app.isLoggedIn, isFalse);
      expect(await store.accessToken, isNull);
      expect(await store.refreshToken, isNull);
      expect(await store.familyId, isNull);
      expect(app.places, isEmpty);
    },
  );

  test(
    'red caída al arrancar: no logout, mismos lugares, no onboarding familia',
    () async {
      final api = FakeApiClient()
        ..meError = ApiException(
          'No pudimos conectar. Revisá tu conexión a internet e intentá de nuevo.',
        );
      final app = await _controllerWithSavedSession(api: api);
      await app.reconcileSessionWithServer();

      expect(app.isLoggedIn, isTrue);
      expect(app.hasFamily, isTrue);
      expect(app.places.single['id'], 'p1');
      expect(app.startRoute, '/home');
      expect(await app.store.accessToken, 'access-1');
    },
  );

  test('401 tras refresh fallido: NO limpia familia local (posible DB wipe)', () async {
    final api = FakeApiClient()
      ..meError = ApiException('Sesión inválida.', statusCode: 401)
      ..refreshError = ApiException('Sesión vencida.', statusCode: 401);
    final app = await _controllerWithSavedSession(api: api);
    await app.reconcileSessionWithServer();

    expect(app.isLoggedIn, isTrue);
    expect(app.hasFamily, isTrue);
    expect(app.sessionValidationFailed, isTrue);
    expect(app.startRoute, '/home');
    expect(await app.store.accessToken, isNotNull);
    expect(await app.store.familyId, 'f1');
    expect(app.places.single['id'], 'p1');
  });

  test('5xx al arrancar: no logout, conserva sesión', () async {
    final api = FakeApiClient()
      ..meError = ApiException('Server error', statusCode: 503);
    final app = await _controllerWithSavedSession(api: api);
    await app.reconcileSessionWithServer();

    expect(app.isLoggedIn, isTrue);
    expect(app.hasFamily, isTrue);
    expect(app.sessionValidationFailed, isTrue);
    expect(await app.store.familyId, 'f1');
  });

  test('logout explícito sí borra sesión', () async {
    final api = FakeApiClient()
      ..meError = ApiException('Sesión inválida.', statusCode: 401)
      ..refreshError = ApiException('Sesión vencida.', statusCode: 401);
    final app = await _controllerWithSavedSession(api: api);
    await app.reconcileSessionWithServer();
    expect(app.sessionValidationFailed, isTrue);

    await app.logout();
    expect(app.isLoggedIn, isFalse);
    expect(await app.store.accessToken, isNull);
    expect(await app.store.familyId, isNull);
  });

  test('401 con refresh OK no limpia familia', () async {
    final api = FakeApiClient()
      ..failMeOnce = true
      ..meBody = {'user': _user(), 'family': _family()}
      ..familyBody = {
        'family': _family(),
        'members': [_user()],
        'places': _places(),
      };
    final app = await _controllerWithSavedSession(api: api);
    await app.reconcileSessionWithServer();

    expect(app.isLoggedIn, isTrue);
    expect(app.hasFamily, isTrue);
    expect(app.sessionValidationFailed, isFalse);
    expect(app.startRoute, '/home');
    expect(api.refreshCalls, greaterThanOrEqualTo(1));
  });

  test('prefs keys estables: no bump de claves por versionCode', () {
    // Contratos de SessionStore: si cambian los nombres, se pierde la sesión
    // al actualizar. Este test documenta las claves canónicas.
    const keys = [
      'access_token',
      'refresh_token',
      'user_json',
      'family_json',
      'user_id',
      'family_id',
      'places_json',
    ];
    final storeSrc = File('lib/core/storage/session_store.dart').readAsStringSync();
    for (final key in keys) {
      expect(storeSrc.contains("'$key'"), isTrue, reason: 'falta clave $key');
    }
    final boot = File('lib/core/state/app_controller.dart').readAsStringSync();
    final bootFn = RegExp(
      r'Future<void> bootstrap\(\) async \{[\s\S]*?\n  \}',
    ).firstMatch(boot)?.group(0);
    expect(bootFn, isNotNull);
    expect(bootFn!.contains('clearAllLocal'), isFalse);
    expect(bootFn.contains('clearSession'), isFalse);
    expect(boot.contains('sessionValidationFailed'), isTrue);
  });

  test('applicationId estable en gradle', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle.contains('applicationId = "com.llegue.llegue_mobile"'), isTrue);
    expect(gradle.contains('signingConfigs.getByName("debug")'), isFalse);
    expect(gradle.contains('sideload.keystore'), isTrue);
  });

  test(
    'server todavía tiene la familia: entra al Home, no a crear familia',
    () async {
      final api = FakeApiClient()
        ..meBody = {'user': _user(), 'family': _family()}
        ..familyBody = {
          'family': _family(),
          'members': [_user()],
          'places': _places(),
          'pendingPlaces': <Map<String, dynamic>>[],
        };
      final app = await _controllerWithSavedSession(api: api);
      await app.reconcileSessionWithServer();

      expect(app.isLoggedIn, isTrue);
      expect(app.hasFamily, isTrue);
      expect(app.startRoute, '/home');
      expect(app.startRoute, isNot('/create-family'));
      expect(app.places.single['name'], 'Casa');
    },
  );

  test('access token vencido: refresh y sigue en la misma familia', () async {
    final expired = _jwt(
      exp: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
    );
    final api = FakeApiClient()
      ..meBody = {'user': _user(), 'family': _family()}
      ..familyBody = {
        'family': _family(),
        'members': [_user()],
        'places': _places(),
      };
    final app = await _controllerWithSavedSession(
      api: api,
      accessToken: expired,
    );
    expect(api.accessTokenNearExpiry, isTrue);
    await app.reconcileSessionWithServer();

    expect(api.refreshCalls, 1);
    expect(app.api.accessToken, 'new-access');
    expect(await app.store.refreshToken, 'new-refresh');
    expect(app.hasFamily, isTrue);
    expect(app.startRoute, '/home');
  });

  test(
    'me 401 y refresh válido: recupera sesión sin pedir OTP de nuevo',
    () async {
      final api = FakeApiClient()
        ..failMeOnce = true
        ..meBody = {'user': _user(), 'family': _family()}
        ..familyBody = {
          'family': _family(),
          'members': [_user()],
          'places': _places(),
        };
      final app = await _controllerWithSavedSession(api: api);
      await app.reconcileSessionWithServer();

      expect(app.isLoggedIn, isTrue);
      expect(app.hasFamily, isTrue);
      expect(app.sessionValidationFailed, isFalse);
      expect(app.startRoute, '/home');
      expect(api.refreshCalls, greaterThanOrEqualTo(1));
    },
  );

  test('family/status falla por red: no borra lugares locales', () async {
    final api = FakeApiClient()
      ..meBody = {'user': _user(), 'family': _family()}
      ..familyError = ApiException('No pudimos conectar.');
    final app = await _controllerWithSavedSession(api: api);
    expect(app.places.single['id'], 'p1');
    await app.reconcileSessionWithServer();

    expect(app.isLoggedIn, isTrue);
    expect(app.places.single['id'], 'p1');
    expect(app.startRoute, '/home');
  });

  test('refreshFamilyStatus offline no limpia lugares en memoria', () async {
    final api = FakeApiClient()
      ..familyError = ApiException('No pudimos conectar.');
    final app = await _controllerWithSavedSession(api: api);
    expect(() => app.refreshFamilyStatus(), throwsA(isA<ApiException>()));
    expect(app.places.single['name'], 'Casa');
  });

  test('ApiException distingue 401 de red', () {
    expect(ApiException('caído').isUnauthorized, isFalse);
    expect(
      ApiException('Sesión vencida.', statusCode: 401).isUnauthorized,
      isTrue,
    );
  });

  test('refresh 404 no mata sesión: sigue con /auth/me', () async {
    final api = FakeApiClient()
      ..refreshError = ApiException('No encontrado', statusCode: 404)
      ..meBody = {'user': _user(), 'family': _family()}
      ..familyBody = {
        'family': _family(),
        'members': [_user()],
        'places': _places(),
      };
    final expired = _jwt(
      exp: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
    );
    final app = await _controllerWithSavedSession(
      api: api,
      accessToken: expired,
    );
    await app.reconcileSessionWithServer();

    expect(api.refreshCalls, 1);
    expect(api.meCalls, greaterThanOrEqualTo(1));
    expect(app.isLoggedIn, isTrue);
    expect(app.hasFamily, isTrue);
  });

  test('inviteErrorMessage: adulto con 403 confuso pide re-login', () async {
    final app = await _controllerWithSavedSession(api: FakeApiClient());
    expect(app.isAdult, isTrue);
    final msg = app.inviteErrorMessage(
      ApiException('Solo un adulto de la familia puede invitar.', statusCode: 403),
    );
    expect(msg.toLowerCase(), contains('sesión'));
  });

  test('inviteErrorMessage: menor ve mensaje de menores', () async {
    final api = FakeApiClient();
    final store = SessionStore();
    SharedPreferences.setMockInitialValues({});
    await store.saveAuth(
      accessToken: 'a',
      refreshToken: 'r',
      user: {
        'id': 'k1',
        'role': 'kid',
        'name': 'Mateo',
        'familyId': 'f1',
      },
      family: _family(),
    );
    final app = AppController(api: api, store: store, alerts: SilentAlerts());
    await app.restorePersistedSession();
    final msg = app.inviteErrorMessage(
      ApiException('Solo un adulto de la familia puede invitar.', statusCode: 403),
    );
    expect(msg.toLowerCase(), contains('menores'));
  });

  test('OTP de desarrollo no se toca en el cliente', () {
    // El código 123456 vive en el server (otpDevCode). El APK no debe
    // hardcodearlo ni cambiar el verify.
    final api = File('lib/core/api/api_client.dart').readAsStringSync();
    expect(api.contains("'123456'"), isFalse);
    expect(api.contains('/auth/verify-otp'), isTrue);
  });
}
