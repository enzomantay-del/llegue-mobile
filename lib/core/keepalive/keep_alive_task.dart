import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../api/api_client.dart';
import '../geofence/family_watch.dart';
import '../geofence/geofence_events.dart';
import '../geofence/geofence_monitor.dart';
import '../notifications/alert_inbox.dart';
import '../notifications/local_alerts.dart';
import '../storage/session_store.dart';

/// Arranque del servicio. Tiene que ser una función de nivel superior.
@pragma('vm:entry-point')
void llegueKeepAliveCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(LlegueKeepAliveTask());
}

/// Corre en un isolate que Android no pausa mientras el servicio está adelante.
/// Adulto: busca avisos y los muestra. Hijo/a: vigila lugares y hace POST /events.
class LlegueKeepAliveTask extends TaskHandler {
  GeofenceMonitor? _monitor;
  LocalAlerts? _alerts;
  String? _tripId;
  String? _destinationPlaceId;
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _alerts = LocalAlerts();
    _monitor = GeofenceMonitor(
      onTransition: (transition) {
        unawaited(_onTransition(transition));
      },
    );
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data['type'] != 'places') return;
    final rawPlaces = data['places'];
    if (rawPlaces is List) {
      _monitor?.updatePlaces([
        for (final item in rawPlaces)
          if (item is Map) Map<String, dynamic>.from(item),
      ]);
    }
    final tripId = data['tripId'];
    final dest = data['destinationPlaceId'];
    _tripId = tripId is String && tripId.isNotEmpty ? tripId : _tripId;
    _destinationPlaceId =
        dest is String && dest.isNotEmpty ? dest : _destinationPlaceId;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _monitor?.stop();
    _monitor = null;
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final store = SessionStore();
      final user = await store.user;
      final token = await store.accessToken;
      if (user == null || token == null || token.isEmpty) return;
      final role = user['role'] as String?;
      final kid = role == 'kid';
      final api = await _client(store, user, token);
      if (kid) {
        await _kidTick(api, store, user);
      } else if (role == 'adult' || role == 'admin_adult') {
        await _adultTick(api, store);
      }
    } catch (e) {
      debugPrint('KeepAlive tick: $e');
    } finally {
      _busy = false;
    }
  }

  Future<ApiClient> _client(
    SessionStore store,
    Map<String, dynamic> user,
    String token,
  ) async {
    final saved = await store.baseUrl;
    final api = ApiClient(
      baseUrl: saved == null || saved.isEmpty ? null : saved,
    );
    api.accessToken = token;
    api.refreshToken = await store.refreshToken;
    api.onTokensRefreshed = (access, refresh, refreshed) async {
      await store.saveAuth(
        accessToken: access,
        refreshToken: refresh,
        user: refreshed.isEmpty ? user : refreshed,
        family: await store.family,
      );
    };
    return api;
  }

  Future<void> _kidTick(
    ApiClient api,
    SessionStore store,
    Map<String, dynamic> user,
  ) async {
    final monitor = _monitor;
    if (monitor == null) return;
    var statusText = 'Activando detección';
    try {
      final since = await store.notificationsSince;
      final data = await api.familyStatus(
        notificationsSince: since == null || since.isEmpty
            ? DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 36))
                .toIso8601String()
            : since,
      );
      final watch = familyWatchFromStatus(
        data,
        userId: user['id'] as String?,
      );
      _tripId = watch.tripId ?? _tripId;
      _destinationPlaceId = watch.destinationPlaceId ?? _destinationPlaceId;
      monitor.updatePlaces(watch.places);
      final alerts = _alerts;
      if (alerts != null && watch.notifications.isNotEmpty) {
        await deliverPlannedAlerts(
          store: store,
          alerts: alerts,
          notifications: watch.notifications,
          kid: true,
        );
      }
    } catch (e) {
      debugPrint('KeepAlive family: $e');
      if (monitor.watchedPlaceIds.isEmpty) {
        final cached = await store.places;
        final pending = await store.pendingPlaces;
        monitor.updatePlaces(
          placesForKidGeofence(
            familyPlaces: cached,
            extraPlaces: pending,
          ),
        );
      }
    }

    if (!monitor.running) {
      await monitor.start(foregroundNotification: false);
    }
    await flushPendingGeofenceEvents(api, store);

    if (monitor.running) {
      statusText = monitor.watchedPlaceIds.isEmpty
          ? 'Falta agregar lugares'
          : 'Detección activa';
    } else {
      statusText = monitor.lastError ?? 'Detección apagada';
    }
    _report(
      running: monitor.running,
      status: statusText,
      error: monitor.running ? null : monitor.lastError,
    );
  }

  Future<void> _adultTick(ApiClient api, SessionStore store) async {
    final alerts = _alerts;
    if (alerts == null) return;
    try {
      final since = await store.notificationsSince;
      final data = await api.familyStatus(
        notificationsSince: since == null || since.isEmpty
            ? DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 36))
                .toIso8601String()
            : since,
      );
      final notes = data['notifications'];
      if (notes is! List) return;
      await deliverPlannedAlerts(
        store: store,
        alerts: alerts,
        notifications: [
          for (final item in notes)
            if (item is Map) Map<String, dynamic>.from(item),
        ],
        kid: false,
      );
    } catch (e) {
      debugPrint('KeepAlive alerts: $e');
    }
  }

  Future<void> _onTransition(GeofenceTransition transition) async {
    final store = SessionStore();
    final user = await store.user;
    final token = await store.accessToken;
    if (user == null || user['role'] != 'kid') return;
    if (token == null || token.isEmpty) return;
    final api = await _client(store, user, token);
    final tripId = _tripId;
    final dest = _destinationPlaceId;
    try {
      await postGeofenceTransition(
        api: api,
        transition: transition,
        tripId: tripId,
        destinationPlaceId: dest,
      );
      _report(running: true, status: 'Detección activa', error: null);
    } catch (e) {
      await store.enqueuePendingGeofenceEvent(
        pendingFromTransition(
          transition,
          tripId: tripId,
          destinationPlaceId: dest,
        ),
      );
      debugPrint('KeepAlive event: $e');
      _report(
        running: _monitor?.running == true,
        status: 'Detección activa',
        error: transition.type == 'arrival'
            ? 'No pudimos avisar la llegada. Reintentamos.'
            : 'No pudimos avisar la salida. Reintentamos.',
      );
    }
  }

  void _report({
    required bool running,
    required String status,
    required String? error,
  }) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'detection',
      'running': running,
      'status': status,
      'error': error,
    });
  }
}
