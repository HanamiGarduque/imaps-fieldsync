import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';
import '../widgets/insight_widgets.dart';

/// ==================================================================
/// SCREEN 17 — COMPLETED INSPECTION DETAILS
/// New placeholder screen, opened from InspectionHistoryScreen.
/// ==================================================================
class CompletedInspectionDetailScreen extends StatelessWidget {
  final String title;
  final String status;
  final InsightPillKind pill;

  const CompletedInspectionDetailScreen({super.key, required this.title, required this.status, required this.pill});

  @override
  Widget build(BuildContext context) {
    return InsightScaffold(
      topBar: InsightTopBar(title: title),
      body: ListView(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Ref. ZN-2026-00871 · Jul 15, 2026', style: InsightText.body(11.5, c: InsightColors.slate))),
              InsightPill(status, kind: pill),
            ],
          ),
          const SizedBox(height: 14),
          const InsightSectionLabel('Photos'),
          InsightPhotoGrid(tags: const ['14.0522, 121.1503', 'Front facade', 'Side setback']),
          const SizedBox(height: 6),
          const InsightSectionLabel('Findings'),
          const InsightTextBlock(
            'Unpermitted accessory structure in rear yard, approx. 12 sqm. Main residence matches declared layout.',
          ),
          const InsightSectionLabel('Zoning comparison'),
          const Row(
            children: [
              InsightCompareCell(label: 'Declared', value: 'Residential'),
              SizedBox(width: 10),
              InsightCompareCell(label: 'Observed', value: 'Res. + storage', mismatch: true),
            ],
          ),
        ],
      ),
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: InsightSecondaryButton(
          label: 'View full report',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Full report is a draft placeholder — not yet wired to a data source.')),
          ),
        ),
      ),
    );
  }
}
