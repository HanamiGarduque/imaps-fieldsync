import 'package:flutter/material.dart';

import '../../core/models/user_profile.dart';
import '../../core/models/task_submission.dart';
import '../../core/navigation/parcel_detail_screen.dart';
import '../../core/services/db_helper.dart';
import '../../core/widgets/insight_bottom_nav.dart';
import '../../core/widgets/sensitive_screen.dart';
import '../../core/widgets/imaps_loading_indicator.dart';
import '../analytics_dashboard/screens/home_dashboard_screen.dart';
import '../tasks/screens/tasks_screen.dart';
import '../offline_sync/screens/updates_screen.dart';
import '../profile_settings/screens/profile_screen.dart';
import '../inspection/screens/completed_inspection_detail_screen.dart';
import '../inspection/screens/site_map_screen.dart';
import '../inspection/screens/gps_verification_screen.dart';
import '../inspection/screens/capture_photo_screen.dart';
import '../inspection/screens/inspection_checklist_screen.dart';
import '../inspection/screens/field_findings_screen.dart';
import '../inspection/screens/review_submit_screen.dart';
import 'guide_coordinator.dart';
import 'guide_overlay.dart';
import 'guide_preferences.dart';
import 'guide_data_loader.dart';
import 'guide_read_only_data.dart';
import 'guide_examples.dart';
import 'guide_script.dart';
import 'guide_targets.dart';

class GuideReplayRequest {
  const GuideReplayRequest(this.language);
  final GuideLanguage language;
}

/// Actual screens with passive display inputs. The original shell remains
/// mounted, with its own target registry, work, filters and navigation intact.
class GuideHost extends StatefulWidget {
  const GuideHost({
    super.key,
    required this.coordinator,
    required this.child,
    required this.profile,
    this.preferredTaskId,
  });
  final GuideCoordinator coordinator;
  final Widget child;
  final UserProfile profile;
  final String? preferredTaskId;

