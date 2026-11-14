import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../copy/outing_copy.dart';
import '../device/detection_health.dart';
import '../device/device_identity.dart';
import '../geofence/geofence_events.dart';
import '../geofence/geofence_monitor.dart';
import '../keepalive/keep_alive_host.dart';
import '../keepalive/plugin_keep_alive.dart';
import '../notifications/alert_inbox.dart';
import '../notifications/local_alerts.dart';
import '../notifications/push_service.dart';
import '../permissions/permissions_service.dart';
import '../storage/session_store.dart';
import '../trips/trip_conflict.dart';

class AppController extends ChangeNotifier {
  AppController({
    ApiClient? api,
    SessionStore? store,
    PermissionsService? permissions,
    LocalAlerts? alerts,
    GeofenceMonitor? geofence,
    PushService? push,
    KeepAliveHost? keepAlive,
  }) : api = api ?? ApiClient(),
       store = store ?? SessionStore(),
       permissions = permissions ?? PermissionsService(),
       alerts = alerts ?? LocalAlerts(),
       keepAlive = keepAlive ?? PluginKeepAliveHost() {
    final monitor =
        geofence ??
        GeofenceMonitor(
          onStatus: (status) {
            geofenceStatus = status;
            notifyListeners();
          },
        );
    monitor.onTransition = _onGeofenceTransition;
    monitor.onStatus ??= (status) {
      geofenceStatus = status;
      notifyListeners();
    };
    this.geofence = monitor;
    this.push = push ?? PushService(alerts: this.alerts);
    this.api.onTokensRefreshed = _persistRefreshedTokens;
  }

  final ApiClient api;
  final SessionStore store;
  final PermissionsService permissions;
  final LocalAlerts alerts;
  late final GeofenceMonitor geofence;
  late final PushService push;
  final KeepAliveHost keepAlive;
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
  /// Solo cortes de red / 5xx. Un 401 (token muerto o usuario borrado) no deja
  /// esta bandera: borra la sesión y vuelve al inicio.
  bool sessionValidationFailed = false;
  String? sessionValidationMessage;
  /// La UI debe ir a la pantalla de bienvenida (sesión inválida o Salir).
  bool pendingLoginRedirect = false;
  String? lastError;
  String geofenceStatus = 'Detección pausada';
  bool monitoring = false;
  String? installId;
  String? boundUserName;
  String? boundUserRole;
  String? boundUserPhone;
  bool deviceBoundOnServer = false;

  /// El servidor va a pedir sesión para soltar el celular. Si no hay token,
  /// el próximo ingreso manda reassignDevice (la persona ya confirmó el cambio).
  bool reassignPending = false;

  /// Una vez por proceso: el server solo sella "está compartiendo" si los
  /// avisos figuran granted. El hijo/a no los necesita.
  bool _kidShareStamped = false;

  Timer? _pollTimer;
  Timer? _batteryTimer;
  Timer? _healthTimer;
  Timer? _kidBackgroundTimer;
  Timer? _watchdogTimer;
  DateTime? _lastLowBatterySent;
  bool _inForeground = true;
  bool taskDetectionRunning = false;
  bool keepAliveServiceStarted = false;
  String? lastDetectionError;
  bool? batteryUnrestricted;
  DateTime _suppressDetectionWarningUntil = DateTime.fromMillisecondsSinceEpoch(0);

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

  /// El hijo/a ve esto en Inicio cuando la detección no está corriendo.
  bool get showDetectionOff => detectionLooksOff(
        kid: isKid,
        permissionsReady: permissionsReady,
        inProcessRunning: geofence.running,
        taskRunning: taskDetectionRunning,
        hasStartError:
            !geofence.running &&
            !taskDetectionRunning &&
            (geofence.lastError != null || lastDetectionError != null),
        now: DateTime.now(),
        suppressUntil: _suppressDetectionWarningUntil,
      );

  bool get detectionRunning => geofence.running || taskDetectionRunning;

