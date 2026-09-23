import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/api/api_client.dart';
import 'package:llegue_mobile/core/notifications/local_alerts.dart';
import 'package:llegue_mobile/core/state/app_controller.dart';
import 'package:llegue_mobile/core/storage/session_store.dart';
import 'package:llegue_mobile/features/onboarding/switch_person_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SilentAlerts extends LocalAlerts {
  @override
  Future<void> init() async {}

  @override
  Future<void> stopListeningOngoing() async {}

  @override
  Future<void> showListeningOngoing() async {}
}

class ReleaseApi extends ApiClient {
  int releaseCalls = 0;
  bool confirm = false;

  @override
  Future<Map<String, dynamic>> releaseDevice({
    required String installId,
    required bool confirm,
  }) async {
    releaseCalls++;
    this.confirm = confirm;
    if (!confirm) {
      throw ApiException('Confirmá que este celular va a cambiar de persona.', statusCode: 400);
    }
    return {
      'ok': true,
      'released': true,
      'previousUser': {'name': 'Soraya', 'role': 'admin_adult'},
    };
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

  test('confirmación nombra a quién sale y a quién entra', () {
    expect(
      switchPersonMessage(fromName: 'Soraya', toName: 'Mateo'),
      'Este celular pasará a ser de Mateo y saldrá Soraya de este aparato.',
    );
    expect(
      switchPersonMessage(fromName: 'Soraya'),
      contains('saldrá Soraya'),
    );
  });

  test('soltar el celular borra sesión y el nombre viejo', () async {
    final api = ReleaseApi();
    final store = SessionStore();
    await store.saveAuth(
      accessToken: 'a',
      refreshToken: 'r',
      user: {
        'id': 'u1',
        'name': 'Soraya',
        'role': 'admin_adult',
        'familyId': 'f1',
      },
      family: {'id': 'f1', 'name': 'Casa'},
    );
    await store.savePlaces([
      {'id': 'p1', 'name': 'Casa'},
    ]);
    await store.setBoundIdentity(name: 'Soraya', role: 'admin_adult');

    final app = AppController(api: api, store: store, alerts: SilentAlerts());
    await app.restorePersistedSession();
    app.boundUserName = 'Soraya';
    app.deviceBoundOnServer = true;
    expect(app.isLoggedIn, isTrue);

    await app.releaseDeviceForSomeoneElse();

    expect(api.releaseCalls, 1);
    expect(api.confirm, isTrue);
    expect(app.isLoggedIn, isFalse);
    expect(app.places, isEmpty);
    expect(app.boundUserName, isNull);
    expect(app.deviceBoundOnServer, isFalse);
    expect(await store.accessToken, isNull);
    expect(await store.familyId, isNull);
    expect(await store.places, isEmpty);
    expect(await store.boundUserName, isNull);
  });

  test('número de otra persona no se confunde con el celular trabado', () {
    final phone = ApiException(
      'Ese número es de Soraya; para Mateo usá el número de Mateo.',
      statusCode: 409,
      code: 'phone_owner',
    );
    final device = ApiException(
      'Este celular estaba como Soraya.',
      statusCode: 409,
      code: 'device_bound',
      body: {
        'boundUser': {'name': 'Soraya'},
      },
    );
    expect(phone.isPhoneOwner, isTrue);
    expect(phone.isDeviceBound, isFalse);
    expect(device.boundUserName, 'Soraya');
    expect(device.isPhoneOwner, isFalse);
  });
}
