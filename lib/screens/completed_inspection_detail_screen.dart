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

class _CompletedInspectionDetailScreenState extends State<CompletedInspectionDetailScreen> {
  TaskItem? _fullTask;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFullDetail();
  }

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
        backgroundColor: InsightTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rework this step?', style: InsightTheme.poppins(18, w: FontWeight.w600)),
        content: Text(
          'Only "${InspectionProgress.stepTitles[step - 1]}" needs to be '
          'redone. The rest of the submitted inspection stays as-is until '
          'you resubmit.',
          style: InsightTheme.inter(14, c: InsightTheme.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink3)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: InsightTheme.blue1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Rework', style: InsightTheme.inter(14, w: FontWeight.w600, c: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();

    try {
      await SupabaseService.reopenForRework(jobId: task.id, locationLabel: task.location);
      
      // FIXED: Moved mounted check above the context usage across the async gap
      if (!mounted) return;
      
      context.read<InspectionProvider>().hydrateForRework(task);
      InspectionProgress.instance.unlockAllForReview(task.id, label: task.location);

      _navigateToStep(step, task);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reopen: $e')));
    }
  }

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
        backgroundColor: InsightTheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: InsightTheme.ink),
        title: Text('Inspection Summary', style: InsightTheme.poppins(16, w: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: InsightTheme.line, height: 1.0),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: InsightTheme.blue1))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: InsightTheme.inter(14, c: InsightTheme.ink2)),
                  ),
                )
              : _buildBody(_fullTask!),
    );
  }

  Widget _buildBody(TaskItem task) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildHeaderCard(task),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('INSPECTION DATA', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.2)),
        ),
        _CollapsibleStepCard(
          step: 1,
          title: 'Site Verification',
          icon: Icons.location_on_outlined,
          onRework: () => _reworkStep(1),
          content: _buildDetailRows({
            'Land use class': task.landUseClass,
            'Lot area (sqm)': task.lotAreaSqm?.toStringAsFixed(2) ?? '—',
            'Property index no.': task.propertyIndexNumber ?? '—',
          }),
        ),
        _CollapsibleStepCard(
          step: 2,
          title: 'GPS Verification',
          icon: Icons.satellite_alt_outlined,
          onRework: () => _reworkStep(2),
          content: _buildDetailRows({
            'Confirmed latitude': task.confirmedLatitude?.toStringAsFixed(6) ?? '—',
            'Confirmed longitude': task.confirmedLongitude?.toStringAsFixed(6) ?? '—',
            'Accuracy (m)': task.gpsAccuracyM?.toStringAsFixed(1) ?? '—',
            'Confirmed at': task.gpsConfirmedAt ?? '—',
          }),
        ),
        _CollapsibleStepCard(
          step: 3,
          title: 'Photographic Evidence',
          icon: Icons.camera_alt_outlined,
          onRework: () => _reworkStep(3),
          content: _buildPhotoGrid(task),
        ),
        _CollapsibleStepCard(
          step: 4,
          title: 'Checklist',
          icon: Icons.checklist_rtl_rounded,
          onRework: () => _reworkStep(4),
          content: _buildDetailRows({
            'Completed': '${task.checklistCompletedCount} of ${task.checklistTotalCount} verified',
          }),
        ),
        _CollapsibleStepCard(
          step: 5,
          title: 'Field Findings',
          icon: Icons.edit_document,
          onRework: () => _reworkStep(5),
          content: _buildDetailRows({
            'Observations': task.observations?.isNotEmpty == true ? task.observations! : 'None recorded',
            'Discrepancies': task.discrepancies?.isNotEmpty == true ? task.discrepancies! : 'None recorded',
            'Recommendations': task.recommendations?.isNotEmpty == true ? task.recommendations! : 'None recorded',
            'Inspector notes': task.inspectorNotes?.isNotEmpty == true ? task.inspectorNotes! : 'None recorded',
          }),
        ),
        _CollapsibleStepCard(
          step: 6,
          title: 'Review & Submit',
          icon: Icons.verified_outlined,
          onRework: () => _reworkStep(6),
          content: _buildDetailRows({
            'Result': task.inspectionResult ?? '—',
            'Compliant': task.isCompliant == null ? '—' : (task.isCompliant! ? 'Yes' : 'No (Discrepancy Found)'),
            'Submitted at': task.submittedAt ?? '—',
          }),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(TaskItem task) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: InsightTheme.greenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded, color: InsightTheme.green, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.inspectionNo,
                  style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink3),
                ),
                const SizedBox(height: 2),
                Text(
                  task.location,
                  style: InsightTheme.poppins(15, w: FontWeight.w600, c: InsightTheme.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  task.name,
                  style: InsightTheme.inter(13, c: InsightTheme.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRows(Map<String, String> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.key.toUpperCase(), style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.ink3, ls: 0.5)),
              const SizedBox(height: 4),
              Text(e.value, style: InsightTheme.inter(13, w: FontWeight.w500, c: InsightTheme.ink)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotoGrid(TaskItem task) {
    if (task.photoPaths.isEmpty) {
      return Text('No photos attached to this report.', style: InsightTheme.inter(13, c: InsightTheme.ink2));
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: task.photoPaths.length,
        // FIXED: Added identifiers context and index
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            task.photoPaths[i],
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            // FIXED: Added identifiers context, error, and stackTrace
            errorBuilder: (context, error, stackTrace) => Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: InsightTheme.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: InsightTheme.line),
              ),
              child: const Icon(Icons.broken_image_outlined, size: 24, color: InsightTheme.ink3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A collapsible card mimicking the _CompactTaskCard from tasks_screen.dart
class _CollapsibleStepCard extends StatefulWidget {
  final int step;
  final String title;
  final IconData icon;
  final Widget content;
  final VoidCallback onRework;

  const _CollapsibleStepCard({
    required this.step,
    required this.title,
    required this.icon,
    required this.content,
    required this.onRework,
  });

  @override
  State<_CollapsibleStepCard> createState() => _CollapsibleStepCardState();
}

class _CollapsibleStepCardState extends State<_CollapsibleStepCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: InsightTheme.line),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () {
                setState(() => _isExpanded = !_isExpanded);
                HapticFeedback.selectionClick();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: InsightTheme.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: InsightTheme.line),
                      ),
                      child: Center(
                        child: Text('${widget.step}', style: InsightTheme.inter(11, w: FontWeight.w700, c: InsightTheme.ink)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: InsightTheme.inter(14, w: FontWeight.w600, c: InsightTheme.ink),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: InsightTheme.ink3,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              Container(color: InsightTheme.line, height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.content,
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: widget.onRework,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: InsightTheme.blueTint,
                          // FIXED: Replaced 😎 with 8)
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: InsightTheme.blue1.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.refresh_rounded, color: InsightTheme.blue2, size: 16),
                            // FIXED: Replaced 😎 with 8)
                            const SizedBox(width: 8),
                            Text('Rework this step', style: InsightTheme.inter(12, w: FontWeight.w600, c: InsightTheme.blue2)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}