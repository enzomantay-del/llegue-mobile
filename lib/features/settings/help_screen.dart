import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import '../legal/terms_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const route = '/help';

  static const _faqs = <(String, String)>[
    (
      '¿Qué hace Llegué?',
      'Te avisa cuando un hijo/a llega o sale de un lugar que cargaste '
          '(Casa, colegio, etc.), y cuando hay una salida especial. '
          'No hace falta que te escriban “llegué”.',
    ),
    (
      '¿Hace falta que el celular esté siempre abierto?',
      'La app del hijo/a necesita permiso de ubicación (idealmente “Siempre”) '
          'y puede seguir detectando en segundo plano. Si apaga la ubicación '
          'o cierra la app de forma forzada, los adultos pueden recibir un aviso.',
    ),
    (
      '¿Cómo cargo un lugar o una rutina?',
      'Desde el inicio, entrá a Lugares o Rutinas. Podés crear, editar '
          '(ícono de lápiz) o eliminar. Las rutinas marcan horarios habituales '
          'como el colegio.',
    ),
    (
      '¿Qué es una salida especial?',
      'Es cuando va a un lugar fuera de la rutina (cumpleaños, ensayo, etc.). '
          'El hijo/a o un adulto la avisan y la familia se entera al llegar o salir.',
    ),
    (
      '¿Por qué no me llegan avisos?',
      'Revisá en Cuenta → Qué avisos quiero recibir. También comprobá '
          'notificaciones del sistema y que el celular del hijo/a tenga ubicación activa.',
    ),
    (
      '¿Puedo usar Llegué en iPhone?',
      'La app está pensada para Android e iOS. La versión de prueba actual '
          'se distribuye como APK en Android; iOS requiere el proceso de Apple.',
    ),
    (
      '¿Qué plan tengo?',
      'Por ahora todas las cuentas usan el plan Gratis. Más adelante '
          'vas a poder ver y cambiar el plan desde Mi perfil.',
    ),
  ];

  void _chatbotSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El chat de soporte todavía no está disponible. '
          'Pronto lo vamos a activar acá.',
        ),
      ),
    );
  }

  Future<void> _testAlarm(BuildContext context) async {
    final app = context.read<AppController>();
    await app.alerts.showTestAlarm();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Prueba de alarma'),
        content: const Text(
          'Tenés que escuchar el tono y sentir vibración. '
          'Subí el volumen de NOTIFICACIONES (no Alarma) y sacá '
          'el celular de silencio o vibrar.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Ayuda')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                'Preguntas frecuentes',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Respuestas rápidas para configurar y usar Llegué.',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              for (final faq in _faqs)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: appGlassDecoration(radius: 14),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.white12,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white70,
                      title: Text(
                        faq.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      children: [
                        Text(
                          faq.$2,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            height: 1.4,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Probar',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: appGlassDecoration(radius: 14),
                child: ListTile(
                  leading: const Icon(Icons.alarm_rounded, color: Colors.white),
                  title: const Text(
                    'Probar la alarma',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Comprobá sonido y vibración en este celular',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  onTap: () => _testAlarm(context),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Soporte',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Si no encontrás la respuesta, podés hablar con el asistente '
                'de soporte (próximamente).',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _chatbotSoon(context),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Abrir chat de soporte'),
              ),
              const SizedBox(height: 8),
              Text(
                'Todavía no conecta con un chat: el botón queda listo '
                'para cuando activemos el asistente.',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                decoration: appGlassDecoration(radius: 14),
                child: ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Bases y condiciones',
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  onTap: () =>
                      Navigator.of(context).pushNamed(TermsScreen.route),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
