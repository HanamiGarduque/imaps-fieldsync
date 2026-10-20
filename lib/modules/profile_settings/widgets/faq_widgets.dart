import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../models/faq_item.dart';

class FaqExpansionTile extends StatelessWidget {
  final FaqItem item;
  final bool isTagalog;

  const FaqExpansionTile({
    super.key,
    required this.item,
    required this.isTagalog,
  });

  @override
  Widget build(BuildContext context) {
    final question = isTagalog ? item.questionTl : item.questionEn;
    final answer = isTagalog ? item.answerTl : item.answerEn;
    return ExpansionTile(
      key: PageStorageKey(question),
      minTileHeight: 48,
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: InsightTheme.blueInk,
      collapsedIconColor: InsightTheme.ink3,
      onExpansionChanged: (_) => HapticFeedback.selectionClick(),
      title: Text(
        question,
        style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.ink),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            answer,
            style: InsightTheme.inter(14, c: InsightTheme.ink2, h: 1.6),
          ),
        ),
      ],
    );
  }
}

class FaqLanguageSegmentControl extends StatelessWidget {
  final bool isTagalog;
  final ValueChanged<bool> onToggle;

  const FaqLanguageSegmentControl({
    super.key,
    required this.isTagalog,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return FieldSegmentedControl<bool>(
      labels: const {false: 'English', true: 'Tagalog'},
      value: isTagalog,
      onChanged: (selection) {
        HapticFeedback.selectionClick();
        onToggle(selection);
      },
    );
  }
}
