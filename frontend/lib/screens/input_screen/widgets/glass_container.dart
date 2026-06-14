import 'package:flutter/material.dart';
import 'dart:ui';

/// Dark-mode glass container — semi-transparent navy surface
/// with a subtle amber-tinted border and deep shadow.
class GlassContainer extends StatelessWidget {
  final Widget child;
  const GlassContainer({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            // Dark navy glass surface
            color: const Color(0xFF141C2E).withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF2A3652).withValues(alpha: 0.8),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 48,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: const Color(0xFFF5A623).withValues(alpha: 0.04),
                blurRadius: 80,
                spreadRadius: 0,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}