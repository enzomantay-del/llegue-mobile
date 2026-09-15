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
  void Function(String payload)? onSelected;

  /// Android congela sonido/volumen del canal al crearlo.
  /// v5 usaba USAGE_ALARM + URI de alarma: vibraba y no sonaba si el usuario
  /// subía Notificaciones (no Alarma), o si el URI no resolvía.
  /// v6 = stream de NOTIFICACIÓN + WAV en res/raw. Volumen a subir: Notificaciones.
  /// Si un APK viejo ya creó v5, hay que desinstalar una vez o dejar que init
  /// borre v4/v5; los avisos nuevos van a v6.
  static const _alertsChannel = 'llegue_alerts_v6';
  static const _sirenChannel = 'llegue_siren_v6';
  static const _listeningChannel = 'llegue_listening_v1';

  static const _alertSound = RawResourceAndroidNotificationSound('llegue_alert');

  static const _staleChannelIds = [
    'llegue_alerts_v4',
    'llegue_siren_v4',
    'llegue_alerts_v5',
    'llegue_siren_v5',
  ];

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onSelected?.call(payload);
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    try {
      await androidPlugin?.requestFullScreenIntentPermission();
    } catch (_) {}

    for (final id in _staleChannelIds) {
      try {
        await androidPlugin?.deleteNotificationChannel(channelId: id);
      } catch (_) {}
    }

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _alertsChannel,
        'Avisos de familia',
        description: 'Llegadas, salidas y novedades (volumen de notificaciones)',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
        sound: _alertSound,
        vibrationPattern: Int64List.fromList([0, 250, 120, 250]),
      ),
    );
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _sirenChannel,
        'Alarmas Llegué',
        description: 'Ayuda, app cerrada y avisos fuertes (volumen de notificaciones)',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
        sound: _alertSound,
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

  Future<String?> consumeLaunchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) return payload;
      }
    } catch (_) {}
    return null;
  }

  Future<void> show({
    required String title,
    required String body,
    bool urgent = false,
    DateTime? eventTime,
    String? payload,
  }) async {
    await init();
    await _plugin.show(
      id: _id++,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          urgent ? _sirenChannel : _alertsChannel,
          urgent ? 'Alarmas Llegué' : 'Avisos de familia',
          channelDescription: urgent
              ? 'Ayuda, app cerrada y avisos fuertes (volumen de notificaciones)'
              : 'Llegadas, salidas y novedades (volumen de notificaciones)',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          enableLights: urgent,
          fullScreenIntent: urgent,
          category: urgent
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.message,
          audioAttributesUsage: AudioAttributesUsage.notification,
          sound: _alertSound,
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
          presentBanner: true,
          presentSound: true,
          presentList: true,
          // iOS no usa stream de alarma. Critical Alerts requiere entitlement
          // de Apple; sin eso el sistema degrada a timeSensitive.
          interruptionLevel: urgent
              ? InterruptionLevel.critical
              : InterruptionLevel.timeSensitive,
          criticalSoundVolume: urgent ? 1.0 : null,
        ),
      ),
    );
  }

  /// Prueba fuerte: aviso urgente + sonido + vibración (confianza del adulto).
  Future<void> showTestAlarm() async {
    await show(
      title: 'Llegué — prueba de alarma',
      body:
          'Si no suena, subí el volumen de NOTIFICACIONES y sacá el celular de silencio o vibrar.',
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
