import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'brand_mark.dart';

/// Shell de onboarding con identidad de marca.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.child,
    this.progress,
    this.onBack,
  });

  final Widget child;
  final double? progress;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: appBrandGradientDecoration()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      if (onBack != null)
                        IconButton(
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          color: Colors.white,
                        )
                      else
                        const SizedBox(width: 48),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const BrandMark(size: 28, showShadow: false),
                            const SizedBox(width: 10),
                            Text(
                              'Llegué',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingStepBody extends StatelessWidget {
  const OnboardingStepBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryEnabled = true,
    this.busy = false,
    this.error,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(child: child),
          if (error != null) ...[
            Text(
              error!,
              style: GoogleFonts.dmSans(
                color: const Color(0xFFFFB4A8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: (!primaryEnabled || busy) ? null : onPrimary,
            child: Text(busy ? 'Esperá…' : primaryLabel),
          ),
        ],
      ),
    );
  }
}

InputDecoration onboardingFieldDecoration(String label, {String? helper}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.12),
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
  );
}
