import 'package:flutter/material.dart';

/// Paleta única de Llegué (oscuro, moderno, serio).
abstract final class AppColors {
  static const ink = Color(0xFF0F1F1C);
  static const inkSoft = Color(0xFF1A2E2A);
  static const brand = Color(0xFF1F8A70);
  static const brandDeep = Color(0xFF146B56);
  static const brandSoft = Color(0xFF2A9B82);
  static const accent = Color(0xFFE8B86D);
  static const alert = Color(0xFFE15A4F);
  static const onDark = Color(0xFFFFFFFF);
  static const onDarkMuted = Color(0xD9FFFFFF);
  static const onDarkFaint = Color(0x99FFFFFF);
  static const glass = Color(0x1FFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const fieldFill = Color(0x1FFFFFFF);

  /// Degradé de marca (bienvenida, home, shells).
  static const gradient = [
    Color(0xFF0F1F1C),
    Color(0xFF146B56),
    Color(0xFF1F8A70),
    Color(0xFF2A3D36),
  ];

  static const gradientStops = [0.0, 0.35, 0.7, 1.0];

  // Compat (pantallas viejas / diálogos claros).
  static const bgTop = Color(0xFF0F1F1C);
  static const bgBottom = Color(0xFF1F8A70);
  static const muted = Color(0xB3FFFFFF);
  static const line = Color(0x33FFFFFF);
}

BoxDecoration appGlassDecoration({double radius = 18}) {
  return BoxDecoration(
    color: AppColors.glass,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.glassBorder),
  );
}

Decoration appBrandGradientDecoration() {
  return const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.gradient,
      stops: AppColors.gradientStops,
    ),
  );
}
