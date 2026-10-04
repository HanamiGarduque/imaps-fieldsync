import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// Note: this screen is a standalone assessment picker used from the
// Zoning Comparison placeholder flow. The main 6-step inspection
// workflow (Site → GPS → Photos → Checklist → Findings → Review &
// submit) now handles final-status selection directly inside the
// Review & Submit screen, so this one simply returns the chosen
// status to whoever opened it.

import '../theme/insight_theme.dart';

/// ==================================================================
/// SCREEN 13 — INSPECTION RESULT
/// ==================================================================
class InspectionResultScreen extends StatefulWidget {
  const InspectionResultScreen({super.key});

  @override
  State<InspectionResultScreen> createState() => _InspectionResultScreenState();
}

class _InspectionResultScreenState extends State<InspectionResultScreen> {
  // Preserved options and state[cite: 10]
  static const _options = [
    (title: 'Compliant', subtitle: 'Matches declared use, no issues'),
    (title: 'With Discrepancy', subtitle: 'Observed use differs from declared'),
    (title: 'For Review', subtitle: 'Needs supervisor sign-off'),
    (title: 'Requires Reinspection', subtitle: 'Site access or conditions incomplete'),
  ];

  String _selected = 'With Discrepancy'; //[cite: 10]

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
            top: -60,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.20),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: InsightTheme.blue1.withOpacity(0.10),
                ),
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
                        child: Text(
                          'Inspection result',
                          style: InsightTheme.poppins(17, w: FontWeight.w700, c: InsightTheme.ink),
                        ),
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
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.833, // 83.3% Step 5 of 6
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [InsightTheme.blue1, InsightTheme.blue2],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 5 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — ASSESSMENT', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE LIST OF OPTIONS
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      const _SectionLabel(title: 'SELECT FINAL STATUS'),
                      const SizedBox(height: 10),
                      ..._options.map((o) => _ResultOption(
                            title: o.title,
                            subtitle: o.subtitle,
                            isSelected: _selected == o.title,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selected = o.title); //[cite: 10]
                            },
                          )),
                    ],
                  ),
                ),

                // BOTTOM ACTION BUTTON
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(_selected);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ).copyWith(
                      elevation: WidgetStateProperty.all(0),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [InsightTheme.blue1, InsightTheme.blue2],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: InsightTheme.blue1.withOpacity(0.32), blurRadius: 22, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Text(
                          'Save assessment',
                          style: InsightTheme.poppins(14.5, w: FontWeight.w600, c: Colors.white),
                        ),
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
/// COMPONENT WIDGETS
/// ==================================================================

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

class _ResultOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _ResultOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected ? const LinearGradient(
            colors: [InsightTheme.blue1, InsightTheme.blue2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ) : null,
          color: isSelected ? null : InsightTheme.surface,
          border: isSelected ? null : Border.all(color: InsightTheme.line, width: 1.5),
          boxShadow: isSelected ? [
            BoxShadow(color: InsightTheme.blue1.withOpacity(0.3), blurRadius: 22, offset: const Offset(0, 10))
          ] : [
            const BoxShadow(color: Color(0x0A141628), blurRadius: 2, offset: Offset(0, 1))
          ],
        ),
        child: Row(
          children: [
            // Custom Radio Button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.white.withOpacity(0.9) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? Colors.white : InsightTheme.lineStrong,
                  width: isSelected ? 5 : 2, // 5 creates the inner dot effect when filled with semi-transparent white
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: InsightTheme.inter(13.5, w: FontWeight.w600, c: isSelected ? Colors.white : InsightTheme.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: InsightTheme.inter(11.5, c: isSelected ? Colors.white.withOpacity(0.85) : InsightTheme.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
        width: 38,
        height: 38,
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