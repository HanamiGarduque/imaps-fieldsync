import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../structured_checklist.dart';

/// Read-only Step 5/6 rendering of the CE-05 answers. Unanswered questions
/// stay visibly "Not recorded" so they can never be read as No.
class StructuredChecklistSummary extends StatelessWidget {
  const StructuredChecklistSummary({
    super.key,
    required this.answers,
    this.heading,
  });

  final Map<String, String?> answers;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final rows = StructuredChecklist.reviewRows(answers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null) FieldSectionHeading(title: heading!),
        FieldReadOnlyCard(
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : const Border(
                          bottom: BorderSide(color: InsightTheme.line),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rows[i].label,
                      style: InsightTheme.inter(13, c: InsightTheme.ink3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rows[i].value,
                      style: InsightTheme.inter(
                        15,
                        w: FontWeight.w500,
                        c: rows[i].value == 'Not recorded'
                            ? InsightTheme.ink3
                            : InsightTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (answers[StructuredChecklist.mojonObserved] != null) ...[
          const SizedBox(height: 8),
          Text(
            'A marker observation does not certify cadastral boundaries.',
            style: InsightTheme.inter(12, c: InsightTheme.ink3),
          ),
        ],
      ],
    );
  }
}
