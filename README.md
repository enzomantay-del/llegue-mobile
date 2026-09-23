# llegue_mobile

App Android de Llegué.

## Sesión y reinstalación

Si la sesión del servidor ya no vale (401), la app vuelve al inicio y no deja la familia en pantalla.

Al desinstalar, Android **no** debería restaurar el token (`allowBackup=false`). Si después de instalar sigue la cuenta vieja:

1. Ajustes → Apps → Llegué → Almacenamiento → **Borrar datos** en cada celular.
2. Instalá el APK de nuevo y creá la familia desde cero.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
