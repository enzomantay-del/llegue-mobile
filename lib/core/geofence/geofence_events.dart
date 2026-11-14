import '../api/api_client.dart';
import '../storage/session_store.dart';
import 'geofence_monitor.dart';

/// POST /events de una llegada o salida. Mismo cuerpo en la pantalla y en
/// el servicio que sigue cuando Android cierra la actividad.
Future<void> postGeofenceTransition({
  required ApiClient api,
  required GeofenceTransition transition,
  String? tripId,
  String? destinationPlaceId,
}) async {
  try {
    await api.postEvent(
      type: transition.type,
      placeId: transition.placeId,
      tripId: tripId,
      forceNotify: true,
      payload: _eventPayload(transition, tripId, destinationPlaceId),
    );
  } on ApiException catch (e) {
    if (!e.isUnauthorized) rethrow;
    // Token vencido: refrescar y reintentar. Si no hay sesión, se relanza
    // y queda en la cola (no se tira el evento).
    await api.refreshSession();
    await api.postEvent(
      type: transition.type,
      placeId: transition.placeId,
      tripId: tripId,
      forceNotify: true,
      payload: _eventPayload(transition, tripId, destinationPlaceId),
    );
  }
}

Map<String, dynamic> _eventPayload(
  GeofenceTransition transition,
  String? tripId,
  String? destinationPlaceId,
) {
  return {
    'source': 'geofence',
    'lat': transition.lat,
    'lng': transition.lng,
    if (tripId != null) 'tripId': tripId,
    if (destinationPlaceId != null) 'destinationPlaceId': destinationPlaceId,
  };
}

Map<String, dynamic> pendingFromTransition(
  GeofenceTransition transition, {
  String? tripId,
  String? destinationPlaceId,
  int? createdAtMs,
}) {
  return {
    'type': transition.type,
    'placeId': transition.placeId,
    'lat': transition.lat,
    'lng': transition.lng,
    'createdAtMs': createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
    if (tripId != null) 'tripId': tripId,
    if (destinationPlaceId != null) 'destinationPlaceId': destinationPlaceId,
  };
}

/// Reintenta avisos que no llegaron al servidor. Corta en el primer fallo
/// para no perder el orden.
Future<int> flushPendingGeofenceEvents(
  ApiClient api,
  SessionStore store,
) async {
  final pending = await store.pendingGeofenceEvents();
  var sent = 0;
  for (final raw in pending) {
    final type = raw['type'];
    if (type is! String || type.isEmpty) {
      await store.removePendingGeofenceEvent(raw);
      continue;
    }
    try {
      await api.postEvent(
        type: type,
        placeId: raw['placeId'] as String?,
        tripId: raw['tripId'] as String?,
        forceNotify: true,
        payload: {
          'source': 'geofence',
          'retry': true,
          'lat': raw['lat'],
          'lng': raw['lng'],
          if (raw['tripId'] != null) 'tripId': raw['tripId'],
          if (raw['destinationPlaceId'] != null)
            'destinationPlaceId': raw['destinationPlaceId'],
        },
      );
      await store.removePendingGeofenceEvent(raw);
      sent++;
    } catch (_) {
      break;
    }
  }
  return sent;
}
