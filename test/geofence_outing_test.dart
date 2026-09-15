import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/geofence/geofence_monitor.dart';

void main() {
  test('salida especial: el menor vigila el destino, no solo Casa', () {
    final home = {
      'id': 'home-1',
      'name': 'Casa',
      'type': 'home',
      'lat': -27.0,
      'lng': -55.0,
      'radiusM': 60,
      'status': 'active',
    };
    final superMarket = {
      'id': 'dest-1',
      'name': 'Supermercado',
      'type': 'favorite',
      'lat': -27.1,
      'lng': -55.1,
      'radiusM': 80,
      'status': 'active',
    };
    final watched = placesForKidGeofence(
      familyPlaces: [home, superMarket],
      activeTrip: {
        'id': 'trip-1',
        'destinationPlaceId': 'dest-1',
        'destinationName': 'Supermercado',
      },
    );
    final ids = watched.map((p) => p['id']).toSet();
    expect(ids.contains('home-1'), isTrue);
    expect(ids.contains('dest-1'), isTrue);

    final monitor = GeofenceMonitor();
    monitor.updatePlaces(watched);
    expect(monitor.watchedPlaceIds, contains('dest-1'));
    expect(monitor.watchedPlaceIds, contains('home-1'));
  });

  test('destino de la especial entra aunque no esté en places activos', () {
    final home = {
      'id': 'home-1',
      'name': 'Casa',
      'type': 'home',
      'lat': -27.0,
      'lng': -55.0,
      'status': 'active',
    };
    final watched = placesForKidGeofence(
      familyPlaces: [home],
      activeTrip: {
        'id': 'trip-1',
        'destinationPlaceId': 'dest-1',
        'destinationName': 'Supermercado',
        'destinationLat': -27.2,
        'destinationLng': -55.2,
      },
    );
    expect(watched.map((p) => p['id']), contains('dest-1'));
    expect(watched.map((p) => p['id']), contains('home-1'));
  });

  test('destino pendiente se fuerza a la geocerca', () {
    final home = {
      'id': 'home-1',
      'name': 'Casa',
      'lat': -27.0,
      'lng': -55.0,
      'status': 'active',
    };
    final pendingDest = {
      'id': 'dest-1',
      'name': 'Supermercado',
      'lat': -27.2,
      'lng': -55.2,
      'status': 'pending_approval',
    };
    final watched = placesForKidGeofence(
      familyPlaces: [home, pendingDest],
      activeTrip: {'id': 'trip-1', 'destinationPlaceId': 'dest-1'},
    );
    final dest = watched.firstWhere((p) => p['id'] == 'dest-1');
    expect(dest['status'], 'active');
    final monitor = GeofenceMonitor();
    monitor.updatePlaces(watched);
    expect(monitor.watchedPlaceIds, contains('dest-1'));
  });

  test('POST de llegada/salida de geofence manda tripId y placeId', () {
    final src =
        File('lib/core/state/app_controller.dart').readAsStringSync();
    expect(src.contains('placesForKidGeofence('), isTrue);
    expect(src.contains('tripId: tripId'), isTrue);
    expect(src.contains("placeId: t.placeId"), isTrue);
    expect(src.contains('_syncGeofencePlaces()'), isTrue);
  });
}
