import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_mark.dart';
import '../legal/terms_screen.dart';
import 'phone_login_screen.dart';
import 'titular_onboarding_screen.dart';
import '../family_setup/join_family_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  static const route = '/';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppController>();
      app.refreshDeviceBinding();
      if (app.termsAccepted && mounted) {
        setState(() => _checked = true);
      }
    });
  }

  /// Ajuste técnico oculto (mantener pulsado el nombre Llegué).
  Future<void> _editServerHidden(BuildContext context) async {
    final app = context.read<AppController>();
    final ctrl = TextEditingController(text: app.api.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conexión'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Dirección del servicio',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await app.setBaseUrl(ctrl.text.trim());
      try {
        await app.refreshDeviceBinding();
      } on ApiException catch (_) {}
    }
  }

  Future<bool> _ensureTermsAccepted() async {
    final app = context.read<AppController>();
    if (app.termsAccepted) return true;

    final accepted = await Navigator.of(context).pushNamed(
      TermsScreen.route,
      arguments: {'requireAccept': true},
    );
    if (accepted == true && mounted) {
      setState(() => _checked = true);
      return true;
    }
    return false;
  }

  Future<void> _onTermsCheckChanged(bool? value) async {
    final want = value == true;
    if (!want) {
      setState(() => _checked = false);
      return;
    }
    final ok = await _ensureTermsAccepted();
    if (!mounted) return;
    setState(() => _checked = ok);
  }

  Future<void> _go(Future<void> Function() action) async {
    if (!_checked) {
      final ok = await _ensureTermsAccepted();
      if (!ok || !mounted) return;
    } else if (!context.read<AppController>().termsAccepted) {
      await context.read<AppController>().acceptTerms();
    }
    if (!mounted) return;
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final bound = app.deviceBoundOnServer &&
        app.boundUserName != null &&
        app.boundUserName!.isNotEmpty;
    final loggedIn = app.isLoggedIn && app.hasFamily;
    final needsAcceptGate = !loggedIn;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: appBrandGradientDecoration()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PARA FAMILIAS',
                    style: GoogleFonts.dmSans(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  const BrandMark(size: 88),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onLongPress: () => _editServerHidden(context),
                    child: Text(
                      'Llegué',
                      style: GoogleFonts.outfit(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 0.95,
                        letterSpacing: -1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    bound
                        ? 'Bienvenido de nuevo, ${app.boundUserName}.'
                        : 'Tranquilidad al saber que llegaron.\n'
                            'Sin pedir que te avisen.',
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (needsAcceptGate) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: Checkbox(
                            value: _checked,
                            onChanged: _onTermsCheckChanged,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            fillColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return Colors.transparent;
                            }),
                            checkColor: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(
                                style: GoogleFonts.dmSans(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Leí y acepto las ',
                                  ),
                                  TextSpan(
                                    text: 'Bases y condiciones',
                                    style: const TextStyle(
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () async {
                                        final ok = await _ensureTermsAccepted();
                                        if (!mounted) return;
                                        setState(() => _checked = ok);
                                      },
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (loggedIn) ...[
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/home',
                          (_) => false,
                        );
                      },
                      child: const Text('Continuar'),
                    ),
                  ] else if (bound) ...[
                    FilledButton(
                      onPressed: _checked
                          ? () => _go(() async {
                                Navigator.of(context).pushNamed(
                                  PhoneLoginScreen.route,
                                  arguments: {
                                    'mode': 'reenter',
                                    'phone': app.boundUserPhone,
                                    'name': app.boundUserName,
                                  },
                                );
                              })
                          : null,
                      child: const Text('Entrar'),
                    ),
                  ] else ...[
                    FilledButton(
                      onPressed: _checked
                          ? () => _go(() async {
                                Navigator.of(context).pushNamed(
                                  TitularOnboardingScreen.route,
                                );
                              })
                          : null,
                      child: const Text('Comenzar'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _checked
                          ? () => _go(() async {
                                Navigator.of(context).pushNamed(
                                  JoinFamilyScreen.route,
                                );
                              })
                          : null,
                      child: const Text('Me invitaron'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _checked
                          ? () => _go(() async {
                                Navigator.of(context).pushNamed(
                                  PhoneLoginScreen.route,
                                  arguments: {'mode': 'reenter'},
                                );
                              })
                          : null,
                      child: Text(
                        'Ya tengo cuenta',
                        style: GoogleFonts.dmSans(
                          color: Colors.white.withValues(
                            alpha: _checked ? 0.8 : 0.4,
                          ),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
