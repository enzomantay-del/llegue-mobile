/// Textos para que el celular no hiberne Llegué.
/// Rioplatense, corto. Xiaomi/MIUI va siempre: en la prueba de campo
/// "Pausar actividad" y el autostart eran lo que mataba la detección.
class OemKeepAliveCopy {
  static String androidKid() {
    return 'Dejá Llegué instalada. Si la cerrás a la fuerza o le sacás '
        'el permiso de ubicación, tu familia deja de recibir avisos.\n\n'
        'Sacá a Llegué de la optimización de batería. En los ajustes de la app, '
        'apagá "Pausar actividad en la app si no se usa".\n\n'
        '${xiaomiAutostart()}';
  }

  static String androidAdult() {
    return 'Dejá Llegué instalada. El aviso fijo mantiene la app despierta '
        'para avisarte cuando llega o sale tu hijo/a, aunque la pantalla esté apagada.\n\n'
        'Sacá a Llegué de la optimización de batería. En los ajustes de la app, '
        'apagá "Pausar actividad en la app si no se usa".\n\n'
        '${xiaomiAutostart()}';
  }

  static String xiaomiAutostart() {
    return 'En Xiaomi, Redmi o POCO: Seguridad → Permisos → Inicio automático '
        '→ activá Llegué. Si no, el celular la frena solo.';
  }

  static String iosKid() {
    return 'Dejá Llegué instalada y no la cierres del todo. '
        'Si la deslizás hacia arriba en el selector de apps, '
        'el iPhone deja de avisar llegadas y salidas.';
  }

  static String iosAdult() {
    return 'Dejá Llegué instalada y no la cierres del todo. '
        'Si la deslizás hacia arriba en el selector de apps, '
        'podés dejar de recibir los avisos de tu familia.';
  }
}

bool isXiaomiFamily(String? manufacturer) {
  final value = (manufacturer ?? '').toLowerCase();
  return value.contains('xiaomi') ||
      value.contains('redmi') ||
      value.contains('poco');
}
