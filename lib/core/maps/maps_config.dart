/// Si cargás una API key de Google (Maps + Places), la búsqueda usa Google.
/// Sin key, usa búsqueda gratuita (OpenStreetMap) que ya permite escribir
/// direcciones y lugares cercanos.
///
/// Para Google: creá una key en Google Cloud (Maps SDK + Places API) y pasala:
///   flutter run --dart-define=GOOGLE_MAPS_API_KEY=TU_KEY
/// o completá [googleMapsApiKey] acá.
class MapsConfig {
  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static bool get useGoogle => googleMapsApiKey.trim().isNotEmpty;
}
