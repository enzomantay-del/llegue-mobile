import 'package:flutter/foundation.dart';

import 'local_alerts.dart';

/// Push FCM (app cerrada).
/// El código cliente se activa cuando esté google-services.json + paquetes Firebase.
/// Mientras tanto no rompe el build; el servidor ya soporta FCM (ver FIREBASE-SETUP.txt).
/// Cuando se cablee FCM, usar los mismos canales Android que LocalAlerts
/// (`llegue_alerts_v6` / `llegue_siren_v6`, stream NOTIFICACIÓN + raw llegue_alert).
class PushService {
  PushService({required this.alerts});

  final LocalAlerts alerts;
  bool ready = false;
  String? token;

  Future<bool> init() async {
    // Placeholder: se habilita al configurar Firebase (FIREBASE-SETUP.txt).
    ready = false;
    token = null;
    debugPrint(
      'Push: Firebase aún no configurado en este APK. '
      'Seguí FIREBASE-SETUP.txt para avisos con app cerrada.',
    );
    return false;
  }

  Future<void> dispose() async {}
}
