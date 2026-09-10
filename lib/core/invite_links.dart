String? inviteTokenFromUri(Uri? uri) {
  if (uri == null) return null;
  if (uri.scheme == 'llegue') {
    if (uri.host == 'join') {
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first.toUpperCase();
      }
      final q = uri.queryParameters['token'] ?? uri.queryParameters['t'];
      if (q != null && q.trim().isNotEmpty) return q.trim().toUpperCase();
    }
  }
  if (uri.scheme == 'https' || uri.scheme == 'http') {
    final segs = uri.pathSegments;
    final i = segs.indexOf('i');
    if (i >= 0 && i + 1 < segs.length) {
      return segs[i + 1].toUpperCase();
    }
  }
  return null;
}

String normalizeInviteInput(String raw) {
  var value = raw.trim();
  if (value.startsWith('//')) {
    value = 'http:$value';
  }
  final uri = Uri.tryParse(value);
  final fromUri = inviteTokenFromUri(uri);
  if (fromUri != null) return fromUri;

  // Por si pegaron texto con la URL rota: .../i/TOKEN
  final match = RegExp(r'/i/([A-Za-z0-9]+)').firstMatch(value);
  if (match != null) {
    return match.group(1)!.toUpperCase();
  }

  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
