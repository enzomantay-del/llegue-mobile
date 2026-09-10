import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/widgets/onboarding_shell.dart';
import 'permissions_blocked_screen.dart';
import 'setup_checklist_screen.dart';

/// Onboarding corto del titular: nombre → teléfono → permisos → familia.
class TitularOnboardingScreen extends StatefulWidget {
  const TitularOnboardingScreen({super.key});

  static const route = '/onboarding-titular';

  @override
  State<TitularOnboardingScreen> createState() =>
      _TitularOnboardingScreenState();
}

class _TitularOnboardingScreenState extends State<TitularOnboardingScreen> {
  static const _totalSteps = 5;

  int _step = 0;
  bool _busy = false;
  String? _error;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _phoneCode = TextEditingController();
  final _familyName = TextEditingController(text: 'Mi familia');

  String _relationship = 'Padre';

  static const _roles = ['Padre', 'Madre', 'Abuelo/a', 'Tío/a', 'Tutor/a', 'Otro'];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _phoneCode.dispose();
    _familyName.dispose();
    super.dispose();
  }

  double get _progress => (_step + 1) / _totalSteps;

  void _next() => setState(() {
        _error = null;
        _step = (_step + 1).clamp(0, _totalSteps - 1);
      });

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPhoneCode() async {
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() => _error = 'Escribí un teléfono válido.');
      return;
    }
    await _run(() async {
      await context.read<AppController>().requestOtp(phone);
      _next();
    });
  }

  Future<void> _verifyPhone() async {
    if (_phoneCode.text.trim().length < 4) {
      setState(() => _error = 'Escribí el código.');
      return;
    }
    await _run(() async {
      await context.read<AppController>().verifyOtp(
            phone: _phone.text.trim(),
            code: _phoneCode.text.trim(),
            name: _name.text.trim(),
          );
      _next();
    });
  }

  Future<void> _requestPermissions() async {
    await _run(() async {
      final app = context.read<AppController>();
      final status = await app.permissions.requestLocationChain();
      if (status != 'always') {
        if (!mounted) return;
        Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
        return;
      }
      final notif = await app.permissions.requestNotifications();
      if (notif != 'granted') {
        if (!mounted) return;
        Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
        return;
      }
      await app.syncPermissions(
        locationPermission: status,
        notificationsPermission: notif,
        locationOk: true,
        restartServices: false,
      );
      _next();
    });
  }

  Future<void> _finishFamily() async {
    if (_familyName.text.trim().length < 2) {
      setState(() => _error = 'Escribí el nombre de la familia.');
      return;
    }
    await _run(() async {
      final app = context.read<AppController>();
      try {
        await app.createFamily(
          familyName: _familyName.text.trim(),
          relationshipLabel: _relationship,
          displayName: _name.text.trim(),
        );
      } on ApiException catch (e) {
        // Si ya se creó en un intento anterior, seguimos al checklist.
        final msg = e.message.toLowerCase();
        if (!msg.contains('ya estás en una familia') &&
            !msg.contains('ya estas en una familia')) {
          rethrow;
        }
      }
      await app.markSetupChecklistNeeded();
      try {
        await app.syncRuntimeServices();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SetupChecklistScreen.route,
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      progress: _progress,
      onBack: _busy ? null : _back,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return OnboardingStepBody(
          title: '¿Cómo te llamás?',
          subtitle: 'Vos te enterás. Ellos no tienen que acordarse de avisar.',
          error: _error,
          busy: _busy,
          primaryEnabled: _name.text.trim().length >= 2,
          primaryLabel: 'Continuar',
          onPrimary: () {
            if (_name.text.trim().length < 2) {
              setState(() => _error = 'Escribí tu nombre.');
              return;
            }
            _next();
          },
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            cursorColor: Colors.white,
            onChanged: (_) => setState(() {}),
            decoration: onboardingFieldDecoration('Tu nombre'),
          ),
        );
      case 1:
        return OnboardingStepBody(
          title: 'Tu teléfono',
          subtitle: 'Con este número entrás a Llegué en este celular.',
          error: _error,
          busy: _busy,
          primaryLabel: 'Enviar código',
          onPrimary: _sendPhoneCode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                cursorColor: Colors.white,
                decoration: onboardingFieldDecoration('Teléfono'),
              ),
            ],
          ),
        );
      case 2:
        return OnboardingStepBody(
          title: 'Código',
          subtitle: 'Ingresá el código que te enviamos.',
          error: _error,
          busy: _busy,
          primaryEnabled: _phoneCode.text.trim().length >= 4,
          primaryLabel: 'Continuar',
          onPrimary: _verifyPhone,
          child: TextField(
            controller: _phoneCode,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 4,
            ),
            cursorColor: Colors.white,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: onboardingFieldDecoration('Código'),
          ),
        );
      case 3:
        return OnboardingStepBody(
          title: 'Permisos',
          subtitle:
              'Ubicación “Siempre” y avisos: así Llegué te avisa solo '
              'cuando tu hijo/a llega o sale.',
          error: _error,
          busy: _busy,
          primaryLabel: 'Permitir y seguir',
          onPrimary: _requestPermissions,
          child: _infoCard(
            'Sin estos permisos, la app no puede darte tranquilidad sola.',
          ),
        );
      case 4:
      default:
        return OnboardingStepBody(
          title: 'Tu familia',
          subtitle: 'Poné un nombre al círculo. Después invitás a tu hijo/a.',
          error: _error,
          busy: _busy,
          primaryLabel: 'Crear familia',
          onPrimary: _finishFamily,
          child: ListView(
            children: [
              TextField(
                controller: _familyName,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                cursorColor: Colors.white,
                decoration: onboardingFieldDecoration('Nombre de la familia'),
              ),
              const SizedBox(height: 18),
              Text(
                '¿Quién sos?',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _roles.map((r) {
                  final selected = _relationship == r;
                  return Material(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: () => setState(() => _relationship = r),
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: selected ? 0 : 0.45,
                            ),
                          ),
                        ),
                        child: Text(
                          r,
                          style: GoogleFonts.dmSans(
                            color: selected
                                ? const Color(0xFF146B56)
                                : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
    }
  }

  Widget _infoCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
