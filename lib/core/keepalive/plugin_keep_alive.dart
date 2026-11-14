import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'keep_alive_host.dart';
import 'keep_alive_task.dart';

/// Servicio en primer plano. Adulto: specialUse, sin ubicación.
/// Hijo/a: location, para poder detectar con la pantalla apagada.
/// Si el plugin no está (pruebas, escritorio), devuelve false y la app
/// sigue con el camino de siempre.
class PluginKeepAliveHost implements KeepAliveHost {
  bool _inited = false;

  void _ensureInit() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'llegue_keepalive_v1',
        channelName: 'Llegué en segundo plano',
        channelDescription:
            'Aviso fijo para seguir recibiendo avisos con la pantalla apagada',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  @override
  Future<bool> start({required bool kid}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      _ensureInit();
      final title = 'Llegué activo';
      final text = kid
          ? 'Detectando llegadas y salidas.'
          : 'Te avisamos si tu familia llega o sale.';
      final types = kid
          ? const [ForegroundServiceTypes.location]
          : const [ForegroundServiceTypes.specialUse];
      final running = await FlutterForegroundTask.isRunningService;
      final ServiceRequestResult result;
      if (running) {
        result = await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
          callback: llegueKeepAliveCallback,
        );
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: 710,
          serviceTypes: types,
          notificationTitle: title,
          notificationText: text,
          callback: llegueKeepAliveCallback,
        );
      }
      return result is ServiceRequestSuccess;
    } catch (e) {
      debugPrint('KeepAlive start: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      if (!await isServiceRunning()) return;
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('KeepAlive stop: $e');
    }
  }

  @override
  Future<bool> isServiceRunning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool?> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      return true;
    } catch (e) {
      debugPrint('KeepAlive battery: $e');
      return false;
    }
  }

  @override
  void sendToTask(Object data) {
    try {
      FlutterForegroundTask.sendDataToTask(data);
    } catch (e) {
      debugPrint('KeepAlive send: $e');
    }
  }
}
