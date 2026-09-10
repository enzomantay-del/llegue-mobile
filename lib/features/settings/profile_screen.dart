import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const route = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _kidsCountCtrl = TextEditingController();
  final _kidsAgesCtrl = TextEditingController();

  String? _mainConcern;
  String? _howFound;
  String _planLabel = 'Gratis';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _concernOptions = <String, String>{
    'school_alone': 'Que vayan solos al colegio / actividades',
    'peace_of_mind': 'Tranquilidad general del día a día',
    'routines': 'Controlar horarios y rutinas',
    'after_school': 'Después del colegio / extracurriculares',
    'other': 'Otro motivo',
  };

  static const _foundOptions = <String, String>{
    'recommendation': 'Me lo recomendaron',
    'school': 'Por la escuela / club',
    'social': 'Redes sociales',
    'search': 'Lo busqué en internet / tienda',
    'other': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    _kidsCountCtrl.dispose();
    _kidsAgesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await app.loadAccountProfile();
      final user = Map<String, dynamic>.from(data['user'] as Map? ?? {});
      final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? {});
      if (!mounted) return;
      _nameCtrl.text = (user['name'] as String?) ?? app.displayName;
      _emailCtrl.text =
          (profile['email'] as String?) ?? (user['email'] as String?) ?? '';
      _cityCtrl.text = (profile['city'] as String?) ?? '';
      final kids = profile['kidsCount'];
      _kidsCountCtrl.text = kids == null ? '' : '$kids';
      _kidsAgesCtrl.text = (profile['kidsAges'] as String?) ?? '';
      _mainConcern = profile['mainConcern'] as String?;
      _howFound = profile['howFound'] as String?;
      _planLabel = (profile['planLabel'] as String?) ?? 'Gratis';
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _nameCtrl.text = app.displayName;
        _planLabel = 'Gratis';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar el perfil. Probá de nuevo.';
        _loading = false;
        _nameCtrl.text = app.displayName;
        _planLabel = 'Gratis';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppController>().saveAccountProfile({
        'displayName': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'kidsCount': _kidsCountCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_kidsCountCtrl.text.trim()),
        'kidsAges': _kidsAgesCtrl.text.trim(),
        'mainConcern': _mainConcern ?? '',
        'howFound': _howFound ?? '',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil guardado.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _roleLabel(AppController app) {
    final role = app.user?['role'] as String?;
    if (role == 'admin_adult') return 'Titular de la cuenta';
    if (role == 'adult') return 'Adulto/a de la familia';
    if (role == 'kid') return 'Hijo/a';
    return 'Usuario';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final canEdit = app.isAdult;
    final phone = (app.user?['phone'] as String?) ?? app.boundUserPhone ?? '—';
    final familyName = (app.family?['name'] as String?) ?? 'Sin familia';

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Mi perfil')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _sectionTitle('Tu cuenta'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: appGlassDecoration(radius: 16),
                      child: Column(
                        children: [
                          _InfoRow(label: 'Plan', value: _planLabel),
                          const Divider(color: AppColors.line, height: 22),
                          _InfoRow(label: 'Rol', value: _roleLabel(app)),
                          const Divider(color: AppColors.line, height: 22),
                          _InfoRow(label: 'Teléfono', value: phone),
                          const Divider(color: AppColors.line, height: 22),
                          _InfoRow(label: 'Familia', value: familyName),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Por ahora todas las cuentas usan el plan Gratis. '
                      'Más adelante vas a poder elegir un plan pago si lo necesitás.',
                      style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionTitle('Datos personales'),
                    _field(
                      controller: _nameCtrl,
                      label: 'Nombre',
                      enabled: canEdit,
                    ),
                    _field(
                      controller: _emailCtrl,
                      label: 'Correo (opcional)',
                      keyboardType: TextInputType.emailAddress,
                      enabled: canEdit,
                      hint: 'Para avisarte novedades del servicio',
                    ),
                    _field(
                      controller: _cityCtrl,
                      label: 'Ciudad o localidad',
                      enabled: canEdit,
                      hint: 'Ej. Jardín América, Misiones',
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: 18),
                      _sectionTitle('Para conocerte mejor'),
                      Text(
                        'Estas respuestas nos ayudan a mejorar Llegué. '
                        'No se muestran a otros miembros de la familia.',
                        style: GoogleFonts.dmSans(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _kidsCountCtrl,
                        label: '¿Cuántos hijos/as usan o van a usar la app?',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      _field(
                        controller: _kidsAgesCtrl,
                        label: 'Edades aproximadas',
                        hint: 'Ej. 9 y 13',
                      ),
                      const SizedBox(height: 8),
                      _dropdown(
                        label: '¿Qué te importa más?',
                        value: _mainConcern,
                        items: _concernOptions,
                        onChanged: (v) => setState(() => _mainConcern = v),
                      ),
                      const SizedBox(height: 12),
                      _dropdown(
                        label: '¿Cómo nos conociste?',
                        value: _howFound,
                        items: _foundOptions,
                        onChanged: (v) => setState(() => _howFound = v),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Guardando…' : 'Guardar perfil'),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(
                        'El adulto titular completa los datos de la cuenta.',
                        style: GoogleFonts.dmSans(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppColors.fieldFill,
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safe = value != null && items.containsKey(value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: appGlassDecoration(radius: 14),
      child: DropdownButtonFormField<String>(
        value: safe,
        dropdownColor: AppColors.inkSoft,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
