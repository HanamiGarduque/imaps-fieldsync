import 'package:flutter/material.dart';

import '../layout/responsive_layout.dart';
import '../theme/insight_theme.dart';

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
  });
  final String title;
  final String? hint;
  final Widget? trailing;

  /// Hint size for guidance that must stay fully readable but must not compete
  /// with the section title. Defaults to the shared 14px hint size.
  final double hintSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
