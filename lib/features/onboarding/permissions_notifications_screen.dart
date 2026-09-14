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

  Future<void> _continue() async {
    setState(() => _busy = true);
    final app = context.read<AppController>();
    final location =
        ModalRoute.of(context)?.settings.arguments as String? ?? 'while_in_use';
    final notif = await app.permissions.requestNotifications();
    if (!mounted) return;

    if (notif != 'granted') {
      setState(() => _busy = false);
      Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
      return;
    }

    final ready = await app.syncPermissions(
      locationPermission: location,
      notificationsPermission: notif,
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
                Text(
                  'Para enterarte cuando tu hijo/a llega, sale o pide ayuda, '
                  'activá los avisos de este celular.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 17,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Cuando el celular pregunte, tocá “Permitir”.\n\n'
                    'Sin esto, no vas a ver los avisos a tiempo.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _continue,
                  child: Text(_busy ? 'Esperá…' : 'Activar avisos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
