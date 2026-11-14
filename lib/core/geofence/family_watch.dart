import 'geofence_monitor.dart';

/// Lo que el celular del hijo/a tiene que vigilar, sacado de /family/status.
/// Lo usa la pantalla y el servicio que sigue vivo con la app cerrada.
class FamilyWatch {
  const FamilyWatch({
    required this.places,
    required this.notifications,
    this.tripId,
    this.destinationPlaceId,
  });

  final List<Map<String, dynamic>> places;
  final List<Map<String, dynamic>> notifications;
  final String? tripId;
  final String? destinationPlaceId;
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

FamilyWatch familyWatchFromStatus(
  Map<String, dynamic> data, {
  required String? userId,
}) {
  final places = _mapList(data['places']);
  final pending = _mapList(data['pendingPlaces']);
  final members = _mapList(data['members']);
  Map<String, dynamic>? trip;
  for (final member in members) {
    if (userId != null && member['id'] == userId && member['activeTrip'] is Map) {
      trip = Map<String, dynamic>.from(member['activeTrip'] as Map);
      break;
    }
  }
  final top = data['activeTrip'];
  if (trip == null && top is Map) {
    trip = Map<String, dynamic>.from(top);
  }
  final tripId = trip?['id'];
  final destId = trip?['destinationPlaceId'];
  return FamilyWatch(
    places: placesForKidGeofence(
      familyPlaces: places,
      extraPlaces: pending,
      activeTrip: trip,
    ),
    notifications: _mapList(data['notifications']),
    tripId: tripId is String && tripId.isNotEmpty ? tripId : null,
    destinationPlaceId: destId is String && destId.isNotEmpty ? destId : null,
  );
}
