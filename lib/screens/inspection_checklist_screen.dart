import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'field_findings_screen.dart';
import 'tasks_screen.dart';
import 'inspection_progress.dart';
import 'package:provider/provider.dart';
import '../providers/inspection_provider.dart';
import '../services/supabase_service.dart';
import '../services/sync_outbox_service.dart';
import '../widgets/exit_confirm_dialog.dart';

class InsightTheme {
  static const Color bg = Color(0xFFF2F4FB);
  static const Color surface = Colors.white;
  static const Color surface2 = Color(0xFFEEF1FC);
  static const Color ink = Color(0xFF12141F);
  static const Color ink2 = Color(0xFF666C82);
  static const Color ink3 = Color(0xFFA2A7BC);
  static const Color blue1 = Color(0xFF3D6BFF);
  static const Color blue2 = Color(0xFF0B2FBF);
  static const Color blueInk = Color(0xFF1A3FC4);
  static const Color line = Color(0x1A141628); 
  static const Color lineStrong = Color(0x2A141628); 
  
  static TextStyle poppins(double size, {FontWeight w = FontWeight.w600, Color? c, double? h, double? ls}) => GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c ?? ink, height: h ?? 1.2, letterSpacing: ls);
  static TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color? c, double? h, double? ls}) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? ink2, height: h ?? 1.5, letterSpacing: ls);
  static TextStyle jetBrains(double size, {FontWeight w = FontWeight.w500, Color? c, double? ls}) => GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c ?? ink3, letterSpacing: ls);
}

class InspectionChecklistScreen extends StatefulWidget {
  final TaskItem task;
  final List<Map<String, dynamic>> capturedPhotos;
  const InspectionChecklistScreen({super.key, required this.task, this.capturedPhotos = const []});
  @override
  State<InspectionChecklistScreen> createState() => _InspectionChecklistScreenState();
}

class _InspectionChecklistScreenState extends State<InspectionChecklistScreen> {
  // BUG FIX #4C — Summary Sync Lock / Form Update Mismatch.
  // These used to be hardcoded defaults that ignored whatever real state
  // InspectionProvider already had (loaded via startInspection's local
  // draft recovery, or hydrateForRework for a reopened job). That's why the
  // screen always rendered the same "3/5" regardless of what was actually
  // saved, and why edits made here didn't stick. Now they're seeded from
  // the provider on first frame.
  final Map<String, bool> _siteCondition = {'Structure matches declared use': true, 'Setback distances compliant': true};
  bool _isSaving = false;
  final Map<String, bool> _zoningObservations = {'Accessibility & road frontage': true, 'Surrounding developments noted': false, 'Signage / commercial activity present': false};

  int get _doneCount => _siteCondition.values.where((v) => v).length + _zoningObservations.values.where((v) => v).length;
  int get _totalCount => _siteCondition.length + _zoningObservations.length;

  @override
  void initState() {
    super.initState();
    final provider = context.read<InspectionProvider>();
    _siteCondition
      ..clear()
      ..addAll(provider.siteCondition);
    _zoningObservations
      ..clear()
      ..addAll(provider.zoningObservations);
  }

  // Guards against a burst of rapid taps piling up out-of-order requests —
  // only the latest call's result matters, so we don't need to await/queue
  // each one, just make sure an older response can't clobber the DB after
  // a newer one already landed.
  int _syncSeq = 0;

  /// Pushes the checklist as it stands right now to `field_jobs`, using the
  /// same {'item','checked'} shape the final submit writes — so if the app
  /// dies before Step 6, the ticks the inspector already made aren't lost,
  /// and reopening this job for rework picks up mid-checklist state too.
  /// This was `updateJobInspectionProgress()`'s original intended purpose;
  /// it previously had zero callers.
  Future<void> _syncChecklistProgress() async {
    final mySeq = ++_syncSeq;
    final checklist = [
      ..._siteCondition.entries.map((e) => {'item': e.key, 'checked': e.value}),
      ..._zoningObservations.entries.map((e) => {'item': e.key, 'checked': e.value}),
    ];
    try {
      await SupabaseService.updateJobInspectionProgress(
        jobId: widget.task.id,
        updateData: {
          'checklist_data': checklist,
          'checklist_completed_count': _doneCount,
          'checklist_total_count': _totalCount,
        },
      );
    } catch (_) {
      // Ignore stale results from superseded calls — a newer toggle
      // already fired after this one.
      if (mySeq != _syncSeq) return;
      // Couldn't reach Supabase (e.g. offline) — queue it instead of just
      // dropping the update. enqueueChecklistUpdate reuses one row per
      // job, so repeated offline taps don't pile up duplicate queued
      // rows — only the latest checklist state is kept. Step 6 submit
      // still carries the authoritative checklist either way, so a
      // failure here (queue included) never actually loses data.
      try {
        await SyncOutboxService.enqueueChecklistUpdate(
          jobId: widget.task.id,
          checklistData: checklist,
          checklistCompletedCount: _doneCount,
          checklistTotalCount: _totalCount,
        );
      } catch (_) {
        // Nothing more we can do — safe to ignore, see comment above.
      }
    }
  }

