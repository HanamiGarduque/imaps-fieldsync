import 'package:flutter/material.dart';
import '../theme/insight_theme.dart';

/// ==================================================================
/// Shared draft-screen chrome & components, ported from the shared CSS
/// classes in insight_prototype.html (.topbar, .stepbar, .card,
/// .list-row, .pill, .btn-primary/.btn-secondary, .bottomnav, .readout)
/// so every placeholder screen looks consistent with the prototype.
/// ==================================================================

/// Wraps a screen body in the InSight dark scaffold background.
class InsightScaffold extends StatelessWidget {
  final Widget? topBar;
  final Widget? stepBar;
  final Widget body;
  final Widget? bottomBar;
  final EdgeInsets bodyPadding;

  const InsightScaffold({
    super.key,
    this.topBar,
    this.stepBar,
    required this.body,
    this.bottomBar,
    this.bodyPadding = const EdgeInsets.fromLTRB(20, 0, 20, 16),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InsightColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            if (topBar != null) topBar!,
            if (stepBar != null) stepBar!,
            Expanded(child: Padding(padding: bodyPadding, child: body)),
            if (bottomBar != null) bottomBar!,
          ],
        ),
      ),
    );
  }
}

/// .topbar — back icon + title.
class InsightTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final Widget? trailing;

  const InsightTopBar({super.key, required this.title, this.showBack = true, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 12),
      child: Row(
        children: [
          if (showBack)
            InsightIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: InsightText.display(17, w: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(52);
}

class InsightIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const InsightIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: InsightColors.lineStrong),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: InsightColors.parchment),
      ),
    );
  }
}

/// .stepbar + .stepcaption — the 6-segment wizard progress indicator.
class InsightStepBar extends StatelessWidget {
  final int totalSteps;
  final int currentStep; // 1-based
  final String stepNumber; // e.g. "01"
  final String caption;

  const InsightStepBar({
    super.key,
    this.totalSteps = 6,
    required this.currentStep,
    required this.stepNumber,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            children: List.generate(totalSteps, (i) {
              final done = i < currentStep - 1;
              final now = i == currentStep - 1;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 5),
                  height: 4,
                  decoration: BoxDecoration(
                    color: now
                        ? InsightColors.amber
                        : done
                            ? InsightColors.surveyBlue
                            : InsightColors.lineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: '$stepNumber  ', style: InsightText.mono(10, w: FontWeight.w600, c: InsightColors.amber, ls: 1.2)),
                  TextSpan(text: caption.toUpperCase(), style: InsightText.mono(10, ls: 1.2)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// .card
class InsightCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final Color? bgColor;
  const InsightCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.borderColor, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor ?? InsightColors.panel,
        border: Border.all(color: borderColor ?? InsightColors.lineStrong),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// .section-label
class InsightSectionLabel extends StatelessWidget {
  final String text;
  const InsightSectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(text.toUpperCase(), style: InsightText.mono(10, ls: 1.4)),
    );
  }
}

/// .list-row
class InsightListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? iconBorderColor;

  const InsightListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.iconBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: InsightColors.lineColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: InsightColors.panel,
                border: Border.all(color: iconBorderColor ?? InsightColors.lineStrong),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: iconColor ?? InsightColors.surveyBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightText.body(13.5, w: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: InsightText.body(11.5, c: InsightColors.slate)),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: InsightColors.slateDim),
          ],
        ),
      ),
    );
  }
}

enum InsightPillKind { pending, ongoing, completed, discrepancy, compliant, review }

/// .pill
class InsightPill extends StatelessWidget {
  final String label;
  final InsightPillKind kind;
  const InsightPill(this.label, {super.key, required this.kind});

  ({Color fg, Color bg, Color border}) get _palette {
    switch (kind) {
      case InsightPillKind.pending:
        return (fg: InsightColors.slate, bg: InsightColors.panelTranslucent, border: InsightColors.lineStrong);
      case InsightPillKind.ongoing:
      case InsightPillKind.review:
        return (fg: InsightColors.amber, bg: InsightColors.amberDim, border: InsightColors.amber);
      case InsightPillKind.completed:
      case InsightPillKind.compliant:
        return (fg: InsightColors.green, bg: InsightColors.greenDim, border: InsightColors.green);
      case InsightPillKind.discrepancy:
        return (fg: InsightColors.coral, bg: InsightColors.coralDim, border: InsightColors.coral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label.toUpperCase(), style: InsightText.mono(9.5, c: p.fg, w: FontWeight.w500, ls: 0.6)),
    );
  }
}

