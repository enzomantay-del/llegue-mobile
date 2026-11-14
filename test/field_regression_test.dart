import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:llegue_mobile/core/api/api_client.dart';
import 'package:llegue_mobile/core/device/detection_health.dart';
import 'package:llegue_mobile/core/device/oem_keep_alive.dart';
import 'package:llegue_mobile/core/geofence/family_watch.dart';
import 'package:llegue_mobile/core/geofence/geofence_monitor.dart';
import 'package:llegue_mobile/core/keepalive/keep_alive_host.dart';
import 'package:llegue_mobile/core/notifications/alert_inbox.dart';
import 'package:llegue_mobile/core/notifications/local_alerts.dart';
import 'package:llegue_mobile/core/state/app_controller.dart';
import 'package:llegue_mobile/core/storage/session_store.dart';
import 'package:llegue_mobile/core/trips/trip_conflict.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingAlerts extends LocalAlerts {
  final shown = <String>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    bool urgent = false,
    DateTime? eventTime,
    String? payload,
    String? idKey,
  }) async {
    shown.add(idKey ?? title);
  }

  @override
  Future<void> showListeningOngoing() async {}

  @override
  Future<void> stopListeningOngoing() async {}
}

class DeadGeofence extends GeofenceMonitor {
  @override
  Future<void> start({bool foregroundNotification = true}) async {
    running = false;
    lastError = 'Sin permiso de ubicación';
  }

  @override
  Future<void> stop() async {
    running = false;
  }
}

class FakeKeepAlive implements KeepAliveHost {
  @override
  Future<bool> start({required bool kid}) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isServiceRunning() async => false;

  @override
  Future<bool?> isIgnoringBatteryOptimizations() async => null;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => false;

  @override
  void sendToTask(Object data) {}
}

class ScriptApi extends ApiClient {
  final posts = <Map<String, dynamic>>[];
  final cancels = <String>[];
  ApiException? postError;
  ApiException? startError;
  String? lastKey;
  bool lastReplace = false;
  String? lastSince;
  int postCalls = 0;

  @override
  Future<Map<String, dynamic>> registerDevice({
    required String platform,
    required String installId,
    String? pushToken,
  }) async {
    return {
      'device': {'id': 'dev-1'},
    };
  }

  @override
  Future<Map<String, dynamic>> familyStatus({String? notificationsSince}) async {
    lastSince = notificationsSince;
    return {
      'family': {'id': 'f1', 'name': 'Casa'},
      'members': [],
      'places': [],
      'pendingPlaces': [],
      'recentEvents': [],
      'notifications': notes,
    };
  }

  List<Map<String, dynamic>> notes = [];

  @override
  Future<Map<String, dynamic>> postEvent({
    required String type,
    String? kidId,
    String? placeId,
    String? tripId,
    Map<String, dynamic>? payload,
    bool? forceNotify,
  }) async {
    postCalls++;
    final err = postError;
    if (err != null) {
      postError = null;
      throw err;
    }
    posts.add({
      'type': type,
      'placeId': placeId,
      'tripId': tripId,
      'force': forceNotify,
    });
    return {'ok': true, 'event': {'id': 'e$postCalls', 'type': type}};
  }