  @override
  State<GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends State<GuideHost> {
  final _liveTargets = GuideTargetRegistry();
  final _walkthroughTargets = GuideTargetRegistry();
  GuideReadOnlyData? _data;
  int _epoch = 0;
  bool _loading = false;
  EdgeInsets _viewportInsets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onGuideChanged);
    _onGuideChanged();
  }

  void _onGuideChanged() {
    final guide = widget.coordinator;
    if (guide.phase != GuidePhase.active) {
      _epoch++;
      _data = null;
      _loading = false;
      _viewportInsets = EdgeInsets.zero;
      return;
    }
    if (_data != null || _loading) return;
    _loading = true;
    final epoch = ++_epoch;
    final owner = guide.inspectorId;
    loadGuideReadOnlyData(
      ownerId: owner,
      language: guide.language,
      preferredTaskId: widget.preferredTaskId,
    ).then(
      (data) {
        if (!mounted ||
            epoch != _epoch ||
            guide.phase != GuidePhase.active ||
            owner != widget.profile.id ||
            owner != DBHelper.currentInspectorId) {
          return;
        }
        setState(() {
          _data = data;
          _loading = false;
        });
      },
      onError: (Object error) {
        if (!mounted || epoch != _epoch || guide.phase != GuidePhase.active) {
          return;
        }
        if (DBHelper.currentInspectorId != owner) {
          guide.invalidate();
          return;
        }
        setState(() {
          _loading = false;
          _data = GuideReadOnlyData(
            ownerId: owner,
            language: guide.language,
            unavailable: GuideDataSection.values.toSet(),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.coordinator,
    child: GuideTargetScope(registry: _liveTargets, child: widget.child),
    builder: (context, realShell) {
      final guide = widget.coordinator;
      final stop = guideStops[guide.stopIndex];
      final active = guide.phase == GuidePhase.active;
      return SensitiveScreen(
        child: GuideOverlay(
          coordinator: guide,
          targets: active ? _walkthroughTargets : _liveTargets,
          onOpenTask: guide.next,
          onViewportInsetsChanged: (insets) {
            if (!mounted || _viewportInsets == insets) return;
            setState(() => _viewportInsets = insets);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: active,
                child: SensitiveScreenVisibility(
                  visible: !active,
                  child: realShell!,
                ),
              ),
              if (active)
                Navigator(
                  pages: [
                    MaterialPage<void>(
                      key: const ValueKey('guide-active-route'),
                      child: _actualPage(stop),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _actualPage(GuideStop stop) {
    final index = switch (stop.page) {
      GuidePage.tasks || GuidePage.overview => 1,
      GuidePage.sync => 2,
      GuidePage.profile => 3,
      _ => 0,
    };
    return GuideTargetScope(
      registry: _walkthroughTargets,
      child: Scaffold(
        extendBody: true,
        body: Padding(
          padding: _viewportInsets,
          child: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: _viewportInsets.bottom > 0
                        ? 12
                        : kInsightBottomNavRailReserve +
                              media.viewPadding.bottom +
                              12,
                  ),
                ),
                child: KeyedSubtree(
                  key: const ValueKey('guide-active-page'),
                  child: _data == null
                      ? const Center(child: ImapsLoadingIndicator())
                      : _screen(stop, _data!),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: InsightBottomNav(
          currentIndex: index,
          onTap: (_) {},
          // The fingerprint stays the guide's voice; normal Quick Actions is
          // still owned by the retained real shell, not this passive page.
          isQuickActionsOpen: false,
          onQuickActionsTap: () {},
          items: const [
            InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
            InsightNavItem(icon: Icons.assignment_outlined, label: 'Tasks'),
            InsightNavItem(icon: Icons.sync_rounded, label: 'Sync'),
            InsightNavItem(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _screen(GuideStop stop, GuideReadOnlyData data) {
    var task = data.selectedJob == null
        ? TaskItem(
            id: '',
            name: data.canShowTaskExample
                ? guideExample.applicant
                : 'Saved task unavailable',
            location: data.canShowTaskExample
                ? guideExample.location
                : 'Saved site unavailable',
            parcels: '',
            status: 'assigned',
            inspectionNo: data.canShowTaskExample
                ? guideExample.reference
                : '—',
            isSelfScheduled: data.canShowTaskExample,
            scheduledDate: data.canShowTaskExample ? '2026-11-04' : '',
            deadlineDate: data.canShowTaskExample ? '2026-11-10' : null,
          )
        : TaskItem.fromCachedJob({
            ...data.selectedJob!,
            ...data.savedInspectionFields,
          });
    TaskSubmission? submission;
    for (final row in data.submissions.where(
      (row) => row['job_id'] == task.id,
    )) {
      try {
        submission = TaskSubmission.fromRow(row);
      } catch (_) {
        /* No false receipt. */
      }
      if (submission != null) break;
    }
    if (submission != null && data.selectedJob != null) {
      task = TaskItem.fromCachedJob({
        ...data.selectedJob!,
        ...submission.evidenceFields,
        ...data.savedInspectionFields,
      });
    }
    if (stop.page == GuidePage.overview && stop.targetId.startsWith('step_')) {
      return switch (stop.targetId) {
        'step_1' => SiteMapScreen(task: task, walkthrough: data),
        'step_2' => GpsVerificationScreen(task: task, walkthrough: data),
        'step_3' => CapturePhotoScreen(task: task, walkthrough: data),
        'step_4' => InspectionChecklistScreen(task: task, walkthrough: data),
        'step_5' => FieldFindingsScreen(task: task, walkthrough: data),
        _ => ReviewSubmitScreen(task: task, walkthrough: data),
      };
    }
    return switch (stop.page) {
      GuidePage.home => HomeDashboardScreen(
        profile: widget.profile,
        walkthrough: data,
      ),
      GuidePage.tasks => TasksScreen(
        profile: widget.profile,
        walkthrough: data,
      ),
      GuidePage.sync => UpdatesScreen(
        profile: widget.profile,
        walkthrough: data,
      ),
      GuidePage.profile => ProfileScreen(
        profile: widget.profile,
        walkthrough: data,
      ),
      GuidePage.overview =>
        task.category == 'Completed' || submission != null
            ? CompletedInspectionDetailScreen(
                task: task,
                submission: submission,
                walkthrough: data,
              )
            : ParcelDetailScreen(task: task, walkthrough: data),
    };
  }

  @override
  void dispose() {
    _liveTargets.dispose();
    _epoch++;
    widget.coordinator.removeListener(_onGuideChanged);
    _walkthroughTargets.dispose();
    super.dispose();
  }
}