/// .btn-primary
class InsightPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const InsightPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: InsightColors.amber,
          foregroundColor: const Color(0xFF241A05),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF241A05)))
            : Text(label, style: InsightText.display(14.5, w: FontWeight.w600, c: const Color(0xFF241A05))),
      ),
    );
  }
}

/// .btn-secondary
class InsightSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const InsightSecondaryButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: InsightColors.parchment,
          side: const BorderSide(color: InsightColors.lineStrong),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: InsightText.body(13.5, w: FontWeight.w500)),
      ),
    );
  }
}

/// .readout — GPS coordinate readout used on login & GPS screens.
class InsightReadout extends StatelessWidget {
  final String label1;
  final String value1;
  final String accValue;
  final String accLabel;
  const InsightReadout({super.key, required this.label1, required this.value1, required this.accValue, required this.accLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: InsightColors.panelTranslucent,
        border: Border.all(color: InsightColors.lineStrong),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: InsightColors.green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: InsightColors.green.withOpacity(0.18), blurRadius: 6, spreadRadius: 3)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(children: [
                TextSpan(text: '$label1  ', style: InsightText.mono(9.5, ls: 0.6)),
                TextSpan(text: value1, style: InsightText.mono(11.5, c: InsightColors.parchment)),
              ]),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(accValue, style: InsightText.mono(13, c: InsightColors.surveyBlue, w: FontWeight.w500)),
              Text(accLabel, style: InsightText.mono(9)),
            ],
          ),
        ],
      ),
    );
  }
}

/// .checklist-item
class InsightChecklistItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  const InsightChecklistItem({super.key, required this.title, this.subtitle, required this.checked, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: InsightColors.lineColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20, height: 20,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: checked ? InsightColors.green : Colors.transparent,
                border: Border.all(color: checked ? InsightColors.green : InsightColors.lineStrong, width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: checked ? const Icon(Icons.check_rounded, size: 13, color: InsightColors.ink) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightText.body(13.5, w: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: InsightText.body(11.5, c: InsightColors.slate)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .compare-row / .compare-cell
class InsightCompareCell extends StatelessWidget {
  final String label;
  final String value;
  final bool mismatch;
  const InsightCompareCell({super.key, required this.label, required this.value, this.mismatch = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: mismatch ? InsightColors.coralDim : InsightColors.panel,
          border: Border.all(color: mismatch ? InsightColors.coral : InsightColors.lineStrong),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: InsightText.mono(9, ls: 0.6)),
            const SizedBox(height: 5),
            Text(value, style: InsightText.body(13, w: FontWeight.w500, c: mismatch ? InsightColors.coral : InsightColors.parchment)),
          ],
        ),
      ),
    );
  }
}

/// .resultopt
class InsightResultOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const InsightResultOption({super.key, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? InsightColors.amberDim : Colors.transparent,
          border: Border.all(color: selected ? InsightColors.amber : InsightColors.lineStrong),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? InsightColors.amber : Colors.transparent,
                border: Border.all(color: selected ? InsightColors.amber : InsightColors.lineStrong, width: 1.5),
              ),
              child: selected ? Center(child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: InsightColors.ink, shape: BoxShape.circle))) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: InsightText.body(13.5, w: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: InsightText.body(11, c: InsightColors.slate)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .textarea-mock — read-only styled block used for findings/notes text.
class InsightTextBlock extends StatelessWidget {
  final String text;
  const InsightTextBlock(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 80),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: InsightColors.panel,
        border: Border.all(color: InsightColors.lineStrong),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: InsightText.body(12.5, c: InsightColors.parchmentDim)),
    );
  }
}

/// .photogrid / .photocell
class InsightPhotoGrid extends StatelessWidget {
  final List<String> tags;
  final VoidCallback? onAddTap;
  const InsightPhotoGrid({super.key, required this.tags, this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tags.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) {
        if (i == tags.length) {
          return InkWell(
            onTap: onAddTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: InsightColors.slate, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add_rounded, color: InsightColors.slate),
            ),
          );
        }
        return Container(
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: InsightColors.lineStrong),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF233246), Color(0xFF1A2634)],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: InsightColors.ink.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
            child: Text(tags[i], style: InsightText.mono(8, c: InsightColors.parchmentDim)),
          ),
        );
      },
    );
  }
}

// NOTE: an old prototype-era 5-tab bottom nav (InsightTab enum +
// InsightBottomNav class, for a "Home / Inspections / Map / History /
// Profile" layout) previously lived here. It was never imported or
// instantiated anywhere in the app — confirmed via a project-wide search
// during the bottom-nav persistence refactor (see NAVIGATION_REFACTOR.md)
// — and has been removed as confirmed dead code. The bottom nav actually
// in use is `InsightBottomNav` in widgets/insight_bottom_nav.dart, owned
// solely by MainShellScreen.