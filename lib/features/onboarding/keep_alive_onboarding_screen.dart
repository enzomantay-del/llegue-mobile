import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/device/oem_keep_alive.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

/// Un paso después de ubicación Siempre + avisos, antes del Home.
/// No se puede saltear. Se guarda en el celular y no se vuelve a mostrar.
class KeepAliveOnboardingScreen extends StatelessWidget {
  const KeepAliveOnboardingScreen({super.key});

  static const route = '/onboarding-keep-alive';

  static String copyForPlatform(TargetPlatform platform) {
    return copyFor(platform: platform, kid: true);
  }

  static String copyFor({
    required TargetPlatform platform,
    required bool kid,
  }) {
    if (platform == TargetPlatform.iOS) {
      return kid ? OemKeepAliveCopy.iosKid() : OemKeepAliveCopy.iosAdult();
    }
    return kid ? OemKeepAliveCopy.androidKid() : OemKeepAliveCopy.androidAdult();
  }

  static const _channel = MethodChannel('com.llegue/keep_alive');

  bool _revisit(BuildContext context) =>
      ModalRoute.of(context)?.settings.arguments == true;

  Future<void> _understood(BuildContext context) async {
    final revisit = _revisit(context);
    final app = context.read<AppController>();
    await app.markKeepAliveOnboardingSeen();
    if (!context.mounted) return;
    if (revisit) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      app.startRoute,
      (_) => false,
    );
  }

  Future<void> _battery(BuildContext context) async {
    final app = context.read<AppController>();
    final ok = await app.keepAlive.requestIgnoreBatteryOptimizations();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se abrió solo. Andá a Ajustes → Apps → Llegué → Batería → Sin restricciones.',
          ),
        ),
      );
    }
  }

  Future<void> _appSettings() => openAppSettings();

  Future<void> _autostart(BuildContext context) async {
    var opened = false;
    try {
      opened = await _channel.invokeMethod<bool>('openAutostart') == true;
    } catch (_) {}
    if (opened) return;
    await openAppSettings();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'En Xiaomi: Seguridad → Permisos → Inicio automático → Llegué.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final revisit = _revisit(context);
    return PopScope(
      canPop: revisit,
      child: AppBackground(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Llegué'),
            automaticallyImplyLeading: revisit,
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          copyFor(
                            platform: defaultTargetPlatform,
                            kid: context.watch<AppController>().isKid,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _battery(context),
                    child: const Text('Sacar restricciones de batería'),
                  ),
                  TextButton(
                    onPressed: _appSettings,
                    child: const Text('Abrir ajustes de la app'),
                  ),
                  TextButton(
                    onPressed: () => _autostart(context),
                    child: const Text('Inicio automático (Xiaomi)'),
                  ),
                  const SizedBox(height: 8),
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
