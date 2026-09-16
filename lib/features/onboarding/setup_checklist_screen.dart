import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onboarding_shell.dart';
import '../family_circle/home_screen.dart';
import '../places/place_picker_screen.dart';

/// Guía rápida post-registro: invitar hijo → Casa → Colegio.
class SetupChecklistScreen extends StatefulWidget {
  const SetupChecklistScreen({super.key});

  static const route = '/setup-checklist';

  @override
  State<SetupChecklistScreen> createState() => _SetupChecklistScreenState();
}

class _SetupChecklistScreenState extends State<SetupChecklistScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    try {
      await context.read<AppController>().refreshFamilyStatus();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  bool _hasKid(AppController app) =>
      app.members.any((m) => m['role'] == 'kid');

  bool _hasHome(AppController app) => app.places.any((p) {
        final t = p['type'] as String?;
        final n = (p['name'] as String? ?? '').toLowerCase();
        return t == 'home' || n.contains('casa');
      });

  bool _hasSchool(AppController app) => app.places.any((p) {
        final t = p['type'] as String?;
        final n = (p['name'] as String? ?? '').toLowerCase();
        return t == 'school' || n.contains('colegio') || n.contains('escuela');
      });

  Future<void> _inviteKid() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2E2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Invitar hijo/a',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cargás el nombre y le mandás el link por WhatsApp.',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white),
                decoration: onboardingFieldDecoration('Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: onboardingFieldDecoration('PIN (opcional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Crear invitación'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final app = context.read<AppController>();
      final data = await app.createInvitation(
        name: name,
        role: 'kid',
        pin: pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim(),
      );
      final invite = data['invitation'] is Map
          ? Map<String, dynamic>.from(data['invitation'] as Map)
          : <String, dynamic>{};
      final inviteUrl = (data['inviteUrl'] as String?)?.trim().isNotEmpty == true
          ? data['inviteUrl'] as String
          : (invite['inviteUrl'] as String? ?? '');
      final code = invite['code'] as String? ?? '';
      final shareMessage = (data['shareMessage'] as String?)?.trim().isNotEmpty ==
              true
          ? data['shareMessage'] as String
          : 'Hola $name, te sumé a Llegué.\n\nEntrá acá: $inviteUrl\n\nCódigo: $code';

      if (inviteUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar el link. Intentá de nuevo.')),
        );
        return;
      }

      await Clipboard.setData(ClipboardData(text: shareMessage));
      if (!mounted) return;
      final goWhatsApp = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Link listo'),
          content: Text('Mandale el link a $name por WhatsApp.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Solo copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir WhatsApp'),
            ),
          ],
        ),
      );
      if (goWhatsApp == true) {
        final encoded = Uri.encodeComponent(shareMessage);
        final uri = Uri.parse('whatsapp://send?text=$encoded');
        final opened =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) {
          await launchUrl(
            Uri.parse('https://wa.me/?text=$encoded'),
            mode: LaunchMode.externalApplication,
          );
        }
      }
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        final app = context.read<AppController>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.inviteErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPlace({
    required String type,
    required String name,
  }) async {
    final result = await Navigator.of(context).push<PlacePickResult>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          initialType: type,
          initialName: name,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AppController>().createPlace(
            name: result.name,
            lat: result.lat,
            lng: result.lng,
            type: result.type,
          );
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({bool skip = false}) async {
    final app = context.read<AppController>();
    if (!skip && app.needsSetupChecklist) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Todavía falta algo'),
          content: const Text(
            'Podés seguir igual, pero Llegué funciona mejor con hijo/a, '
            'Casa y Colegio cargados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir armando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ir al inicio'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await app.completeSetupChecklist();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      HomeScreen.route,
      (_) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final kidDone = _hasKid(app);
    final homeDone = _hasHome(app);
    final schoolDone = _hasSchool(app);
    final allDone = kidDone && homeDone && schoolDone;

    return OnboardingShell(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Listo en 3 pasos',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Así Llegué ya puede avisarte solo.',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: ListView(
                    children: [
                      _StepTile(
                        number: '1',
                        title: 'Invitar hijo/a',
                        subtitle: 'Mandale el link por WhatsApp',
                        done: kidDone,
                        onTap: kidDone ? null : _inviteKid,
                      ),
                      const SizedBox(height: 12),
                      _StepTile(
                        number: '2',
                        title: 'Agregar Casa',
                        subtitle: 'El lugar de donde sale y a donde vuelve',
                        done: homeDone,
                        onTap: homeDone
                            ? null
                            : () => _addPlace(type: 'home', name: 'Casa'),
                      ),
                      const SizedBox(height: 12),
                      _StepTile(
                        number: '3',
                        title: 'Agregar Colegio',
                        subtitle: 'O el lugar que más usa entre semana',
                        done: schoolDone,
                        onTap: schoolDone
                            ? null
                            : () =>
                                _addPlace(type: 'school', name: 'Colegio'),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _finish(skip: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    allDone ? 'Empezar' : 'Continuar',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (!allDone)
                  TextButton(
                    onPressed: _busy ? null : () => _finish(skip: true),
                    child: Text(
                      'Saltar por ahora',
                      style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.done,
    this.onTap,
  });

  final String number;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: done ? 0.2 : 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? Colors.white : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, color: Color(0xFF146B56))
                    : Text(
                        number,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done ? 'Listo' : subtitle,
                      style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (!done)
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
