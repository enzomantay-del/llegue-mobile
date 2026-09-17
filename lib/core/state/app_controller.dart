import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/api_client.dart';
import '../copy/outing_copy.dart';
import '../device/device_identity.dart';
import '../geofence/geofence_monitor.dart';
import '../notifications/local_alerts.dart';
import '../notifications/push_service.dart';
import '../permissions/permissions_service.dart';
import '../storage/session_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    ApiClient? api,
    SessionStore? store,
    PermissionsService? permissions,
    LocalAlerts? alerts,
    GeofenceMonitor? geofence,
    PushService? push,
  }) : api = api ?? ApiClient(),
       store = store ?? SessionStore(),
       permissions = permissions ?? PermissionsService(),
       alerts = alerts ?? LocalAlerts() {
    this.geofence =
        geofence ??
        GeofenceMonitor(
          onTransition: _onGeofenceTransition,
          onStatus: (status) {
            geofenceStatus = status;
            notifyListeners();
          },
        );
    this.push = push ?? PushService(alerts: this.alerts);
    this.api.onTokensRefreshed = _persistRefreshedTokens;
  }

  final ApiClient api;
  final SessionStore store;
  final PermissionsService permissions;
  final LocalAlerts alerts;
  late final GeofenceMonitor geofence;
  late final PushService push;
  final Battery _battery = Battery();

  Map<String, dynamic>? user;
  Map<String, dynamic>? family;
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> places = [];
  List<Map<String, dynamic>> pendingPlaces = [];
  List<Map<String, dynamic>> recentEvents = [];
  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic>? activeTrip;
  bool permissionsReady = false;
  bool setupChecklistDone = false;
  bool termsAccepted = false;
  bool keepAliveOnboardingSeen = false;
  String? pendingInviteToken;
  bool bootstrapped = false;
  /// Sesión local intacta pero el server no la validó (401 / outage / DB reset).
  /// No implica clearSession: el usuario puede reintentar o cerrar sesión a mano.
  bool sessionValidationFailed = false;
  String? sessionValidationMessage;
  String? lastError;
  String geofenceStatus = 'Detección pausada';
  bool monitoring = false;
  String? installId;
  String? boundUserName;
  String? boundUserRole;
  String? boundUserPhone;
  bool deviceBoundOnServer = false;

  Timer? _pollTimer;
  Timer? _batteryTimer;
  Timer? _healthTimer;
  Timer? _kidBackgroundTimer;
  final Set<String> _seenNotificationIds = {};
  bool _alertsPrimed = false;
  DateTime? _lastLowBatterySent;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  String get boundRoleLabel {
    if (boundUserRole == 'kid') return 'hijo/a';
    if (boundUserRole == 'admin_adult' || boundUserRole == 'adult') {
      return 'adulto';
    }
    return 'persona';
  }

  bool get isLoggedIn => api.accessToken != null && user != null;
  bool get hasFamily =>
      family != null || (user?['familyId'] as String?)?.isNotEmpty == true;
  bool get isKid => user?['role'] == 'kid';
  bool get isAdult =>
      user?['role'] == 'adult' || user?['role'] == 'admin_adult';

  String get displayName =>
      (user?['name'] as String?)?.trim().isNotEmpty == true
      ? user!['name'] as String
      : 'Sin nombre';

  Future<void> bootstrap() async {
    await alerts.init();
    await push.init();
    installId = await DeviceIdentity.getInstallId();
    boundUserName = await store.boundUserName;
    boundUserRole = await store.boundUserRole;

    // Fase de prueba: siempre el endpoint público actual (evita URLs viejas guardadas).
    api.baseUrl = ApiClient.defaultBaseUrl;
    await store.setBaseUrl(api.baseUrl);

    await restorePersistedSession();
    final hadAccess =
        api.accessToken != null && api.accessToken!.isNotEmpty;
    final hadRefresh =
        api.refreshToken != null && api.refreshToken!.isNotEmpty;
    final hadUserId = (await store.userId)?.isNotEmpty == true;
    final hadFamilyId = (await store.familyId)?.isNotEmpty == true;
    debugPrint(
      '[llegue:bootstrap] prefs before reconcile: '
      'access=$hadAccess refresh=$hadRefresh userId=$hadUserId familyId=$hadFamilyId',
    );

    await refreshDeviceBinding();
    await reconcileSessionWithServer();

    debugPrint(
      '[llegue:bootstrap] after reconcile: loggedIn=$isLoggedIn '
      'hasFamily=$hasFamily validationFailed=$sessionValidationFailed '
      'access=${api.accessToken != null}',
    );

    bootstrapped = true;
    notifyListeners();
    await syncRuntimeServices();
  }

  /// Carga token/refresh/userId/familyId y lugares cacheados. No llama al server.
  Future<void> restorePersistedSession() async {
    api.accessToken = await store.accessToken;
    api.refreshToken = await store.refreshToken;
    user = await store.user;
    family = await store.family;
    places = await store.places;
    pendingPlaces = await store.pendingPlaces;
    permissionsReady = await store.permissionsReady;
    // null = app vieja: no empujar checklist. Solo false fuerza el flujo nuevo.
    setupChecklistDone = (await store.setupChecklistDoneFlag) ?? true;
    termsAccepted = await store.termsAccepted;
    keepAliveOnboardingSeen = await store.keepAliveOnboardingSeen;
    pendingInviteToken = await store.pendingInvite;

    final storedUserId = await store.userId;
    final storedFamilyId = await store.familyId;
    if (user != null && storedUserId != null && storedUserId.isNotEmpty) {
      user!['id'] ??= storedUserId;
    }
    if (storedFamilyId != null && storedFamilyId.isNotEmpty) {
      if (user != null) {
        final existing = user!['familyId'] as String?;
        if (existing == null || existing.isEmpty) {
          user!['familyId'] = storedFamilyId;
        }
      }
      family ??= {'id': storedFamilyId};
    }
  }

  /// Si hay token, confirma sesión contra /auth/me y /family/status.
  /// Red / 5xx: se queda la sesión local.
  /// 401 tras refresh fallido: NO borra prefs (puede ser DB wipe en Render);
  /// marca [sessionValidationFailed] para reintento / login explícito.
  Future<void> reconcileSessionWithServer() async {
    sessionValidationFailed = false;
    sessionValidationMessage = null;
    final hasAccess = api.accessToken != null && api.accessToken!.isNotEmpty;
    final hasRefresh = api.refreshToken != null && api.refreshToken!.isNotEmpty;
    if (!hasAccess && !hasRefresh) return;

    try {
      if (hasRefresh && (!hasAccess || api.accessTokenNearExpiry)) {
        try {
          await api.refreshSession();
        } on ApiException catch (e) {
          // Refresh caído (404 viejo) o red: seguir con /auth/me si el access aún sirve.
          if (e.isUnauthorized) rethrow;
          if (e.isServerError) {
            _markValidationFailed(
              'El servidor no respondió bien. Tus datos locales siguen acá.',
            );
            return;
          }
        }
      }
      await _applyMeAndFamilyStatus();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _recoverFromUnauthorized();
        return;
      }
      if (e.isServerError) {
        _markValidationFailed(
          'El servidor no respondió bien. Tus datos locales siguen acá.',
        );
        return;
      }
      // Red / timeout / 4xx no-auth: conservar sesión local.
      debugPrint('[llegue:bootstrap] reconcile soft-fail: ${e.statusCode} ${e.message}');
    } catch (e) {
      // Offline / timeout: no fingir cuenta nueva.
      debugPrint('[llegue:bootstrap] reconcile offline: $e');
    }
  }

  void _markValidationFailed(String message) {
    sessionValidationFailed = true;
    sessionValidationMessage = message;
    debugPrint('[llegue:bootstrap] validationFailed (no clearSession): $message');
    notifyListeners();
  }

  /// Mensaje claro si el server rechaza invitar por rol/sesión (no el 403 genérico solo).
  String inviteErrorMessage(ApiException e) {
    if (e.isUnauthorized) {
      return 'Tu sesión venció. Cerrá sesión y volvé a entrar como adulto.';
    }
    final msg = e.message;
    final lower = msg.toLowerCase();
    if (isAdult &&
        (lower.contains('solo un adulto') || lower.contains('no es de adulto'))) {
      return 'Tu sesión no es de adulto o quedó desfasada. '
          'Cerrá sesión y volvé a entrar con tu cuenta de padre/madre.';
    }
    if (isKid || lower.contains('solo un adulto')) {
      return 'Los menores no pueden invitar. Pedile a un adulto de la familia.';
    }
    return msg;
  }

  Future<void> _applyMeAndFamilyStatus() async {
    final me = await api.me();
    user = Map<String, dynamic>.from(me['user'] as Map);
    family = me['family'] == null
        ? null
        : Map<String, dynamic>.from(me['family'] as Map);
    await store.saveUser(user!);
    await store.saveFamily(family);
    sessionValidationFailed = false;
    sessionValidationMessage = null;
    if (!hasFamily) return;
    try {
      await refreshFamilyStatus();
    } on ApiException catch (e) {
      if (e.isUnauthorized) rethrow;
      // Red: conservar lugares locales.
    } catch (_) {}
  }

  Future<void> _recoverFromUnauthorized() async {
    final hasRefresh = api.refreshToken != null && api.refreshToken!.isNotEmpty;
    if (hasRefresh) {
      try {
        await api.refreshSession();
        await _applyMeAndFamilyStatus();
        return;
      } on ApiException catch (e) {
        if (!e.isUnauthorized) {
          // Red / 5xx en refresh: conservar sesión local.
          _markValidationFailed(
            'No pudimos validar la sesión. Revisá la conexión e intentá de nuevo.',
          );
          return;
        }
      } catch (_) {
        _markValidationFailed(
          'No pudimos validar la sesión. Revisá la conexión e intentá de nuevo.',
        );
        return;
      }
    }

    // 401 definitivo del server (token inválido o usuario borrado en DB).
    // NO clearSession: puede ser wipe efímero de Render. El usuario reintenta
    // o elige “Cerrar sesión” a mano.
    debugPrint(
      '[llegue:bootstrap] 401 after refresh — keeping local session '
      '(no clearSession). familyId=${await store.familyId}',
    );
    _markValidationFailed(
      'No pudimos validar la sesión con el servidor. '
      'Tus datos en este celular siguen guardados. Reintentá; '
      'si sigue fallando, cerrá sesión desde Ajustes y volvé a entrar.',
    );
  }

  Future<void> retrySessionValidation() async {
    await reconcileSessionWithServer();
    notifyListeners();
  }

  Future<void> _persistRefreshedTokens(
    String accessToken,
    String refreshToken,
    Map<String, dynamic> refreshedUser,
  ) async {
    api.accessToken = accessToken;
    api.refreshToken = refreshToken;
    if (refreshedUser.isNotEmpty) {
      user = refreshedUser;
    }
    if (user == null) return;
    await store.saveAuth(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user!,
      family: family,
    );
  }

  Future<void> refreshDeviceBinding() async {
    installId ??= await DeviceIdentity.getInstallId();
    try {
      final data = await api.lookupInstall(installId!);
      deviceBoundOnServer = data['bound'] == true;
      if (deviceBoundOnServer && data['user'] is Map) {
        final u = Map<String, dynamic>.from(data['user'] as Map);
        boundUserName = u['name'] as String? ?? boundUserName;
        boundUserRole = u['role'] as String? ?? boundUserRole;
        boundUserPhone = u['phone'] as String?;
        await store.setBoundIdentity(name: boundUserName, role: boundUserRole);
      } else {
        deviceBoundOnServer = false;
        boundUserName = null;
        boundUserRole = null;
        boundUserPhone = null;
        await store.clearBoundIdentity();
      }
    } catch (_) {
      deviceBoundOnServer = boundUserName != null;
    }
    notifyListeners();
  }

  /// Deja el celular como instalación nueva (conserva URL del servidor).
  Future<void> resetLocalInstall() async {
    await stopRuntimeServices();
    api.accessToken = null;
    api.refreshToken = null;
    user = null;
    family = null;
    members = [];
    places = [];
    pendingPlaces = [];
    recentEvents = [];
    notifications = [];
    activeTrip = null;
    permissionsReady = false;
    setupChecklistDone = false;
    termsAccepted = false;
    keepAliveOnboardingSeen = false;
    pendingInviteToken = null;
    boundUserName = null;
    boundUserRole = null;
    boundUserPhone = null;
    deviceBoundOnServer = false;
    _seenNotificationIds.clear();
    _alertsPrimed = false;
    await store.clearAllLocal(keepBaseUrl: true);
    installId = await DeviceIdentity.resetInstallId();
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    api.baseUrl = url.trim();
    await store.setBaseUrl(api.baseUrl);
    notifyListeners();
  }

  Future<void> acceptTerms() async {
    termsAccepted = true;
    await store.setTermsAccepted(true);
    notifyListeners();
  }

  Future<void> markKeepAliveOnboardingSeen() async {
    keepAliveOnboardingSeen = true;
    await store.setKeepAliveOnboardingSeen(true);
    notifyListeners();
  }

  Future<Map<String, dynamic>> requestOtp(String phone) async {
    final before = api.baseUrl;
    final data = await api.requestOtp(phone);
    if (api.baseUrl != before) {
      await store.setBaseUrl(api.baseUrl);
    }
    return data;
  }

  Future<Map<String, dynamic>> requestEmailOtp(String email) =>
      api.requestEmailOtp(email);

  Future<void> registerTitular({
    required String name,
    String? birthDate,
    required String email,
    required String emailCode,
    required String phone,
    required String phoneCode,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.registerTitular(
      name: name,
      birthDate: birthDate,
      email: email,
      emailCode: emailCode,
      phone: phone,
      phoneCode: phoneCode,
      installId: installId!,
      platform: _platform,
    );
    await _applyAuth(data);
    permissionsReady = false;
    await store.setPermissionsReady(false);
  }

  Future<void> verifyOtp({
    required String phone,
    required String code,
    String? name,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.verifyOtp(
      phone: phone,
      code: code,
      name: name,
      installId: installId!,
      platform: _platform,
    );
    await _applyAuth(data);
  }

  Future<void> loginWithPin({
    required String inviteTokenOrCode,
    required String pin,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.loginWithPin(
      inviteTokenOrCode: inviteTokenOrCode,
      pin: pin,
      installId: installId!,
      platform: _platform,
    );
    await _applyAuth(data);
    permissionsReady = false;
    await store.setPermissionsReady(false);
  }

  Future<void> createFamily({
    required String familyName,
    required String relationshipLabel,
    required String displayName,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.createFamily(
      name: familyName,
      relationshipLabel: relationshipLabel,
      displayName: displayName,
      installId: installId!,
      platform: _platform,
    );
    await _applyAuth(data);
  }

  Future<void> markSetupChecklistNeeded() async {
    setupChecklistDone = false;
    await store.setSetupChecklistDone(false);
    notifyListeners();
  }

  Future<void> completeSetupChecklist() async {
    setupChecklistDone = true;
    await store.setSetupChecklistDone(true);
    notifyListeners();
  }

  bool get needsSetupChecklist {
    if (!isAdult || !hasFamily || setupChecklistDone) return false;
    final kids = members.where((m) => m['role'] == 'kid');
    final hasHome = places.any((p) {
      final t = p['type'] as String?;
      final n = (p['name'] as String? ?? '').toLowerCase();
      return t == 'home' || n.contains('casa');
    });
    final hasSchool = places.any((p) {
      final t = p['type'] as String?;
      final n = (p['name'] as String? ?? '').toLowerCase();
      return t == 'school' || n.contains('colegio') || n.contains('escuela');
    });
    return kids.isEmpty || !hasHome || !hasSchool;
  }

  Future<Map<String, dynamic>> createInvitation({
    required String name,
    required String role,
    String? pin,
  }) {
    return api.createInvitation(
      name: name,
      role: role,
      pin: pin,
      // Misma URL que usa el celular (IP de la PC), no localhost
      publicBaseUrl: api.baseUrl,
    );
  }

  Future<Map<String, dynamic>> previewInvitation(String token) async {
    final data = await api.getInvitation(token);
    return Map<String, dynamic>.from(data['invitation'] as Map);
  }

  Future<void> acceptInvitation(String token, {String? pin}) async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.acceptInvitation(
      token,
      pin: pin,
      installId: installId!,
      platform: _platform,
    );
    await _applyAuth(data);
    pendingInviteToken = null;
    await store.setPendingInvite(null);
    permissionsReady = false;
    await store.setPermissionsReady(false);
  }

  Future<void> setPendingInvite(String? token) async {
    pendingInviteToken = token?.trim().toUpperCase();
    await store.setPendingInvite(pendingInviteToken);
    notifyListeners();
  }

  Future<void> ensureDeviceRegistered() async {
    installId ??= await DeviceIdentity.getInstallId();
    final data = await api.registerDevice(
      platform: _platform,
      installId: installId!,
      pushToken: push.token,
    );
    final device = Map<String, dynamic>.from(data['device'] as Map);
    await store.setDeviceId(device['id'] as String);
    deviceBoundOnServer = true;
  }

  Future<bool> syncPermissions({
    required String locationPermission,
    required String notificationsPermission,
    bool? locationOk,
    bool restartServices = true,
  }) async {
    await ensureDeviceRegistered();
    final deviceId = await store.deviceId;
    final data = await api.patchPermissions(
      locationPermission: locationPermission,
      notificationsPermission: notificationsPermission,
      deviceId: deviceId,
      locationOk: locationOk,
    );
    permissionsReady = data['permissionsReady'] == true;
    await store.setPermissionsReady(permissionsReady);
    notifyListeners();
    if (restartServices) await syncRuntimeServices();
    return permissionsReady;
  }

  Future<void> reportDeviceHealth() async {
    if (!isLoggedIn) return;
    try {
      final loc = await permissions.locationStatus();
      final notif = await permissions.notificationsStatus();
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      await syncPermissions(
        locationPermission: loc,
        notificationsPermission: notif,
        locationOk: serviceOn && loc != 'denied',
        restartServices: false,
      );
    } catch (_) {}
  }

  Future<void> refreshFamilyStatus() async {
    if (!hasFamily) return;
    final data = await api.familyStatus();
    family = Map<String, dynamic>.from(data['family'] as Map);
    members = (data['members'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    places = (data['places'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    pendingPlaces = (data['pendingPlaces'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    recentEvents = (data['recentEvents'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    notifications = (data['notifications'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    for (var i = 0; i < members.length; i++) {
      final m = members[i];
      if (m['role'] != 'kid') continue;
      final tripRaw = m['activeTrip'];
      if (tripRaw is Map) {
        m['activeTrip'] = await _hydrateTrip(
          Map<String, dynamic>.from(tripRaw),
          kidId: m['id'] as String?,
        );
      }
    }

    if (isKid) {
      Map<String, dynamic>? me;
      for (final m in members) {
        if (m['id'] == user?['id']) {
          me = m;
          break;
        }
      }
      activeTrip = me?['activeTrip'] == null
          ? null
          : Map<String, dynamic>.from(me!['activeTrip'] as Map);
    } else {
      activeTrip = null;
    }

    _syncGeofencePlaces();
    await _notifyNewAdultAlerts();
    await store.saveFamily(family);
    await store.savePlaces(places, pendingPlaces: pendingPlaces);
    // Familia ya armada (seed): no forzar checklist
    if (isAdult &&
        hasFamily &&
        !setupChecklistDone &&
        members.any((m) => m['role'] == 'kid') &&
        places.isNotEmpty) {
      await completeSetupChecklist();
    }
    notifyListeners();
  }

  Future<void> syncRuntimeServices() async {
    if (!isLoggedIn || !hasFamily || !permissionsReady) {
      await stopRuntimeServices();
      return;
    }

    _syncGeofencePlaces();
    if (!geofence.running) {
      await geofence.start();
      monitoring = geofence.running;
      geofenceStatus = geofence.running
          ? (places.isEmpty ? 'Falta agregar lugares' : 'Detección activa')
          : (geofence.lastError ?? 'Detección pausada');
      notifyListeners();
    }

    _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        await refreshFamilyStatus();
      } catch (_) {}
    });

    _batteryTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_reportBattery());
    });
    // Heartbeat frecuente: si el menor cierra la app, el adulto se entera en ~2 min
    _healthTimer ??= Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(reportDeviceHealth());
    });
    unawaited(_reportBattery());
    unawaited(reportDeviceHealth());
    if (isAdult) {
      unawaited(alerts.showListeningOngoing());
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      // Re-registrar token FCM si Firebase ya está listo
      if (push.ready && push.token != null) {
        unawaited(ensureDeviceRegistered());
      }
    }
    if (isKid) {
      unawaited(reportPresence(state: 'foreground'));
    }
  }

  Future<void> stopRuntimeServices() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _kidBackgroundTimer?.cancel();
    _kidBackgroundTimer = null;
    await geofence.stop();
    await alerts.stopListeningOngoing();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    monitoring = false;
    geofenceStatus = 'Detección pausada';
    notifyListeners();
  }

  void _syncGeofencePlaces() {
    final watched = isKid
        ? placesForKidGeofence(
            familyPlaces: places,
            extraPlaces: pendingPlaces,
            activeTrip: activeTrip,
          )
        : places;
    geofence.updatePlaces(watched);
  }

  Future<void> _onGeofenceTransition(GeofenceTransition t) async {
    // Solo el celular del hijo/a genera llegadas y salidas.
    if (!isKid) return;
    try {
      final tripId = activeTrip?['id'] as String?;
      await api.postEvent(
        type: t.type,
        placeId: t.placeId,
        tripId: tripId,
        forceNotify: true,
        payload: {
          'source': 'geofence',
          'lat': t.lat,
          'lng': t.lng,
          if (tripId != null) 'tripId': tripId,
          if (activeTrip?['destinationPlaceId'] != null)
            'destinationPlaceId': activeTrip!['destinationPlaceId'],
        },
      );
      await refreshFamilyStatus();
      // El adulto recibe el aviso por poll/push. Al hijo no le saturamos el celular.
    } catch (e) {
      debugPrint('Geofence event failed: $e');
    }
  }

  String? _formatClock(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _notifyNewAdultAlerts() async {
    if (!_alertsPrimed) {
      for (final n in notifications) {
        final id = n['id'] as String?;
        if (id != null) _seenNotificationIds.add(id);
      }
      for (final e in recentEvents) {
        final id = e['id'] as String?;
        if (id != null) _seenNotificationIds.add('ev-$id');
      }
      _alertsPrimed = true;
      return;
    }

    if (isAdult) {
      for (final n in notifications.reversed) {
        final id = n['id'] as String?;
        if (id == null || _seenNotificationIds.contains(id)) continue;
        _seenNotificationIds.add(id);
        final title = n['title'] as String? ?? 'Llegué';
        var body = n['body'] as String? ?? 'Hay un aviso nuevo';
        final iso = n['createdAt'] as String? ?? n['sentAt'] as String?;
        final clock = _formatClock(iso);
        final eventTime = iso == null
            ? null
            : DateTime.tryParse(iso)?.toLocal();
        // Hora del hecho al frente, para que el padre se guíe aunque el aviso llegue tarde.
        if (clock != null && !body.contains(clock)) {
          body = '$clock · $body';
        }
        body = formatFamilyMessage(body);
        final lower = '${title.toLowerCase()} ${body.toLowerCase()}';
        final urgent =
            lower.contains('ayuda') ||
            lower.contains('llegó') ||
            lower.contains('salió') ||
            lower.contains('regresa') ||
            lower.contains('va a') ||
            lower.contains('demora') ||
            lower.contains('batería') ||
            lower.contains('ubicación') ||
            lower.contains('cerró') ||
            lower.contains('suger') ||
            lower.contains('casa');
        await alerts.show(
          title: title,
          body: body,
          urgent: urgent,
          eventTime: eventTime,
          payload: _payloadForNotice(title: title, body: body, notice: n),
        );
      }
      return;
    }

    // Hijo/a: SOLO aceptaciones del adulto (lugar o salida armada).
    for (final n in notifications.reversed) {
      final id = n['id'] as String?;
      if (id == null || _seenNotificationIds.contains(id)) continue;
      _seenNotificationIds.add(id);
      final title = (n['title'] as String? ?? '').toLowerCase();
      final body = (n['body'] as String? ?? '').toLowerCase();
      final allowed =
          title.contains('lugar') ||
          title.contains('salida') ||
          body.contains('acept') ||
          body.contains('armar') ||
          body.contains('podés usar');
      if (!allowed) continue;
      await alerts.show(
        title: n['title'] as String? ?? 'Llegué',
        body: formatFamilyMessage(n['body'] as String? ?? 'Hay una novedad'),
      );
    }
  }

  Future<void> _reportBattery() async {
    if (!isLoggedIn || kIsWeb) return;
    try {
      final level = await _battery.batteryLevel;
      final deviceId = await store.deviceId;
      await api.reportBattery(batteryLevel: level, deviceId: deviceId);
      if (isKid &&
          level <= 20 &&
          (_lastLowBatterySent == null ||
              DateTime.now().difference(_lastLowBatterySent!) >
                  const Duration(hours: 2))) {
        _lastLowBatterySent = DateTime.now();
      }
    } catch (_) {}
  }

  Future<void> reportPresence({
    required String state,
    bool immediate = false,
  }) async {
    if (!isLoggedIn || !isKid) return;
    try {
      final deviceId = await store.deviceId;
      await api.reportPresence(
        state: state,
        deviceId: deviceId,
        immediate: immediate,
      );
    } catch (_) {}
  }

  /// Ciclo de vida del celular del menor.
  /// Pantalla apagada / ahorro ≠ cerró la app. Solo avisamos al cerrar de verdad.
  void onAppLifecycle(AppLifecycleState state) {
    if (!isLoggedIn || !hasFamily) return;
    if (!isKid) return;

    if (state == AppLifecycleState.resumed) {
      _kidBackgroundTimer?.cancel();
      _kidBackgroundTimer = null;
      unawaited(reportPresence(state: 'foreground'));
      return;
    }

    // inactive / hidden / paused = pantalla apagada, otra app, o ahorro.
    // No es “cerró Llegué”: no avisamos al padre.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      return;
    }

    if (state == AppLifecycleState.detached) {
      _kidBackgroundTimer?.cancel();
      unawaited(reportPresence(state: 'background', immediate: true));
    }
  }

  Future<Map<String, dynamic>> createPlace({
    required String name,
    required double lat,
    required double lng,
    String type = 'favorite',
  }) async {
    final data = await api.createPlace(
      name: name,
      lat: lat,
      lng: lng,
      type: type,
    );
    await refreshFamilyStatus();
    await syncRuntimeServices();
    return data;
  }

  Future<Map<String, dynamic>> suggestPlace({
    required String name,
    required double lat,
    required double lng,
  }) async {
    final data = await api.suggestPlace(name: name, lat: lat, lng: lng);
    await refreshFamilyStatus();
    return data;
  }

  Future<void> approvePlace(String placeId) async {
    await api.approvePlace(placeId);
    await refreshFamilyStatus();
    await syncRuntimeServices();
  }

  Future<void> deletePlace(String placeId) async {
    await api.deletePlace(placeId);
    await refreshFamilyStatus();
    _syncGeofencePlaces();
  }

  Future<Map<String, dynamic>> updatePlace({
    required String placeId,
    required String name,
    required double lat,
    required double lng,
    String type = 'favorite',
  }) async {
    final data = await api.updatePlace(
      placeId: placeId,
      name: name,
      lat: lat,
      lng: lng,
      type: type,
    );
    await refreshFamilyStatus();
    await syncRuntimeServices();
    return data;
  }

  Future<Map<String, dynamic>> createRoutine({
    required String kidId,
    required String placeId,
    required String label,
    required List<int> daysOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final data = await api.createRoutine(
      kidId: kidId,
      placeId: placeId,
      label: label,
      daysOfWeek: daysOfWeek,
      startTime: startTime,
      endTime: endTime,
    );
    await refreshFamilyStatus();
    return data;
  }

  Future<Map<String, dynamic>> updateRoutine({
    required String routineId,
    required String kidId,
    required String placeId,
    required String label,
    required List<int> daysOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final data = await api.updateRoutine(
      routineId: routineId,
      kidId: kidId,
      placeId: placeId,
      label: label,
      daysOfWeek: daysOfWeek,
      startTime: startTime,
      endTime: endTime,
    );
    await refreshFamilyStatus();
    return data;
  }

  Future<void> deleteRoutine(String routineId) async {
    await api.deleteRoutine(routineId);
  }

  Future<void> updateActiveTrip({
    required String tripId,
    String? destinationPlaceId,
  }) async {
    await api.patchTrip(
      tripId,
      action: 'update',
      destinationPlaceId: destinationPlaceId,
    );
    await refreshFamilyStatus();
  }

  Future<Map<String, bool>> loadAlertPrefs() async {
    final data = await api.getAlertPrefs();
    final raw = Map<String, dynamic>.from(data['prefs'] as Map? ?? {});
    return raw.map((k, v) => MapEntry(k, v == true));
  }

  Future<Map<String, bool>> saveAlertPrefs(Map<String, bool> prefs) async {
    final data = await api.putAlertPrefs(prefs);
    final raw = Map<String, dynamic>.from(data['prefs'] as Map? ?? {});
    return raw.map((k, v) => MapEntry(k, v == true));
  }

  Future<Map<String, dynamic>> loadAccountProfile() async {
    return api.getAccountProfile();
  }

  Future<Map<String, dynamic>> saveAccountProfile(
    Map<String, dynamic> body,
  ) async {
    final data = await api.updateAccountProfile(body);
    final u = data['user'];
    if (u is Map) {
      user = Map<String, dynamic>.from(u);
      await store.saveUser(user!);
    }
    final f = data['family'];
    if (f is Map) {
      family = Map<String, dynamic>.from(f);
      await store.saveFamily(family);
    }
    notifyListeners();
    return data;
  }

  Map<String, dynamic>? get homePlace {
    for (final p in places) {
      if (p['type'] == 'home') return p;
    }
    return null;
  }

  bool get needsGoHome {
    if (!isKid) return false;
    for (final m in members) {
      if (m['id'] == user?['id']) {
        return m['needsGoHome'] == true;
      }
    }
    return activeTrip != null && activeTrip!['expectedReturnAt'] == null;
  }

  /// Atajo: avisar que voy a casa (cierra salida abierta y abre viaje a Casa).
  Future<Map<String, dynamic>> goHome() async {
    final home = homePlace;
    if (home == null) {
      throw ApiException(
        'Todavía no hay un lugar Casa. Pedile a un adulto que lo agregue.',
      );
    }
    if (activeTrip != null) {
      try {
        await api.patchTrip(activeTrip!['id'] as String, action: 'cancel');
      } catch (_) {}
    }
    return startTrip(
      destinationPlaceId: home['id'] as String,
      kind: 'walking_home',
    );
  }

  Future<Map<String, dynamic>> startTrip({
    String? kidId,
    String? destinationPlaceId,
    String? expectedReturnAt,
    String? kind,
    bool? forceNotify,
  }) async {
    final createdById = user?['id'] as String?;
    final createdByName = displayName;
    final data = await api.startTrip(
      kidId: kidId,
      destinationPlaceId: destinationPlaceId,
      expectedReturnAt: expectedReturnAt,
      kind: kind,
      forceNotify: forceNotify,
      createdById: createdById,
      createdByName: createdByName,
    );
    final tripRaw = data['trip'];
    if (tripRaw is Map && createdById != null) {
      final trip = Map<String, dynamic>.from(tripRaw);
      trip['createdById'] ??= createdById;
      trip['createdByName'] ??= createdByName;
      data['trip'] = trip;
      final tripId = trip['id'] as String?;
      if (tripId != null && tripId.isNotEmpty) {
        await store.saveTripCreator(
          tripId: tripId,
          createdById: createdById,
          createdByName: createdByName,
          kidId: kidId ?? (isKid ? (user?['id'] as String?) : null),
        );
      }
    }
    await refreshFamilyStatus();
    return data;
  }

  Future<Map<String, dynamic>> arriveTrip(String tripId) async {
    final data = await api.patchTrip(tripId, action: 'arrive');
    await refreshFamilyStatus();
    return data;
  }

  Future<Map<String, dynamic>> cancelTrip(String tripId) async {
    final data = await api.patchTrip(tripId, action: 'cancel');
    await refreshFamilyStatus();
    return data;
  }

  Future<Map<String, dynamic>> postEvent({
    required String type,
    String? placeId,
  }) async {
    final data = await api.postEvent(type: type, placeId: placeId);
    await refreshFamilyStatus();
    return data;
  }

  Future<void> logout() async {
    await stopRuntimeServices();
    api.accessToken = null;
    api.refreshToken = null;
    user = null;
    family = null;
    members = [];
    places = [];
    pendingPlaces = [];
    recentEvents = [];
    notifications = [];
    activeTrip = null;
    permissionsReady = false;
    sessionValidationFailed = false;
    sessionValidationMessage = null;
    _seenNotificationIds.clear();
    _alertsPrimed = false;
    // Conserva boundUserName/Role e installId: este celular sigue siendo de esa persona
    await store.clearSession();
    await refreshDeviceBinding();
    notifyListeners();
  }

  Future<void> _applyAuth(Map<String, dynamic> data) async {
    api.accessToken = data['accessToken'] as String?;
    api.refreshToken = data['refreshToken'] as String? ?? '';
    user = Map<String, dynamic>.from(data['user'] as Map);
    family = data['family'] == null
        ? null
        : Map<String, dynamic>.from(data['family'] as Map);
    if (data['deviceId'] != null) {
      await store.setDeviceId(data['deviceId'] as String);
    }
    boundUserName = user?['name'] as String?;
    boundUserRole = user?['role'] as String?;
    deviceBoundOnServer = true;
    await store.saveAuth(
      accessToken: api.accessToken!,
      refreshToken: data['refreshToken'] as String? ?? '',
      user: user!,
      family: family,
    );
    notifyListeners();
  }

  String get startRoute {
    if (!isLoggedIn) {
      if (pendingInviteToken != null && pendingInviteToken!.isNotEmpty) {
        return '/join';
      }
      return '/';
    }
    if (!hasFamily) {
      if (pendingInviteToken != null && pendingInviteToken!.isNotEmpty) {
        return '/join';
      }
      return '/create-family';
    }
    if (!permissionsReady) return '/permissions-location';
    if (!keepAliveOnboardingSeen) return '/onboarding-keep-alive';
    if (isAdult && !setupChecklistDone) return '/setup-checklist';
    return '/home';
  }

  Future<Map<String, dynamic>> _hydrateTrip(
    Map<String, dynamic> trip, {
    String? kidId,
  }) async {
    if (OutingCopy.creatorNameFromTrip(trip) != null &&
        OutingCopy.creatorIdFromTrip(trip) != null) {
      return trip;
    }
    final saved = await store.tripCreator(
      tripId: trip['id'] as String?,
      kidId: kidId ?? trip['kidId'] as String?,
    );
    if (saved == null) return trip;
    trip['createdById'] ??= saved['createdById'];
    trip['createdByName'] ??= saved['createdByName'];
    return trip;
  }

  Map<String, dynamic>? tripForKid(String? kidId) {
    if (kidId == null) return isKid ? activeTrip : null;
    for (final m in members) {
      if (m['id'] == kidId && m['activeTrip'] is Map) {
        return Map<String, dynamic>.from(m['activeTrip'] as Map);
      }
    }
    return null;
  }

  String _kidName(String? kidId) {
    if (kidId != null) {
      for (final m in members) {
        if (m['id'] == kidId) {
          final n = (m['name'] as String?)?.trim();
          if (n != null && n.isNotEmpty) return n;
        }
      }
    }
    if (isKid) return displayName;
    final kids = members.where((m) => m['role'] == 'kid').toList();
    if (kids.length == 1) {
      return (kids.first['name'] as String?)?.trim().isNotEmpty == true
          ? kids.first['name'] as String
          : 'tu hijo/a';
    }
    return 'tu hijo/a';
  }

  ({String? id, String? name, bool viewerCreated}) resolveOutingCreator({
    Map<String, dynamic>? trip,
    Map<String, dynamic>? event,
    String? kidId,
  }) {
    Map<String, dynamic>? payload;
    final rawPayload = event?['payload'];
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    }
    var id =
        OutingCopy.creatorIdFromTrip(trip) ??
        payload?['createdById'] as String? ??
        payload?['createdByUserId'] as String?;
    var name =
        OutingCopy.creatorNameFromTrip(trip) ??
        payload?['createdByName'] as String?;
    if ((name ?? '').trim().isEmpty) name = null;

    if (id == null || name == null) {
      final adults = members
          .where((m) => m['role'] == 'adult' || m['role'] == 'admin_adult')
          .toList();
      final titular = adults.where((m) => m['role'] == 'admin_adult').toList();
      Map<String, dynamic>? guess;
      if (adults.length == 1) {
        guess = adults.first;
      } else if (titular.length == 1) {
        guess = titular.first;
      }
      if (guess != null) {
        id ??= guess['id'] as String?;
        name ??= (guess['name'] as String?)?.trim();
      }
    }

    final viewerId = user?['id'] as String? ?? '';
    return (id: id, name: name, viewerCreated: id != null && id == viewerId);
  }

  String formatFamilyMessage(
    String raw, {
    String? kidName,
    String? kidId,
    Map<String, dynamic>? trip,
    Map<String, dynamic>? event,
  }) {
    if (!OutingCopy.looksLikeSpecialOutingCopy(raw)) return raw;
    final resolvedKidId =
        kidId ?? event?['kidId'] as String? ?? trip?['kidId'] as String?;
    final resolvedTrip = trip ?? tripForKid(resolvedKidId);
    final creator = resolveOutingCreator(
      trip: resolvedTrip,
      event: event,
      kidId: resolvedKidId,
    );
    return OutingCopy.rewrite(
      raw: raw,
      viewerIsKid: isKid,
      viewerId: user?['id'] as String? ?? '',
      kidName: kidName ?? _kidName(resolvedKidId),
      creatorId: creator.id,
      creatorName: creator.name,
      destination: resolvedTrip?['destinationName'] as String?,
      viewerCreated: creator.viewerCreated,
    );
  }

  String? _payloadForNotice({
    required String title,
    required String body,
    Map<String, dynamic>? notice,
  }) {
    final info = KidOfflineInfo.resolve(
      title: title,
      body: body,
      type: notice?['type'] as String?,
      kidId: notice?['kidId'] as String?,
      members: members,
    );
    if (info == null) return null;
    return jsonEncode(info.toJson());
  }

  KidOfflineInfo? kidOfflineFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final map = jsonDecode(payload);
      if (map is Map) {
        return KidOfflineInfo.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return KidOfflineInfo.resolve(
      title: payload,
      body: payload,
      members: members,
    );
  }
}
