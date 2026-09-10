import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

class AlertPrefsScreen extends StatefulWidget {
  const AlertPrefsScreen({super.key});

  static const route = '/alert-prefs';

  @override
  State<AlertPrefsScreen> createState() => _AlertPrefsScreenState();
}

class _AlertPrefsScreenState extends State<AlertPrefsScreen> {
  Map<String, bool> _prefs = {};
  bool _loading = true;
  bool _saving = false;

  static const _labels = <String, String>{
    'arrival': 'Cuando llega a un lugar',
    'departure': 'Cuando sale de un lugar',
    'walking_home': 'Cuando regresa a casa',
    'going_to': 'Cuando avisa una salida especial',
    'place_suggested': 'Cuando sugiere un lugar nuevo',
    'delay': 'Si no llega a horario (rutina)',
    'return_prompt': 'Si salió y no dijo a dónde va',
    'low_battery': 'Si la batería está baja',
    'location_lost': 'Si apaga la ubicación o la app',
    'app_closed': 'Si cierra o elimina la app Llegué',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    try {
      final prefs = await app.loadAlertPrefs();
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _prefs = {
            for (final k in _labels.keys) k: true,
          };
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await context.read<AppController>().saveAlertPrefs(_prefs);
      if (!mounted) return;
      setState(() => _prefs = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listo. Guardamos lo que querés recibir.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Qué avisos quiero')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Text(
                      'Si hay más de un adulto, cada uno elige acá qué avisos quiere.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 16,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 16),
                    for (final entry in _labels.entries)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: appGlassDecoration(radius: 16),
                        child: SwitchListTile(
                          title: Text(
                            entry.value,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            (_prefs[entry.key] ?? true) ? 'Sí, quiero' : 'No',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          value: _prefs[entry.key] ?? true,
                          onChanged: (v) => setState(() => _prefs[entry.key] = v),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Guardando…' : 'Guardar'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
