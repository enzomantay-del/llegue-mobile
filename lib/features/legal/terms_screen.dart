import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';

/// Bases y condiciones. Con `requireAccept: true` exige aceptación para continuar.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const route = '/terms';

  static const sections = <(String, String)>[
    (
      '1. Aceptación',
      'Al descargar, instalar o usar Llegué, aceptás estas Bases y Condiciones '
          'y nuestra Política de Privacidad. Si no estás de acuerdo, no uses la app.\n\n'
          'Estas bases aplican a la versión de prueba y a las versiones futuras '
          'publicadas en tiendas digitales.',
    ),
    (
      '2. Qué es Llegué (y qué no es)',
      'Llegué es un servicio de tranquilidad familiar: ayuda a enterarte cuando '
          'un integrante llega o sale de lugares que la familia cargó '
          '(por ejemplo Casa o Colegio), y a coordinar salidas, sin depender '
          'de que alguien te escriba un mensaje.\n\n'
          'Llegué NO es:\n'
          '• un servicio de emergencia (112 / 911 / policía / ambulancia);\n'
          '• un rastreador en tiempo real permanente tipo “ver el punto en el mapa todo el día” '
          'como producto principal;\n'
          '• un reemplazo del cuidado, la comunicación o la responsabilidad de madres, '
          'padres o tutores.',
    ),
    (
      '3. Quién puede usar la app',
      'El titular de la cuenta familiar debe ser mayor de edad y capaz de '
          'contratar según la ley aplicable.\n\n'
          'Los menores solo pueden usar Llegué con autorización y supervisión '
          'de su madre, padre, tutor o adulto responsable. El adulto es quien '
          'configura la familia, invita al menor y decide los lugares y avisos.\n\n'
          'Al invitar a un menor, declarás que tenés facultad para hacerlo y '
          'que el uso es en interés de su cuidado y seguridad.',
    ),
    (
      '4. Cuenta, teléfono y un celular por persona',
      'El acceso se realiza con teléfono (y/o mecanismos que habilitemos) '
          'para proteger la cuenta familiar.\n\n'
          'Por seguridad, cada celular suele quedar asociado a una sola persona '
          'y rol dentro de la familia. No compartas códigos de acceso, links '
          'de invitación ni PIN con personas ajenas a tu círculo.',
    ),
    (
      '5. Ubicación y permisos',
      'Para funcionar, Llegué necesita permisos del sistema, en especial:\n'
          '• ubicación (idealmente “Siempre” / en segundo plano) en el celular '
          'de quien se desplaza;\n'
          '• notificaciones, para que los avisos lleguen a tiempo.\n\n'
          'La ubicación se usa para detectar llegadas y salidas de lugares '
          'configurados por la familia, y para funciones relacionadas '
          '(por ejemplo salidas avisadas). No vendemos tu ubicación a terceros '
          'con fines publicitarios.\n\n'
          'Si el sistema operativo, el ahorro de batería o el usuario limitan '
          'esos permisos, Llegué puede fallar o demorar avisos. Eso no siempre '
          'está bajo nuestro control.',
    ),
    (
      '6. Datos personales y privacidad',
      'Tratamos datos como nombre, teléfono, rol familiar, lugares, eventos '
          'de llegada/salida, estado del dispositivo (por ejemplo batería baja) '
          'y tokens técnicos necesarios para el servicio.\n\n'
          'Los usamos para prestar Llegué, mejorar la seguridad del producto, '
          'cumplir obligaciones legales y, cuando corresponda, gestionar '
          'suscripciones.\n\n'
          'Podés pedir información, corrección o baja de tu cuenta según la '
          'ley aplicable. El detalle completo estará en la Política de Privacidad '
          'publicada junto con el lanzamiento en tiendas.',
    ),
    (
      '7. Menores y cuidado especial',
      'Los datos de menores se tratan con mayor cuidado y solo en el marco '
          'del servicio familiar autorizado por el adulto responsable.\n\n'
          'El adulto se compromete a no usar Llegué para hostigar, controlar '
          'de forma abusiva ni vulnerar derechos del niño, niña o adolescente.',
    ),
    (
      '8. Uso correcto',
      'Te comprometés a:\n'
          '• usar Llegué de buena fe, en el ámbito familiar o de cuidado;\n'
          '• no intentar vulnerar la seguridad, copiar el servicio ni usarlo '
          'con fines ilegales;\n'
          '• no suplantar identidades ni invitar personas sin derecho;\n'
          '• mantener actualizados permisos y una conexión razonable para '
          'que el servicio pueda operar.',
    ),
    (
      '9. Limitaciones del servicio',
      'Los avisos dependen de GPS, red, batería, sistema operativo y de que '
          'la app pueda ejecutarse en segundo plano. Puede haber demoras, '
          'falsos positivos o negativos (por ejemplo zonas con mala señal, '
          'ahorro agresivo del celular, o permisos incompletos).\n\n'
          'Por eso Llegué se ofrece como apoyo a la tranquilidad familiar, '
          'no como garantía absoluta ni como sistema de alerta crítica.',
    ),
    (
      '10. Etapas del producto y pagos',
      'Llegué puede ofrecerse primero en prueba cerrada, luego con acceso '
          'gratuito y después con suscripciones u otras modalidades de pago.\n\n'
          'Cuando haya cobros, se informarán precios, período de prueba '
          '(si existe), renovación y cancelación de forma clara en la tienda '
          '(Google Play / App Store) y/o en la app, antes de que pagues.',
    ),
    (
      '11. Responsabilidad',
      'En la medida que permita la ley, Llegué y sus responsables no '
          'responden por daños derivados de:\n'
          '• falta de permisos, batería o conexión;\n'
          '• decisiones tomadas solo en base a un aviso o a la ausencia de aviso;\n'
          '• uso indebido por parte de usuarios de la familia;\n'
          '• interrupciones del servicio durante pruebas o mantenimiento.\n\n'
          'Nada de esto limita derechos irrenunciables del consumidor.',
    ),
    (
      '12. Cambios',
      'Podemos actualizar estas Bases. Si el cambio es relevante, lo '
          'avisaremos en la app o por otro medio razonable. El uso continuo '
          'después del aviso implica aceptación de la versión vigente.',
    ),
    (
      '13. Contacto y ley aplicable',
      'Consultas sobre estas Bases: el canal de contacto que indiquemos '
          'en la ficha de la tienda o en la app.\n\n'
          'Salvo norma imperativa en contrario, se aplica la legislación '
          'de la República Argentina y los tribunales competentes según '
          'las normas de consumo y protección de datos vigentes.',
    ),
  ];

  bool _requireAccept(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['requireAccept'] == true) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final requireAccept = _requireAccept(context);

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bases y condiciones'),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(
                    'Llegué — Bases y condiciones de uso',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    requireAccept
                        ? 'Leé estas bases. Para usar Llegué tenés que aceptarlas.'
                        : 'Documento vigente de uso del servicio.',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final s in sections) ...[
                    Text(
                      s.$1,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  Text(
                    'Última actualización: septiembre 2026',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.onDarkFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (requireAccept)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FilledButton(
                    onPressed: () async {
                      await context.read<AppController>().acceptTerms();
                      if (!context.mounted) return;
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('Leí y acepto'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
