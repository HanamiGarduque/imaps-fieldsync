import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// iMAPS FieldSync - Active Assignments folder card (light iMAPS language)
//
// Stack architecture:
//   Layer 0 - White folder back (surface card, hairline border, kCardShadow)
//   Layer 1 - (removed with the dark gloss treatment)
//   Layer 2 — Document sheets fanning out from inside the folder
//   Layer 3 - Light pocket (surface2, asymmetric folder-tab ClipPath kept)
//   Layer 4 - (removed with the dark gloss treatment)
//   Layer 5 — Content: iMAPS FieldSync brand + assignment data
//   Layer 6 - Status badge (canonical status tint/ink pair)
// ─────────────────────────────────────────────────────────────────────────────

/// One semantic status-color mapping, shared with the Tasks screen and the
/// dashboard progress ring (canonical InsightTheme tokens):
/// Ongoing = blue | Scheduled/Pending = orange | Completed = green.
class _FolderAccent {
  static Color tone(String status) {
    switch (status) {
      case 'Ongoing':   return InsightTheme.blue1;
      case 'Completed': return InsightTheme.green;
      default:          return InsightTheme.orange; // Pending & Scheduled
    }
  }

  static Color tintOf(String status) {
    switch (status) {
      case 'Ongoing':   return InsightTheme.blueTint;
      case 'Completed': return InsightTheme.greenTint;
      default:          return InsightTheme.orangeTint;
    }
  }

