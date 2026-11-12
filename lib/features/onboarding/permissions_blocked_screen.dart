import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/widgets/app_background.dart';

class PermissionsBlockedScreen extends StatelessWidget {
  const PermissionsBlockedScreen({super.key});

  static const route = '/permissions-blocked';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final kid = app.isKid;
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
                  kid
                      ? 'Sin ubicación “Siempre”, Llegué no puede avisar a tu '
                          'familia con la app cerrada.\n\n'
                          'En Xiaomi o Samsung, además: Ajustes → Batería → '
                          'Llegué → Sin restricciones.\n\n'
                          'Activá la ubicación en Ajustes y volvé.'
                      : 'Sin los avisos activados, no te enterás cuando tu '
                          'hijo/a llega o sale.\n\n'
                          'Activá los avisos de Llegué en Ajustes y volvé.',
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
                      app.permissionsEntryRoute,
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
