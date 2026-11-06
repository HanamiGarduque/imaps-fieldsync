import 'package:flutter/material.dart';

import '../../core/theme/insight_theme.dart';
import 'guide_preferences.dart';
import 'guide_script.dart';

/// Fictional view data only. No job/application ID or persistence conversion.
class GuideExample {
  const GuideExample({
    required this.applicant,
    required this.location,
    required this.reference,
    required this.visitDate,
    required this.deadline,
  });
  final String applicant, location, reference, visitDate, deadline;
}

const guideExample = GuideExample(
  applicant: 'Sample Applicant — Fictional',
  location: 'Sample District — Fictional',
  reference: 'GUIDE-SAMPLE',
  visitDate: 'Nov 4, 2026',
  deadline: 'Nov 10, 2026',
);

class GuideSample extends StatelessWidget {
  const GuideSample({
    super.key,
    required this.child,
    this.language = GuideLanguage.english,
  });
  final Widget child;
  final GuideLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: InsightTheme.surface,
      borderRadius: InsightTheme.roundedMd,
      border: Border.all(color: InsightTheme.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          guideSampleLabel,
          style: InsightTheme.inter(
            12,
            w: FontWeight.w700,
            c: InsightTheme.blueInk,
          ),
        ),
        if (language == GuideLanguage.tagalog)
          Text(
            guideSampleTagalog,
            style: InsightTheme.inter(
              12,
              w: FontWeight.w600,
              c: InsightTheme.blueInk,
            ),
          ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}
