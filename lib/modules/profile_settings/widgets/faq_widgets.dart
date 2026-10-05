import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../models/faq_item.dart';

class FaqExpansionTile extends StatefulWidget {
  final FaqItem item;
  final bool isTagalog;

  const FaqExpansionTile({
    super.key,
    required this.item,
    required this.isTagalog,
  });

  @override
  State<FaqExpansionTile> createState() => _FaqExpansionTileState();
}

class _FaqExpansionTileState extends State<FaqExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final question = widget.isTagalog ? widget.item.questionTl : widget.item.questionEn;
    final answer = widget.isTagalog ? widget.item.answerTl : widget.item.answerEn;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: InsightTheme.blueTint,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        key: PageStorageKey(question),
        initiallyExpanded: false,
        onExpansionChanged: (expanded) {
          HapticFeedback.selectionClick();
          setState(() => _isExpanded = expanded);
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isExpanded ? InsightTheme.blueTint : InsightTheme.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              'Q',
              style: InsightTheme.jetBrains(
                12,
                w: FontWeight.w700,
                c: _isExpanded ? InsightTheme.blue1 : InsightTheme.ink3,
              ),
            ),
          ),
        ),
        title: Text(
          question,
          style: InsightTheme.urbanist(
            14.5,
            w: _isExpanded ? FontWeight.w700 : FontWeight.w600,
            c: _isExpanded ? InsightTheme.blueInk : InsightTheme.ink,
          ),
        ),
        trailing: AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: _isExpanded ? InsightTheme.blue1 : InsightTheme.ink3,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: InsightTheme.surface2.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: InsightTheme.line.withValues(alpha: 0.8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: InsightTheme.blue1.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      'A',
                      style: InsightTheme.jetBrains(
                        10,
                        w: FontWeight.w700,
                        c: InsightTheme.blue1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    answer,
                    style: InsightTheme.inter(
                      13,
                      w: FontWeight.w400,
                      c: InsightTheme.ink,
                      h: 1.45,
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
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x05141628), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: !isTagalog ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggle(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: InsightTheme.inter(
                        13,
                        w: !isTagalog ? FontWeight.w700 : FontWeight.w500,
                        c: !isTagalog ? InsightTheme.blueInk : InsightTheme.ink2,
                      ),
                      child: const Text('English'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggle(true);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: InsightTheme.inter(
                        13,
                        w: isTagalog ? FontWeight.w700 : FontWeight.w500,
                        c: isTagalog ? InsightTheme.blueInk : InsightTheme.ink2,
                      ),
                      child: const Text('Tagalog'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FaqGlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const FaqGlassBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x06141628), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.only(left: 5.0),
                child: Icon(Icons.arrow_back_ios, size: 16, color: InsightTheme.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
