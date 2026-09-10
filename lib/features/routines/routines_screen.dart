import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  static const route = '/routines';

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Map<String, dynamic>> _routines = [];
  bool _loading = true;
  String? _kidId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final app = context.read<AppController>();
    final kids = app.members.where((m) => m['role'] == 'kid').toList();
    _kidId = kids.isNotEmpty ? kids.first['id'] as String : null;
    await _load();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    if (_kidId == null) {
      setState(() {
        _routines = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await app.api.listRoutines(kidId: _kidId);
      _routines = (data['routines'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _routines = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() => _editRoutine();

  Future<void> _editRoutine([Map<String, dynamic>? existing]) async {
    final app = context.read<AppController>();
    final kids = app.members.where((m) => m['role'] == 'kid').toList();
    if (kids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero invitá a un hijo/a.')),
      );
      return;
    }
    if (app.places.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero agregá un lugar (Casa o Colegio).')),
      );
      return;
    }

    var kidId = (existing?['kidId'] as String?) ?? _kidId ?? kids.first['id'] as String;
    var placeId = (existing?['placeId'] as String?) ?? app.places.first['id'] as String;
    if (!app.places.any((p) => p['id'] == placeId)) {
      placeId = app.places.first['id'] as String;
    }
    final labelCtrl = TextEditingController(
      text: (existing?['label'] as String?) ??
          (app.places.firstWhere((p) => p['id'] == placeId)['name'] as String? ?? 'Colegio'),
    );
    TimeOfDay parseHm(String? raw, TimeOfDay fallback) {
      final parts = (raw ?? '').split(':');
      if (parts.length < 2) return fallback;
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? fallback.hour,
        minute: int.tryParse(parts[1]) ?? fallback.minute,
      );
    }
    var startTime = parseHm(existing?['startTime'] as String?, const TimeOfDay(hour: 8, minute: 0));
    var endTime = parseHm(existing?['endTime'] as String?, const TimeOfDay(hour: 13, minute: 0));
    final selectedDays = <int>{
      ...((existing?['daysOfWeek'] as List?)
              ?.map((e) => int.tryParse('$e') ?? 0)
              .where((d) => d > 0) ??
          const [1, 2, 3, 4, 5]),
    };
    if (selectedDays.isEmpty) {
      selectedDays.addAll([1, 2, 3, 4, 5]);
    }
    final editing = existing != null;

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    const dayLabels = {
      1: 'L',
      2: 'M',
      3: 'X',
      4: 'J',
      5: 'V',
      6: 'S',
      7: 'D',
    };

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      editing ? 'Editar rutina' : 'Nueva rutina',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ejemplo: colegio 7:00–12:00. Si a las 7:05 no llegó, te avisamos. '
                      'Si llega después, también te avisamos la llegada.',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: kidId,
                      decoration: const InputDecoration(
                        labelText: 'Hijo/a',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        for (final k in kids)
                          DropdownMenuItem(
                            value: k['id'] as String,
                            child: Text(k['name'] as String? ?? 'Hijo/a'),
                          ),
                      ],
                      onChanged: (v) => setModal(() => kidId = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: placeId,
                      decoration: const InputDecoration(
                        labelText: 'Lugar',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        for (final p in app.places)
                          DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['name'] as String? ?? 'Lugar'),
                          ),
                      ],
                      onChanged: (v) {
                        setModal(() {
                          placeId = v!;
                          final p = app.places.firstWhere((x) => x['id'] == v);
                          labelCtrl.text = p['name'] as String? ?? labelCtrl.text;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la rutina',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Días', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final d in dayLabels.keys)
                          FilterChip(
                            label: Text(dayLabels[d]!),
                            selected: selectedDays.contains(d),
                            onSelected: (sel) {
                              setModal(() {
                                if (sel) {
                                  selectedDays.add(d);
                                } else {
                                  selectedDays.remove(d);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: startTime,
                                helpText: 'Hora de inicio',
                                builder: (context, child) {
                                  return MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      alwaysUse24HourFormat: true,
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setModal(() => startTime = picked);
                              }
                            },
                            icon: const Icon(Icons.schedule),
                            label: Text('Desde ${fmt(startTime)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: endTime,
                                helpText: 'Hora de fin',
                                builder: (context, child) {
                                  return MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      alwaysUse24HourFormat: true,
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setModal(() => endTime = picked);
                              }
                            },
                            icon: const Icon(Icons.schedule),
                            label: Text('Hasta ${fmt(endTime)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: selectedDays.isEmpty
                          ? null
                          : () => Navigator.pop(context, true),
                      child: Text(editing ? 'Guardar cambios' : 'Guardar rutina'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;
    try {
      final label = labelCtrl.text.trim().isEmpty ? 'Rutina' : labelCtrl.text.trim();
      final days = selectedDays.toList()..sort();
      if (editing) {
        await app.updateRoutine(
          routineId: existing['id'] as String,
          kidId: kidId,
          placeId: placeId,
          label: label,
          daysOfWeek: days,
          startTime: fmt(startTime),
          endTime: fmt(endTime),
        );
      } else {
        await app.createRoutine(
          kidId: kidId,
          placeId: placeId,
          label: label,
          daysOfWeek: days,
          startTime: fmt(startTime),
          endTime: fmt(endTime),
        );
      }
      _kidId = kidId;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editing ? 'Rutina actualizada' : 'Rutina guardada')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _daysLabel(dynamic raw) {
    final days = (raw is List)
        ? raw.map((e) => int.tryParse('$e') ?? 0).where((d) => d > 0).toList()
        : <int>[];
    if (days.isEmpty) return 'Sin días';
    const names = {
      1: 'Lun',
      2: 'Mar',
      3: 'Mié',
      4: 'Jue',
      5: 'Vie',
      6: 'Sáb',
      7: 'Dom',
    };
    if (days.length == 5 &&
        days.contains(1) &&
        days.contains(2) &&
        days.contains(3) &&
        days.contains(4) &&
        days.contains(5)) {
      return 'Lun–Vie';
    }
    return days.map((d) => names[d] ?? '$d').join(', ');
  }

  Future<void> _deleteRoutine(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar rutina?'),
        content: Text('Se va a borrar “${r['label'] ?? 'esta rutina'}”.'),
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
      await context.read<AppController>().deleteRoutine(r['id'] as String);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final kids = app.members.where((m) => m['role'] == 'kid').toList();

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Rutinas')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Text(
                      'Las rutinas son lo de siempre (colegio, inglés, danza).\n'
                      'Avisamos cuando llega o sale. Si a los 5 minutos del horario '
                      'de inicio todavía no llegó, también te avisamos.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 16,
                            height: 1.4,
                          ),
                    ),
                    if (kids.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _kidId ?? kids.first['id'] as String,
                    decoration: const InputDecoration(
                          labelText: 'Ver rutinas de',
                        ),
                        items: [
                          for (final k in kids)
                            DropdownMenuItem(
                              value: k['id'] as String,
                              child: Text(k['name'] as String? ?? 'Hijo/a'),
                            ),
                        ],
                        onChanged: (v) async {
                          _kidId = v;
                          await _load();
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (app.isAdult)
                      FilledButton(
                        onPressed: _create,
                        child: const Text('Crear rutina'),
                      ),
                    const SizedBox(height: 20),
                    if (_routines.isEmpty)
                      const Text('Todavía no hay rutinas cargadas.')
                    else
                      ..._routines.map((r) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: appGlassDecoration(radius: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['label'] as String? ?? 'Rutina',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '${_daysLabel(r['daysOfWeek'])} · ${r['startTime']} a ${r['endTime']}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.75),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (app.isAdult)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar',
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () => _editRoutine(r),
                                      ),
                                      IconButton(
                                        tooltip: 'Borrar',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () => _deleteRoutine(r),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }
}
