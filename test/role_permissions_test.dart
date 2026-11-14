import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/api/api_client.dart';
import 'package:llegue_mobile/core/geofence/geofence_monitor.dart';
import 'package:llegue_mobile/core/notifications/local_alerts.dart';
import 'package:llegue_mobile/core/permissions/permissions_service.dart';
import 'package:llegue_mobile/core/state/app_controller.dart';
import 'package:llegue_mobile/core/storage/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingGeofence extends GeofenceMonitor {
  int starts = 0;

  @override
  Future<void> start({bool foregroundNotification = true}) async {
    starts++;
    running = true;
  }

  @override
  Future<void> stop() async {
    running = false;
  }
}

class CountingAlerts extends LocalAlerts {
  int listening = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> showListeningOngoing() async {
    listening++;
  }

  @override
  Future<void> stopListeningOngoing() async {}
}

class FixedPermissions extends PermissionsService {
  FixedPermissions({required this.location, required this.notifications});

  final String location;
  final String notifications;

  @override
  Future<String> locationStatus() async => location;

  @override
  Future<String> notificationsStatus() async => notifications;
}

class PermApi extends ApiClient {
  final notifs = <String>[];

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
  Future<Map<String, dynamic>> patchPermissions({
    required String locationPermission,
    required String notificationsPermission,
    String? deviceId,
    bool? locationOk,
  }) async {
    notifs.add(notificationsPermission);
    return {'permissionsReady': false};
  }

  @override
  Future<Map<String, dynamic>> reportBattery({
    required int batteryLevel,
    String? deviceId,
  }) async {
    return {'ok': true};
  }
}

class LookupApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> lookupInstall(String installId) async {
    return {
      'bound': true,
      'user': {'name': 'Soraya', 'role': 'admin_adult'},
    };
  }
}

class ReleaseApi extends ApiClient {
  int releaseCalls = 0;

  @override
  Future<Map<String, dynamic>> releaseDevice({
    required String installId,
    required bool confirm,
  }) async {
    releaseCalls++;
    return {'ok': true, 'released': true};
  }

