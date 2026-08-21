import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'inspection_result_screen.dart';

/// ==================================================================
/// SCREEN 11 — ZONING COMPARISON (STANDALONE / FINDINGS PREVIEW)
/// Converted to standard Light Theme matching Home and Tasks.
/// ==================================================================
class ZoningComparisonScreen extends StatelessWidget {
  const ZoningComparisonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return SensitiveScreen(
      child: Scaffold(
        backgroundColor: InsightTheme.bg,
        body: Stack(
          children: [
            // Soft ambient glow
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
                    color: InsightTheme.blue1.withValues(alpha: 0.20),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // App Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white),
                              boxShadow: kCardShadow,
                            ),
                            child: const Center(
                              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Zoning Comparison', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                              Text('Observed vs Declared land use', style: InsightTheme.inter(12, c: InsightTheme.ink2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Step Bar (Step 5 of 6)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: InsightTheme.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 5 / 6,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: InsightTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('STEP 5 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                            Text(' — LOG OBSERVATIONS', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Comparison Content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Text('DECLARED VS. OBSERVED USE', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(child: _buildInfoCard('Declared Use', 'Residential', false)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInfoCard('Zoning Class', 'R-1 (Low Density)', false)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(child: _buildInfoCard('Actual Observed', 'Residential + Commercial Storage', true)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInfoCard('Lot Area', '312 sqm', false)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Mismatch alert box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: InsightTheme.redTint,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: InsightTheme.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 20, color: InsightTheme.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Discrepancy Flagged', style: InsightTheme.poppins(13, w: FontWeight.w600, c: InsightTheme.redInk)),
                                    const SizedBox(height: 2),
                                    Text('Observed land use does not strictly conform to residential zoning permit.', style: InsightTheme.inter(12, c: InsightTheme.redInk)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Action Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionResultScreen()));
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: InsightTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: InsightTheme.blue1.withValues(alpha: 0.32),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text('Continue to Assessment', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
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
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, bool isHighlight) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isHighlight ? InsightTheme.red.withValues(alpha: 0.4) : InsightTheme.line),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: InsightTheme.jetBrains(9, w: FontWeight.w700, c: isHighlight ? InsightTheme.red : InsightTheme.ink3, ls: 0.5)),
          const SizedBox(height: 6),
          Text(value, style: InsightTheme.poppins(13, w: FontWeight.w600, c: isHighlight ? InsightTheme.redInk : InsightTheme.ink)),
        ],
      ),
    );
  }
}
