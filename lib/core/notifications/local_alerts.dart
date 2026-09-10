import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalAlerts {
  LocalAlerts();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _listeningShown = false;
  int _id = 100;

  /// Canal nuevo: Android no deja cambiar el volumen/sonido de un canal viejo.
  static const _alertsChannel = 'llegue_alerts_v4';
  static const _sirenChannel = 'llegue_siren_v4';
  static const _listeningChannel = 'llegue_listening_v1';

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    try {
      await androidPlugin?.requestFullScreenIntentPermission();
    } catch (_) {}

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertsChannel,
        'Avisos de familia',
        description: 'Llegadas, salidas y novedades',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _sirenChannel,
        'Alarmas Llegué',
        description: 'Ayuda, app cerrada y avisos fuertes',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        // Usa el volumen de ALARMA del celular (más fuerte que multimedia)
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 800]),
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _listeningChannel,
        'Llegué en segundo plano',
        description: 'Aviso fijo para seguir recibiendo notificaciones',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
      ),
    );
    _ready = true;
  }

  Future<void> show({
    required String title,
    required String body,
    bool urgent = false,
    DateTime? eventTime,
  }) async {
    await init();
    await _plugin.show(
      id: _id++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          urgent ? _sirenChannel : _alertsChannel,
          urgent ? 'Alarmas Llegué' : 'Avisos de familia',
          channelDescription: urgent
              ? 'Ayuda, app cerrada y avisos fuertes'
              : 'Llegadas, salidas y novedades',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: urgent,
          category: urgent
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.message,
          audioAttributesUsage: urgent
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          vibrationPattern: urgent
              ? Int64List.fromList([0, 600, 200, 600, 200, 800, 200, 1000])
              : Int64List.fromList([0, 250, 120, 250]),
          visibility: NotificationVisibility.public,
          ticker: body,
          // Usa la hora del HECHO (llegada/salida), no la hora en que llegó el aviso.
          when: eventTime?.millisecondsSinceEpoch,
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: urgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }

  /// Prueba fuerte: aviso urgente + vibración (confianza del adulto).
  Future<void> showTestAlarm() async {
    await show(
      title: 'Llegué — prueba de alarma',
      body:
          'Si el sonido es bajo, subí el volumen de ALARMA del celular (no solo multimedia).',
      urgent: true,
    );
    for (var i = 0; i < 8; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
  }

  /// Aviso fijo silencioso: permite seguir recibiendo avisos sin Firebase.
  /// Solo se muestra una vez por sesión para no molestar.
  Future<void> showListeningOngoing() async {
    if (_listeningShown) return;
    await init();
    await _plugin.show(
      id: 7,
      title: 'Llegué activo',
      body: 'Así te llegan los avisos aunque no estés mirando la app.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _listeningChannel,
          'Llegué en segundo plano',
          channelDescription:
              'Aviso fijo para seguir recibiendo notificaciones',
          importance: Importance.min,
          priority: Priority.min,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          category: AndroidNotificationCategory.service,
          silent: true,
        ),
      ),
    );
    _listeningShown = true;
  }

  Future<void> stopListeningOngoing() async {
    await init();
    await _plugin.cancel(id: 7);
    _listeningShown = false;
  }
}
