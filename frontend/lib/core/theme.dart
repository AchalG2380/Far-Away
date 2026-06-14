import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ══════════════════════════════════════════════════════════════
///  MANEORA — Midnight Navy + Amber Design System
///  Fonts : Archivo Black (headings) · Outfit (body/UI)
///  Both loaded via google_fonts package — no asset declaration needed.
/// ══════════════════════════════════════════════════════════════
class AppTheme {

  // ── Core Palette ──────────────────────────────────────────────
  static const Color bgDeep        = Color(0xFF0A0F1E);
  static const Color bgCard        = Color(0xFF141C2E);
  static const Color bgSurface     = Color(0xFF1A2236);
  static const Color bgHover       = Color(0xFF1E2840);
  static const Color borderDefault = Color(0xFF2A3652);
  static const Color borderAmber   = Color(0xFF8A5C0F);

  // ── Accent ───────────────────────────────────────────────────
  static const Color amber         = Color(0xFFF5A623);
  static const Color amberLight    = Color(0xFFFFD080);
  static const Color amberDim      = Color(0xFF8A5C0F);
  static const Color sky           = Color(0xFF4B9EFF);
  static const Color green         = Color(0xFF3DD68C);

  // ── Text ─────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFFB0BCDA);
  static const Color textMuted     = Color(0xFF8A95B0);

  // ── Semantic ─────────────────────────────────────────────────
  static const Color error         = Color(0xFFFF5C6A);
  static const Color accentGreen   = Color(0xFF3DD68C);
  static const Color accentAmber   = Color(0xFFF5A623);

  // ── Legacy aliases (for files not yet updated) ────────────────
  static const Color inkBlack      = textPrimary;
  static const Color inkSoft       = textSecondary;
  static const Color inkMuted      = textMuted;
  static const Color buttercream   = bgCard;
  static const Color vanillaBeige  = bgSurface;
  static const Color clay          = borderDefault;
  static const Color clayDark      = borderAmber;

  // ── Gradients ────────────────────────────────────────────────
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A0F1E), Color(0xFF0F1628), Color(0xFF0A0F1E)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141C2E), Color(0xFF111827)],
  );

  // ── Main ThemeData ────────────────────────────────────────────
  static ThemeData get vanillaClayTheme => midnightAmberTheme;

  static ThemeData get midnightAmberTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,

      colorScheme: const ColorScheme.dark(
        primary: amber,
        secondary: sky,
        surface: bgCard,
        error: error,
        onPrimary: bgDeep,
        onSecondary: bgDeep,
        onSurface: textPrimary,
      ),

      textTheme: TextTheme(
        displayLarge: GoogleFonts.archivoBlack(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.archivoBlack(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.archivoBlack(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          letterSpacing: 0.2,
        ),
        titleMedium: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          height: 1.6,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textMuted,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textSecondary,
          letterSpacing: 1.8,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: bgDeep,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          textStyle: GoogleFonts.archivoBlack(
            fontWeight: FontWeight.w400,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          side: const BorderSide(color: borderDefault, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        hintStyle: GoogleFonts.outfit(
          color: textMuted,
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderDefault, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderDefault, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: amber, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),

      dividerTheme: const DividerThemeData(
        color: borderDefault,
        thickness: 1,
        space: 0,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderDefault, width: 1),
        ),
        titleTextStyle: GoogleFonts.archivoBlack(
          fontSize: 20,
          color: textPrimary,
        ),
      ),

      iconTheme: const IconThemeData(color: textMuted, size: 22),
    );
  }
}