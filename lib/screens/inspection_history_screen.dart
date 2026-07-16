import 'package:flutter/material.dart';

import '../theme/insight_theme.dart';
import '../widgets/insight_widgets.dart';
import 'completed_inspection_detail_screen.dart';

/// ==================================================================
/// SCREEN 16 — INSPECTION HISTORY
/// New placeholder screen. Tapping a row opens
/// CompletedInspectionDetailScreen (screen 17).
/// ==================================================================
class InspectionHistoryScreen extends StatelessWidget {
  const InspectionHistoryScreen({super.key});

  static const _entries = [
    (title: '12 Mabini Ave.', date: 'Submitted Jul 14, 2026', pill: InsightPillKind.compliant, label: 'Compliant'),
    (title: 'Lot 22-B, Brgy. Maligaya', date: 'Submitted Jul 15, 2026', pill: InsightPillKind.discrepancy, label: 'Discrepancy'),
    (title: '88 Del Pilar St.', date: 'Submitted Jul 10, 2026', pill: InsightPillKind.review, label: 'For review'),
    (title: 'Warehouse 7, Industrial Park', date: 'Submitted Jul 8, 2026', pill: InsightPillKind.compliant, label: 'Compliant'),
  ];

  @override
  Widget build(BuildContext context) {
    return InsightScaffold(
      topBar: InsightTopBar(title: 'Inspection history', showBack: false, trailing: InsightIconButton(icon: Icons.search_rounded, onTap: () {})),
      body: ListView(
        children: _entries
            .map((e) => InsightListRow(
                  icon: Icons.history_rounded,
                  title: e.title,
                  subtitle: e.date,
                  trailing: InsightPill(e.label, kind: e.pill),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CompletedInspectionDetailScreen(title: e.title, status: e.label, pill: e.pill),
                    ),
                  ),
                ))
            .toList(),
      ),
      bottomBar: InsightBottomNav(
        current: InsightTab.history,
        onSelect: (tab) {
          if (tab == InsightTab.history) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
