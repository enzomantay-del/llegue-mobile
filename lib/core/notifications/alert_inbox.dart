import '../storage/session_store.dart';
import 'local_alerts.dart';

/// Qué avisos hay que mostrar y cuáles son historia vieja del primer arranque.
class AlertDeliveryPlan {
  const AlertDeliveryPlan({required this.toShow, required this.markQuiet});

  final List<Map<String, dynamic>> toShow;

  /// Historia anterior al baseline, o avisos que el hijo/a no tiene que oír.
  /// No son alertas perdidas: quedan en la lista y no suenan.
  final List<String> markQuiet;
}

DateTime? alertCreatedAt(Map<String, dynamic> notice) {
  final iso = notice['createdAt'] as String? ?? notice['sentAt'] as String?;
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

bool kidShouldSeeNotice(Map<String, dynamic> notice) {
  final title = (notice['title'] as String? ?? '').toLowerCase();
  final body = (notice['body'] as String? ?? '').toLowerCase();
  return title.contains('lugar') ||
      title.contains('salida') ||
      body.contains('acept') ||
      body.contains('armar') ||
      body.contains('podés usar');
}

bool alertLooksUrgent(String title, String body) {
  final lower = '${title.toLowerCase()} ${body.toLowerCase()}';
  return lower.contains('ayuda') ||
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
}

String withEventClock(String body, String? iso) {
  final created = iso == null || iso.isEmpty
      ? null
      : DateTime.tryParse(iso)?.toLocal();
  if (created == null) return body;
  final clock =
      '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
  if (body.contains(clock)) return body;
  return '$clock · $body';
}

/// Sin baseline (primera vez con esta versión): se muestran los avisos de las
/// últimas [historyWindow]. Los más viejos no suenan, para no vaciar el historial,
/// y siguen en la lista de la app.
/// Con baseline, todo lo que no se mostró se muestra. Un aviso reciente no se
/// marca visto sin haberlo mostrado.
AlertDeliveryPlan planAlertDelivery({
  required List<Map<String, dynamic>> notifications,
  required Set<String> alreadyShown,
  required bool hasBaseline,
  required DateTime now,
  required bool kid,
  Duration historyWindow = const Duration(hours: 36),
}) {
  final toShow = <Map<String, dynamic>>[];
  final markQuiet = <String>[];
  final cutoff = now.subtract(historyWindow);
  for (final n in notifications) {
    final id = n['id'];
    if (id is! String || id.isEmpty || alreadyShown.contains(id)) continue;
    if (kid && !kidShouldSeeNotice(n)) {
      markQuiet.add(id);
      continue;
    }
    final created = alertCreatedAt(n);
    final recent = created == null || !created.isBefore(cutoff);
    if (!hasBaseline && !recent) {
      markQuiet.add(id);
      continue;
    }
    toShow.add(n);
  }
  return AlertDeliveryPlan(toShow: toShow, markQuiet: markQuiet);
}

/// Muestra avisos nuevos y recién después los marca vistos.
/// Si el aviso no se puede mostrar, no queda marcado: se reintenta.
Future<int> deliverPlannedAlerts({
  required SessionStore store,
  required LocalAlerts alerts,
  required List<Map<String, dynamic>> notifications,
  required bool kid,
  String Function(Map<String, dynamic> notice)? formatBody,
  String? Function(Map<String, dynamic> notice)? payloadFor,
  DateTime? now,
}) async {
  final shown = await store.shownAlertIds();
  final baseline = await store.hasAlertBaseline();
  final plan = planAlertDelivery(
    notifications: notifications,
    alreadyShown: shown,
    hasBaseline: baseline,
    now: now ?? DateTime.now(),
    kid: kid,
  );
  if (plan.markQuiet.isNotEmpty) {
    await store.markAlertsShown(plan.markQuiet);
  }
  var delivered = 0;
  for (final n in plan.toShow) {
    final id = n['id'] as String;
    final claimed = await store.tryClaimAlert(id);
    if (!claimed) continue;
    final title = n['title'] as String? ?? 'Llegué';
    final iso = n['createdAt'] as String? ?? n['sentAt'] as String?;
    var body = n['body'] as String? ?? 'Hay un aviso nuevo';
    if (formatBody != null) body = formatBody(n);
    body = withEventClock(body, iso);
    final eventTime = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    try {
      await alerts.show(
        title: title,
        body: body,
        urgent: alertLooksUrgent(title, body),
        eventTime: eventTime,
        payload: payloadFor?.call(n),
        idKey: id,
      );
      await store.markAlertShown(id);
      delivered++;
    } catch (_) {
      // El reclamo vence solo. No se marca visto.
    }
  }
  if (!baseline) await store.setAlertBaseline();
  return delivered;
}

/// Cursor para /family/status?notificationsSince= y /notifications/me?since=.
/// Si queda alguno sin mostrar, no avanzamos más allá de ese.
String? nextNotificationsSince({
  required List<Map<String, dynamic>> notifications,
  required Set<String> shownIds,
}) {
  DateTime? oldestUnshown;
  DateTime? newestShown;
  for (final notice in notifications) {
    final id = notice['id'];
    final created = alertCreatedAt(notice)?.toUtc();
    if (id is! String || created == null) continue;
    if (!shownIds.contains(id)) {
      if (oldestUnshown == null || created.isBefore(oldestUnshown)) {
        oldestUnshown = created;
      }
    } else if (newestShown == null || created.isAfter(newestShown)) {
      newestShown = created;
    }
  }
  final cursor = oldestUnshown ?? newestShown;
  if (cursor == null) return null;
  return cursor.subtract(const Duration(seconds: 1)).toIso8601String();
}