  String get detectionBannerTitle {
    if (showDetectionOff) return 'Detección apagada';
    if (detectionRunning) return 'Detección activa';
    return 'Activando detección';
  }

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
    boundUserPhone = await store.boundUserPhone;

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
    await refreshPermissionGateFromDevice();

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
  /// Red / 5xx: se queda la sesión local y se puede reintentar.
  /// 401 definitivo (token inválido o usuario que ya no existe): borra
  /// tokens, usuario, familia y lugares, y pide volver al inicio.
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
    debugPrint('[llegue:bootstrap] validationFailed (sesión local conservada): $message');
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
    final rawUser = me['user'];
    if (rawUser is! Map) {
      await dropInvalidSession();
      return;
    }
    final nextUser = Map<String, dynamic>.from(rawUser);
    final userId = nextUser['id'] as String?;
    if (userId == null || userId.isEmpty) {
      await dropInvalidSession();
      return;
    }
    user = nextUser;
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
        if (e.isUnauthorized) {
          await dropInvalidSession();
          return;
        }
        // Red / 5xx en refresh: conservar sesión local para reintentar.
        _markValidationFailed(
          'No pudimos validar la sesión. Revisá la conexión e intentá de nuevo.',
        );
        return;
      } catch (_) {
        _markValidationFailed(
          'No pudimos validar la sesión. Revisá la conexión e intentá de nuevo.',
        );
        return;
      }
    }

    // 401 definitivo: token inválido o el usuario ya no existe en el servidor.
    debugPrint(
      '[llegue:bootstrap] 401 after refresh — clearSession → login. '
      'familyId=${await store.familyId}',
    );
    await dropInvalidSession();
  }

  /// Borra tokens, usuario, familia y lugares. Si la app ya está en pantalla,
  /// pide volver al inicio (no deja el home con sesión muerta).
  Future<void> dropInvalidSession() async {
    final showLogin = bootstrapped;
    await _wipeLocalSession();
    try {
      await refreshDeviceBinding();
    } catch (_) {}
    if (showLogin) {
      pendingLoginRedirect = true;
      notifyListeners();
    }
  }

  Future<void> retrySessionValidation() async {
    await reconcileSessionWithServer();
    // Si Reintentar vuelve a chocar con auth, no dejar el banner en loop.
    if (sessionValidationFailed && !isLoggedIn) {
      await dropInvalidSession();
    }
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
    final hasSession =
        api.accessToken != null && api.accessToken!.isNotEmpty;
    // /devices/lookup pide sesión. Sin token usamos el nombre guardado en el
    // celular (el lookup ya no trae el teléfono).
    if (!hasSession) {
      deviceBoundOnServer =
          boundUserName != null && boundUserName!.trim().isNotEmpty;
      notifyListeners();
      return;
    }
    try {
      final data = await api.lookupInstall(installId!);
      deviceBoundOnServer = data['bound'] == true;
      if (deviceBoundOnServer && data['user'] is Map) {
        final u = Map<String, dynamic>.from(data['user'] as Map);
        boundUserName = u['name'] as String? ?? boundUserName;
        boundUserRole = u['role'] as String? ?? boundUserRole;
        final phone = u['phone'] as String?;
        if (phone != null && phone.isNotEmpty) {
          boundUserPhone = phone;
        }
        await store.setBoundIdentity(
          name: boundUserName,
          role: boundUserRole,
          phone: boundUserPhone,
        );
      } else if (isLoggedIn) {
        // Install nuevo (por ejemplo se dejó de usar Build.ID): todavía no
        // está registrado, pero la sesión sigue siendo de esta persona.
        deviceBoundOnServer = false;
        boundUserName ??= user?['name'] as String?;
        boundUserRole ??= user?['role'] as String?;
        boundUserPhone ??= user?['phone'] as String?;
        await store.setBoundIdentity(
          name: boundUserName,
          role: boundUserRole,
          phone: boundUserPhone,
        );
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
    lastDetectionError = null;
    taskDetectionRunning = false;
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
    final takeReassign = reassignPending;
    final data = await api.registerTitular(
      name: name,
      birthDate: birthDate,
      email: email,
      emailCode: emailCode,
      phone: phone,
      phoneCode: phoneCode,
      installId: installId!,
      platform: _platform,
      reassignDevice: takeReassign,
    );
    if (takeReassign) reassignPending = false;
    await _applyAuth(data);
    permissionsReady = false;
    await store.setPermissionsReady(false);
  }

  Future<void> verifyOtp({
    required String phone,
    required String code,
    String? name,
    bool reassignDevice = false,
    String? inviteToken,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final takeReassign = reassignDevice || reassignPending;
    final data = await api.verifyOtp(
      phone: phone,
      code: code,
      name: name,
      installId: installId!,
      platform: _platform,
      reassignDevice: takeReassign,
      inviteToken: inviteToken,
    );
    if (takeReassign) reassignPending = false;
    await _applyAuth(data);
  }

  Future<void> loginWithPin({
    required String inviteTokenOrCode,
    required String pin,
    bool reassignDevice = false,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final takeReassign = reassignDevice || reassignPending;
    final data = await api.loginWithPin(
      inviteTokenOrCode: inviteTokenOrCode,
      pin: pin,
      installId: installId!,
      platform: _platform,
      reassignDevice: takeReassign,
    );
    if (takeReassign) reassignPending = false;
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

  Future<void> acceptInvitation(
    String token, {
    String? pin,
    bool reassignDevice = false,
  }) async {
    installId ??= await DeviceIdentity.getInstallId();
    final takeReassign = reassignDevice || reassignPending;
    final data = await api.acceptInvitation(
      token,
      pin: pin,
      installId: installId!,
      platform: _platform,
      reassignDevice: takeReassign,
    );
    if (takeReassign) reassignPending = false;
    await _applyAuth(data);
    pendingInviteToken = null;
    await store.setPendingInvite(null);
    permissionsReady = false;
    await store.setPermissionsReady(false);
  }

  Future<void> releaseDeviceForSomeoneElse() async {
    installId ??= await DeviceIdentity.getInstallId();
    final hasSession =
        api.accessToken != null && api.accessToken!.isNotEmpty;
    if (!hasSession) {
      await _armReassignWithoutSession();
      return;
    }
    try {
      await api.releaseDevice(installId: installId!, confirm: true);
    } on ApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      // La sesión no alcanzó para soltar el celular. El próximo ingreso
      // reasigna el aparato: la persona ya confirmó el cambio.
      reassignPending = true;
      await _clearLocalAfterRelease(redirectIfLoggedIn: true);
      return;
    }
    reassignPending = false;
    await _clearLocalAfterRelease(redirectIfLoggedIn: true);
  }

  Future<void> _armReassignWithoutSession() async {
    reassignPending = true;
    deviceBoundOnServer = false;
    boundUserName = null;
    boundUserRole = null;
    boundUserPhone = null;
    await store.clearBoundIdentity();
    notifyListeners();
  }

  Future<void> _clearLocalAfterRelease({required bool redirectIfLoggedIn}) async {
    final showLogin = redirectIfLoggedIn && bootstrapped && isLoggedIn;
    await _wipeLocalSession();
    boundUserName = null;
    boundUserRole = null;
    boundUserPhone = null;
    deviceBoundOnServer = false;
    await store.clearBoundIdentity();
    if (showLogin) pendingLoginRedirect = true;
    notifyListeners();
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
    // El servidor marca "está compartiendo" solo si hay Siempre Y avisos.
    // Al hijo/a le alcanza la ubicación. Si los avisos están apagados,
    // primero sellamos el dispositivo (el server no borra ese sello) y
    // después guardamos el estado real, para que el adulto vea "Sin avisos"
    // y no "Todavía no está compartiendo".
    if (isKid &&
        locationPermission == 'always' &&
        notificationsPermission != 'granted' &&
        !_kidShareStamped) {
      await api.patchPermissions(
        locationPermission: locationPermission,
        notificationsPermission: 'granted',
        deviceId: deviceId,
        locationOk: locationOk,
      );
      _kidShareStamped = true;
    }
    await api.patchPermissions(
      locationPermission: locationPermission,
      notificationsPermission: notificationsPermission,
      deviceId: deviceId,
      locationOk: locationOk,
    );
    final next = permissionsReadyForRole(
      kid: isKid,
      locationPermission: locationPermission,
      notificationsPermission: notificationsPermission,
    );
    final changed = next != permissionsReady;
    permissionsReady = next;
    await store.setPermissionsReady(permissionsReady);
    notifyListeners();
    if (restartServices || changed) await syncRuntimeServices();
    return permissionsReady;
  }

  /// Relee los permisos del sistema. El hijo/a no vuelve a la pantalla de
  /// permisos solo porque apagó los avisos. El adulto no necesita Siempre.
  Future<void> refreshPermissionGateFromDevice() async {
    if (!isLoggedIn || !hasFamily) return;
    try {
      final loc = await permissions.locationStatus();
      final notif = await permissions.notificationsStatus();
      final next = permissionsReadyForRole(
        kid: isKid,
        locationPermission: loc,
        notificationsPermission: notif,
      );
      if (next == permissionsReady) return;
      permissionsReady = next;
      await store.setPermissionsReady(next);
    } catch (_) {}
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
    final since = await _notificationsSince();
    final data = await api.familyStatus(notificationsSince: since);
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
    notifications.sort((a, b) {
      final as = a['createdAt'] as String? ?? a['sentAt'] as String? ?? '';
      final bs = b['createdAt'] as String? ?? b['sentAt'] as String? ?? '';
      return bs.compareTo(as);
    });

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
    await _advanceNotificationCursor();
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

    _suppressDetectionWarningUntil =
        DateTime.now().add(const Duration(seconds: 20));

    // El hijo/a detecta con un servicio de ubicación. El adulto no prende GPS:
    // un servicio en primer plano (sin ubicación) mantiene el poll y los avisos
    // con la pantalla apagada. Sin Firebase, si el proceso muere no hay avisos.
    if (isKid) {
      try {
        await ensureDeviceRegistered().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('device register before detection: $e');
      }
      _syncGeofencePlaces();
      final started = await keepAlive.start(kid: true);
      keepAliveServiceStarted = started;
      if (started) {
        // El servicio es el dueño del GPS. No abrimos un segundo stream.
        if (geofence.running) await geofence.stop();
        monitoring = taskDetectionRunning;
        if (!taskDetectionRunning && geofence.lastError == null) {
          geofenceStatus = 'Activando detección';
        }
      } else if (!geofence.running) {
        await geofence.start();
        monitoring = geofence.running;
        geofenceStatus = geofence.running
            ? (places.isEmpty ? 'Falta agregar lugares' : 'Detección activa')
            : (geofence.lastError ?? 'Detección apagada');
      }
      unawaited(flushPendingGeofenceEvents(api, store));
    } else {
      if (geofence.running) await geofence.stop();
      monitoring = false;
      final started = await keepAlive.start(kid: false);
      keepAliveServiceStarted = started;
      if (started) {
        await alerts.stopListeningOngoing();
        geofenceStatus = 'Avisos en segundo plano';
      } else {
        unawaited(alerts.showListeningOngoing());
        geofenceStatus = 'Detección pausada';
      }
      if (push.ready && push.token != null) {
        unawaited(ensureDeviceRegistered());
      }
    }
    notifyListeners();

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
    _watchdogTimer ??= Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_watchdogTick());
    });
    unawaited(_reportBattery());
    unawaited(reportDeviceHealth());
    unawaited(_refreshBatteryExemption());
    if (isKid) {
      unawaited(reportPresence(state: 'foreground'));
    }
  }

  Future<void> _watchdogTick() async {
    if (!isLoggedIn || !hasFamily || !permissionsReady) return;
    if (isKid) {
      final serviceUp = await keepAlive.isServiceRunning();
      keepAliveServiceStarted = serviceUp;
      if (shouldRestartInProcessDetection(
        serviceRunning: serviceUp,
        inProcessRunning: geofence.running,
      )) {
        await geofence.start();
        monitoring = geofence.running;
        geofenceStatus = geofence.running
            ? 'Detección activa'
            : (geofence.lastError ?? 'Detección apagada');
        notifyListeners();
      }
      await flushPendingGeofenceEvents(api, store);
      return;
    }
    final serviceUp = await keepAlive.isServiceRunning();
    keepAliveServiceStarted = serviceUp;
    if (!serviceUp) {
      final started = await keepAlive.start(kid: false);
      keepAliveServiceStarted = started;
      if (!started) unawaited(alerts.showListeningOngoing());
    }
  }

  /// Lo llama el botón de Inicio cuando la detección está apagada.
  Future<void> restartDetection() async {
    _suppressDetectionWarningUntil =
        DateTime.now().add(const Duration(seconds: 12));
    taskDetectionRunning = false;
    if (geofence.running) await geofence.stop();
    await syncRuntimeServices();
  }

  Future<void> _refreshBatteryExemption() async {
    final next = await keepAlive.isIgnoringBatteryOptimizations();
    if (next == batteryUnrestricted) return;
    batteryUnrestricted = next;
    notifyListeners();
  }

  void onKeepAliveMessage(Object data) {
    if (data is! Map) return;
    if (data['type'] != 'detection') return;
    taskDetectionRunning = data['running'] == true;
    final status = data['status'];
    if (status is String && status.isNotEmpty) geofenceStatus = status;
    if (data.containsKey('error')) {
      final err = data['error'];
      lastDetectionError = err is String && err.isNotEmpty ? err : null;
    }
    monitoring = taskDetectionRunning || geofence.running;
    notifyListeners();
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
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await geofence.stop();
    await keepAlive.stop();
    keepAliveServiceStarted = false;
    taskDetectionRunning = false;
    await alerts.stopListeningOngoing();
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
    if (!isKid || !keepAliveServiceStarted) return;
    keepAlive.sendToTask({
      'type': 'places',
      'tripId': activeTrip?['id'],
      'destinationPlaceId': activeTrip?['destinationPlaceId'],
      'places': [
        for (final place in watched)
          {
            'id': place['id'],
            'name': place['name'],
            'lat': place['lat'],
            'lng': place['lng'],
            'radiusM': place['radiusM'],
            'status': 'active',
          },
      ],
    });
  }

  Future<void> _onGeofenceTransition(GeofenceTransition t) async {
    // Solo el celular del hijo/a genera llegadas y salidas.
    if (!isKid) return;
    final tripId = activeTrip?['id'] as String?;
    final destRaw = activeTrip?['destinationPlaceId'];
    final dest = destRaw is String && destRaw.isNotEmpty ? destRaw : null;
    try {
      await postGeofenceTransition(
        api: api,
        transition: t,
        tripId: tripId,
        destinationPlaceId: dest,
      );
      lastDetectionError = null;
      await refreshFamilyStatus();
    } catch (e) {
      await store.enqueuePendingGeofenceEvent(
        pendingFromTransition(
          t,
          tripId: tripId,
          destinationPlaceId: dest,
        ),
      );
      lastDetectionError = t.type == 'arrival'
          ? 'No pudimos avisar la llegada. Reintentamos.'
          : 'No pudimos avisar la salida. Reintentamos.';
      debugPrint('Geofence event failed: $e');
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> debugHandleTransition(GeofenceTransition transition) =>
      _onGeofenceTransition(transition);

  @visibleForTesting
  Future<void> debugFlushPendingEvents() =>
      flushPendingGeofenceEvents(api, store);

  Future<void> _notifyNewAdultAlerts() async {
    // Con la pantalla apagada avisa el servicio. No marcar vistos acá:
    // si el servicio no llegó a mostrarlos, aparecen al volver.
    if (!_inForeground && keepAliveServiceStarted) return;
    await deliverPlannedAlerts(
      store: store,
      alerts: alerts,
      notifications: notifications,
      kid: isKid,
      formatBody: (notice) => formatFamilyMessage(
        notice['body'] as String? ?? 'Hay un aviso nuevo',
        kidId: notice['kidId'] as String?,
        event: notice,
      ),
      payloadFor: (notice) => _payloadForNotice(
        title: notice['title'] as String? ?? 'Llegué',
        body: notice['body'] as String? ?? '',
        notice: notice,
      ),
    );
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
    _inForeground = state == AppLifecycleState.resumed;
    if (!isLoggedIn || !hasFamily) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
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

  Future<void> _onResumed() async {
    try {
      await refreshFamilyStatus();
    } catch (_) {}
    await syncRuntimeServices();
    if (isKid) {
      final sent = await flushPendingGeofenceEvents(api, store);
      if (sent > 0) lastDetectionError = null;
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
      activeTrip = null;
    }
    try {
      return await startTrip(
        destinationPlaceId: home['id'] as String,
        kind: 'walking_home',
        forceNotify: true,
      );
    } on ApiException catch (e) {
      // Carrera: quedó una salida abierta → cancelar y reintentar una vez.
      // El hijo/a no puede replaceOpen; cierra la suya y vuelve a avisar.
      if (!e.isTripAlreadyOpen) rethrow;
      try {
        final live = await api.activeTrip();
        final id = live['trip'] is Map ? (live['trip'] as Map)['id'] : null;
        if (id is String && id.isNotEmpty) {
          await api.patchTrip(id, action: 'cancel');
        }
      } catch (_) {}
      return startTrip(
        destinationPlaceId: home['id'] as String,
        kind: 'walking_home',
        forceNotify: true,
      );
    }
  }

  Future<String> _notificationsSince() async {
    final saved = await store.notificationsSince;
    if (saved != null && saved.isNotEmpty) return saved;
    return DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 36))
        .toIso8601String();
  }

  Future<void> _advanceNotificationCursor() async {
    final shown = await store.shownAlertIds();
    final next = nextNotificationsSince(
      notifications: notifications,
      shownIds: shown,
    );
    if (next != null) await store.setNotificationsSince(next);
  }

  Future<Map<String, dynamic>> startTrip({
    String? kidId,
    String? destinationPlaceId,
    String? expectedReturnAt,
    String? kind,
    bool? forceNotify,
    bool replaceOpen = false,
  }) async {
    final key = newIdempotencyKey();
    try {
      final data = await api.startTrip(
        kidId: kidId,
        destinationPlaceId: destinationPlaceId,
        expectedReturnAt: expectedReturnAt,
        kind: kind,
        forceNotify: forceNotify,
        createdById: user?['id'] as String?,
        createdByName: displayName,
        idempotencyKey: key,
        replaceOpen: replaceOpen,
      );
      await _rememberTripCreator(data, kidId: kidId);
      await refreshFamilyStatus();
      return data;
    } on ApiException catch (e) {
      Map<String, dynamic>? live;
      if (e.isTripAlreadyOpen || isSoftNetworkFailure(e)) {
        try {
          live = tripFromApiBody(await api.activeTrip(kidId: kidId));
        } catch (_) {}
        live = openTripFromBody(e.body) ?? live;
      }
      if (sameDestination(live, destinationPlaceId)) {
        final recovered = {'trip': live, 'recovered': true};
        await _rememberTripCreator(recovered, kidId: kidId);
        await refreshFamilyStatus();
        return recovered;
      }
      if (e.isTripAlreadyOpen) {
        throw TripAlreadyOpenException(
          e.message.trim().isEmpty ? 'Ya hay una salida en curso' : e.message,
          statusCode: e.statusCode,
          code: e.code,
          body: e.body,
          trip: live,
        );
      }
      rethrow;
    }
  }

  /// El adulto reenvía POST /trips con replaceOpen (clave nueva: el cuerpo cambia).
  /// El hijo/a no puede reemplazar: cierra la suya y crea otra.
  Future<Map<String, dynamic>> replaceOpenTrip({
    String? openTripId,
    String? kidId,
    String? destinationPlaceId,
    String? expectedReturnAt,
    String? kind,
    bool? forceNotify,
  }) async {
    if (isAdult) {
      return startTrip(
        kidId: kidId,
        destinationPlaceId: destinationPlaceId,
        expectedReturnAt: expectedReturnAt,
        kind: kind,
        forceNotify: forceNotify,
        replaceOpen: true,
      );
    }
    if (openTripId == null || openTripId.isEmpty) {
      throw ApiException(
        'No encontramos la salida abierta para cerrarla.',
      );
    }
    await api.patchTrip(openTripId, action: 'cancel');
    if (activeTrip?['id'] == openTripId) activeTrip = null;
    return startTrip(
      kidId: kidId,
      destinationPlaceId: destinationPlaceId,
      expectedReturnAt: expectedReturnAt,
      kind: kind,
      forceNotify: forceNotify,
    );
  }

  Future<void> _rememberTripCreator(
    Map<String, dynamic> data, {
    String? kidId,
  }) async {
    final createdById = user?['id'] as String?;
    final createdByName = displayName;
    final tripRaw = data['trip'];
    if (tripRaw is! Map || createdById == null) return;
    final trip = Map<String, dynamic>.from(tripRaw);
    trip['createdById'] ??= createdById;
    trip['createdByName'] ??= createdByName;
    data['trip'] = trip;
    final tripId = trip['id'] as String?;
    if (tripId == null || tripId.isEmpty) return;
    await store.saveTripCreator(
      tripId: tripId,
      createdById: createdById,
      createdByName: createdByName,
      kidId: kidId ?? (isKid ? (user?['id'] as String?) : null),
    );
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

  Future<void> _wipeLocalSession() async {
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
    lastDetectionError = null;
    taskDetectionRunning = false;
    await store.clearSession();
    notifyListeners();
  }

  Future<void> logout() async {
    final showLogin = bootstrapped;
    await _wipeLocalSession();
    try {
      await refreshDeviceBinding();
    } catch (_) {}
    if (showLogin) {
      pendingLoginRedirect = true;
      notifyListeners();
    }
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
    final phone = user?['phone'] as String?;
    if (phone != null && phone.isNotEmpty) boundUserPhone = phone;
    deviceBoundOnServer = true;
    await store.setBoundIdentity(
      name: boundUserName,
      role: boundUserRole,
      phone: boundUserPhone,
    );
    await store.saveAuth(
      accessToken: api.accessToken!,
      refreshToken: data['refreshToken'] as String? ?? '',
      user: user!,
      family: family,
    );
    notifyListeners();
  }

  /// Hijo/a: ubicación Siempre. Adulto: avisos (no ubicación Siempre).
  String get permissionsEntryRoute =>
      isKid ? '/permissions-location' : '/permissions-notifications';

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
    if (!permissionsReady) return permissionsEntryRoute;
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
