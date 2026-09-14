import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

/// Un paso después de ubicación Siempre + avisos, antes del Home.
/// No se puede saltear. Se guarda en el celular y no se vuelve a mostrar.
class KeepAliveOnboardingScreen extends StatelessWidget {
  const KeepAliveOnboardingScreen({super.key});

  static const route = '/onboarding-keep-alive';

  static String copyForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.iOS) {
      return 'Dejá Llegué instalada y no la cierres del todo. '
          'Si la deslizás hacia arriba en el selector de apps, '
          'el iPhone deja de avisar llegadas y salidas.';
    }
    return 'Dejá Llegué instalada. Si la cerrás a la fuerza o le sacás '
        'el permiso de ubicación, tu familia deja de recibir avisos.';
  }

  Future<void> _understood(BuildContext context) async {
    final app = context.read<AppController>();
    await app.markKeepAliveOnboardingSeen();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      app.startRoute,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AppBackground(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Llegué'),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Para que Llegué avise de verdad',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      copyForPlatform(defaultTargetPlatform),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _understood(context),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
