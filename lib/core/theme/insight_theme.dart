import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// CANONICAL INSIGHT LIGHT THEME & DESIGN SYSTEM
/// Standardized against the Home Dashboard and Tasks screens.
/// ==================================================================
class InsightTheme {
  InsightTheme._();

  // Background & Surfaces
  static const Color bg = Color(0xFFF4F6FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEDF0F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Typography Colors (Inks)
  static const Color ink = Color(0xFF0F111A);
  static const Color ink2 = Color(0xFF595E73);
  static const Color ink3 = Color(0xFF969CB3);

  // Primary Brand Blues
  static const Color blue1 = Color(0xFF3563FF);
  static const Color blue2 = Color(0xFF0F32CA);
  static const Color blueTint = Color(0xFFE4EBFF);
  static const Color blueInk = Color(0xFF1336B8);

  // Semantics & Accents
  static const Color red = Color(0xFFE23B4E);
  static const Color redInk = Color(0xFFB72A3B);
  static const Color redTint = Color(0xFFFFECEE);

  static const Color green = Color(0xFF22C55E);
  static const Color greenInk = Color(0xFF15803D);
  static const Color greenTint = Color(0xFFEAF8F0);
  static const Color greenDim = Color(0x296FAE86);

  static const Color orange = Color(0xFFF59E0B);
  static const Color orangeTint = Color(0xFFFEF3C7);
  static const Color orangeInk = Color(0xFF78350F);
  static const Color amber = Color(0xFFE0A526);
  static const Color amberTint = Color(0xFFFEF3DE);
  static const Color amberInk = Color(0xFFA66C00);
  static const Color coral = Color(0xFFD9765A);

  // Borders & Divider Lines
  static const Color line = Color(0x15141628);
  static const Color lineStrong = Color(0x25141628);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [blue1, blue2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [blue1, Color(0xFF6B8EFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Typography Helpers
  static TextStyle poppins(
    double size, {
    FontWeight w = FontWeight.w600,
    Color? c,
    double? h,
    double? ls,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: w,
        color: c ?? ink,
        height: h ?? 1.2,
        letterSpacing: ls,
      );

  static TextStyle inter(
    double size, {
    FontWeight w = FontWeight.w400,
    Color? c,
    double? h,
    double? ls,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: w,
        color: c ?? ink2,
        height: h ?? 1.5,
        letterSpacing: ls,
      );

  static TextStyle jetBrains(
    double size, {
    FontWeight w = FontWeight.w500,
    Color? c,
    double? ls,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: w,
        color: c ?? ink3,
        letterSpacing: ls,
      );

  // Standard Dimension & Radii Tokens
  static const double radiusSm = 12.0; // Inputs, badges, mini-pills
  static const double radiusMd = 16.0; // Standard cards, action buttons
  static const double radiusLg = 24.0; // Hero folders, big modal sheets

  static final BorderRadius roundedSm = BorderRadius.circular(radiusSm);
  static final BorderRadius roundedMd = BorderRadius.circular(radiusMd);
  static final BorderRadius roundedLg = BorderRadius.circular(radiusLg);

  // Standard Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x0A141628),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0F141628),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

/// Global convenience constant for light card shadow
const List<BoxShadow> kCardShadow = InsightTheme.cardShadow;

/// Backwards compatibility alias
typedef InsightColors = InsightTheme;