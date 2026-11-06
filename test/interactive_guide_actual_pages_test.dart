import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/inspection/services/photo_source_resolver.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/home_guide_sections.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_data_loader.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_examples.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_read_only_data.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_round_widgets.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_protocol_view.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

class _NoGuideNetwork extends HttpOverrides {
  final attempts = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts.add('HttpClient');
    throw StateError('Walkthrough must not create a network client');
  }
}

void main() {
  final fixture = OfflineReliabilityFixture();
  final profile = UserProfile.fromMap(offlineProfile);
  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    await fixture.db.update(
      'local_jobs',
      {
        'status': 'assigned',
        'applicant_name': 'Saved selected applicant',
        'reference_number': 'SAVED-2026-42',
        'barangay': 'Saved barangay',
        'is_self_scheduled': 1,
        'scheduled_date': '2026-11-04',
        'deadline_date': '2026-11-10',
      },
      where: 'id = ?',
      whereArgs: [offlineRound2],
    );
    await fixture.db.delete(
      'local_jobs',
      where: 'id = ?',
      whereArgs: [offlineJob],
    );
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<GuideReadOnlyData> data(WidgetTester tester) async =>
      (await tester.runAsync(
        () => loadGuideReadOnlyData(
          ownerId: offlineInspector,
          language: GuideLanguage.english,
          preferredTaskId: offlineRound2,
        ),
      ))!;
  Future<String> snapshot(WidgetTester tester) async =>
      (await tester.runAsync(fixture.guideSafetySnapshot))!;
  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  fixture.widgetTest(
    'actual routing uses saved values and the six real inspection screens',
    (tester) async {
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: profile,
          preferredTaskId: offlineRound2,
          child: const Scaffold(body: Text('Retained origin')),
        ),
      );
      await guide.start(GuideLanguage.english, replay: true);
      await settle(tester);
      for (final stop in guideStops) {
        final active = find.byKey(const ValueKey('guide-active-page'));
        final expected = switch (stop.targetId) {
          'step_1' => SiteMapScreen,
          'step_2' => GpsVerificationScreen,
          'step_3' => CapturePhotoScreen,
          'step_4' => InspectionChecklistScreen,
          'step_5' => FieldFindingsScreen,
          'step_6' => ReviewSubmitScreen,
          _ => switch (stop.page) {
            GuidePage.home => HomeDashboardScreen,
            GuidePage.tasks => TasksScreen,
            GuidePage.overview => ParcelDetailScreen,
            GuidePage.sync => UpdatesScreen,
            GuidePage.profile => ProfileScreen,
          },
        };
        expect(
          find.descendant(of: active, matching: find.byType(expected)),
          findsOneWidget,
          reason: stop.id,
        );
        expect(
          find.descendant(
            of: active,
            matching: find.text('Sample Applicant — Fictional'),
          ),
          findsNothing,
          reason: stop.id,
        );
        expect(tester.takeException(), isNull, reason: stop.id);
        guide.next();
        await settle(tester);
      }
      await guide.finish();
      await settle(tester);
      expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
      expect(find.text('Retained origin'), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      guide.dispose();
    },
  );

  fixture.widgetTest('retired replay cannot paint a late actual page', (
    tester,
  ) async {
    final guide = GuideCoordinator(
      inspectorId: offlineInspector,
      preferences: GuidePreferences(),
      canPresent: () => true,
    );
    await fixture.mount(
      tester,
      GuideHost(
        coordinator: guide,
        profile: profile,
        child: const Scaffold(body: Text('Retained origin')),
      ),
    );
    await guide.start(GuideLanguage.english, replay: true);
    await tester.pump();
    await guide.skip();
    await settle(tester);
    expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
    expect(find.text('Retained origin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
  });

  fixture.widgetTest(
    'actual routing unreadable assignments never become fictional task details',
    (tester) async {
      await tester.runAsync(
        () => fixture.db.execute(
          'ALTER TABLE local_jobs RENAME TO unavailable_jobs',
        ),
      );
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: profile,
          child: const Scaffold(),
        ),
      );
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G16')) {
        guide.next();
      }
      await settle(tester);
      expect(
        tester
            .widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen))
            .task
            .name,
        'Saved task unavailable',
      );
      expect(find.byType(GuideSample), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
    },
  );

  fixture.widgetTest(
    'read-only checklist keeps its five rows without an active provider',
    (tester) async {
      final saved = await data(tester);
      fixture.provider.dispose();
      fixture.provider = InspectionProvider();
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        InspectionChecklistScreen(
          task: TaskItem.fromCachedJob(saved.selectedJob!),
          walkthrough: saved,
        ),
      );
      await settle(tester);
      expect(find.text('0 of 5 checked'), findsOneWidget);
      for (final label in const [
        'Structure matches declared use',
        'Setback distances compliant',
        'Accessibility & road frontage',
        'Surrounding developments noted',
        'Signage / commercial activity present',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(label), findsOneWidget);
      }
      expect(await snapshot(tester), before);
    },
  );

  fixture.widgetTest(
    'read-only GPS retains the durable synced fix without requesting a live fix',
    (tester) async {
      await tester.runAsync(
        () => DBHelper.saveGpsVerification(
          jobId: offlineRound2,
          latitude: 13.5,
          longitude: 121.25,
          accuracyMeters: 7,
          fixAt: DateTime.utc(2026, 11, 2),
          verifiedAt: DateTime.utc(2026, 11, 2),
        ),
      );
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        GpsVerificationScreen(
          task: TaskItem.fromCachedJob(saved.selectedJob!),
          walkthrough: saved,
        ),
      );
      await settle(tester);
      expect(find.text('Saved reading — not a live fix'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('± 7 m'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('± 7 m'), findsOneWidget);
      expect(
        tester
            .widget<FieldPrimaryButton>(find.byType(FieldPrimaryButton))
            .onPressed,
        isNull,
      );
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
    },
  );

  final hardwareCalls = <String>[];
  void backgroundAndResume(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void denyHardware(WidgetTester tester) {
    hardwareCalls.clear();
    for (final channel in [
      'flutter.baseflow.com/geolocator',
      'flutter.baseflow.com/geolocator_updates',
      'flutter_compass',
      'plugins.flutter.io/camera',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          hardwareCalls.add('$channel/${call.method}');
          return call.method == 'isLocationServiceEnabled' ? false : null;
        },
      );
    }
  }

  fixture.widgetTest(
    'read-only overview/maps leaves a different active inspection intact',
    (tester) async {
      final saved = await data(tester);
      final task = TaskItem.fromCachedJob(saved.selectedJob!);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        ParcelDetailScreen(task: task, walkthrough: saved),
      );
      await settle(tester);
      expect(
        tester
            .widget<RoundContextCard>(find.byType(RoundContextCard))
            .task
            .inspectionNo,
        'SAVED-2026-42',
      );
      await tester.scrollUntilVisible(
        find.text('Saved selected applicant'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Saved selected applicant'), findsWidgets);
      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        button.onPressed?.call();
      }
      backgroundAndResume(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only overview/maps completed detail never refreshes remote data',
    (tester) async {
      await tester.runAsync(
        () => fixture.db.update(
          'local_jobs',
          {'status': 'completed'},
          where: 'id = ?',
          whereArgs: [offlineRound2],
        ),
      );
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        CompletedInspectionDetailScreen(
          task: TaskItem.fromCachedJob(saved.selectedJob!),
          walkthrough: saved,
        ),
      );
      await settle(tester);
      expect(find.text('Saved selected applicant'), findsWidgets);
      expect(find.text('Inspection Summary'), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'review protocol preserves independently saved steps and times',
    (tester) async {
      await tester.runAsync(
        () => fixture.db.insert('local_inspections', {
          'id': offlineRound2,
          'inspector_id': offlineInspector,
          'current_step': 5,
          'step_timestamps': jsonEncode({
            '1': '2026-11-02T08:00:00Z',
            '2': '2026-11-02T08:01:00Z',
            '5': '2026-11-02T08:05:00Z',
          }),
        }),
      );
      final before = await snapshot(tester);
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: profile,
          preferredTaskId: offlineRound2,
          child: const Scaffold(),
        ),
      );
      await guide.start(GuideLanguage.english, replay: true);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G17')) {
        guide.next();
      }
      await settle(tester);
      final protocol = tester.widget<InspectionProtocolView>(
        find.byType(InspectionProtocolView),
      );
      expect(protocol.completedCount, 3);
      expect(find.text('50%'), findsOneWidget);
      expect(protocol.steps.map((step) => step.done), [
        true,
        true,
        false,
        false,
        true,
        false,
      ]);
      expect(protocol.steps.map((step) => step.locked), [
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
      expect(protocol.steps.map((step) => step.current), [
        false,
        false,
        true,
        false,
        false,
        false,
      ]);
      expect(protocol.steps[4].savedAt, '2026-11-02T08:05:00Z');
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
    },
  );

  for (final local in [true, false]) {
    fixture.widgetTest(
      'review receipt is ${local ? 'historical to saved rework' : 'fallback without local components'}',
      (tester) async {
        await tester.runAsync(() async {
          await fixture.db.update(
            'local_jobs',
            {'status': 'completed'},
            where: 'id = ?',
            whereArgs: [offlineRound2],
          );
          await fixture.db.insert('pending_actions', {
            'id': 'old-receipt',
            'job_id': offlineRound2,
            'inspector_id': offlineInspector,
            'type': 'submit_inspection',
            'status': 'synced',
            'created_at': '2026-11-01T00:00:00Z',
            'updated_at': '2026-11-01T00:00:00Z',
            'payload': jsonEncode({
              'findings': 'Prior submission',
              'isCompliant': true,
              'inspectionResult': 'Compliant',
              'inspectorNotes': 'Prior notes',
              'discrepancies': 'Prior explanation',
              'checklistData': [
                {'item': 'Structure matches declared use', 'checked': false},
              ],
              'checklistCompletedCount': 0,
              'checklistTotalCount': 5,
              'photosData': [
                {
                  'photoPath': File('assets/icon/app_icon.png').absolute.path,
                  'notes': 'Prior photo',
                },
              ],
            }),
          });
          if (local) {
            await fixture.db.insert('local_inspections', {
              'id': offlineRound2,
              'inspector_id': offlineInspector,
              'notes': 'Current saved notes',
              'inspection_result': 'For Review',
              'updated_at': '2026-11-02T00:00:00Z',
              'checklist_json': jsonEncode({
                'Structure matches declared use': true,
                '_draft_findings': {'discrepancies': 'Current explanation'},
              }),
            });
            await fixture.db.insert('local_photos', {
              'id': 'current-photo',
              'job_id': offlineRound2,
              'inspector_id': offlineInspector,
              'photo_path': File('assets/icon/app_icon.png').absolute.path,
              'notes': 'Current photo',
              'captured_at': '2026-11-02T00:00:00Z',
            });
          }
        });
        final before = await snapshot(tester);
        final guide = GuideCoordinator(
          inspectorId: offlineInspector,
          preferences: GuidePreferences(),
          canPresent: () => true,
        );
        await fixture.mount(
          tester,
          GuideHost(
            coordinator: guide,
            profile: profile,
            preferredTaskId: offlineRound2,
            child: const Scaffold(),
          ),
        );
        await guide.start(GuideLanguage.english, replay: true);
        while (guide.stopIndex <
            guideStops.indexWhere((stop) => stop.id == 'G16')) {
          guide.next();
        }
        await settle(tester);
        final detail = tester.widget<CompletedInspectionDetailScreen>(
          find.byType(CompletedInspectionDetailScreen),
        );
        expect(
          detail.task.inspectorNotes,
          local ? 'Current saved notes' : 'Prior notes',
        );
        expect(
          detail.task.discrepancies,
          local ? 'Current explanation' : 'Prior explanation',
        );
        expect(detail.task.checklistCompletedCount, local ? 1 : 0);
        expect(
          detail.task.photoDetails.single['notes'],
          local ? 'Current photo' : 'Prior photo',
        );
        final saved = await data(tester);
        final receipt = detail.submission;
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
        // Direct passive entry must use the same precedence, not only the host.
        await fixture.mount(
          tester,
          CompletedInspectionDetailScreen(
            task: TaskItem.fromCachedJob(saved.selectedJob!),
            submission: receipt,
            walkthrough: saved,
          ),
        );
        await settle(tester);
        await tester.scrollUntilVisible(
          find.text('Field Findings'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Field Findings'));
        await tester.pumpAndSettle();
        expect(
          find.text(local ? 'Current saved notes' : 'Prior notes'),
          findsOneWidget,
        );
        expect(await snapshot(tester), before);
        expect(fixture.requests, isEmpty);
      },
    );
  }

  fixture.widgetTest(
    'read-only overview/maps creates no network client or sensor subscription',
    (tester) async {
      await tester.runAsync(() async {
        await fixture.db.update(
          'local_jobs',
          {
            'supabase_parcel_id': 'saved-parcel',
            'parcel_lat': 13.84,
            'parcel_lng': 121.20,
          },
          where: 'id = ?',
          whereArgs: [offlineRound2],
        );
        await fixture.db.insert('local_route_cache', {
          'job_id': offlineRound2,
          'geometry_json': '[[121.199,13.839],[121.20,13.84]]',
          'origin_lat': 13.839,
          'origin_lng': 121.199,
          'distance_meters': 200.0,
          'duration_seconds': 60.0,
          'fetched_at': '2026-11-02T00:00:00Z',
        });
        await fixture.db.insert('pending_actions', {
          'id': 'saved-gps',
          'job_id': offlineRound2,
          'inspector_id': offlineInspector,
          'type': 'gps_confirm',
          'status': 'pending',
          'created_at': '2026-11-02T00:00:00Z',
          'updated_at': '2026-11-02T00:00:00Z',
          'payload': jsonEncode({
            'latitude': 13.839,
            'longitude': 121.199,
            'accuracyMeters': 8.0,
          }),
        });
      });
      final saved = await data(tester);
      final task = TaskItem.fromCachedJob(saved.selectedJob!);
      final before = await snapshot(tester);
      denyHardware(tester);
      final network = _NoGuideNetwork();
      final previous = HttpOverrides.current;
      HttpOverrides.global = network;
      try {
        await fixture.mount(
          tester,
          SiteMapScreen(task: task, walkthrough: saved),
        );
        await settle(tester);
        expect(find.byType(FlutterMap), findsOneWidget);
        expect(find.byType(TileLayer), findsNothing);
        expect(find.byType(PolylineLayer), findsWidgets);
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.mount(
          tester,
          GpsVerificationScreen(task: task, walkthrough: saved),
        );
        await settle(tester);
        expect(find.textContaining('Saved reading'), findsWidgets);
        final pop = tester.widget<PopScope>(
          find.byWidgetPredicate((widget) => widget is PopScope).first,
        );
        pop.onPopInvokedWithResult?.call(true, null);
        backgroundAndResume(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(await snapshot(tester), before);
        expect(hardwareCalls, isEmpty);
        expect(network.attempts, isEmpty);
        expect(fixture.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        HttpOverrides.global = previous;
      }
    },
  );

  fixture.widgetTest(
    'read-only overview/maps remote image uses only an existing local fallback',
    (tester) async {
      var downloads = 0;
      final resolver = PhotoSourceResolver(
        projectUrl: Uri.parse('https://fs04.test'),
        download: (_) async {
          downloads++;
          throw StateError('Network forbidden');
        },
      );
      await fixture.mount(
        tester,
        Scaffold(
          body: AdaptivePhotoImage(
            path: 'inspections/$offlineRound2/photo_saved.jpg',
            allowNetwork: false,
            resolver: resolver,
            errorBuilder: (_) => const Text('Saved evidence unavailable'),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Saved evidence unavailable'), findsOneWidget);
      expect(downloads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only evidence/forms ignores lifecycle, pop and dispose saves',
    (tester) async {
      late File photo;
      await tester.runAsync(() async {
        photo = File('${fixture.directory.path}/selected-evidence.png');
        photo.writeAsBytesSync(
          File('assets/icon/app_icon.png').readAsBytesSync(),
        );
        await fixture.db.insert('local_photos', {
          'id': 'selected-photo',
          'job_id': offlineRound2,
          'inspector_id': offlineInspector,
          'photo_path': photo.path,
          'notes': 'Saved selected photo',
          'captured_at': '2026-11-02T00:00:00Z',
        });
        await fixture.db.insert('local_inspections', {
          'id': offlineRound2,
          'inspector_id': offlineInspector,
          'notes': 'Existing saved finding',
          'inspection_result': 'For Review',
          'updated_at': '2026-11-02T00:00:00Z',
          'checklist_json': jsonEncode({
            'Structure matches declared use': true,
            '_draft_findings': {
              'discrepancies': 'Saved explanation',
              'recommendations': 'Saved recommendation',
            },
          }),
        });
      });
      final saved = await data(tester);
      final task = TaskItem.fromCachedJob(saved.selectedJob!);
      final before = await snapshot(tester);
      denyHardware(tester);
      final network = _NoGuideNetwork();
      final previous = HttpOverrides.current;
      HttpOverrides.global = network;
      try {
        for (final screen in <Widget>[
          CapturePhotoScreen(task: task, walkthrough: saved),
          InspectionChecklistScreen(task: task, walkthrough: saved),
          FieldFindingsScreen(task: task, walkthrough: saved),
          ReviewSubmitScreen(task: task, walkthrough: saved),
        ]) {
          await fixture.mount(tester, screen);
          await settle(tester);
          if (screen is CapturePhotoScreen) {
            expect(find.text('1 site photo'), findsOneWidget);
            expect(
              tester
                  .widget<AdaptivePhotoImage>(find.byType(AdaptivePhotoImage))
                  .path,
              photo.path,
            );
          } else if (screen is InspectionChecklistScreen) {
            expect(find.text('1 of 5 checked'), findsOneWidget);
            await tester.tap(find.text('Structure matches declared use'));
          } else if (screen is FieldFindingsScreen) {
            expect(find.text('Existing saved finding'), findsOneWidget);
          } else if (screen is ReviewSubmitScreen) {
            expect(find.text('For Review'), findsWidgets);
            await tester.scrollUntilVisible(
              find.text('Existing saved finding'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.text('Existing saved finding'), findsOneWidget);
          }
          for (final field in tester.widgetList<TextField>(
            find.byType(TextField),
          )) {
            field.controller?.text = 'Do not save this walkthrough edit';
            field.onChanged?.call('Do not save this walkthrough edit');
          }
          for (final action in tester.widgetList<FieldPrimaryButton>(
            find.byType(FieldPrimaryButton),
          )) {
            action.onPressed?.call();
          }
          for (final pop in tester.widgetList<PopScope>(
            find.byWidgetPredicate((w) => w is PopScope),
          )) {
            pop.onPopInvokedWithResult?.call(true, null);
            pop.onPopInvokedWithResult?.call(false, null);
          }
          backgroundAndResume(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await fixture.flush(tester);
          expect(
            await snapshot(tester),
            before,
            reason: '${screen.runtimeType}',
          );
          expect(hardwareCalls, isEmpty, reason: '${screen.runtimeType}');
          expect(network.attempts, isEmpty);
          expect(fixture.requests, isEmpty);
          expect(photo.existsSync(), isTrue);
          expect(tester.takeException(), isNull);
        }
      } finally {
        HttpOverrides.global = previous;
      }
    },
  );

  fixture.widgetTest(
    'read-only evidence/forms latest saved intent wins without provider hydration',
    (tester) async {
      final saved = GuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
        selectedJob: {'id': offlineRound2},
        draft: {
          'notes': 'Older draft',
          'updated_at': '2026-11-01T00:00:00Z',
          'checklist_json': jsonEncode({
            '_draft_findings': {'discrepancies': 'Older explanation'},
          }),
        },
        findingsIntent: {
          'inspectorNotes': 'Newer saved intent',
          'discrepancies': 'Newer explanation',
          'localCreatedAt': '2026-11-02T00:00:00Z',
        },
      );
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        FieldFindingsScreen(
          task: TaskItem.fromCachedJob(saved.selectedJob!),
          walkthrough: saved,
        ),
      );
      await settle(tester);
      expect(find.text('Newer saved intent'), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'review failed inspection read stays unknown in ${language.name} forms',
      (tester) async {
        await tester.runAsync(
          () => fixture.db.execute(
            'ALTER TABLE local_photos RENAME TO unavailable_photos',
          ),
        );
        final saved = (await tester.runAsync(
          () => loadGuideReadOnlyData(
            ownerId: offlineInspector,
            language: language,
            preferredTaskId: offlineRound2,
          ),
        ))!;
        expect(saved.unavailable, contains(GuideDataSection.inspection));
        final task = TaskItem.fromCachedJob(saved.selectedJob!);
        final before = await snapshot(tester);
        for (final screen in <Widget>[
          GpsVerificationScreen(task: task, walkthrough: saved),
          CapturePhotoScreen(task: task, walkthrough: saved),
          InspectionChecklistScreen(task: task, walkthrough: saved),
          FieldFindingsScreen(task: task, walkthrough: saved),
          ReviewSubmitScreen(task: task, walkthrough: saved),
        ]) {
          await fixture.mount(tester, screen);
          await settle(tester);
          expect(
            find.text(
              language == GuideLanguage.english
                  ? 'Saved inspection data unavailable'
                  : 'Hindi mabasa ang naka-save na datos ng inspeksiyon',
            ),
            findsWidgets,
            reason: '${screen.runtimeType}',
          );
          expect(find.byType(GuideSample), findsNothing);
          for (final claim in [
            '0 site photos',
            '0 of 5 checked',
            '0/5 checked',
            'No saved GPS reading',
            'No observations recorded',
            'No discrepancies recorded',
            'No recommendations recorded',
          ]) {
            expect(
              find.text(claim),
              findsNothing,
              reason: '${screen.runtimeType}',
            );
          }
          expect(await snapshot(tester), before);
          expect(fixture.requests, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  fixture.widgetTest(
    'review local camera evidence ignores another task rework mode',
    (tester) async {
      fixture.provider.hydrateForRework(offlineTask);
      await tester.runAsync(
        () => fixture.db.insert('local_photos', {
          'id': 'camera-no-notes',
          'job_id': offlineRound2,
          'inspector_id': offlineInspector,
          'photo_path': File('assets/icon/app_icon.png').absolute.path,
          'notes': '',
          'captured_at': '2026-11-02T00:00:00Z',
        }),
      );
      final saved = await data(tester);
      final task = TaskItem.fromCachedJob(saved.selectedJob!);
      final before = await snapshot(tester);
      for (final screen in <Widget>[
        CapturePhotoScreen(task: task, walkthrough: saved),
        FieldFindingsScreen(task: task, walkthrough: saved),
        ReviewSubmitScreen(task: task, walkthrough: saved),
      ]) {
        await fixture.mount(tester, screen);
        await settle(tester);
        if (screen is CapturePhotoScreen) {
          expect(find.text('1 site photo'), findsOneWidget);
        } else if (screen is FieldFindingsScreen) {
          expect(find.text('1 site photo attached'), findsOneWidget);
        } else {
          final summary = find
              .ancestor(
                of: find.text('Site photos'),
                matching: find.byType(Column),
              )
              .first;
          expect(
            find.descendant(of: summary, matching: find.text('1')),
            findsOneWidget,
          );
        }
        expect(await snapshot(tester), before);
        expect(fixture.requests, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'review fictional record sections are locally labelled in ${language.name}',
      (tester) async {
        await tester.runAsync(() => fixture.db.delete('local_jobs'));
        final before = await snapshot(tester);
        final guide = GuideCoordinator(
          inspectorId: offlineInspector,
          preferences: GuidePreferences(),
          canPresent: () => true,
        );
        await fixture.mount(
          tester,
          GuideHost(
            coordinator: guide,
            profile: profile,
            child: const Scaffold(),
          ),
        );
        await guide.start(language, replay: true);
        while (guide.stopIndex <
            guideStops.indexWhere((stop) => stop.id == 'G16')) {
          guide.next();
        }
        await settle(tester);
        for (final id in ['G16', 'G23']) {
          final index = guideStops.indexWhere((stop) => stop.id == id);
          while (guide.stopIndex < index) {
            guide.next();
          }
          await tester.pumpAndSettle();
          final applicant = find.text(
            guideExample.applicant,
            skipOffstage: false,
          );
          expect(applicant, findsOneWidget);
          await Scrollable.ensureVisible(tester.element(applicant));
          await tester.pumpAndSettle();
          final sample = find.ancestor(
            of: find.text(guideExample.applicant),
            matching: find.byType(GuideSample),
          );
          expect(
            sample,
            findsOneWidget,
            reason:
                '${guideStops[index].id}: fictional applicant needs its own sample label',
          );
          expect(
            find.descendant(of: sample, matching: find.text(guideSampleLabel)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: sample,
              matching: find.text(guideExample.location),
            ),
            findsOneWidget,
          );
          if (language == GuideLanguage.tagalog) {
            expect(
              find.descendant(
                of: sample,
                matching: find.text(guideSampleTagalog),
              ),
              findsOneWidget,
            );
          }
        }
        expect(await snapshot(tester), before);
        expect(fixture.requests, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
      },
    );
  }

  fixture.widgetTest(
    'read-only evidence/forms findings cannot autosave on background or disposal',
    (tester) async {
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        FieldFindingsScreen(
          task: TaskItem.fromCachedJob(saved.selectedJob!),
          walkthrough: saved,
        ),
      );
      await settle(tester);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      field.controller!.text = 'Forbidden walkthrough edit';
      field.onChanged!('Forbidden walkthrough edit');
      backgroundAndResume(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.flush(tester);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
    },
  );

  fixture.widgetTest(
    'read-only main pages Home keeps identity and saved assignments',
    (tester) async {
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        HomeDashboardScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.text('Fixture Inspector'), findsOneWidget);
      expect(find.text('Saved selected applicant'), findsWidgets);
      expect(find.byType(GuideSample), findsNothing);
      expect(
        tester
            .widget<ActiveAssignmentsFolderCard>(
              find.byType(ActiveAssignmentsFolderCard).first,
            )
            .referenceNo,
        'SAVED-2026-42',
      );
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        button.onPressed?.call();
      }
      await settle(tester);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final page in ['Home', 'Tasks']) {
    for (final payload in ['{bad json', '{}']) {
      fixture.widgetTest(
        'review malformed final intent on $page ($payload) is unavailable, not loading',
        (tester) async {
          await tester.runAsync(
            () => fixture.db.insert('pending_actions', {
              'id': 'unreadable-submit',
              'job_id': offlineRound2,
              'inspector_id': offlineInspector,
              'type': 'submit_inspection',
              'status': 'pending',
              'payload': payload,
              'created_at': '2026-11-02T00:00:00Z',
              'updated_at': '2026-11-02T00:00:00Z',
            }),
          );
          final saved = await data(tester);
          final before = await snapshot(tester);
          await fixture.mount(
            tester,
            page == 'Home'
                ? HomeDashboardScreen(profile: profile, walkthrough: saved)
                : TasksScreen(profile: profile, walkthrough: saved),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          if (page == 'Home') {
            await tester.scrollUntilVisible(
              find.textContaining('Could not read saved tasks'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
          }
          expect(
            find.textContaining('Could not read saved tasks'),
            findsOneWidget,
          );
          expect(find.byType(GuideSample), findsNothing);
          expect(await snapshot(tester), before);
          expect(fixture.requests, isEmpty);
        },
      );
    }
  }

  fixture.widgetTest(
    'read-only main pages selects Pending instead of an empty Ongoing tab',
    (tester) async {
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        TasksScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.text('Scheduled'), findsWidgets);
      expect(find.text('Saved selected applicant'), findsWidgets);
      expect(find.text('No ongoing tasks found'), findsNothing);
      expect(find.byType(GuideSample), findsNothing);
      await tester.tap(find.text('Saved selected applicant').first);
      await settle(tester);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only main pages Profile uses saved analytics without fetching',
    (tester) async {
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        ProfileScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.text('Fixture Inspector'), findsOneWidget);
      expect(find.text('Performance Analytics'), findsOneWidget);
      final edit = tester.widget<TextButton>(
        find.byKey(const Key('profile-edit-button')),
      );
      edit.onPressed?.call();
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only main pages Sync shows saved queue and receipt without draining',
    (tester) async {
      await tester.runAsync(() async {
        for (final status in ['pending', 'synced']) {
          await fixture.db.insert('pending_actions', {
            'id': 'guide-$status',
            'job_id': offlineRound2,
            'inspector_id': offlineInspector,
            'type': 'checklist_update',
            'status': status,
            'payload': jsonEncode({
              'checklistCompletedCount': 3,
              'checklistTotalCount': 5,
            }),
            'created_at': '2026-11-02T07:08:09Z',
            'updated_at': '2026-11-02T07:08:09Z',
          });
        }
      });
      final saved = await data(tester);
      final before = await snapshot(tester);
      fixture.online = true;
      await fixture.mount(
        tester,
        UpdatesScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.text('1 change waiting'), findsOneWidget);
      expect(find.text('Saved selected applicant'), findsWidgets);
      final sync = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sync now'),
      );
      sync.onPressed?.call();
      await tester.pump(const Duration(seconds: 9));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('1 recent receipt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1 recent receipt'), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only main pages empty assignment section alone gets a sample',
    (tester) async {
      await tester.runAsync(() => fixture.db.delete('local_jobs'));
      final saved = await data(tester);
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        HomeDashboardScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.text('Fixture Inspector'), findsOneWidget);
      expect(find.text('Sample Inspector — Fictional'), findsNothing);
      expect(find.byType(GuideSample), findsOneWidget);
      expect(find.byType(ActiveAssignmentsFolderCard), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(HomeTaskStatusChart),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final chart = tester.widget<HomeTaskStatusChart>(
        find.byType(HomeTaskStatusChart),
      );
      expect(chart.total, 0);
      expect(chart.counts, [0, 0, 0, 0]);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'read-only main pages unreadable assignments never claim an empty account',
    (tester) async {
      final saved = GuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
        unavailable: {GuideDataSection.tasks},
      );
      final before = await snapshot(tester);
      await fixture.mount(
        tester,
        TasksScreen(profile: profile, walkthrough: saved),
      );
      await settle(tester);
      expect(find.byType(GuideSample), findsNothing);
      expect(find.text('Saved tasks unavailable'), findsOneWidget);
      expect(await snapshot(tester), before);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
