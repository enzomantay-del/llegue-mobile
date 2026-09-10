import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import 'place_picker_screen.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  static const route = '/places';

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  bool _busy = false;

  Future<void> _addPlace() async {
    final app = context.read<AppController>();
    final picked = await Navigator.of(context).push<PlacePickResult>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(isKid: app.isKid),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (app.isKid) {
        await app.suggestPlace(
          name: picked.name,
          lat: picked.lat,
          lng: picked.lng,
        );
      } else {
        await app.createPlace(
          name: picked.name,
          lat: picked.lat,
          lng: picked.lng,
          type: picked.type,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            app.isKid
                ? 'Sugerencia enviada: ${picked.name}'
                : 'Lugar guardado: ${picked.name}',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPlace(Map<String, dynamic> place) async {
    final app = context.read<AppController>();
    final picked = await Navigator.of(context).push<PlacePickResult>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          isKid: false,
          title: 'Editar lugar',
          confirmLabel: 'Guardar cambios',
          initialName: place['name'] as String?,
          initialType: place['type'] as String?,
          initialLat: (place['lat'] as num?)?.toDouble(),
          initialLng: (place['lng'] as num?)?.toDouble(),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await app.updatePlace(
        placeId: place['id'] as String,
        name: picked.name,
        lat: picked.lat,
        lng: picked.lng,
        type: picked.type,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lugar actualizado: ${picked.name}')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePlace(Map<String, dynamic> place) async {
    final app = context.read<AppController>();
    final name = place['name'] as String? ?? 'este lugar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar lugar?'),
        content: Text('Se va a borrar “$name”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await app.deletePlace(place['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se borró “$name”')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'home':
        return 'Casa';
      case 'school':
        return 'Colegio';
      case 'activity':
        return 'Actividad';
      default:
        return 'Lugar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Lugares')),
        body: SafeArea(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: AppColors.brandDeep,
                  onRefresh: () => app.refreshFamilyStatus(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      Text(
                        app.isKid
                            ? 'Podés sugerir un lugar. Un adulto lo aprueba una vez y después la app avisa sola.'
                            : 'Agregá Casa, Colegio y otros lugares importantes para tu familia.',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _addPlace,
                        child: Text(
                          app.isKid
                              ? 'Sugerir lugar'
                              : 'Agregar lugar',
                        ),
                      ),
                      if (app.isAdult && app.pendingPlaces.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Text(
                          'Pedidos por aprobar',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...app.pendingPlaces.map((p) {
                          return _PlaceTile(
                            title: p['name'] as String? ?? '',
                            subtitle: 'Esperando tu OK',
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await app.approvePlace(p['id'] as String);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Aprobado: ${p['name'] ?? 'lugar'}',
                                      ),
                                    ),
                                  );
                                } on ApiException catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                                }
                              },
                              child: Text(
                                'Aprobar',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 28),
                      Text(
                        'Guardados',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (app.places.isEmpty)
                        Text(
                          'Todavía no hay lugares. Agregá el primero.',
                          style: GoogleFonts.dmSans(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        )
                      else
                        ...app.places.map((p) {
                          final radius = p['radiusM'] ?? 60;
                          return _PlaceTile(
                            title: p['name'] as String? ?? '',
                            subtitle:
                                '${_typeLabel(p['type'] as String?)} · radio ${radius} m',
                            trailing: app.isAdult
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar',
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () => _editPlace(p),
                                      ),
                                      IconButton(
                                        tooltip: 'Borrar',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () => _deletePlace(p),
                                      ),
                                    ],
                                  )
                                : null,
                          );
                        }),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: appGlassDecoration(radius: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
