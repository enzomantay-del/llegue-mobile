import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/maps/maps_config.dart';
import '../../core/maps/place_search_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

class PlacePickResult {
  PlacePickResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.type,
    this.address,
  });

  final String name;
  final double lat;
  final double lng;
  final String type;
  final String? address;
}

class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({
    super.key,
    this.isKid = false,
    this.initialType,
    this.initialName,
    this.initialLat,
    this.initialLng,
    this.title,
    this.confirmLabel,
  });

  static const route = '/place-picker';

  final bool isKid;
  final String? initialType;
  final String? initialName;
  final double? initialLat;
  final double? initialLng;
  final String? title;
  final String? confirmLabel;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _mapController = MapController();
  final _search = PlaceSearchService();
  final _nameCtrl = TextEditingController();
  final _queryCtrl = TextEditingController();

  LatLng? _center;
  LatLng? _pin;
  String? _address;
  late String _type;
  bool _loadingGps = true;
  bool _searching = false;
  List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? (widget.isKid ? 'favorite' : 'home');
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _nameCtrl.text = widget.initialName!;
    }
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _queryCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Si estamos editando, partimos del punto guardado.
    if (widget.initialLat != null && widget.initialLng != null) {
      final here = LatLng(widget.initialLat!, widget.initialLng!);
      setState(() {
        _center = here;
        _pin = here;
        _address = 'Ubicación actual del lugar';
        _loadingGps = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(here, 16);
        } catch (_) {}
      });
      return;
    }

    // Fallback solo si el GPS falla de verdad
    const fallback = LatLng(-27.3671, -55.8961);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('sin_permiso');
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        throw Exception('gps_apagado');
      }

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _center = here;
        _pin = here;
        _loadingGps = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(here, 16);
        } catch (_) {}
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _center = fallback;
        _pin = fallback;
        _loadingGps = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos leer tu GPS. Activá la ubicación y tocá el botón '
            'de centrar (abajo a la derecha), o buscá la dirección.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _goToMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Necesitamos permiso de ubicación.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _center = here;
        _pin = here;
        _address = 'Mi ubicación actual';
      });
      _mapController.move(here, 16);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos obtener tu ubicación ahora.')),
      );
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final pin = _pin ?? _center;
      if (pin == null || value.trim().length < 2) {
        setState(() => _suggestions = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final list = await _search.search(
          query: value,
          nearLat: pin.latitude,
          nearLng: pin.longitude,
        );
        if (!mounted) return;
        setState(() => _suggestions = list);
      } catch (_) {
        if (!mounted) return;
        setState(() => _suggestions = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _selectSuggestion(PlaceSuggestion s) {
    final point = LatLng(s.lat, s.lng);
    setState(() {
      _pin = point;
      _address = s.subtitle.isNotEmpty ? '${s.title}, ${s.subtitle}' : s.title;
      _suggestions = [];
      _queryCtrl.text = s.title;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = s.title;
      }
    });
    _mapController.move(point, 17);
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _pin = point;
      _address = 'Punto marcado en el mapa';
      _suggestions = [];
    });
  }

  Future<void> _openInGoogleMaps() async {
    final pin = _pin;
    if (pin == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${pin.latitude},${pin.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _confirm() {
    final name = _nameCtrl.text.trim();
    final pin = _pin;
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre al lugar (ej. Gimnasio)')),
      );
      return;
    }
    if (pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcá el lugar en el mapa o buscalo')),
      );
      return;
    }
    Navigator.pop(
      context,
      PlacePickResult(
        name: name,
        lat: pin.latitude,
        lng: pin.longitude,
        type: _type,
        address: _address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    final center = _center ?? const LatLng(-27.3671, -55.8961);

    return AppBackground(
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (widget.isKid ? 'Sugerir lugar' : 'Elegir lugar'),
        ),
        actions: [
          if (pin != null)
            IconButton(
              tooltip: 'Abrir en Google Maps',
              onPressed: _openInGoogleMaps,
              icon: const Icon(Icons.map_outlined),
            ),
        ],
      ),
      body: _loadingGps
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        MapsConfig.useGoogle
                            ? 'Buscá la dirección o el lugar. El mapa empieza en tu ubicación.'
                            : 'Buscá la dirección o el lugar (colegio, gimnasio…). Tocá el mapa para ajustar el punto.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Dirección o lugar',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _queryCtrl,
                        textInputAction: TextInputAction.search,
                        onChanged: _onQueryChanged,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                        ),
                        cursorColor: AppColors.brandDeep,
                        decoration: InputDecoration(
                          hintText: 'Ej. Gimnasio, Escuela Normal, Av. Uruguay',
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          hintStyle: TextStyle(
                            color: AppColors.ink.withValues(alpha: 0.45),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.brandDeep,
                          ),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.brandDeep,
                                    ),
                                  ),
                                )
                              : (_queryCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: AppColors.ink,
                                      ),
                                      onPressed: () {
                                        _queryCtrl.clear();
                                        setState(() => _suggestions = []);
                                      },
                                    )),
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(
                              color: AppColors.brandDeep,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.ink.withValues(alpha: 0.12),
                            ),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: AppColors.ink.withValues(alpha: 0.1),
                            ),
                            itemBuilder: (context, i) {
                              final s = _suggestions[i];
                              return ListTile(
                                dense: true,
                                iconColor: AppColors.brandDeep,
                                textColor: AppColors.ink,
                                leading: const Icon(Icons.place_outlined),
                                title: Text(
                                  s.title,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  s.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.ink.withValues(alpha: 0.65),
                                  ),
                                ),
                                onTap: () => _selectSuggestion(s),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 16,
                          onTap: _onMapTap,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.llegue.llegue_mobile',
                          ),
                          if (pin != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: pin,
                                  width: 48,
                                  height: 48,
                                  child: const Icon(
                                    Icons.location_on,
                                    color: AppColors.alert,
                                    size: 48,
                                  ),
                                ),
                              ],
                            ),
                          CircleLayer(
                            circles: [
                              if (pin != null)
                                CircleMarker(
                                  point: pin,
                                  radius: 60,
                                  useRadiusInMeter: true,
                                  color: AppColors.brand.withValues(alpha: 0.15),
                                  borderStrokeWidth: 2,
                                  borderColor: AppColors.brandDeep,
                                ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'my_loc',
                          backgroundColor: Colors.white,
                          onPressed: _goToMyLocation,
                          child: const Icon(Icons.my_location, color: AppColors.brandDeep),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    color: AppColors.bgBottom,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_address != null)
                          Text(
                            _address!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Nombre para la familia',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                          ),
                          cursorColor: AppColors.brandDeep,
                          decoration: InputDecoration(
                            hintText: 'Ej. Gimnasio, Casa de la abuela',
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            hintStyle: TextStyle(
                              color: AppColors.ink.withValues(alpha: 0.45),
                            ),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(14)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(14)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(14)),
                              borderSide: BorderSide(
                                color: AppColors.brandDeep,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                        if (!widget.isKid) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final t in [
                                ('home', 'Casa'),
                                ('school', 'Colegio'),
                                ('activity', 'Actividad'),
                                ('favorite', 'Otro'),
                              ])
                                ChoiceChip(
                                  label: Text(t.$2),
                                  selected: _type == t.$1,
                                  onSelected: (_) => setState(() => _type = t.$1),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _confirm,
                          child: Text(
                            widget.confirmLabel ??
                                (widget.isKid
                                    ? 'Enviar sugerencia'
                                    : 'Usar este lugar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
