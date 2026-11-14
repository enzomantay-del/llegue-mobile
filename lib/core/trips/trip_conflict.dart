import '../api/api_client.dart';

/// Clave estable para los reintentos de un mismo POST /trips.
/// El servidor puede ignorarla; si la entiende, el segundo intento
/// devuelve el viaje ya creado en vez de abrir otro.
String newIdempotencyKey() {
  final us = DateTime.now().microsecondsSinceEpoch;
  return 'trip-$us-${us % 999983}';
}

Map<String, dynamic>? tripFromApiBody(Map<String, dynamic>? body) {
  if (body == null) return null;
  final trip = body['trip'];
  if (trip is Map) return Map<String, dynamic>.from(trip);
  return null;
}

/// 409 trip_in_progress trae openTrip (id, destination, phase, hora).
Map<String, dynamic>? openTripFromBody(Map<String, dynamic>? body) {
  if (body == null) return null;
  final open = body['openTrip'];
  if (open is Map) return Map<String, dynamic>.from(open);
  return tripFromApiBody(body);
}

bool sameDestination(Map<String, dynamic>? trip, String? destinationPlaceId) {
  if (trip == null) return false;
  final wanted = destinationPlaceId?.trim() ?? '';
  if (wanted.isEmpty) return false;
  final id = trip['destinationPlaceId'];
  if (id is String && id == wanted) return true;
  final dest = trip['destination'];
  if (dest is Map && dest['id'] is String && dest['id'] == wanted) return true;
  return false;
}

String tripDestinationName(Map<String, dynamic>? trip) {
  final name = trip?['destinationName'];
  if (name is String && name.trim().isNotEmpty) return name.trim();
  final dest = trip?['destination'];
  if (dest is String && dest.trim().isNotEmpty) return dest.trim();
  if (dest is Map) {
    final nested = dest['name'];
    if (nested is String && nested.trim().isNotEmpty) return nested.trim();
  }
  return '';
}

String? tripClock(Map<String, dynamic>? trip) {
  final raw = trip?['startedAt'] ?? trip?['createdAt'] ?? trip?['time'];
  if (raw is! String || raw.isEmpty) return null;
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return null;
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Texto del diálogo cuando el servidor (o el celular) ya tiene una salida abierta.
String tripAlreadyOpenBody(Map<String, dynamic>? trip) {
  final dest = tripDestinationName(trip);
  final clock = tripClock(trip);
  final where = dest.isEmpty
      ? 'Ya hay una salida en curso'
      : 'Ya hay una salida en curso a $dest';
  final when = clock == null ? '' : ' (desde $clock)';
  return '$where$when. Si no la cerrás, esta nueva no se registra.';
}

const tripCreateFailedTitle = 'No se armó la salida';

String tripCreateFailedBody(String? message) {
  final text = message?.trim() ?? '';
  if (text.isEmpty) {
    return 'No se registró la salida. Probá de nuevo.';
  }
  return text;
}

/// El POST pudo haber llegado aunque la respuesta se haya perdido.
bool isSoftNetworkFailure(ApiException error) => error.statusCode == null;
