import 'dart:convert';

import 'package:http/http.dart' as http;

import 'maps_config.dart';

class PlaceSuggestion {
  PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.placeId,
  });

  final String title;
  final String subtitle;
  final double lat;
  final double lng;
  final String? placeId;
}

class PlaceSearchService {
  static const _userAgent = 'LlegueApp/1.0 (familia; contacto: llegue-local)';

  Future<List<PlaceSuggestion>> search({
    required String query,
    required double nearLat,
    required double nearLng,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];
    if (MapsConfig.useGoogle) {
      return _searchGoogle(q, nearLat, nearLng);
    }
    return _searchNominatim(q, nearLat, nearLng);
  }

  Future<List<PlaceSuggestion>> _searchNominatim(
    String query,
    double nearLat,
    double nearLng,
  ) async {
    // Caja ~40 km alrededor de la ubicación actual
    const d = 0.35;
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'addressdetails': '1',
      'limit': '8',
      'countrycodes': 'ar',
      'viewbox':
          '${nearLng - d},${nearLat + d},${nearLng + d},${nearLat - d}',
      'bounded': '0',
    });
    final res = await http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'es',
      },
    );
    if (res.statusCode >= 400) return [];
    final list = jsonDecode(res.body);
    if (list is! List) return [];
    return list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final display = (m['display_name'] as String?) ?? '';
      final parts = display.split(',');
      final title = parts.isNotEmpty ? parts.first.trim() : query;
      final subtitle = parts.length > 1
          ? parts.skip(1).take(3).join(',').trim()
          : display;
      return PlaceSuggestion(
        title: title,
        subtitle: subtitle,
        lat: double.parse(m['lat'] as String),
        lng: double.parse(m['lon'] as String),
        placeId: m['place_id']?.toString(),
      );
    }).toList();
  }

  Future<List<PlaceSuggestion>> _searchGoogle(
    String query,
    double nearLat,
    double nearLng,
  ) async {
    final autoUri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': MapsConfig.googleMapsApiKey,
        'language': 'es',
        'components': 'country:ar',
        'location': '$nearLat,$nearLng',
        'radius': '40000',
      },
    );
    final autoRes = await http.get(autoUri);
    if (autoRes.statusCode >= 400) return [];
    final autoBody = jsonDecode(autoRes.body) as Map<String, dynamic>;
    final predictions = (autoBody['predictions'] as List<dynamic>? ?? []);
    final out = <PlaceSuggestion>[];
    for (final raw in predictions.take(8)) {
      final p = Map<String, dynamic>.from(raw as Map);
      final placeId = p['place_id'] as String?;
      if (placeId == null) continue;
      final details = await _googleDetails(placeId);
      if (details == null) continue;
      out.add(details);
    }
    return out;
  }

  Future<PlaceSuggestion?> _googleDetails(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'key': MapsConfig.googleMapsApiKey,
        'language': 'es',
        'fields': 'name,formatted_address,geometry',
      },
    );
    final res = await http.get(uri);
    if (res.statusCode >= 400) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result = body['result'];
    if (result is! Map) return null;
    final m = Map<String, dynamic>.from(result);
    final loc = m['geometry']?['location'];
    if (loc is! Map) return null;
    return PlaceSuggestion(
      title: (m['name'] as String?) ?? 'Lugar',
      subtitle: (m['formatted_address'] as String?) ?? '',
      lat: (loc['lat'] as num).toDouble(),
      lng: (loc['lng'] as num).toDouble(),
      placeId: placeId,
    );
  }
}
