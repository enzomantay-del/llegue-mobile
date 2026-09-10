import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import 'permissions_blocked_screen.dart';
import 'permissions_notifications_screen.dart';

class PermissionsLocationScreen extends StatefulWidget {
  const PermissionsLocationScreen({super.key});

  static const route = '/permissions-location';

  @override
  State<PermissionsLocationScreen> createState() =>
      _PermissionsLocationScreenState();
}

class _PermissionsLocationScreenState extends State<PermissionsLocationScreen> {
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    final app = context.read<AppController>();
    final status = await app.permissions.requestLocationChain();
    if (!mounted) return;
    setState(() => _busy = false);
    if (status != 'always') {
      Navigator.of(context).pushNamed(PermissionsBlockedScreen.route);
      return;
    }
    Navigator.of(context).pushNamed(
      PermissionsNotificationsScreen.route,
      arguments: status,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ubicación'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Para que la app avise sola cuando llegás o salís, '
                  'necesitamos la ubicación de este celular.',
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
                    'Cuando el celular pregunte, tocá “Permitir” y después '
                    'elegí “Siempre” o “Permitir todo el tiempo”.\n\n'
                    'Si elegís otra opción, tu familia no va a recibir avisos.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _continue,
                  child: Text(_busy ? 'Esperá…' : 'Permitir ubicación'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
