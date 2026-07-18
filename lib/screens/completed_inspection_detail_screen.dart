import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'tasks_screen.dart'; // TaskItem, InsightTheme
import '../services/supabase_service.dart';
import '../providers/inspection_provider.dart';
import 'inspection_progress.dart';

import 'parcel_detail_screen.dart' hide InsightTheme;
import 'gps_verification_screen.dart' hide InsightTheme;
import 'inspection_checklist_screen.dart' hide InsightTheme;
import 'capture_photo_screen.dart' hide InsightTheme;
import 'field_findings_screen.dart' hide InsightTheme;
import 'review_submit_screen.dart' hide InsightTheme;
class CompletedInspectionDetailScreen extends StatefulWidget {
  final TaskItem task;
  const CompletedInspectionDetailScreen({super.key, required this.task});

  @override
  State<CompletedInspectionDetailScreen> createState() =>
      _CompletedInspectionDetailScreenState();
}

class _CompletedInspectionDetailScreenState
    extends State<CompletedInspectionDetailScreen> {
  TaskItem? _fullTask;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFullDetail();
  }

  // The task passed in comes from the Tasks list (fetchMyJobs), which
  // doesn't select findings/observations/checklist_data/photo_paths/GPS
  // fields. Re-fetch the full row before showing anything.
  Future<void> _loadFullDetail() async {
    try {
      final job = await SupabaseService.fetchJobDetail(widget.task.id);
      if (job == null) {
        setState(() {
          _error = 'Could not load this inspection.';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _fullTask = TaskItem.fromJob(job);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _reworkStep(int step) async {
    final task = _fullTask;
    if (task == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rework this step?'),
        content: Text(
          'Only "${InspectionProgress.stepTitles[step - 1]}" needs to be '
          'redone. The rest of the submitted inspection stays as-is until '
          'you resubmit.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rework')),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();

    try {
      // 1. Flip status back to in_progress — keeps existing submitted data.
      await SupabaseService.reopenForRework(jobId: task.id, locationLabel: task.location);

      // 2. Load real submitted data into the provider (not blanks).
      context.read<InspectionProvider>().hydrateForRework(task);

      // 3. Unlock every step, keyed by task.id — not inspectionNo, since
      //    two jobs can share a reference_number (see notes above).
      InspectionProgress.instance.unlockAllForReview(task.id, label: task.location);

      if (!mounted) return;
      _navigateToStep(step, task);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not reopen: $e')));
    }
  }

  // ⚠️ I don't have the source for the individual step screens
  // (GPS verification, capture photo, checklist, findings, review/submit)
  // or ParcelDetailScreen, so I can't safely fill in real class names and
  // constructors here — guessing would break the build. Placeholder below;
  // swap in the real screens. Important: whichever screen you land on must
  // NOT call `startInspection()`, since that resets everything
  // `hydrateForRework()` just loaded.
  void _navigateToStep(int step, TaskItem task) {
    final Widget target;
    switch (step) {
      case 1:
        target = ParcelDetailScreen(task: task);
        break;
      case 2:
        target = GpsVerificationScreen(task: task);
        break;
      case 3:
        target = CapturePhotoScreen(task: task);
      break;
    case 4:
      target = InspectionChecklistScreen(task: task);
      break;
    case 5:
      target = FieldFindingsScreen(task: task);
      break;
    default:
      target = ReviewSubmitScreen(task: task);
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => target));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      appBar: AppBar(
        backgroundColor: InsightTheme.bg,
        elevation: 0,
        title: Text('Inspection summary', style: InsightTheme.poppins(16)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                )
              : _buildBody(_fullTask!),
    );
  }

  Widget _buildBody(TaskItem task) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _headerCard(task),
        const SizedBox(height: 20),
        _stepSection(
          step: 1,
          title: 'Site verification',
          rows: {
            'Land use class': task.landUseClass,
            'Lot area (sqm)': task.lotAreaSqm?.toStringAsFixed(2) ?? '—',
            'Property index no.': task.propertyIndexNumber ?? '—',
          },
        ),
        _stepSection(
          step: 2,
          title: 'GPS verification',
          rows: {
            'Confirmed latitude': task.confirmedLatitude?.toStringAsFixed(6) ?? '—',
            'Confirmed longitude': task.confirmedLongitude?.toStringAsFixed(6) ?? '—',
            'Accuracy (m)': task.gpsAccuracyM?.toStringAsFixed(1) ?? '—',
            'Confirmed at': task.gpsConfirmedAt ?? '—',
          },
        ),
        _photoStepSection(task),
        _stepSection(
          step: 4,
          title: 'Checklist',
          rows: {
            'Completed': '${task.checklistCompletedCount} of ${task.checklistTotalCount}',
          },
        ),
        _stepSection(
          step: 5,
          title: 'Findings',
          rows: {
            'Observations': task.observations ?? '—',
            'Discrepancies': task.discrepancies ?? '—',
            'Recommendations': task.recommendations ?? '—',
            'Inspector notes': task.inspectorNotes ?? '—',
          },
        ),
        _stepSection(
          step: 6,
          title: 'Review & submit',
          rows: {
            'Result': task.inspectionResult ?? '—',
            'Compliant': task.isCompliant == null
                ? '—'
                : (task.isCompliant! ? 'Yes' : 'No'),
            'Submitted at': task.submittedAt ?? '—',
          },
        ),
      ],
    );
  }

  Widget _headerCard(TaskItem task) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.location, style: InsightTheme.poppins(16)),
            const SizedBox(height: 4),
            Text(task.inspectionNo, style: InsightTheme.inter(12)),
          ],
        ),
      );

  Widget _photoStepSection(TaskItem task) => _sectionShell(
        step: 3,
        title: 'Photos',
        child: task.photoPaths.isEmpty
            ? Text('No photos on file.', style: InsightTheme.inter(13))
            : SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: task.photoPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  // photo_paths may be remote URLs OR leftover local device
                  // paths depending on which submit path wrote them (see
                  // note above about submitInspection vs syncToServer) —
                  // errorBuilder covers the case Image.network can't load it.
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      task.photoPaths[i],
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: InsightTheme.surface2,
                        child: const Icon(Icons.broken_image_outlined, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
      );

  Widget _stepSection({
    required int step,
    required String title,
    required Map<String, String> rows,
  }) =>
      _sectionShell(
        step: step,
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows.entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: '${e.key}: ',
                          style: InsightTheme.inter(13,
                              w: FontWeight.w600, c: InsightTheme.ink),
                        ),
                        TextSpan(text: e.value, style: InsightTheme.inter(13)),
                      ]),
                    ),
                  ))
              .toList(),
        ),
      );

  Widget _sectionShell({required int step, required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: InsightTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: InsightTheme.poppins(14)),
              TextButton.icon(
                onPressed: () => _reworkStep(step),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Rework this step'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}