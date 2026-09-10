import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionsService {
  Future<String> locationStatus() async {
    if (kIsWeb) return 'while_in_use';
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return 'denied';
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return 'not_asked';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'denied';
    }
    if (permission == LocationPermission.always) {
      return 'always';
    }
    return 'while_in_use';
  }

  Future<String> requestLocationChain() async {
    if (kIsWeb) return 'while_in_use';
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) {
      await Geolocator.openLocationSettings();
      return 'denied';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'denied';
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.unableToDetermine) {
      if (!kIsWeb && Platform.isAndroid) {
        final bg = await ph.Permission.locationAlways.request();
        if (bg.isGranted) return 'always';
      } else {
        permission = await Geolocator.requestPermission();
      }
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return 'always';
    if (permission == LocationPermission.whileInUse) return 'while_in_use';
    return 'denied';
  }

  Future<String> notificationsStatus() async {
    if (kIsWeb) return 'granted';
    final status = await ph.Permission.notification.status;
    if (status.isGranted) return 'granted';
    if (status.isDenied) return 'not_asked';
    if (status.isPermanentlyDenied) return 'denied';
    return 'not_asked';
  }

  Future<String> requestNotifications() async {
    if (kIsWeb) return 'granted';
    final status = await ph.Permission.notification.request();
    return status.isGranted ? 'granted' : 'denied';
  }

  Future<void> openSettings() => ph.openAppSettings();
}
