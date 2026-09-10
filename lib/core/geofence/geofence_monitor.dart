import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeofenceTransition {
  GeofenceTransition({
    required this.type,
    required this.placeId,
    required this.placeName,
    required this.lat,
    required this.lng,
  });

  /// 'arrival' | 'departure'
  final String type;
  final String placeId;
  final String placeName;
  final double lat;
  final double lng;
}

/// Detecta entrar/salir de lugares con tiempo de gracia (anti-rebote GPS).
class GeofenceMonitor {
  GeofenceMonitor({
    // Antes 2–3 min: llegaba tarde en trayectos cortos. 45–60 s alcanza anti-rebote.
    this.enterGrace = const Duration(seconds: 45),
    this.exitGrace = const Duration(seconds: 60),
    this.onTransition,
    this.onStatus,
  });

  final Duration enterGrace;
  final Duration exitGrace;
  final void Function(GeofenceTransition transition)? onTransition;
  final void Function(String status)? onStatus;

  StreamSubscription<Position>? _sub;
  List<Map<String, dynamic>> _places = [];
  final Map<String, bool> _inside = {};
  final Map<String, DateTime> _pendingSince = {};
  final Map<String, String> _pendingType = {};
  bool _primed = false;
  bool running = false;
  String? lastError;

  void updatePlaces(List<Map<String, dynamic>> places) {
    _places = places
        .where((p) => p['status'] == null || p['status'] == 'active')
        .toList();
  }

  Future<void> start() async {
    if (kIsWeb) return;
    await stop();
    lastError = null;
    _primed = false;
    _inside.clear();
    _pendingSince.clear();
    _pendingType.clear();

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      lastError = 'Sin permiso de ubicación';
      onStatus?.call('Sin permiso de ubicación');
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      lastError = 'Ubicación apagada';
      onStatus?.call('Ubicación apagada');
      return;
    }

    LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Llegué activo',
          notificationText: 'Detectando llegadas y salidas',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    }

    try {
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (Object e) {
          lastError = 'Error de ubicación';
          onStatus?.call('Error de ubicación');
          debugPrint('GeofenceMonitor error: $e');
        },
      );
      running = true;
      onStatus?.call('Detección activa');
    } catch (e) {
      lastError = 'No se pudo iniciar la detección';
      onStatus?.call('No se pudo iniciar la detección');
      debugPrint('GeofenceMonitor start failed: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    running = false;
    onStatus?.call('Detección pausada');
  }

  void _onPosition(Position pos) {
    if (_places.isEmpty) {
      onStatus?.call('Falta agregar lugares');
      return;
    }

    for (final place in _places) {
      final id = place['id'] as String?;
      final lat = (place['lat'] as num?)?.toDouble();
      final lng = (place['lng'] as num?)?.toDouble();
      if (id == null || lat == null || lng == null) continue;

      final radius = ((place['radiusM'] as num?)?.toDouble() ?? 60).clamp(40, 500);
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      final nowInside = dist <= radius;

      if (!_primed) {
        _inside[id] = nowInside;
        continue;
      }

      final wasInside = _inside[id] ?? false;
      if (nowInside == wasInside) {
        _pendingSince.remove(id);
        _pendingType.remove(id);
        continue;
      }

      final type = nowInside ? 'arrival' : 'departure';
      final grace = nowInside ? enterGrace : exitGrace;
      final pending = _pendingType[id];
      if (pending != type) {
        _pendingType[id] = type;
        _pendingSince[id] = DateTime.now();
        continue;
      }

      final since = _pendingSince[id];
      if (since == null) {
        _pendingSince[id] = DateTime.now();
        continue;
      }
      if (DateTime.now().difference(since) < grace) continue;

      _inside[id] = nowInside;
      _pendingSince.remove(id);
      _pendingType.remove(id);
      onTransition?.call(
        GeofenceTransition(
          type: type,
          placeId: id,
          placeName: place['name'] as String? ?? 'Lugar',
          lat: pos.latitude,
          lng: pos.longitude,
        ),
      );
    }

    if (!_primed) {
      _primed = true;
      onStatus?.call('Detección activa');
    }
  }
}
