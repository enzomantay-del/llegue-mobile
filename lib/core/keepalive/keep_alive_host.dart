/// Mantiene el proceso vivo con un servicio en primer plano de Android.
/// El adulto no usa ubicación. El hijo/a sí, para la detección.
abstract class KeepAliveHost {
  Future<bool> start({required bool kid});

  Future<void> stop();

  Future<bool> isServiceRunning();

  /// null = no se pudo saber (escritorio, prueba, iOS).
  Future<bool?> isIgnoringBatteryOptimizations();

  Future<bool> requestIgnoreBatteryOptimizations();

  void sendToTask(Object data);
}
