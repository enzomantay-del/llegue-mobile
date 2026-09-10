import 'package:flutter/material.dart';

/// Logo de marca Llegué.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 72,
    this.showShadow = true,
  });

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/brand/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) => Container(
          color: const Color(0xFF146B56),
          alignment: Alignment.center,
          child: Icon(
            Icons.place_rounded,
            color: Colors.white,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}
