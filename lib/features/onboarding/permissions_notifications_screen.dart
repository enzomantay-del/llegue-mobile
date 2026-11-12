import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import 'keep_alive_onboarding_screen.dart';
import 'permissions_blocked_screen.dart';

class PermissionsNotificationsScreen extends StatefulWidget {
  const PermissionsNotificationsScreen({super.key});

  static const route = '/permissions-notifications';

  @override
  State<PermissionsNotificationsScreen> createState() =>
      _PermissionsNotificationsScreenState();
}

class _PermissionsNotificationsScreenState
    extends State<PermissionsNotificationsScreen> {
  bool _busy = false;

  bool get _isKid {
    try {
      return context.watch<AppController>().isKid;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    final app = context.read<AppController>();
    final notif = await app.permissions.requestNotifications();
    if (!mounted) return;
    await _finish(app, notif);
  }

  /// El hijo/a puede seguir sin avisos: la detección no depende de eso.
  Future<void> _skipNotifications() async {
    setState(() => _busy = true);
    final app = context.read<AppController>();
    await _finish(app, 'denied');
  }

  Future<void> _finish(AppController app, String notif) async {
    final kid = app.isKid;
    if (!kid && notif != 'granted') {
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
      return;
    }

    final location = kid
        ? (ModalRoute.of(context)?.settings.arguments as String? ?? 'always')
        : await app.permissions.locationStatus();
    final ready = await app.syncPermissions(
      locationPermission: location,
      notificationsPermission: notif,
      locationOk: kid ? true : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ready) {
      Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      app.keepAliveOnboardingSeen
          ? '/home'
          : KeepAliveOnboardingScreen.route,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Avisos'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: appGlassDecoration(radius: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isKid
                            ? 'Si querés, activá los avisos de este celular. '
                                'No hace falta para avisar cuando llegás o salís.'
                            : 'Para enterarte cuando tu hijo/a llega, sale o pide ayuda, '
                                'activá los avisos de este celular.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isKid
                            ? 'Si los desactivás después, la detección sigue.'
                            : 'Cuando el celular pregunte, tocá “Permitir”.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.3,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isKid
                            ? 'Podés seguir sin avisos.'
                            : 'Sin esto, no vas a ver los avisos a tiempo.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _continue,
                  child: Text(_busy ? 'Esperá…' : 'Activar avisos'),
                ),
                if (_isKid) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _skipNotifications,
                    child: const Text('Seguir sin avisos'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
