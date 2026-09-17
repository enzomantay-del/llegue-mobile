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

Map<String, dynamic>? _placeById(
  String id,
  List<List<Map<String, dynamic>>> pools,
) {
  for (final pool in pools) {
    for (final p in pool) {
      if (p['id'] == id) return p;
    }
  }
  return null;
}

/// Lugares que el celular del menor tiene que vigilar.
/// No es “solo Casa”: siempre los lugares activos de la familia, y si hay
/// salida especial, el destinationPlaceId entra sí o sí (aunque falte en la
/// lista filtrada o esté pending/inactive), usando lat/lng del lugar o del viaje.
List<Map<String, dynamic>> placesForKidGeofence({
  required List<Map<String, dynamic>> familyPlaces,
  List<Map<String, dynamic>> extraPlaces = const [],
  Map<String, dynamic>? activeTrip,
}) {
  final byId = <String, Map<String, dynamic>>{};

  void put(Map<String, dynamic> raw, {bool ignoreStatus = false}) {
    final id = raw['id'] as String?;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (id == null || id.isEmpty || lat == null || lng == null) return;
    final status = raw['status'] as String?;
    if (!ignoreStatus && status != null && status != 'active') return;
    byId[id] = {
      ...raw,
      'id': id,
      'lat': lat,
      'lng': lng,
    };
  }

  for (final p in familyPlaces) {
    put(p);
  }

  final destId = activeTrip?['destinationPlaceId'] as String?;
  if (destId != null && destId.isNotEmpty) {
    final found = _placeById(destId, [familyPlaces, extraPlaces]);
    final lat = (found?['lat'] as num?)?.toDouble() ??
        (activeTrip?['destinationLat'] as num?)?.toDouble();
    final lng = (found?['lng'] as num?)?.toDouble() ??
        (activeTrip?['destinationLng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      put({
        ...?found,
        'id': destId,
        'name': found?['name'] ?? activeTrip?['destinationName'] ?? 'Destino',
        'lat': lat,
        'lng': lng,
        'radiusM': found?['radiusM'] ??
            activeTrip?['destinationRadiusM'] ??
            60,
        'status': 'active',
      }, ignoreStatus: true);
    }
  }
  return byId.values.toList();
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
    final ids = <String>{};
    for (final p in _places) {
      final id = p['id'] as String?;
      if (id != null) ids.add(id);
    }
    _inside.removeWhere((id, _) => !ids.contains(id));
    _pendingSince.removeWhere((id, _) => !ids.contains(id));
    _pendingType.removeWhere((id, _) => !ids.contains(id));
  }

  /// IDs actualmente en el loop (tests / diagnóstico).
  List<String> get watchedPlaceIds => [
        for (final p in _places)
          if (p['id'] is String) p['id'] as String,
      ];

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

    // Un solo lugar “activo”: el más cercano dentro del radio.
    // Evita quedar “dentro de Casa” y de Plazoleta a la vez (solape de radios)
    // y perder el ENTER al volver a Casa.
    final scored = <({String id, Map<String, dynamic> place, double dist, double radius, bool inside})>[];
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
      scored.add((
        id: id,
        place: place,
        dist: dist,
        radius: radius.toDouble(),
        inside: dist <= radius,
      ));
    }
    if (scored.isEmpty) return;

    String? primaryId;
    final insides = scored.where((s) => s.inside).toList()
      ..sort((a, b) => a.dist.compareTo(b.dist));
    if (insides.isNotEmpty) primaryId = insides.first.id;

    for (final s in scored) {
      final id = s.id;
      final nowInside = primaryId != null && id == primaryId;

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
      // Salida forzada por solape (entra a otro lugar más cerca): gracia más corta.
      final overlapExit = !nowInside && wasInside && primaryId != null;
      final grace = nowInside
          ? enterGrace
          : (overlapExit ? const Duration(seconds: 20) : exitGrace);
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
          placeName: s.place['name'] as String? ?? 'Lugar',
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
