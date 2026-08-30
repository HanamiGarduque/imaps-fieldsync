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

  // Typography Colors (Outdoor High-Contrast Inks - WCAG AA/AAA compliant)
  static const Color ink = Color(0xFF0F172A); // Primary text (900 slate)
  static const Color ink2 = Color(
    0xFF334155,
  ); // Secondary text / active labels (700 slate)
  static const Color ink3 = Color(
    0xFF475569,
  ); // Meta text / captions / icons (600 slate)
  static const Color inkMuted = Color(
    0xFF64748B,
  ); // Supporting secondary elements (500 slate)

  // Primary Brand Blues
  static const Color blue1 = Color(0xFF2563EB); // Vibrant Primary Blue
  static const Color blue2 = Color(0xFF1D4ED8); // Deep Brand Blue
  static const Color blueTint = Color(0xFFEFF6FF); // Light Blue Pill Tint
  static const Color blueInk = Color(
    0xFF1E40AF,
  ); // High Contrast Blue Text (800)

  // Semantics & Accents (High Contrast Text & Badges)
  static const Color red = Color(0xFFDC2626);
  static const Color redInk = Color(0xFF991B1B);
  static const Color redTint = Color(0xFFFEF2F2);

  static const Color green = Color(0xFF16A34A);
  static const Color greenInk = Color(0xFF166534);
  static const Color greenTint = Color(0xFFF0FDF4);
  static const Color greenDim = Color(0x2916A34A);

  static const Color orange = Color(0xFFD97706);
  static const Color orangeTint = Color(0xFFFFFBEB);
  static const Color orangeInk = Color(0xFF9A3412);
  static const Color amber = Color(0xFFD97706);
  static const Color amberTint = Color(0xFFFEF3C7);
  static const Color amberInk = Color(0xFF92400E);
  static const Color coral = Color(0xFFEA580C);

  // Borders & Divider Lines
  static const Color line = Color(0x1F141628);
  static const Color lineStrong = Color(0x35141628);

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

  // ─────────────────────────────────────────────────────────────────
  // Canonical Typography — Urbanist + Inter ONLY
  // Single source of truth for all font usage across iMAPS FieldSync.
  // Legacy fonts (Open Sans, Poppins, JetBrains Mono) are fully removed.
  // ─────────────────────────────────────────────────────────────────

  /// Urbanist — Display, hero headers, screen titles, section headers.
  /// Use for any text that leads the visual hierarchy on a surface.
  static TextStyle urbanist(
    double size, {
    FontWeight w = FontWeight.w700,
    Color? c,
    double? h,
    double? ls,
  }) => GoogleFonts.urbanist(
    fontSize: size < 12.0 ? 12.0 : size,
    fontWeight: w,
    color: c ?? ink,
    height: h ?? 1.2,
    letterSpacing: ls,
  );

  /// Inter — Body copy, card labels, buttons, microcopy, captions,
  /// and numerical data displays (replaces Open Sans + JetBrains Mono).
  static TextStyle inter(
    double size, {
    FontWeight w = FontWeight.w400,
    Color? c,
    double? h,
    double? ls,
  }) => GoogleFonts.inter(
    fontSize: size < 12.0 ? 12.0 : size,
    fontWeight: w,
    color: c ?? ink2,
    height: h ?? 1.4,
    letterSpacing: ls,
  );

  // ─────────────────────────────────────────────────────────────────
  // Semantic Role Aliases (call-site clarity; backed by Urbanist/Inter)
  // ─────────────────────────────────────────────────────────────────

  /// Monospace-style data display: coordinates, IDs, bearings, timestamps.
  /// Uses Inter w600 with tight tracking — same legibility, correct font.
  static TextStyle mono(
    double size, {
    FontWeight w = FontWeight.w600,
    Color? c,
    double? ls,
  }) => inter(size, w: w, c: c ?? ink3, ls: ls ?? 0.0);

  /// @deprecated — use [urbanist] directly.
  /// Kept as a one-cycle compatibility shim; will be removed next sprint.
  static TextStyle poppins(
    double size, {
    FontWeight w = FontWeight.w600,
    Color? c,
    double? h,
    double? ls,
  }) => urbanist(size, w: w, c: c, h: h, ls: ls);

  /// @deprecated — use [inter] directly.
  /// Kept as a one-cycle compatibility shim; will be removed next sprint.
  static TextStyle openSans(
    double size, {
    FontWeight w = FontWeight.w400,
    Color? c,
    double? h,
    double? ls,
  }) => inter(size, w: w, c: c, h: h, ls: ls);

  /// @deprecated — use [mono] directly.
  /// Kept as a one-cycle compatibility shim; will be removed next sprint.
  static TextStyle jetBrains(
    double size, {
    FontWeight w = FontWeight.w500,
    Color? c,
    double? ls,
  }) => mono(size, w: w, c: c, ls: ls);

  // Standard Dimension & Radii Tokens
  static const double radiusSm = 12.0; // Inputs, badges, mini-pills
  static const double radiusMd = 16.0; // Standard cards, action buttons
  static const double radiusLg = 24.0; // Hero folders, big modal sheets

  static final BorderRadius roundedSm = BorderRadius.circular(radiusSm);
  static final BorderRadius roundedMd = BorderRadius.circular(radiusMd);
  static final BorderRadius roundedLg = BorderRadius.circular(radiusLg);

  // Standard Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F141628), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Shared low-elevation inspection/workflow card shadow.
  static const List<BoxShadow> inspectionCardShadow = [
    BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4)),
  ];

  /// Shared floating glass icon button recipe used across repeated map/inspection controls.
  static BoxDecoration glassIconButtonDecoration({
    double size = 44,
    double radius = 16,
    Color fill = const Color(0xD9FFFFFF),
    Color border = const Color(0xB3FFFFFF),
    Color shadow = const Color(0x140B1440),
  }) => BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
    boxShadow: [
      BoxShadow(color: shadow, blurRadius: 20, offset: const Offset(0, 8)),
    ],
  );
}