  void _continueToFindings() {
    InspectionProgress.instance.markStepComplete(4);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FieldFindingsScreen(task: widget.task, capturedPhotos: widget.capturedPhotos, checklistDone: _doneCount, checklistTotal: _totalCount)));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return PopScope(
      canPop: InspectionProgress.instance.currentStep > 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Already popped natively (smooth swipe/hardware-back animation) —
          // fire the save in the background, nothing to block on here.
          context.read<InspectionProvider>().saveStepChecklist();
          return;
        }
        handleInspectionExit(
          context,
          onSaveProgress: () => context.read<InspectionProvider>().saveStepChecklist(),
        );
      },
      child: Scaffold(
      backgroundColor: InsightTheme.bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -60, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.20))))),
          Positioned(bottom: -80, left: -80, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withValues(alpha: 0.10))))),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => handleInspectionExit(
                        context,
                        onSaveProgress: () => context.read<InspectionProvider>().saveStepChecklist(),
                      )),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Zoning Checklist', style: InsightTheme.poppins(17, w: FontWeight.w700)),
                            Text(widget.task.location, style: InsightTheme.inter(12, c: InsightTheme.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6, decoration: BoxDecoration(color: InsightTheme.surface2, borderRadius: BorderRadius.circular(4)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft, widthFactor: 4/6,
                          child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]), borderRadius: BorderRadius.circular(4))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('STEP 4 OF 6', style: InsightTheme.jetBrains(10, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.5)),
                          Text(' — VERIFY COMPLIANCE', style: InsightTheme.jetBrains(10, c: InsightTheme.ink3, ls: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _SectionLabel(title: 'SITE CONDITION'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: Column(
                          children: _siteCondition.entries.toList().asMap().entries.map((entry) {
                            var e = entry.value;
                            return _ChecklistItem(title: e.key, isChecked: e.value, isLast: entry.key == _siteCondition.length - 1, onTap: () {
                              setState(() => _siteCondition[e.key] = !e.value);
                              context.read<InspectionProvider>().setSiteCondition(e.key, !e.value);
                              _syncChecklistProgress();
                            });
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _SectionLabel(title: 'ZONING OBSERVATIONS'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]),
                        child: Column(
                          children: _zoningObservations.entries.toList().asMap().entries.map((entry) {
                            var e = entry.value;
                            return _ChecklistItem(title: e.key, isChecked: e.value, isLast: entry.key == _zoningObservations.length - 1, onTap: () {
                              setState(() => _zoningObservations[e.key] = !e.value);
                              context.read<InspectionProvider>().setZoningObservation(e.key, !e.value);
                              _syncChecklistProgress();
                            });
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Row(
                    children: [
                      if (context.watch<InspectionProvider>().isReworkMode) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : () async {
                              setState(() => _isSaving = true);
                              final ok = await context.read<InspectionProvider>().saveStepChecklist();
                              if (mounted) {
                                setState(() => _isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Checklist saved.' : 'Save failed.')));
                              }
                            },
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: _isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('Save', style: InsightTheme.poppins(15, w: FontWeight.w600, c: InsightTheme.blue1)),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _continueToFindings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ).copyWith(elevation: WidgetStateProperty.all(0)),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: InsightTheme.blue1.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8))],
                            ),
                            child: Container(
                              alignment: Alignment.center, constraints: const BoxConstraints(minHeight: 52),
                              child: Text('Continue to Findings', style: InsightTheme.poppins(15, w: FontWeight.w600, c: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 10, height: 2, decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 8),
        Text(title, style: InsightTheme.jetBrains(11, w: FontWeight.w500, ls: 1.2)),
      ],
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String title; final bool isChecked; final bool isLast; final VoidCallback onTap;
  const _ChecklistItem({required this.title, required this.isChecked, required this.isLast, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      borderRadius: BorderRadius.vertical(top: isLast ? Radius.zero : const Radius.circular(20), bottom: isLast ? const Radius.circular(20) : Radius.zero),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: InsightTheme.line))),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24, height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: isChecked ? const LinearGradient(colors: [InsightTheme.blue1, InsightTheme.blue2]) : null, color: isChecked ? null : Colors.transparent, border: isChecked ? null : Border.all(color: InsightTheme.lineStrong, width: 2)),
              child: isChecked ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: InsightTheme.inter(14, w: FontWeight.w500, c: InsightTheme.ink))),
          ],
        ),
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.65)), boxShadow: const [BoxShadow(color: Color(0x0F141628), blurRadius: 10, offset: Offset(0, 4))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: const Center(child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: InsightTheme.ink))))),
      ),
    );
  }
}