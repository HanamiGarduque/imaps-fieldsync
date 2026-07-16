import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ==================================================================
/// THEME COLORS & TOKENS (InSight Blue Glass & Gradient Theme)
/// ==================================================================
class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueInk = Color(0xFF1A3FC4);
  
  static const Color green = Color(0xFF12A150);
  
  static const Color line = Color(0x12141628); // ~rgba(20,22,40,0.07)
  static const Color lineStrong = Color(0x21141628); // ~rgba(20,22,40,0.13)
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => 
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
      
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) => 
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5);
      
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => 
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

/// ==================================================================
/// SCREEN 14 — REVIEW & SUBMIT
/// ==================================================================
class ReviewSubmitScreen extends StatelessWidget {
  final String result;
  const ReviewSubmitScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // ----------------------------------------------------
          // BACKGROUND GRADIENT BLOBS
          // ----------------------------------------------------
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),

          // ----------------------------------------------------
          // MAIN CONTENT
          // ----------------------------------------------------
          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Review & submit', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

                // PROGRESS BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, width: double.infinity,
                        decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1.0, // 100% Step 6 of 6
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 6 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — REVIEW & SUBMIT', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE CONTENT
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // SUMMARY CARD
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: InsightTheme.line),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1)),
                            BoxShadow(color: Color(0x0F141628), blurRadius: 30, offset: Offset(0, 14)),
                          ],
                        ),
                        child: Column(
                          children: [
                            _SummaryRow(label: 'Site', value: 'Lot 22-B, Brgy. Maligaya'),
                            _SummaryRow(label: 'Checklist', value: '7 of 7 items reviewed'),
                            _SummaryRow(label: 'Photos', value: '5 geotagged photos'),
                            _SummaryRow(label: 'Result', value: result, isLast: true),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),

                      // SIGNATURE SECTION
                      const _SectionLabel(title: 'INSPECTOR SIGNATURE'),
                      const SizedBox(height: 10),
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          // Approximating the dashed border with a solid subtle border for standard Flutter
                          border: Border.all(color: InsightTheme.lineStrong, width: 1.5), 
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Fake Signature Path
                            SizedBox(
                              width: 130, height: 44,
                              child: CustomPaint(painter: _SignaturePainter()),
                            ),
                            // Hint text at bottom
                            Positioned(
                              bottom: 10,
                              child: Text(
                                'Signed by J. Reyes · Jul 15, 2026',
                                style: InsightTheme.jetBrains(10, c: InsightTheme.ink3),
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const SubmissionSuccessScreen(referenceNo: 'ZN-2026-00871')
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(elevation: WidgetStateProperty.all(0)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text('Submit inspection', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ==================================================================
/// SCREEN 15 — SUBMISSION SUCCESS
/// ==================================================================
class SubmissionSuccessScreen extends StatelessWidget {
  final String referenceNo;
  const SubmissionSuccessScreen({super.key, required this.referenceNo});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          // Background Gradient Blobs
          Positioned(
            top: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.20)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.10)),
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Success Ring
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [InsightTheme.green, Color(0xFF0D7A3C)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: InsightTheme.green.withOpacity(0.35), blurRadius: 28, offset: const Offset(0, 14))
                        ],
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 22),
                    Text('Inspection submitted', style: InsightTheme.poppins(19, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Reference no. $referenceNo has been recorded and sent for review.',
                      textAlign: TextAlign.center,
                      style: InsightTheme.inter(12.5, c: InsightTheme.ink2, h: 1.6),
                    ),
                    const SizedBox(height: 24),
                    
                    // Action Button
                    SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          backgroundColor: Colors.transparent, 
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ).copyWith(elevation: WidgetStateProperty.all(0)),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [InsightTheme.blue1, InsightTheme.blue2],
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(minHeight: 50),
                            child: Text('Back to home', style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _SummaryRow({required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
                const SizedBox(height: 3),
                Text(value, style: InsightTheme.inter(13.5, w: FontWeight.w600, c: InsightTheme.ink)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Text('Edit', style: InsightTheme.inter(12.5, w: FontWeight.w600, c: InsightTheme.blueInk)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10, height: 2,
          decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 7),
        Text(title, style: InsightTheme.jetBrains(10, w: FontWeight.w500, ls: 1.2)),
      ],
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.65)),
          boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter to replicate the HTML SVG signature curve
class _SignaturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = InsightTheme.blue1
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Replicating: <path d="M10 35 Q25 10 40 32 T70 30 Q85 15 100 32 T130 28" />
    path.moveTo(size.width * 0.07, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.18, size.height * 0.2, size.width * 0.28, size.height * 0.64);
    path.quadraticBezierTo(size.width * 0.38, size.height * 1.08, size.width * 0.50, size.height * 0.60);
    path.quadraticBezierTo(size.width * 0.60, size.height * 0.3, size.width * 0.71, size.height * 0.64);
    path.quadraticBezierTo(size.width * 0.82, size.height * 0.98, size.width * 0.92, size.height * 0.56);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}