import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// iMAPS FieldSync • Active Assignments — Premium Glossy Folder Card
//
// Stack architecture:
//   Layer 0 — Deep Navy gradient folder back  (outer squircle shell)
//   Layer 1 — Specular gloss highlight strip across the top-left of back
//   Layer 2 — Document sheets fanning out from inside the folder
//   Layer 3 — Glossy front pocket (ClipPath with asymmetric folder tab)
//   Layer 4 — Radial shine overlay on pocket surface
//   Layer 5 — Content: iMAPS FieldSync brand + assignment data
//   Layer 6 — Status tab badge (top-right)
// ─────────────────────────────────────────────────────────────────────────────

class _FolderAccent {
  static Color forStatus(String status) {
    switch (status) {
      case 'Ongoing':   return const Color(0xFF60A5FA); // electric blue
      case 'Scheduled': return const Color(0xFFA78BFA); // violet
      case 'Completed': return const Color(0xFF34D399); // emerald
      default:          return const Color(0xFFFBBF24); // amber — Pending
    }
  }

  static List<Color> gradientForStatus(String status) {
    switch (status) {
      case 'Ongoing':
        return [const Color(0xFF1E40AF), const Color(0xFF3B82F6)];
      case 'Scheduled':
        return [const Color(0xFF4C1D95), const Color(0xFF7C3AED)];
      case 'Completed':
        return [const Color(0xFF065F46), const Color(0xFF10B981)];
      default: // Pending
        return [const Color(0xFF92400E), const Color(0xFFF59E0B)];
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
    final accent   = _FolderAccent.forStatus(widget.status);
    final gradient = _FolderAccent.gradientForStatus(widget.status);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          // ── Layer 0: Deep Navy gradient folder back ───────────────────────
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1929), Color(0xFF0E2240), Color(0xFF091525)],
              stops: [0.0, 0.55, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                // ── Layer 1: Diagonal grain texture ────────────────────────
                Positioned.fill(
                  child: CustomPaint(painter: _GrainPainter()),
                ),

                // ── Layer 1b: Specular top-left gloss highlight ─────────────
                Positioned(
                  top: -40, left: -30,
                  child: Container(
                    width: 180, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.07),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Layer 2: Document sheets fanning from top ───────────────
                Positioned(
                  top: 16, left: 0, right: 0,
                  child: _DocumentSheetRow(accent: accent, gradient: gradient),
                ),

                // ── Layer 3 + 4 + 5: Glossy pocket + shine + content ───────
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: _GlossyPocket(
                    accent: accent,
                    gradient: gradient,
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
                  child: _StatusBadge(status: widget.status, accent: accent),
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
  final List<Color> gradient;
  const _DocumentSheetRow({required this.accent, required this.gradient});

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
                accent: accent, gradient: gradient, lineWidths: [38, 55, 30]),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Center(
              child: _Sheet(angle: 0.0, width: 98, height: 78,
                  accent: accent, gradient: gradient, lineWidths: [50, 66, 44, 58]),
            ),
          ),
          Positioned(
            right: 46, bottom: 0,
            child: _Sheet(angle: 0.09, width: 84, height: 62,
                accent: accent, gradient: gradient, lineWidths: [34, 52, 28]),
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
  final List<Color> gradient;
  final List<double> lineWidths;

  const _Sheet({
    required this.angle,
    required this.width,
    required this.height,
    required this.accent,
    required this.gradient,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Glossy coloured header bar
            Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
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
                          : const Color(0xFFCBD5E1).withValues(alpha: 0.70),
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
  final List<Color> gradient;
  final String location;
  final String applicantName;
  final String applicationType;
  final String referenceNo;
  final String inspectionId;
  final String date;
  final String status;

  const _GlossyPocket({
    required this.accent,
    required this.gradient,
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradient[0].withValues(alpha: 0.96),
              gradient[1].withValues(alpha: 0.88),
              const Color(0xFF071120),
            ],
            stops: const [0.0, 0.60, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Radial gloss orb (top-left of pocket) ──────────────────────
            Positioned(
              top: -20, left: 0,
              child: Container(
                width: 160, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Gloss rim line at pocket top ────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.40),
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
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
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.30),
                              Colors.white.withValues(alpha: 0.10),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          Icons.map_outlined,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'iMAPS FieldSync',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.70),
                          letterSpacing: 0.4,
                        ),
                      ),
                      const Spacer(),
                      // Date pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          date,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.80),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),

                  // Location — main title
                  Text(
                    location,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    applicantName,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
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
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $inspectionId  ·  $applicationType',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
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
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.22),
                              Colors.white.withValues(alpha: 0.08),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
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
  final Color accent;
  const _StatusBadge({required this.status, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.25),
            accent.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.60),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: GoogleFonts.ibmPlexMono(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.8,
            ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Diagonal linen grain texture for the folder back
// ─────────────────────────────────────────────────────────────────────────────
class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.028)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (double i = -size.height; i < size.width + size.height; i += 24) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height * math.tan(math.pi / 4), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