  @override
  Future<Map<String, dynamic>> startTrip({
    String? kidId,
    String? destinationPlaceId,
    String? expectedReturnAt,
    String? kind,
    bool? forceNotify,
    String? createdById,
    String? createdByName,
    String? idempotencyKey,
    bool replaceOpen = false,
  }) async {
    lastKey = idempotencyKey;
    lastReplace = replaceOpen;
    final err = startError;
    if (err != null) throw err;
    return {
      'trip': {
        'id': 'new-trip',
        'destinationPlaceId': destinationPlaceId,
        'destinationName': 'Club ucraniano',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> activeTrip({String? kidId}) async {
    return {'trip': null};
  }

  @override
  Future<Map<String, dynamic>> patchTrip(
    String tripId, {
    String? action,
    String? destinationPlaceId,
    String? expectedReturnAt,
    bool clearDestination = false,
  }) async {
    cancels.add(tripId);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> reportBattery({
    required int batteryLevel,
    String? deviceId,
  }) async {
    return {'ok': true};
  }
}

class TokenApi extends ApiClient {
  int refreshes = 0;

  @override
  Future<Map<String, dynamic>> refreshSession() async {
    refreshes++;
    accessToken = 'nuevo';
    refreshToken = 'nuevo-refresh';
    return {'accessToken': accessToken};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('un aviso reciente no se marca visto sin mostrarlo', () async {
    final store = SessionStore();
    final alerts = RecordingAlerts();
    final now = DateTime.now();
    final recent = {
      'id': 'n-llegada',
      'title': 'Llegó',
      'body': 'Mateo llegó a Club ucraniano',
      'createdAt': now.subtract(const Duration(hours: 4)).toIso8601String(),
    };
    final old = {
      'id': 'n-viejo',
      'title': 'Llegó',
      'body': 'Historia',
      'createdAt': now.subtract(const Duration(days: 4)).toIso8601String(),
    };
    final delivered = await deliverPlannedAlerts(
      store: store,
      alerts: alerts,
      notifications: [old, recent],
      kid: false,
      now: now,
    );
    expect(delivered, 1);
    expect(alerts.shown, ['n-llegada']);
    expect(await store.shownAlertIds(), contains('n-llegada'));
    expect(await store.shownAlertIds(), contains('n-viejo'));

    alerts.shown.clear();
    final again = await deliverPlannedAlerts(
      store: store,
      alerts: alerts,
      notifications: [old, recent],
      kid: false,
      now: now,
    );
    expect(again, 0);
    expect(alerts.shown, isEmpty);
  });

  test('el poll del adulto muestra el aviso que llegó con la app cerrada', () async {
    final api = ScriptApi();
    final alerts = RecordingAlerts();
    api.notes = [
      {
        'id': 'n1',
        'title': 'Salió',
        'body': 'Mateo salió de casa',
        'createdAt': DateTime.now().toIso8601String(),
      },
    ];
    final app = AppController(
      api: api,
      store: SessionStore(),
      alerts: alerts,
      keepAlive: FakeKeepAlive(),
    );
    app.user = {
      'id': 'adult',
      'name': 'Soraya',
      'role': 'admin_adult',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1', 'name': 'Casa'};
    await app.refreshFamilyStatus();
    expect(alerts.shown, ['n1']);
    expect(api.lastSince, isNotNull);
    await app.refreshFamilyStatus();
    expect(alerts.shown, ['n1']);
  });

  test('409 trip_in_progress muestra la salida abierta y no la da por creada', () async {
    final api = ScriptApi();
    api.startError = ApiException(
      'Ya hay una salida en curso. Primero marcá que llegaste.',
      statusCode: 409,
      code: 'trip_in_progress',
      body: {
        'code': 'trip_in_progress',
        'openTrip': {
          'id': 'old',
          'destinationPlaceId': 'colegio',
          'destinationName': 'Colegio',
          'destination': {'id': 'colegio', 'name': 'Colegio'},
          'phase': 'pending_departure',
          'startedAt': '2026-11-13T21:24:00.000Z',
        },
      },
    );
    final app = _adult(api);
    expect(
      () => app.startTrip(kidId: 'mateo', destinationPlaceId: 'club'),
      throwsA(
        isA<TripAlreadyOpenException>()
            .having((e) => e.code, 'code', 'trip_in_progress')
            .having((e) => e.trip?['id'], 'id', 'old')
            .having(
              (e) => tripDestinationName(e.trip),
              'destino',
              'Colegio',
            ),
      ),
    );
    expect(
      tripAlreadyOpenBody({
        'destination': {'name': 'Club ucraniano'},
        'phase': 'at_destination',
        'startedAt': '2026-11-13T21:24:00.000Z',
      }),
      contains('Club ucraniano'),
    );
  });

  test('el adulto reemplaza con replaceOpen y una clave nueva', () async {
    final api = ScriptApi();
    final app = _adult(api);
    await app.replaceOpenTrip(
      openTripId: 'old',
      kidId: 'mateo',
      destinationPlaceId: 'club',
      forceNotify: false,
    );
    expect(api.lastReplace, isTrue);
    expect(api.lastKey, isNotNull);
    expect(api.cancels, isEmpty);
  });

  test('el hijo cierra la salida y no manda replaceOpen', () async {
    final api = ScriptApi();
    final app = _kid(api);
    await app.replaceOpenTrip(
      openTripId: 'old',
      destinationPlaceId: 'club',
      forceNotify: false,
    );
    expect(api.lastReplace, isFalse);
    expect(api.cancels, ['old']);
  });

  test('el reintento de POST /trips reusa la Idempotency-Key', () async {
    final api = ApiClient();
    api.accessToken = 't';
    var calls = 0;
    String? first;
    String? second;
    api.debugPost = (uri, {headers, body}) async {
      calls++;
      if (calls == 1) {
        first = headers?['Idempotency-Key'];
        throw TimeoutException('tardó');
      }
      second = headers?['Idempotency-Key'];
      final decoded = jsonDecode(body! as String) as Map<String, dynamic>;
      expect(decoded.containsKey('replaceOpen'), isFalse);
      return http.Response(jsonEncode({'trip': {'id': 't1'}}), 201);
    };
    final data = await api.startTrip(destinationPlaceId: 'club');
    expect(calls, 2);
    expect(first, isNotEmpty);
    expect(second, first);
    expect(data['trip']['id'], 't1');
  });

  test('replaceOpen viaja en el cuerpo con la clave pedida', () async {
    final api = ApiClient();
    api.accessToken = 't';
    Map<String, dynamic>? sent;
    String? key;
    api.debugPost = (uri, {headers, body}) async {
      key = headers?['Idempotency-Key'];
      sent = jsonDecode(body! as String) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'trip': {'id': 'nuevo', 'destinationPlaceId': 'club'}}),
        201,
      );
    };
    await api.startTrip(
      kidId: 'mateo',
      destinationPlaceId: 'club',
      idempotencyKey: 'reemplazo-club',
      replaceOpen: true,
    );
    expect(key, 'reemplazo-club');
    expect(sent?['replaceOpen'], isTrue);
    expect(sent?['destinationPlaceId'], 'club');
  });

  test('401 en POST /events refresca la sesión y reintenta', () async {
    final api = TokenApi();
    api.accessToken = 'viejo';
    var calls = 0;
    String? secondAuth;
    api.debugPost = (uri, {headers, body}) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'error': 'Tenés que iniciar sesión.'}),
          401,
        );
      }
      secondAuth = headers?['authorization'];
      return http.Response(jsonEncode({'ok': true, 'event': {'id': 'e1'}}), 201);
    };
    final data = await api.postEvent(type: 'departure', placeId: 'casa');
    expect(calls, 2);
    expect(api.refreshes, 1);
    expect(secondAuth, 'Bearer nuevo');
    expect(data['event']['id'], 'e1');
  });

  test('la llegada del geofence hace POST /events con lugar y salida', () async {
    final api = ScriptApi();
    final app = _kid(api);
    app.activeTrip = {
      'id': 'trip-1',
      'destinationPlaceId': 'club',
    };
    await app.debugHandleTransition(
      GeofenceTransition(
        type: 'arrival',
        placeId: 'club',
        placeName: 'Club ucraniano',
        lat: -27.2,
        lng: -55.8,
      ),
    );
    expect(api.posts, hasLength(1));
    expect(api.posts.single['type'], 'arrival');
    expect(api.posts.single['placeId'], 'club');
    expect(api.posts.single['tripId'], 'trip-1');
    expect(api.posts.single['force'], isTrue);
  });

  test('si el POST falla, el evento queda y se reintenta', () async {
    final api = ScriptApi();
    api.postError = ApiException('se cortó', statusCode: 500);
    final app = _kid(api);
    await app.debugHandleTransition(
      GeofenceTransition(
        type: 'departure',
        placeId: 'casa',
        placeName: 'Casa',
        lat: -27,
        lng: -55,
      ),
    );
    expect(app.lastDetectionError, contains('salida'));
    expect(await app.store.pendingGeofenceEvents(), isNotEmpty);
    await app.debugFlushPendingEvents();
    expect(await app.store.pendingGeofenceEvents(), isEmpty);
    expect(api.posts.single['type'], 'departure');
    expect(api.posts.single['placeId'], 'casa');
  });

  test('la salida especial entra en la vigilancia aunque el proceso se haya reiniciado', () {
    final watch = familyWatchFromStatus(
      {
        'places': [
          {
            'id': 'casa',
            'name': 'Casa',
            'lat': -27.0,
            'lng': -55.0,
            'status': 'active',
          },
        ],
        'members': [
          {
            'id': 'mateo',
            'role': 'kid',
            'activeTrip': {
              'id': 'trip-1',
              'destinationPlaceId': 'club',
              'destinationName': 'Club ucraniano',
              'destinationLat': -27.2,
              'destinationLng': -55.8,
            },
          },
        ],
        'notifications': [],
      },
      userId: 'mateo',
    );
    expect(watch.tripId, 'trip-1');
    expect(watch.destinationPlaceId, 'club');
    expect(watch.places.map((p) => p['id']), containsAll(['casa', 'club']));
  });

  test('detección apagada si no arranca el GPS', () async {
    final api = ScriptApi();
    final app = AppController(
      api: api,
      store: SessionStore(),
      alerts: RecordingAlerts(),
      geofence: DeadGeofence(),
      keepAlive: FakeKeepAlive(),
    );
    app.api.accessToken = 't';
    app.user = {
      'id': 'mateo',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1'};
    app.permissionsReady = true;
    await app.syncRuntimeServices();
    expect(app.showDetectionOff, isTrue);
    expect(app.detectionBannerTitle, 'Detección apagada');
    expect(app.geofence.running, isFalse);
    await app.stopRuntimeServices();
  });

  test('la gracia de arranque no esconde un error de detección', () {
    final now = DateTime.now();
    expect(
      detectionLooksOff(
        kid: true,
        permissionsReady: true,
        inProcessRunning: false,
        taskRunning: false,
        hasStartError: true,
        now: now,
        suppressUntil: now.add(const Duration(seconds: 20)),
      ),
      isTrue,
    );
    expect(
      detectionLooksOff(
        kid: true,
        permissionsReady: true,
        inProcessRunning: false,
        taskRunning: true,
        hasStartError: false,
        now: now,
        suppressUntil: now,
      ),
      isFalse,
    );
  });

  test('Xiaomi: pausar actividad e inicio automático', () {
    expect(isXiaomiFamily('Xiaomi'), isTrue);
    expect(isXiaomiFamily('Redmi'), isTrue);
    final kid = OemKeepAliveCopy.androidKid();
    expect(kid, contains('Pausar actividad'));
    expect(kid, contains('Inicio automático'));
    expect(kid, contains('cerrás a la fuerza'));
    final adult = OemKeepAliveCopy.androidAdult();
    expect(adult, contains('aviso fijo'));
    expect(adult.contains('permiso de ubicación'), isFalse);
  });
}

AppController _adult(ScriptApi api) {
  final app = AppController(
    api: api,
    store: SessionStore(),
    alerts: RecordingAlerts(),
    keepAlive: FakeKeepAlive(),
  );
  app.api.accessToken = 't';
  app.user = {
    'id': 'soraya',
    'name': 'Soraya',
    'role': 'admin_adult',
    'familyId': 'f1',
  };
  app.family = {'id': 'f1'};
  return app;
}

AppController _kid(ScriptApi api) {
  final app = AppController(
    api: api,
    store: SessionStore(),
    alerts: RecordingAlerts(),
    keepAlive: FakeKeepAlive(),
  );
  app.api.accessToken = 't';
  app.user = {
    'id': 'mateo',
    'name': 'Mateo',
    'role': 'kid',
    'familyId': 'f1',
  };
  app.family = {'id': 'f1'};
  return app;
}
