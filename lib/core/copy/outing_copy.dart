/// Copy de salida especial según quién mira y quién la armó.
class OutingCopy {
  static const kidFallback =
      'Te armaron una salida especial';

  static String destinationFrom(String? name) {
    final n = name?.trim() ?? '';
    return n;
  }

  static String? creatorNameFromTrip(Map<String, dynamic>? trip) {
    if (trip == null) return null;
    for (final key in [
      'createdByName',
      'created_by_name',
      'creatorName',
      'createdBy',
    ]) {
      final v = trip[key];
      if (v is String && v.trim().isNotEmpty && !_looksLikeId(v)) {
        return v.trim();
      }
    }
    final nested = trip['createdBy'];
    if (nested is Map) {
      final n = nested['name'] as String?;
      if (n != null && n.trim().isNotEmpty) return n.trim();
    }
    return null;
  }

  static String? creatorIdFromTrip(Map<String, dynamic>? trip) {
    if (trip == null) return null;
    for (final key in [
      'createdById',
      'createdByUserId',
      'created_by_user_id',
      'creatorId',
    ]) {
      final v = trip[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final nested = trip['createdBy'];
    if (nested is Map) {
      final id = nested['id'] as String?;
      if (id != null && id.trim().isNotEmpty) return id.trim();
    }
    return null;
  }

  static bool _looksLikeId(String v) {
    return v.length >= 20 && !v.contains(' ');
  }

  /// Texto para Home / avisos.
  static String specialOuting({
    required bool viewerIsKid,
    required String viewerId,
    required String kidName,
    required String destination,
    String? creatorId,
    String? creatorName,
    bool viewerCreated = false,
    bool isHome = false,
  }) {
    final dest = destination.trim();
    final destPart = dest.isEmpty ? '' : ' a $dest';
    final kid = kidName.trim().isEmpty ? 'tu hijo/a' : kidName.trim();
    final creator = (creatorName ?? '').trim();
    final creatorIsViewer = viewerCreated ||
        (creatorId != null && creatorId.isNotEmpty && creatorId == viewerId);

    if (isHome) {
      if (viewerIsKid) {
        if (creator.isEmpty || creatorIsViewer) {
          return 'Te armaron un regreso a casa';
        }
        return '$creator te armó un regreso a casa';
      }
      if (creatorIsViewer) {
        return 'Armaste un regreso a casa para $kid';
      }
      if (creator.isNotEmpty) {
        return '$creator armó un regreso a casa para $kid';
      }
      return 'Hay un regreso a casa para $kid';
    }

    if (viewerIsKid) {
      if (creator.isNotEmpty && !creatorIsViewer) {
        return '$creator te armó una salida especial$destPart';
      }
      return dest.isEmpty ? kidFallback : '$kidFallback a $dest';
    }

    // Adulto: nunca “Te armaron…”.
    if (creatorIsViewer) {
      return dest.isEmpty
          ? 'Armaste una salida especial para $kid'
          : 'Armaste una salida especial para $kid a $dest';
    }
    if (creator.isNotEmpty) {
      return dest.isEmpty
          ? '$creator armó una salida especial para $kid'
          : '$creator armó una salida especial para $kid a $dest';
    }
    return dest.isEmpty
        ? 'Hay una salida especial para $kid'
        : 'Hay una salida especial para $kid a $dest';
  }

  static bool looksLikeSpecialOutingCopy(String raw) {
    final t = raw.toLowerCase();
    return t.contains('te armaron') ||
        t.contains('te armó') ||
        t.contains('te armo') ||
        t.contains('armaste una salida') ||
        t.contains('armaste un regreso') ||
        t.contains('armó una salida especial') ||
        t.contains('armo una salida especial') ||
        t.contains('armó un regreso') ||
        t.contains('armo un regreso');
  }

  static String? destinationFromMessage(String raw) {
    final t = raw.trim();
    final special = RegExp(
      r'salida especial(?:\s+para\s+.+?)?(?:\s+a\s+(.+))$',
      caseSensitive: false,
    ).firstMatch(t);
    final dest = special?.group(1)?.trim();
    if (dest != null && dest.isNotEmpty) return dest;
    final armed = RegExp(
      r'te arm[oóó].+?\s+a\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    return armed?.group(1)?.trim();
  }

  static bool isHomeOutingMessage(String raw) {
    final t = raw.toLowerCase();
    return t.contains('regreso a casa') || t.contains('regresa a casa');
  }

  /// Reescribe “Te armaron…” u otros textos de salida especial al punto de vista
  /// de quien está mirando. Si no es ese tipo de aviso, devuelve el original.
  static String rewrite({
    required String raw,
    required bool viewerIsKid,
    required String viewerId,
    required String kidName,
    String? creatorId,
    String? creatorName,
    String? destination,
    bool viewerCreated = false,
  }) {
    final text = raw.trim();
    if (text.isEmpty || !looksLikeSpecialOutingCopy(text)) return raw;

    final dest = (destination?.trim().isNotEmpty == true)
        ? destination!.trim()
        : (destinationFromMessage(text) ?? '');
    return specialOuting(
      viewerIsKid: viewerIsKid,
      viewerId: viewerId,
      kidName: kidName,
      destination: dest,
      creatorId: creatorId,
      creatorName: creatorName,
      viewerCreated: viewerCreated,
      isHome: isHomeOutingMessage(text),
    );
  }
}

class KidOfflineInfo {
  const KidOfflineInfo({
    required this.kidName,
    this.kidId,
    this.kidPhone,
  });

  final String kidName;
  final String? kidId;
  final String? kidPhone;

  static const payloadKind = 'kid_offline';
  static const whatsappText =
      'Abrí Llegué, así sé cuándo llegás o salís 📍';

  Map<String, dynamic> toJson() => {
        'kind': payloadKind,
        'kidName': kidName,
        if (kidId != null) 'kidId': kidId,
        if (kidPhone != null) 'kidPhone': kidPhone,
      };

  static KidOfflineInfo? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    if (map['kind'] != payloadKind) return null;
    final name = (map['kidName'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return KidOfflineInfo(
      kidName: name,
      kidId: map['kidId'] as String?,
      kidPhone: map['kidPhone'] as String?,
    );
  }

  static bool matches({String? title, String? body, String? type}) {
    final t = '${title ?? ''} ${body ?? ''} ${type ?? ''}'.toLowerCase();
    return t.contains('location_lost') ||
        t.contains('app_closed') ||
        t.contains('ubicación cortada') ||
        t.contains('ubicacion cortada') ||
        t.contains('dejó de compartir') ||
        t.contains('dejo de compartir') ||
        t.contains('cerró la app') ||
        t.contains('cerro la app') ||
        t.contains('app cerrada');
  }

  static KidOfflineInfo? resolve({
    String? title,
    String? body,
    String? type,
    String? kidId,
    required List<Map<String, dynamic>> members,
  }) {
    if (!matches(title: title, body: body, type: type) && kidId == null) {
      return null;
    }
    final kids = members.where((m) => m['role'] == 'kid').toList();
    Map<String, dynamic>? kid;
    if (kidId != null) {
      for (final k in kids) {
        if (k['id'] == kidId) {
          kid = k;
          break;
        }
      }
    }
    final blob = '${title ?? ''} ${body ?? ''}';
    if (kid == null) {
      for (final k in kids) {
        final name = (k['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty && blob.contains(name)) {
          kid = k;
          break;
        }
      }
    }
    if (kid == null && kids.length == 1) kid = kids.first;
    if (kid == null) return null;
    final phone = (kid['phone'] as String?)?.trim();
    return KidOfflineInfo(
      kidName: (kid['name'] as String?)?.trim().isNotEmpty == true
          ? kid['name'] as String
          : 'tu hijo/a',
      kidId: kid['id'] as String?,
      kidPhone: (phone != null && phone.isNotEmpty) ? phone : null,
    );
  }
}
