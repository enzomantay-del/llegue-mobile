import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/invite_links.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import '../onboarding/permissions_location_screen.dart';
import '../onboarding/phone_login_screen.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  static const route = '/join';

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _link = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _started = false;
  Map<String, dynamic>? _preview;
  String? _error;
  bool _usePinOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    final pending = context.read<AppController>().pendingInviteToken;
    final seed = args is String && args.isNotEmpty ? args : (pending ?? '');
    if (seed.isNotEmpty) {
      _link.text = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _lookup();
        // Si ya tiene sesión (volvió del teléfono), completar la invitación solo.
        final app = context.read<AppController>();
        if (app.isLoggedIn && !app.hasFamily && seed.isNotEmpty) {
          await _enter();
        }
      });
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = normalizeInviteInput(_link.text);
    if (token.length < 4) {
      setState(() => _preview = null);
      return;
    }
    try {
      final preview =
          await context.read<AppController>().previewInvitation(token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = null;
        _usePinOnly = preview['requiresPin'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _preview = null);
    }
  }

  Future<void> _enter() async {
    final token = normalizeInviteInput(_link.text);
    if (token.isEmpty) {
      setState(() => _error = 'Pegá el link o el código que te mandaron.');
      return;
    }

    final app = context.read<AppController>();

    // Solo bloquear si ESTE celular ya está dentro de una familia.
    if (app.hasFamily) {
      setState(() {
        _error =
            'Este celular ya está en la familia de ${app.displayName}. '
            'Si necesitás unirte a otra, pedile al titular que te invite desde un celular distinto.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await app.setPendingInvite(token);

      // Hijo con PIN: entra directo sin teléfono.
      if (_usePinOnly && !app.isLoggedIn) {
        if (_pin.text.trim().length != 4) {
          setState(() => _error = 'Escribí el PIN de 4 números.');
          return;
        }
        await app.loginWithPin(
          inviteTokenOrCode: token,
          pin: _pin.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          PermissionsLocationScreen.route,
          (_) => false,
        );
        return;
      }

      // Sin sesión: pedir teléfono y al volver se acepta sola la invitación.
      if (!app.isLoggedIn) {
        if (!mounted) return;
        Navigator.of(context).pushNamed(
          PhoneLoginScreen.route,
          arguments: {
            'mode': 'join',
            'inviteToken': token,
          },
        );
        return;
      }

      // Ya logueado (ej. “Sin nombre” sin familia): aceptar invitación → Mateo.
      await app.acceptInvitation(
        token,
        pin: _usePinOnly ? _pin.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        PermissionsLocationScreen.route,
        (_) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No pudimos unirte. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Me invitaron')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                'Pegá el código (o el link). Tus datos de nombre/rol ya están cargados.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _link,
                onChanged: (_) {
                  setState(() {});
                  _lookup();
                },
                decoration: const InputDecoration(
                  labelText: 'Link o código',
                  hintText: 'Ej: A9B40FED13',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_preview != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: appGlassDecoration(radius: 16),
                  child: Text(
                    'Vas a entrar a la familia ${_preview!['familyName'] ?? ''}'
                    ' como ${_preview!['nameHint']}.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              if (_usePinOnly) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'PIN de 4 números',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
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
                onPressed: _busy ? null : _enter,
                child: Text(_busy ? 'Entrando…' : 'Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
