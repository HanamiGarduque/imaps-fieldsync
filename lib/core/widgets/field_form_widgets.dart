import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../layout/responsive_layout.dart';
import '../theme/insight_theme.dart';

/// Compact visual plate inside the full native navigation target.
class FieldBackButton extends StatelessWidget {
  const FieldBackButton({super.key, required this.onPressed, this.tooltip = 'Back'});
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: DecoratedBox(
        decoration: BoxDecoration(color: InsightTheme.surface,
          borderRadius: InsightTheme.roundedSm, border: Border.all(color: InsightTheme.line)),
        child: const SizedBox.square(dimension: 38,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: InsightTheme.ink)),
      ),
    ),
  );
}

/// Secondary explanatory control; the screen owns its message and action.
class FieldInfoButton extends StatelessWidget {
  const FieldInfoButton({super.key, required this.label, required this.onPressed,
    this.color = InsightTheme.blueInk, this.backgroundColor = InsightTheme.blueTint});
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor,
          borderRadius: BorderRadius.circular(10)),
        child: SizedBox.square(dimension: 28,
          child: Icon(Icons.info_outline_rounded, size: 18, color: color)),
      ),
    ),
  );
}

/// Existing document/settings navigation, with a content-sized title.
class FieldPageHeader extends StatelessWidget {
  const FieldPageHeader({super.key, required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(children: [
    FieldBackButton(
      onPressed: onBack ?? () => Navigator.maybePop(context),
    ),
    const SizedBox(width: 8),
    Expanded(child: Semantics(header: true,
        child: Text(title, style: InsightTheme.urbanist(20, w: FontWeight.w700)))),
  ]);
}

/// Restyles existing two-way selectors; values and callbacks stay screen-owned.
class FieldSegmentedControl<T extends Object> extends StatelessWidget {
  const FieldSegmentedControl({super.key, required this.labels,
    required this.value, required this.onChanged, this.compact = false});
  final Map<T, String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => CupertinoSlidingSegmentedControl<T>(
    groupValue: value,
    backgroundColor: InsightTheme.surface2,
    thumbColor: InsightTheme.surface,
    padding: const EdgeInsets.all(4),
    children: {
      for (final entry in labels.entries)
        entry.key: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 40 : 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 12, vertical: compact ? 8 : 12),
            child: Text(entry.value, textAlign: TextAlign.center,
                style: InsightTheme.inter(compact ? 12 : 13, w: FontWeight.w600,
                    c: entry.key == value ? InsightTheme.blueInk : InsightTheme.ink2)),
          ),
        ),
    },
    onValueChanged: (selection) {
      if (selection != null) onChanged(selection);
    },
  );
}

/// Shared presentation for FieldSync's document and form screens.
class FieldFormBody extends StatelessWidget {
  const FieldFormBody({
    super.key,
    required this.header,
    required this.children,
    required this.action,
  });

  final Widget header;
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Short/keyboard-constrained screens scroll the action with the document.
        final scrollAction =
            constraints.maxHeight < InsightBreakpoints.shortHeight;
        final footer = Container(
          decoration: const BoxDecoration(
            color: InsightTheme.surface,
            border: Border(top: BorderSide(color: InsightTheme.line)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: action,
        );
        return ConstrainedContent(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    header,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                    if (scrollAction) footer,
                  ],
                ),
              ),
              if (!scrollAction) footer,
            ],
          ),
        );
      },
    ),
  );
}

class FieldSectionHeading extends StatelessWidget {
  const FieldSectionHeading({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
    this.hintSize = 14,
    this.bottomSpacing = 12,
  });
  final String title;
  final String? hint;
  final Widget? trailing;

  /// Hint size for guidance that must stay fully readable but must not compete
  /// with the section title. Defaults to the shared 14px hint size.
  final double hintSize;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: InsightTheme.urbanist(18, w: FontWeight.w700),
              ),
            ),
            ?trailing,
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: InsightTheme.inter(hintSize, c: InsightTheme.ink3),
          ),
        ],
      ],
    ),
  );
}

/// Read-only grouped content — a bordered surface holding the related rows of
/// one section, so a reviewer never reads bare labels floating on the canvas.
class FieldReadOnlyCard extends StatelessWidget {
  const FieldReadOnlyCard({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: InsightTheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: InsightTheme.line),
      boxShadow: InsightTheme.inspectionCardShadow,
    ),
    child: Column(children: children),
  );
}

class FieldPrimaryButton extends StatelessWidget {
  const FieldPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Saving…',
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String busyLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: InsightTheme.blue1,
        foregroundColor: Colors.white,
        disabledBackgroundColor: InsightTheme.blueTint,
        disabledForegroundColor: InsightTheme.blueInk,
        elevation: 0,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedMd),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          Text(
            busy ? busyLabel : label,
            textAlign: TextAlign.center,
            style: InsightTheme.inter(
              16,
              w: FontWeight.w600,
              c: onPressed == null ? InsightTheme.blueInk : Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}
