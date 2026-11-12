import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/device/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('un install nuevo usa id aleatorio, no Build.ID', () async {
    final id = await DeviceIdentity.getInstallId();
    expect(id.startsWith('reset-'), isTrue);
    expect(id.contains('TP1A'), isFalse);
    expect(id.startsWith('and-'), isFalse);
    expect(id.length, greaterThanOrEqualTo(6));
    expect(await DeviceIdentity.getInstallId(), id);
  });

  test('resetInstallId usa el mismo formato y queda guardado', () async {
    final id = await DeviceIdentity.resetInstallId();
    expect(id.startsWith('reset-'), isTrue);
    expect(await DeviceIdentity.getInstallId(), id);
  });

  test('un id viejo and-Build.ID se reemplaza', () async {
    SharedPreferences.setMockInitialValues({
      'install_id_v1': 'and-TP1A.220624.014',
    });
    final id = await DeviceIdentity.getInstallId();
    expect(id.startsWith('reset-'), isTrue);
    expect(id.contains('TP1A'), isFalse);
    expect(await DeviceIdentity.getInstallId(), id);
  });

  test('un id de iOS ya guardado no se toca', () async {
    SharedPreferences.setMockInitialValues({
      'install_id_v1': 'ios-vendor-abc123',
    });
    expect(await DeviceIdentity.getInstallId(), 'ios-vendor-abc123');
  });
}
