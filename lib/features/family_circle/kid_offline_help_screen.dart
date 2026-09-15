import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/copy/outing_copy.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

class KidOfflineHelpScreen extends StatelessWidget {
  const KidOfflineHelpScreen({super.key, this.info});

  static const route = '/kid-offline-help';

  final KidOfflineInfo? info;

  static KidOfflineInfo? argsOf(BuildContext context) {
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is KidOfflineInfo) return raw;
    if (raw is Map) {
      return KidOfflineInfo.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> _openWhatsApp(BuildContext context, KidOfflineInfo data) async {
    final phone = (data.kidPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay un teléfono cargado para ${data.kidName}.',
          ),
        ),
      );
      return;
    }
    final encoded = Uri.encodeComponent(KidOfflineInfo.whatsappText);
    final candidates = [
      Uri.parse('https://wa.me/$phone?text=$encoded'),
      Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
    ];
    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos abrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = info ?? argsOf(context);
    final name = data?.kidName ?? 'tu hijo/a';
    final hasPhone = (data?.kidPhone ?? '').replaceAll(RegExp(r'\D'), '').isNotEmpty;

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ubicación'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  decoration: appGlassDecoration(radius: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name dejó de compartir ubicación',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Si cerró Llegué, pedile que la abra de nuevo. '
                        'Así la app puede avisar sola cuando llegue o salga.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 15,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: data == null
                      ? null
                      : () => _openWhatsApp(context, data),
                  child: Text('Avisale a $name que abra Llegué'),
                ),
                if (!hasPhone) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Si no se abre WhatsApp, cargá el teléfono de $name en la familia.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
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
