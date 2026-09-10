import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/widgets/app_background.dart';
import '../onboarding/permissions_location_screen.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});

  static const route = '/create-family';

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _familyName = TextEditingController(text: 'Mi familia');
  final _displayName = TextEditingController();
  String _role = 'Padre';
  bool _busy = false;
  String? _error;

  static const _roles = ['Padre', 'Madre', 'Abuelo/a', 'Tío/a', 'Tutor/a', 'Otro'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppController>();
    if (_displayName.text.isEmpty) {
      _displayName.text = app.displayName == 'Sin nombre' ? '' : app.displayName;
    }
  }

  @override
  void dispose() {
    _familyName.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_displayName.text.trim().length < 2) {
      setState(() => _error = 'Escribí tu nombre.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final app = context.read<AppController>();
      await app.createFamily(
        familyName: _familyName.text.trim(),
        relationshipLabel: _role,
        displayName: _displayName.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        PermissionsLocationScreen.route,
        (_) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No pudimos crear la familia. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Tu familia')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                'Creá tu círculo familiar. Después vas a poder invitar al resto.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _displayName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _familyName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la familia',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Quién sos en la familia',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _roles.map((r) {
                  return ChoiceChip(
                    label: Text(r),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  );
                }).toList(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFE15A4F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? 'Creando…' : 'Crear familia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
