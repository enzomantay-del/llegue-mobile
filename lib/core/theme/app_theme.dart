import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Tema único de producto (oscuro moderno).
  static ThemeData brand() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brand,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: AppColors.ink,
        error: AppColors.alert,
        onError: Colors.white,
        surface: AppColors.inkSoft,
        onSurface: AppColors.onDark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    final ui = GoogleFonts.dmSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.onDark,
      displayColor: AppColors.onDark,
    );

    return base.copyWith(
      textTheme: ui.copyWith(
        titleLarge: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.onDark,
          letterSpacing: -0.4,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.onDark,
          letterSpacing: -0.6,
        ),
        bodyMedium: GoogleFonts.dmSans(
          fontSize: 15,
          height: 1.4,
          color: AppColors.onDarkMuted,
        ),
        bodyLarge: GoogleFonts.dmSans(
          fontSize: 16,
          height: 1.4,
          color: AppColors.onDark,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.onDark,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.onDark,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.onDark),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.onDarkMuted,
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
        helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.inkSoft,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.onDark,
        ),
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: 15,
          color: AppColors.onDarkMuted,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.inkSoft,
        modalBackgroundColor: AppColors.inkSoft,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.white70;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return Colors.white24;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.onDark,
        textColor: AppColors.onDark,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.white,
      ),
      dividerColor: AppColors.glassBorder,
    );
  }

  /// Alias por compatibilidad.
  static ThemeData light() => brand();
}
