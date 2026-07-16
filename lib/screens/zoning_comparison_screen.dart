import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';
import '../widgets/insight_widgets.dart';
import 'inspection_result_screen.dart';

/// ==================================================================
/// SCREEN 11 — ZONING COMPARISON
/// New placeholder screen.
/// ==================================================================
class ZoningComparisonScreen extends StatelessWidget {
  const ZoningComparisonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return InsightScaffold(
      topBar: const InsightTopBar(title: 'Zoning comparison'),
      stepBar: const InsightStepBar(currentStep: 4, stepNumber: '04', caption: 'Findings'),
      body: ListView(
        children: [
          const InsightSectionLabel('Declared vs. observed'),
          const Row(
            children: [
              InsightCompareCell(label: 'Declared use', value: 'Residential'),
              SizedBox(width: 10),
              InsightCompareCell(label: 'Zoning class', value: 'R-1'),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              InsightCompareCell(label: 'Actual observed use', value: 'Residential + storage', mismatch: true),
              SizedBox(width: 10),
              InsightCompareCell(label: 'Lot area', value: '312 sqm'),
            ],
          ),
          const SizedBox(height: 14),
          InsightCard(
            borderColor: InsightColors.coral,
            bgColor: InsightColors.coralDim,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: InsightColors.coral),
                const SizedBox(width: 8),
                Text('Mismatch flagged', style: InsightText.body(12.5, w: FontWeight.w500, c: InsightColors.coral)),
              ],
            ),
          ),
        ],
      ),
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: InsightPrimaryButton(
          label: 'Continue to assessment',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionResultScreen())),
        ),
      ),
    );
  }
}
