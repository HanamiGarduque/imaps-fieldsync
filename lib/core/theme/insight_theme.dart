import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// PREMIUM INSIGHT DESIGN TOKENS
/// Upgraded for Glassmorphism, richer shadows, and a Master Shell UI.
/// ==================================================================
class InsightColors {
  InsightColors._();

  // Base Backgrounds
  static const bodyBg = Color(0xFF0A1119);
  static const ink = Color(0xFF101B26);
  
  // Premium Panels & Glass
  static const panel = Color(0xFF1B2A3A);
  static const panel2 = Color(0x98203041); // #20304198 (panel-2, ARGB)
  static const panelGlass = Color(0xB31B2A3A); // 70% opacity for frosted glass headers
  static const panelTranslucent = Color(0x8C1B2A3A); // ~55% panel, for readouts

  // Lines & Borders
  static const lineColor = Color(0x1E96AFC4); // rgba(150,175,196,0.12)
  static const lineStrong = Color(0x3D96AFC4); // rgba(150,175,196,0.24)

  // Typography Colors
  static const parchment = Color(0xFFEDE7D9);
  static const parchmentDim = Color(0xFFB9B2A0);
  static const slate = Color(0xFF7C8AA0);
  static const slateDim = Color(0xFF4C596B);

  // Brand & Accents
  static const surveyBlue = Color(0xFF5B9BC9);
  static const surveyBlueDark = Color(0xFF3A729D); // Added for step indicators
  static const amber = Color(0xFFE0A526);
  static const amberDim = Color(0x29E0A526); // rgba(224,165,38,0.16)
  static const green = Color(0xFF6FAE86);
  static const greenDim = Color(0x296FAE86); // rgba(111,174,134,0.16)
  static const coral = Color(0xFFD9765A);
  static const coralDim = Color(0x29D9765A); // rgba(217,118,90,0.16)

  // ==================================================================
  // NEW PREMIUM TOKENS (For Master Shell & Stepper)
  // ==================================================================
  
  static const primaryGradient = LinearGradient(
    colors: [surveyBlue, surveyBlueDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get elegantShadow => [
    BoxShadow(
      color: surveyBlue.withOpacity(0.12),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 8,
      offset: const Offset(0, 4),
    )
  ];
}

class InsightText {
  InsightText._();

  static TextStyle display(double size, {FontWeight w = FontWeight.w600, Color? c, double? h}) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c ?? InsightColors.parchment, height: h);

  static TextStyle body(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
      GoogleFonts.ibmPlexSans(fontSize: size, fontWeight: w, color: c ?? InsightColors.parchment, height: h ?? 1.5);

  static TextStyle mono(double size, {FontWeight w = FontWeight.w400, Color? c, double? ls}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: w, color: c ?? InsightColors.slate, letterSpacing: ls ?? 0.5);
}