  @override
  Future<Map<String, dynamic>> lookupInstall(String installId) async {
    return {'bound': false};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hijo listo con Siempre aunque los avisos estén apagados', () {
    expect(
      permissionsReadyForRole(
        kid: true,
        locationPermission: 'always',
        notificationsPermission: 'denied',
      ),
      isTrue,
    );
    expect(
      permissionsReadyForRole(
        kid: true,
        locationPermission: 'while_in_use',
        notificationsPermission: 'granted',
      ),
      isFalse,
    );
  });

  test('adulto listo con avisos y sin ubicación Siempre', () {
    expect(
      permissionsReadyForRole(
        kid: false,
        locationPermission: 'not_asked',
        notificationsPermission: 'granted',
      ),
      isTrue,
    );
    expect(
      permissionsReadyForRole(
        kid: false,
        locationPermission: 'always',
        notificationsPermission: 'denied',
      ),
      isFalse,
    );
  });

  test('startRoute manda al adulto a avisos y al hijo a ubicación', () {
    final adult = AppController();
    adult.api.accessToken = 't';
    adult.user = {
      'id': 'a1',
      'name': 'Enzo',
      'role': 'admin_adult',
      'familyId': 'f1',
    };
    adult.family = {'id': 'f1'};
    adult.permissionsReady = false;
    expect(adult.permissionsEntryRoute, '/permissions-notifications');
    expect(adult.startRoute, '/permissions-notifications');

    final kid = AppController();
    kid.api.accessToken = 't';
    kid.user = {
      'id': 'k1',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    kid.family = {'id': 'f1'};
    kid.permissionsReady = false;
    expect(kid.startRoute, '/permissions-location');
  });

  test('el adulto no prende el GPS y conserva el aviso fijo', () async {
    final fence = RecordingGeofence();
    final alerts = CountingAlerts();
    final app = AppController(
      api: PermApi(),
      store: SessionStore(),
      alerts: alerts,
      geofence: fence,
      permissions: FixedPermissions(
        location: 'not_asked',
        notifications: 'granted',
      ),
    );
    app.api.accessToken = 't';
    app.user = {
      'id': 'a1',
      'name': 'Enzo',
      'role': 'admin_adult',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1'};
    app.permissionsReady = true;
    try {
      await app.syncRuntimeServices();
      await Future<void>.delayed(Duration.zero);
      expect(fence.starts, 0);
      expect(fence.running, isFalse);
      expect(alerts.listening, 1);
    } finally {
      await app.stopRuntimeServices();
    }
  });

  test('el hijo prende la detección aunque los avisos estén denegados', () async {
    final fence = RecordingGeofence();
    final alerts = CountingAlerts();
    final app = AppController(
      api: PermApi(),
      store: SessionStore(),
      alerts: alerts,
      geofence: fence,
      permissions: FixedPermissions(
        location: 'always',
        notifications: 'denied',
      ),
    );
    app.api.accessToken = 't';
    app.user = {
      'id': 'k1',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1'};
    app.permissionsReady = true;
    try {
      await app.syncRuntimeServices();
      await Future<void>.delayed(Duration.zero);
      expect(fence.starts, 1);
      expect(fence.running, isTrue);
      expect(alerts.listening, 0);
    } finally {
      await app.stopRuntimeServices();
    }
  });

  test('sync del hijo ignora permissionsReady del server si hay Siempre', () async {
    final api = PermApi();
    final app = AppController(
      api: api,
      store: SessionStore(),
      alerts: CountingAlerts(),
      geofence: RecordingGeofence(),
      permissions: FixedPermissions(location: 'always', notifications: 'denied'),
    );
    app.api.accessToken = 't';
    app.user = {
      'id': 'k1',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1'};
    app.permissionsReady = true;
    try {
      final ready = await app.syncPermissions(
        locationPermission: 'always',
        notificationsPermission: 'denied',
        restartServices: false,
      );
      expect(ready, isTrue);
      expect(app.permissionsReady, isTrue);
      expect(api.notifs, ['granted', 'denied']);

      final again = await app.syncPermissions(
        locationPermission: 'always',
        notificationsPermission: 'denied',
        restartServices: false,
      );
      expect(again, isTrue);
      expect(api.notifs, ['granted', 'denied', 'denied']);
    } finally {
      await app.stopRuntimeServices();
    }
  });

  test('lookup sin teléfono no borra el número guardado en el celular', () async {
    final app = AppController(
      api: LookupApi(),
      store: SessionStore(),
      alerts: CountingAlerts(),
    );
    app.api.accessToken = 't';
    app.user = {
      'id': 'a1',
      'name': 'Soraya',
      'role': 'admin_adult',
      'familyId': 'f1',
      'phone': '5491112345678',
    };
    app.family = {'id': 'f1'};
    app.boundUserPhone = '5491112345678';
    await app.refreshDeviceBinding();
    expect(app.deviceBoundOnServer, isTrue);
    expect(app.boundUserName, 'Soraya');
    expect(app.boundUserPhone, '5491112345678');
  });

  test('sin sesión, cambiar de persona no llama al release y rearma el ingreso', () async {
    final api = ReleaseApi();
    final store = SessionStore();
    await store.setBoundIdentity(
      name: 'Soraya',
      role: 'admin_adult',
      phone: '5491112345678',
    );
    final app = AppController(
      api: api,
      store: store,
      alerts: CountingAlerts(),
    );
    app.boundUserName = 'Soraya';
    app.boundUserPhone = '5491112345678';
    app.deviceBoundOnServer = true;

    await app.releaseDeviceForSomeoneElse();

    expect(api.releaseCalls, 0);
    expect(app.reassignPending, isTrue);
    expect(app.boundUserName, isNull);
    expect(app.deviceBoundOnServer, isFalse);
    expect(await store.boundUserName, isNull);
    expect(await store.boundUserPhone, isNull);
  });
}