/// Global convenience constant for light card shadow
const List<BoxShadow> kCardShadow = InsightTheme.cardShadow;

/// ==================================================================
/// CANONICAL SEMANTIC TEXT STYLES (MAS & Design Standard)
/// ==================================================================
class InsightTextStyles {
  InsightTextStyles._();

  /// Display H1: 28px Bold 700 (Urbanist) - Screen & Hero Headers
  static TextStyle displayH1({Color? color}) => InsightTheme.urbanist(
    28,
    w: FontWeight.w700,
    c: color ?? InsightTheme.ink,
    h: 1.15,
    ls: -0.5,
  );

  /// Section H2: 20px SemiBold 600 (Urbanist) - Major Page Sections
  static TextStyle sectionH2({Color? color}) => InsightTheme.urbanist(
    20,
    w: FontWeight.w600,
    c: color ?? InsightTheme.ink,
    h: 1.25,
    ls: -0.2,
  );

  /// Card Title H3: 18px SemiBold 600 (Inter) - Task & Entity Cards
  static TextStyle cardTitleH3({Color? color}) => InsightTheme.inter(
    18,
    w: FontWeight.w600,
    c: color ?? InsightTheme.ink,
    h: 1.3,
  );

  /// Body Primary: 16px Regular 400 or Medium 500 (Inter) - Main copy & Inputs
  static TextStyle bodyPrimary({
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) =>
      InsightTheme.inter(16, w: weight, c: color ?? InsightTheme.ink, h: 1.45);

  /// Body Secondary: 14px Regular 400 (Inter) - Secondary descriptions & Metadata
  static TextStyle bodySecondary({
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) =>
      InsightTheme.inter(14, w: weight, c: color ?? InsightTheme.ink2, h: 1.4);

  /// Form Label: 14px SemiBold 600 (Inter) - Form input labels
  static TextStyle formLabel({Color? color}) => InsightTheme.inter(
    14,
    w: FontWeight.w600,
    c: color ?? InsightTheme.ink2,
    ls: 0.2,
  );

  /// Section Header Pill: 13px SemiBold 600 (Inter) - Category headers
  static TextStyle sectionHeaderPill({Color? color}) => InsightTheme.inter(
    13,
    w: FontWeight.w600,
    c: color ?? InsightTheme.ink2,
    ls: 0.5,
  );

  /// Button Label: 16px SemiBold 600 (Inter) - Primary action buttons
  static TextStyle buttonPrimary({Color? color}) => InsightTheme.inter(
    16,
    w: FontWeight.w600,
    c: color ?? Colors.white,
    ls: 0.1,
  );

  /// Badge / Chip: 12px SemiBold 600 (Inter) - Status chips & tags (12px min)
  static TextStyle badge({Color? color, FontWeight weight = FontWeight.w600}) =>
      InsightTheme.inter(12, w: weight, c: color ?? InsightTheme.ink);

  /// Caption / Microcopy: 12px Medium 500 (Inter) - Smallest permitted UI text
  static TextStyle caption({Color? color}) => InsightTheme.inter(
    12,
    w: FontWeight.w500,
    c: color ?? InsightTheme.ink3,
    h: 1.35,
  );

  /// Technical / Numerical Value: 12px to 14px (Inter w600) - Coordinates & IDs
  static TextStyle monoValue({
    double size = 13,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) => InsightTheme.mono(
    size < 12.0 ? 12.0 : size,
    w: weight,
    c: color ?? InsightTheme.ink,
    ls: 0.3,
  );
}

/// Backwards compatibility alias
typedef InsightColors = InsightTheme;
