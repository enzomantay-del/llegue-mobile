import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/widgets/app_background.dart';
import '../family_setup/create_family_screen.dart';
import '../family_setup/join_family_screen.dart';
import 'permissions_location_screen.dart';
import 'switch_person_dialog.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  static const route = '/login';

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  bool _argsApplied = false;

  Map<String, dynamic> get _args {
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) return {'mode': raw};
    return {'mode': 'create'};
  }

  String get _mode => (_args['mode'] as String?) ?? 'create';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsApplied) return;
    _argsApplied = true;
    final phone = _args['phone'] as String?;
    if (phone != null && phone.isNotEmpty) {
      _phone.text = phone;
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length < 8) {
      setState(() => _error = 'Escribí tu número de teléfono.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().requestOtp(phone);
      setState(() {
        _codeSent = true;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() {
        _error =
            'No pudimos conectar. Revisá tu conexión a internet e intentá de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final app = context.read<AppController>();
      await _verifyWith(app, reassignDevice: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isPhoneOwner) {
        setState(() => _error = e.message);
        return;
      }
      if (e.code == 'device_bound') {
        final from = e.boundUserName ?? 'otra persona';
        final to = _args['inviteName'] as String?;
        final ok = await confirmSwitchPerson(
          context,
          fromName: from,
          toName: to,
        );
        if (!ok || !mounted) return;
        try {
          final app = context.read<AppController>();
          await _verifyWith(app, reassignDevice: true);
          return;
        } on ApiException catch (again) {
          if (!mounted) return;
          setState(() => _error = again.message);
          return;
        }
      }
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No pudimos entrar. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyWith(AppController app, {required bool reassignDevice}) async {
    final inviteToken = (_args['inviteToken'] as String?)?.trim().isNotEmpty == true
        ? _args['inviteToken'] as String
        : app.pendingInviteToken;
    await app.verifyOtp(
      phone: _phone.text.trim(),
      code: _code.text.trim(),
      reassignDevice: reassignDevice,
      inviteToken: inviteToken,
    );
    if (!mounted) return;
    await _goAfterLogin(app, inviteToken);
  }

  Future<void> _goAfterLogin(AppController app, String? inviteToken) async {
      // Flujo invitado: tras el teléfono, aceptar la invitación al toque.
      if (_mode == 'join' ||
          (inviteToken != null && inviteToken.isNotEmpty)) {
        if (inviteToken != null && inviteToken.isNotEmpty && !app.hasFamily) {
          try {
            await app.setPendingInvite(inviteToken);
            await app.acceptInvitation(inviteToken);
            if (!mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              PermissionsLocationScreen.route,
              (_) => false,
            );
            return;
          } on ApiException catch (e) {
            if (e.isPhoneOwner) {
              setState(() => _error = e.message);
              return;
            }
            // Si falla, volvemos a la pantalla de invitación con el error.
            if (!mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              JoinFamilyScreen.route,
              (_) => false,
              arguments: inviteToken,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message)),
            );
            return;
          }
        }
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          JoinFamilyScreen.route,
          (_) => false,
          arguments: inviteToken,
        );
        return;
      }

      if (!app.hasFamily) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          CreateFamilyScreen.route,
          (_) => false,
        );
      } else if (!app.permissionsReady) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          PermissionsLocationScreen.route,
          (_) => false,
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
  }

  @override
  Widget build(BuildContext context) {
    final nameHint = _args['name'] as String?;
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _mode == 'reenter' && nameHint != null
                ? 'Hola, $nameHint'
                : 'Tu teléfono',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                _codeSent
                    ? 'Te enviamos un código. Escribilo para entrar.'
                    : 'Usamos tu teléfono para proteger tu cuenta familiar.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                enabled: !_codeSent,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  hintText: 'Con código de área',
                ),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: const InputDecoration(
                    labelText: 'Código',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFFB4A8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                child: Text(
                  _busy
                      ? 'Esperá…'
                      : (_codeSent ? 'Entrar' : 'Enviar código'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
