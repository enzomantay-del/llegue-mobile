import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/widgets/app_background.dart';
import 'permissions_location_screen.dart';

class PermissionsBlockedScreen extends StatelessWidget {
  const PermissionsBlockedScreen({super.key});

  static const route = '/permissions-blocked';

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Falta un permiso'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sin ubicación “Siempre” y avisos activados, Llegué no puede '
                  'avisar a tu familia con la app cerrada.\n\n'
                  'Activá los permisos en Ajustes y volvé.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 17,
                        height: 1.4,
                      ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => app.permissions.openSettings(),
                  child: const Text('Ir a Ajustes'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      PermissionsLocationScreen.route,
                      (_) => false,
                    );
                  },
                  child: const Text('Ya lo activé — continuar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