  static Color inkOf(String status) {
    switch (status) {
      case 'Ongoing':   return InsightTheme.blueInk;
      case 'Completed': return InsightTheme.greenInk;
      default:          return InsightTheme.orangeInk;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public Widget
// ─────────────────────────────────────────────────────────────────────────────
class ActiveAssignmentsFolderCard extends StatefulWidget {
  final String inspectionId;
  final String referenceNo;
  final String date;
  final String location;
  final String applicantName;
  final String applicationType;
  final String status;
  final VoidCallback onTap;

  const ActiveAssignmentsFolderCard({
    super.key,
    required this.inspectionId,
    required this.referenceNo,
    required this.date,
    required this.location,
    required this.applicantName,
    required this.applicationType,
    required this.status,
    required this.onTap,
  });

  @override
  State<ActiveAssignmentsFolderCard> createState() =>
      _ActiveAssignmentsFolderCardState();
}

class _ActiveAssignmentsFolderCardState
    extends State<ActiveAssignmentsFolderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 0.962, end: 1.0).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _pressCtrl.reverse();
  void _onTapUp(TapUpDetails _)   => _pressCtrl.forward();
  void _onTapCancel()              => _pressCtrl.forward();

  @override
  Widget build(BuildContext context) {
    final accent   = _FolderAccent.tone(widget.status);
    final tint   = _FolderAccent.tintOf(widget.status);
    final ink    = _FolderAccent.inkOf(widget.status);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          // Light iMAPS card language: white surface, hairline border,
          // canonical soft shadow - same recipe as the dashboard group cards.
          decoration: BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: BorderRadius.circular(InsightTheme.radiusLg),
            border: Border.all(color: InsightTheme.line, width: 1.2),
            boxShadow: kCardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(InsightTheme.radiusLg),
            child: Stack(
              children: [

                // ── Layer 2: Document sheets fanning from top ───────────────
                Positioned(
                  top: 16, left: 0, right: 0,
                  child: _DocumentSheetRow(accent: accent),
                ),

                // ── Layer 3 + 4 + 5: Glossy pocket + shine + content ───────
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _GlossyPocket(
                    accent: accent,
                    location: widget.location,
                    applicantName: widget.applicantName,
                    applicationType: widget.applicationType,
                    referenceNo: widget.referenceNo,
                    inspectionId: widget.inspectionId,
                    date: widget.date,
                    status: widget.status,
                  ),
                ),

                // ── Layer 6: Status badge ───────────────────────────────────
                Positioned(
                  top: 14, right: 14,
                  child: _StatusBadge(status: widget.status, tint: tint, ink: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Sheets — fan of 3 papers peeking from top of folder
// ─────────────────────────────────────────────────────────────────────────────
class _DocumentSheetRow extends StatelessWidget {
  final Color accent;
  const _DocumentSheetRow({required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 46, bottom: 0,
            child: _Sheet(angle: -0.09, width: 86, height: 66,
                accent: accent, lineWidths: [38, 55, 30]),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Center(
              child: _Sheet(angle: 0.0, width: 98, height: 78,
                  accent: accent, lineWidths: [50, 66, 44, 58]),
            ),
          ),
          Positioned(
            right: 46, bottom: 0,
            child: _Sheet(angle: 0.09, width: 84, height: 62,
                accent: accent, lineWidths: [34, 52, 28]),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final double angle;
  final double width;
  final double height;
  final Color accent;
  final List<double> lineWidths;

  const _Sheet({
    required this.angle,
    required this.width,
    required this.height,
    required this.accent,
    required this.lineWidths,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: InsightTheme.line),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Glossy coloured header bar
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lineWidths.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Container(
                    height: 3.5,
                    width: lineWidths[i],
                    decoration: BoxDecoration(
                      color: i == 0
                          ? accent.withValues(alpha: 0.35)
                          : InsightTheme.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glossy Pocket — main content area with asymmetric folder tab
// ─────────────────────────────────────────────────────────────────────────────
class _GlossyPocket extends StatelessWidget {
  final Color accent;
  final String location;
  final String applicantName;
  final String applicationType;
  final String referenceNo;
  final String inspectionId;
  final String date;
  final String status;

  const _GlossyPocket({
    required this.accent,
    required this.location,
    required this.applicantName,
    required this.applicationType,
    required this.referenceNo,
    required this.inspectionId,
    required this.date,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _PocketClipper(),
      child: Container(
        height: 154,
        // Pocket is tone-on-tone with the page background so the folder
        // reads as paper in a light folder, not a glossy dark shell.
        decoration: const BoxDecoration(
          color: InsightTheme.surface2,
        ),
        child: Stack(
          children: [

            // Hairline divider along the pocket top edge
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(height: 1, color: InsightTheme.line),
            ),

            // ── Content ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Brand row — iMAPS FieldSync
                  Row(
                    children: [
                      // Mini logo mark
                      Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: InsightTheme.blueTint,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: InsightTheme.blue1.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Icon(
                          Icons.map_outlined,
                          size: 11,
                          color: InsightTheme.blueInk,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'iMAPS FieldSync',
                        style: InsightTheme.jetBrains(9.5, w: FontWeight.w700, c: InsightTheme.ink3, ls: 0.8),
                      ),
                      const Spacer(),
                      // Date pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: InsightTheme.line),
                        ),
                        child: Text(
                          date,
                          style: InsightTheme.jetBrains(9.5, w: FontWeight.w600, c: InsightTheme.ink2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),

                  // Location — main title
                  Text(
                    location,
                    style: InsightTheme.poppins(18, w: FontWeight.w800, c: InsightTheme.ink, ls: -0.4, h: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    applicantName,
                    style: InsightTheme.inter(11.5, w: FontWeight.w400, c: InsightTheme.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(),

                  // Bottom meta row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              referenceNo,
                              style: InsightTheme.jetBrains(12.5, w: FontWeight.w700, c: InsightTheme.ink, ls: 0.4),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $inspectionId  ·  $applicationType',
                              style: InsightTheme.inter(9.5, w: FontWeight.w400, c: InsightTheme.ink3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Glossy action button
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: InsightTheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: InsightTheme.line),
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: accent,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Badge — top-right pill
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final Color tint; // canonical status tint (e.g. InsightTheme.blueTint)
  final Color ink;  // matching deep ink variant for text and dot
  const _StatusBadge({required this.status, required this.tint, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ink.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: ink, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: InsightTheme.jetBrains(9, w: FontWeight.w700, c: ink, ls: 0.8),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomClipper — asymmetric folder-tab top edge for the pocket
// ─────────────────────────────────────────────────────────────────────────────
class _PocketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path();
    // Left tab: high (y=0)
    p.moveTo(0, 24);
    p.quadraticBezierTo(0, 0, 24, 0);
    p.lineTo(size.width * 0.42, 0);
    // Smooth Bezier drop to lower ledge
    p.quadraticBezierTo(size.width * 0.50, 0, size.width * 0.56, 22);
    // Lower ledge
    p.lineTo(size.width - 24, 22);
    p.quadraticBezierTo(size.width, 22, size.width, 42);
    p.lineTo(size.width, size.height);
    p.lineTo(0, size.height);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
