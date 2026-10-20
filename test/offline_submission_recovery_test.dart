import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/gps_verification_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';

import 'support/offline_reliability_fixture.dart';
import 'support/site_map_http_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> queue({String findings = 'Fixture findings'}) =>
      SyncOutboxService.enqueueSubmitInspection(
        jobId: offlineJob,
        findings: findings,
        isCompliant: true,
        inspectionResult: 'Compliant',
        observations: 'Fixture observations',
        inspectorNotes: findings,
        discrepancies: 'Fixture discrepancy',
        recommendations: 'Fixture recommendation',
        checklistData: const [
          {'item': 'Fixture checklist', 'checked': true},
        ],
        checklistCompletedCount: 1,
        checklistTotalCount: 1,
        photosData: const [],
      );

  Future<File> seedDraft() async {
    fixture.provider.updateResult('With Discrepancy');
    fixture.provider.updateFindings(
      actualLandUse: 'Fixture use',
      notes: 'Fixture findings',
      discrepancies: 'Fixture discrepancy',
      recommendations: 'Fixture recommendation',
      boundaryStatus: 'Fixture boundary',
    );
    fixture.provider.setSiteCondition('Structure matches declared use', false);
    final photo = File('${fixture.directory.path}/fixture.png');
    photo.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
    );
    fixture.provider.addPhoto(
      photoPath: photo.path,
      photoNotes: 'Fictional photo',
      latitude: 0,
      longitude: 0,
    );
    await fixture.provider.saveAllInspectionState();
    await DBHelper.saveInspectionStep(offlineJob, 5, {
      '5': '2026-01-01T00:00:00Z',
    }, offlineInspector);
    return photo;
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Submit Inspection'));
    await fixture.flush(tester);
    await tester.tap(find.text('Confirm & Submit'));
    await fixture.flush(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await fixture.flush(tester);
  }

  /// Accepts the draft-progress PATCH the provider's legacy sync sends and
  /// returns exactly the row shape its authority check requires.
  void acceptProgressPatches() {
    fixture.requestOverride = (request) async {
      if (request.method != 'PATCH') return null;
      final filter = request.url.queryParameters['id'];
      final rowId = filter != null && filter.startsWith('eq.')
          ? Uri.decodeComponent(filter.substring(3))
          : offlineJob;
      return http.Response(
        jsonEncode([
          {'id': rowId, 'assigned_inspector_id': offlineInspector},
        ]),
        200,
        request: request,
        headers: {
          'content-type': 'application/json',
          'x-supabase-api-version': '2024-01-01',
        },
      );
    };
  }

  List<Map<String, dynamic>> progressPatchBodies() => fixture.requests
      .where((r) => r.method == 'PATCH')
      .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
      .toList();

  fixture.widgetTest(
    'durable offline final submit opens Pending Sync and returns Home without profile HTTP',
    (tester) async {
      final photo = await tester.runAsync(seedDraft);
      final cachedBefore = await tester.runAsync(
        () => DBHelper.getLocalInspection(offlineJob),
      );
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await submit(tester);
      expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
      expect(find.text('Saved Offline'), findsOneWidget);
      expect(find.textContaining('Pending Sync'), findsWidgets);
      final queued = await tester.runAsync(
        () => DBHelper.getActionableActions(),
      );
      expect(queued, hasLength(1));
      expect(queued!.single['type'], 'submit_inspection');
      expect(queued.single['inspector_id'], offlineInspector);
      expect(
        jsonDecode(queued.single['payload'] as String)['photosData'],
        hasLength(1),
      );
      expect(
        (await tester.runAsync(
          () => DBHelper.getCachedJobs(),
        ))!.firstWhere((r) => r['id'] == offlineJob)['status'],
        'in_progress',
      );
      expect(
        (await tester.runAsync(
          () => fixture.db.query('inspection_job_retention'),
        )),
        hasLength(1),
      );
      expect(photo!.existsSync(), isTrue);
      expect(cachedBefore!['notes'], 'Fixture findings');
      expect(fixture.remoteWrites, 0);
      await fixture.capture(tester, 'local-submit-success');
      await tester.tap(find.text('Back to Home'));
      await fixture.flush(tester);
      await tester.pump(const Duration(seconds: 1));
      await fixture.flush(tester);
      final shell = tester.widget<MainShellScreen>(
        find.byType(MainShellScreen),
      );
      expect(shell.initialIndex, 0);
      expect(shell.profile.id, offlineInspector);
      expect(
        fixture.requests.where((r) => r.url.path.contains('/profiles')),
        isEmpty,
      );
      expect(
        (await tester.runAsync(() => DBHelper.getActionableActions())),
        hasLength(1),
      );
      // Advance actual entrance frames before capturing Home; a single large
      // pump starts each delayed spring but can still capture zero opacity.
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
        await fixture.flush(tester);
      }
      expect(find.text('Fixture Inspector').hitTestable(), findsOneWidget);
      expect(find.text('Active Assignments').hitTestable(), findsOneWidget);
      await fixture.capture(tester, 'local-submit-home');
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'double-tap final submit queues exactly one durable intent',
    (tester) async {
      await tester.runAsync(seedDraft);
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      final submit = find.text('Submit Inspection');
      // Two taps before any frame: the tree still shows an enabled button, so
      // the in-flight guard itself must refuse the second press — no second
      // enqueue, no second navigation, no error state.
      await tester.tap(submit);
      await tester.tap(submit);
      await fixture.flush(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Confirm & Submit'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.flush(tester);
      expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
      expect(find.text('Saved Offline'), findsOneWidget);
      final queued = (await tester.runAsync(
        () => DBHelper.getActionableActions(),
      ))!;
      expect(queued, hasLength(1));
      expect(queued.single['type'], 'submit_inspection');
      expect(
        (await tester.runAsync(
          () => DBHelper.getCachedJobs(),
        ))!.firstWhere((r) => r['id'] == offlineJob)['status'],
        'in_progress',
      );
    },
  );

  for (final rejection in ['ABORT', 'IGNORE']) {
    fixture.widgetTest(
      'SQLite enqueue $rejection keeps Review, draft, photo file and retry usable',
      (tester) async {
        final photo = await tester.runAsync(seedDraft);
        await tester.runAsync(
          () => fixture.db.execute(
            "CREATE TRIGGER reject_queue BEFORE INSERT ON pending_actions BEGIN SELECT RAISE($rejection${rejection == 'ABORT' ? ",'isolated enqueue failure'" : ''}); END",
          ),
        );
        await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
        await submit(tester);
        expect(find.byType(ReviewSubmitScreen), findsOneWidget);
        expect(find.byType(SubmissionSuccessScreen), findsNothing);
        expect(find.textContaining('Could not save locally'), findsOneWidget);
        expect(find.text('Submit Inspection').hitTestable(), findsOneWidget);
        expect(fixture.provider.notes, 'Fixture findings');
        expect(fixture.provider.discrepancies, 'Fixture discrepancy');
        expect(photo!.existsSync(), isTrue);
        expect(
          (await tester.runAsync(() => DBHelper.getLocalPhotos(offlineJob))),
          hasLength(1),
        );
        expect(
          (await tester.runAsync(() => DBHelper.getActionableActions())),
          isEmpty,
        );
        await fixture.capture(tester, 'local-submit-failure');
        await tester.runAsync(
          () => fixture.db.execute('DROP TRIGGER reject_queue'),
        );
        await submit(tester);
        expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
        expect(
          (await tester.runAsync(() => DBHelper.getActionableActions())),
          hasLength(1),
        );
      },
    );
  }

  fixture.widgetTest(
    'reopened Review keeps one intent while immediately verifying remote authority',
    (tester) async {
      fixture.provider.updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await submit(tester);
      final first = (await tester.runAsync(
        () => DBHelper.getActionableActions(),
      ))!.single;
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      SyncOutboxService.hasConnectionOverride = () async => true;
      fixture.online = true;
      fixture.mode = 'success';
      await submit(tester);
      final rows = await tester.runAsync(
        () => DBHelper.getSyncCenterQueueActions(),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['id'], first['id']);
      expect(
        fixture.requests.where((r) => r.url.path.contains('/field_jobs')),
        isNotEmpty,
      );
      expect(rows.single['status'], 'conflict');
      expect(fixture.remoteWrites, 0);
      expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
    },
  );

  test(
    'identical final-submit retries preserve one durable action identity',
    () async {
      await queue();
      final first = (await DBHelper.getActionableActions()).single;
      await fixture.restartDatabase();
      await queue();
      final rows = await DBHelper.getActionableActions();
      expect(rows, hasLength(1));
      expect(rows.single['id'], first['id']);
      expect(rows.single['created_at'], first['created_at']);
    },
  );

  test(
    'different final evidence cannot overwrite or duplicate a preserved intent',
    () async {
      await queue();
      final before = (await DBHelper.getActionableActions()).single;
      await expectLater(
        queue(findings: 'Different intentional draft'),
        throwsStateError,
      );
      final rows = await DBHelper.getActionableActions();
      expect(rows, hasLength(1));
      expect(rows.single['payload'], before['payload']);
    },
  );

  test(
    'owner-scoped queued findings and evidence restore after file-backed restart',
    () async {
      final photo = await seedDraft();
      await SyncOutboxService.enqueueFindingsUpdate(
        jobId: offlineJob,
        observations: 'Fixture observations',
        discrepancies: 'Fixture discrepancy',
        recommendations: 'Fixture recommendation',
        inspectorNotes: 'Fixture findings',
      );
      final before = (await DBHelper.getLocalPhotos(offlineJob)).single;
      await fixture.restartDatabase();
      final restarted = InspectionProvider();
      await restarted.startInspection(offlineTask);
      expect(restarted.currentStep, 5);
      expect(restarted.notes, 'Fixture findings');
      expect(restarted.discrepancies, 'Fixture discrepancy');
      expect(restarted.recommendations, 'Fixture recommendation');
      expect(
        restarted.siteCondition['Structure matches declared use'],
        isFalse,
      );
      expect(restarted.capturedPhotos, hasLength(1));
      expect(
        restarted.capturedPhotos.single['capturedAt'],
        before['captured_at'],
      );
      expect(photo.existsSync(), isTrue);
      restarted.dispose();
      await fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session(owner: otherOfflineInspector)),
      );
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect(await DBHelper.getLocalPhotos(offlineJob), isEmpty);
      final foreign = InspectionProvider();
      await expectLater(foreign.startInspection(offlineTask), throwsStateError);
      foreign.dispose();
    },
  );

  test('snapshot save preserves reached step and step timestamps', () async {
    await seedDraft();
    await fixture.provider.saveAllInspectionState();
    final draft = await DBHelper.getLocalInspection(offlineJob);
    expect(draft!['current_step'], 5);
    expect(
      jsonDecode(draft['step_timestamps'] as String)['5'],
      '2026-01-01T00:00:00Z',
    );
  });

  test(
    'local snapshot retains findings after restart even when no action can enqueue',
    () async {
      await seedDraft();
      await fixture.restartDatabase();
      expect(await DBHelper.getActionableActions(), isEmpty);
      final restarted = InspectionProvider();
      await restarted.startInspection(offlineTask);
      expect(restarted.discrepancies, 'Fixture discrepancy');
      expect(restarted.recommendations, 'Fixture recommendation');
      restarted.dispose();
    },
  );

  test(
    'snapshot resave preserves photo capture time and prior acknowledgement',
    () async {
      await seedDraft();
      final before = (await DBHelper.getLocalPhotos(offlineJob)).single;
      await DBHelper.markPhotosSynced([before['id'] as String]);
      await fixture.provider.saveAllInspectionState();
      final after = (await DBHelper.getLocalPhotos(offlineJob)).single;
      expect(after['captured_at'], before['captured_at']);
      expect(after['is_synced'], 1);
    },
  );

  test(
    'changed photo notes require sync while original capture time stays durable',
    () async {
      await seedDraft();
      final before = (await DBHelper.getLocalPhotos(offlineJob)).single;
      await DBHelper.markPhotosSynced([before['id'] as String]);
      await DBHelper.savePhotoLocally(
        photoId: before['id'] as String,
        jobId: offlineJob,
        photoPath: before['photo_path'] as String,
        notes: 'Changed fictional notes',
        latitude: 0,
        longitude: 0,
      );
      final after = (await DBHelper.getLocalPhotos(offlineJob)).single;
      expect(after['is_synced'], 0);
      expect(after['captured_at'], before['captured_at']);
    },
  );

  test(
    'six-step offline continuation preserves progress and final intent on restart',
    () async {
      final progress = InspectionProgress.instance;
      progress.ensureActiveInspection(offlineJob, initialStep: 0);
      for (var step = 1; step <= 5; step++) {
        progress.markStepComplete(step);
        for (var attempts = 0; attempts < 40; attempts++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          final actions = await DBHelper.getActionableActions();
          if (actions.any(
            (a) =>
                a['type'] == 'current_step_update' &&
                jsonDecode(a['payload'] as String)['currentStep'] == step,
          )) {
            break;
          }
        }
        expect(
          (await DBHelper.getLocalInspection(offlineJob))!['current_step'],
          step,
        );
      }
      await queue();
      // A late persistence call must preserve the earlier step timestamps. The
      // sixth action is durable submit INTENT, never invented remote completion.
      await DBHelper.saveInspectionStep(offlineJob, 5, {
        '5': '2026-01-01T00:00:00Z',
      }, offlineInspector);
      await fixture.restartDatabase();
      final draft = (await DBHelper.getLocalInspection(offlineJob))!;
      expect(draft['current_step'], 5);
      expect(
        (jsonDecode(draft['step_timestamps'] as String) as Map).keys,
        containsAll(['1', '2', '3', '4', '5']),
      );
      expect(
        (await DBHelper.getCachedJobs()).firstWhere(
          (r) => r['id'] == offlineJob,
        )['status'],
        'in_progress',
      );
      expect(
        (await DBHelper.getActionableActions()).where(
          (r) => r['type'] == 'submit_inspection',
        ),
        hasLength(1),
      );
      final intent = (await DBHelper.getActionableActions()).firstWhere(
        (r) => r['type'] == 'submit_inspection',
      );
      expect(DateTime.tryParse(intent['created_at'] as String), isNotNull);
    },
  );

  fixture.widgetTest(
    'real six-step offline flow preserves GPS photo checklist findings and one final intent',
    (tester) async {
      final originalHttp = HttpOverrides.current;
      final maps = SiteMapHttpFixture();
      HttpOverrides.global = maps;
      addTearDown(() => HttpOverrides.global = originalHttp);
      final messenger = fixture.binding.defaultBinaryMessenger;
      for (final channel in [
        'flutter.baseflow.com/geolocator_updates',
        'hemanthraj/flutter_compass',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (_) async => null,
        );
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(MethodChannel(channel), null),
        );
      }
      const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
      messenger.setMockMethodCallHandler(locationChannel, (call) async {
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'checkPermission') return 3;
        if (call.method == 'getCurrentPosition') {
          return {
            'latitude': 13.8425,
            'longitude': 121.1765,
            'accuracy': 5.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'altitude': 0.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
          };
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(locationChannel, null),
      );
      await tester.runAsync(
        () => DBHelper.cacheJobs([
          {
            'id': offlineJob,
            'assigned_inspector_id': offlineInspector,
            'status': 'assigned',
            'supabase_parcel_id': offlineTask.parcelId,
            'supabase_parcels': {'latitude': 13.8425, 'longitude': 121.1765},
          },
          {
            'id': offlineRound2,
            'assigned_inspector_id': offlineInspector,
            'status': 'assigned',
          },
        ]),
      );
      final photo = await tester.runAsync(() async {
        final file = File('${fixture.directory.path}/workflow-photo.png');
        file.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
        return file;
      });
      // Substitute the camera boundary with a generated image; all six real
      // screens, GPS confirmation, saves and navigation execute production code.
      fixture.provider.addPhoto(
        photoPath: photo!.path,
        photoNotes: 'Workflow evidence',
        latitude: 13.8425,
        longitude: 121.1765,
      );
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        initialStep: 0,
      );
      Future<void> tapAction(String label) async {
        final action = find.text(label);
        // scrollUntilVisible can stop while the widget is still outside the
        // viewport, so drag until it is genuinely tappable.
        for (
          var i = 0;
          i < 12 && action.hitTestable().evaluate().isEmpty;
          i++
        ) {
          await tester.drag(
            find.byType(ListView).first,
            const Offset(0, -220),
            warnIfMissed: false,
          );
          await tester.pump();
        }
        await tester.ensureVisible(action);
        await tester.pump();
        await tester.tap(action);
        await fixture.flush(tester);
        await tester.pump(const Duration(milliseconds: 400));
        await fixture.flush(tester);
      }

      await fixture.mount(tester, SiteMapScreen(task: offlineTask));
      await fixture.flush(tester);
      await tapAction('Proceed to Location');
      expect(find.byType(GpsVerificationScreen), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => DBHelper.getCachedJobs(),
        ))!.firstWhere((r) => r['id'] == offlineJob)['status'],
        'assigned',
      );
      await tapAction('Confirm GPS');
      expect(find.byType(CapturePhotoScreen), findsOneWidget);
      await tapAction('Continue to Checklist');
      expect(find.byType(InspectionChecklistScreen), findsOneWidget);
      await tester.tap(find.text('Structure matches declared use'));
      await fixture.flush(tester);
      await tapAction('Continue to Findings');
      expect(find.byType(FieldFindingsScreen), findsOneWidget);
      for (final (label, value) in [
        ('Site observations', 'Workflow fictional notes'),
        ('Issue details', 'Workflow discrepancy'),
        ('Recommended action', 'Workflow recommendation'),
      ]) {
        final field = find.widgetWithText(TextField, label);
        await tester.scrollUntilVisible(
          field,
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(field, value);
      }
      tester.testTextInput.hide();
      await tester.pump();
      await tapAction('Continue to Review');
      expect(find.byType(ReviewSubmitScreen), findsOneWidget);
      await tapAction('With Discrepancy');
      await tapAction('Submit Inspection');
      await tapAction('Confirm & Submit');
      expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
      expect(find.text('Saved Offline'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.flush(tester);
      await tester.runAsync(fixture.restartDatabase);
      final restored = InspectionProvider();
      await tester.runAsync(() => restored.startInspection(offlineTask));
      expect(restored.currentStep, 5);
      expect(restored.notes, 'Workflow fictional notes');
      expect(restored.discrepancies, 'Workflow discrepancy');
      expect(restored.recommendations, 'Workflow recommendation');
      expect(restored.siteCondition['Structure matches declared use'], isTrue);
      expect(restored.capturedPhotos, hasLength(1));
      expect(photo.existsSync(), isTrue);
      restored.dispose();
      final actions = (await tester.runAsync(
        () => DBHelper.getActionableActions(),
      ))!;
      expect(actions.where((a) => a['type'] == 'gps_confirm'), hasLength(1));
      expect(
        actions.where((a) => a['type'] == 'submit_inspection'),
        hasLength(1),
      );
      expect(fixture.remoteWrites, 0);
      expect(maps.requestedRoutes, isEmpty);
      expect(
        (await tester.runAsync(
          () => DBHelper.getCachedJobs(),
        ))!.firstWhere((r) => r['id'] == offlineRound2)['status'],
        'assigned',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'recovered accepted submit reconciles exact local round without remote replay',
    () async {
      fixture.provider.updateFindings(
        actualLandUse: 'Fixture use',
        notes: 'Fixture findings',
        boundaryStatus: 'Compliant',
        discrepancies: '',
        recommendations: '',
      );
      await fixture.provider.saveAllInspectionState(syncOnline: false);
      await queue();
      final action = (await DBHelper.getActionableActions()).single;
      await DBHelper.markActionSyncing(action['id'] as String);
      await fixture.restartDatabase();
      final writes = <Map<String, dynamic>>[];
      SyncOutboxService.recoveryReadForTesting = (_) async => {
        'id': offlineJob,
        'assigned_inspector_id': offlineInspector,
        'status': 'completed',
        'current_step': 6,
        'submitted_at': '2026-01-01T00:00:00Z',
        'rework_started_at': null,
        'findings': 'Fixture findings',
        'is_compliant': true,
        'inspection_result': 'Compliant',
        'observations': 'Fixture observations',
        'discrepancies': 'Fixture discrepancy',
        'recommendations': 'Fixture recommendation',
        'inspector_notes': 'Fixture findings',
        'checklist_data': [
          {'item': 'Fixture checklist', 'checked': true},
        ],
        'checklist_completed_count': 1,
        'checklist_total_count': 1,
        'photo_paths': [],
        'photo_count': 0,
      };
      SyncOutboxService
          .recoveryWriteForTesting = (id, version, status, values) async {
        writes.add(values);
        throw StateError('Already accepted evidence must never be rewritten');
      };
      await SyncOutboxService.drain(trigger: 'manual');
      await SyncOutboxService.drain(trigger: 'manual');
      expect(writes, isEmpty);
      expect(fixture.remoteWrites, 0);
      expect(
        (await DBHelper.getRecentSyncedActions()).single['id'],
        action['id'],
      );
      final jobs = await DBHelper.getCachedJobs();
      expect(
        jobs.firstWhere((r) => r['id'] == offlineJob)['status'],
        'completed',
      );
      expect(
        jobs.firstWhere((r) => r['id'] == offlineRound2)['status'],
        'assigned',
      );
      expect(await fixture.db.query('inspection_job_retention'), isEmpty);
      fixture.online = true;
      fixture.mode = 'success';
      await fixture.provider.syncToServer();
      expect(
        fixture.remoteWrites,
        0,
        reason:
            'Accepted final evidence must not be replayed later as a legacy draft',
      );
    },
  );

  test(
    'legacy draft drainer defers to preserved final-submit intent',
    () async {
      fixture.provider.updateFindings(
        actualLandUse: 'Fixture use',
        notes: 'Fixture findings',
        boundaryStatus: 'Compliant',
        discrepancies: '',
        recommendations: '',
      );
      await fixture.provider.saveAllInspectionState(syncOnline: false);
      await queue();
      fixture.online = true;
      fixture.mode = 'success';
      await fixture.provider.syncToServer();
      expect(fixture.remoteWrites, 0);
      expect(
        (await DBHelper.getActionableActions()).single['type'],
        'submit_inspection',
      );
    },
  );

  test(
    'pending draft sync never sends an empty or invented assessment',
    () async {
      await fixture.provider.saveAllInspectionState(syncOnline: false);
      acceptProgressPatches();
      await fixture.provider.syncToServer();
      final patches = progressPatchBodies();
      expect(patches, hasLength(1));
      expect(patches.single['findings'], contains('Checklist'));
      expect(
        patches.single.containsKey('inspection_result'),
        isFalse,
        reason:
            'An unselected assessment must never be sent as an empty string '
            'or invented from a missing value.',
      );
    },
  );

  test('recorded assessment syncs verbatim', () async {
    fixture.provider.updateResult('For Review');
    fixture.provider.updateFindings(
      actualLandUse: 'Fixture use',
      notes: 'Fixture findings',
      discrepancies: 'Fictional reason for review',
      recommendations: '',
      boundaryStatus: 'Fixture boundary',
    );
    await fixture.provider.saveAllInspectionState(syncOnline: false);
    acceptProgressPatches();
    await fixture.provider.syncToServer();
    expect(progressPatchBodies().single['inspection_result'], 'For Review');
  });

  test(
    'legacy compliant boundary syncs without inventing a discrepancy',
    () async {
      await fixture.db.insert('local_inspections', {
        'id': offlineRound2,
        'inspector_id': offlineInspector,
        'actual_land_use': 'Fixture use',
        'notes': 'Legacy findings',
        'is_compliant': 1,
        'inspection_result': null,
        'checklist_json': jsonEncode({'Fixture item': true}),
        'boundary_status': 'Compliant',
        'is_synced': 0,
        'updated_at': '2026-01-01T00:00:00Z',
      });
      acceptProgressPatches();
      await fixture.provider.syncToServer();
      expect(progressPatchBodies().single['inspection_result'], 'Compliant');
    },
  );

  for (final wrong in ['round', 'owner', 'step', 'conditional-receipt']) {
    test('recovery refuses $wrong mismatch before local completion', () async {
      await queue();
      final action = (await DBHelper.getActionableActions()).single;
      await DBHelper.markActionSyncing(action['id'] as String);
      final payload = jsonDecode(action['payload'] as String) as Map;
      final accepted = <String, dynamic>{
        'id': offlineJob,
        'assigned_inspector_id': offlineInspector,
        'status': 'completed',
        'current_step': 6,
        'submitted_at': '2026-01-01T00:00:00Z',
        'rework_started_at': null,
        'findings': payload['findings'],
        'is_compliant': true,
        'inspection_result': 'Compliant',
        'observations': 'Fixture observations',
        'discrepancies': 'Fixture discrepancy',
        'recommendations': 'Fixture recommendation',
        'inspector_notes': 'Fixture findings',
        'checklist_data': payload['checklistData'],
        'checklist_completed_count': 1,
        'checklist_total_count': 1,
        'photo_paths': [],
        'photo_count': 0,
      };
      if (wrong == 'round') accepted['id'] = offlineRound2;
      if (wrong == 'owner') {
        accepted['assigned_inspector_id'] = otherOfflineInspector;
      }
      if (wrong == 'step') accepted['current_step'] = 5;
      if (wrong == 'conditional-receipt') {
        final base = '2026-01-01T00:00:00Z';
        await fixture.db.update(
          'pending_actions',
          {
            'payload': jsonEncode({
              ...payload,
              'cachedUpdatedAtSnapshot': base,
            }),
          },
          where: 'id = ?',
          whereArgs: [action['id']],
        );
        accepted['status'] = 'in_progress';
        accepted['updated_at'] = base;
        accepted['submitted_at'] = null;
      }
      SyncOutboxService.recoveryReadForTesting = (_) async => accepted;
      SyncOutboxService.recoveryWriteForTesting =
          (id, version, status, values) async => {
            ...accepted,
            'status': 'in_progress',
          };
      await SyncOutboxService.drain(trigger: 'manual');
      expect(await DBHelper.getRecentSyncedActions(), isEmpty);
      expect(
        (await DBHelper.getCachedJobs()).firstWhere(
          (r) => r['id'] == offlineJob,
        )['status'],
        'in_progress',
      );
      expect(
        (await DBHelper.getSyncCenterQueueActions()).single['status'],
        'conflict',
      );
      expect(await fixture.db.query('inspection_job_retention'), hasLength(1));
    });
  }

  for (final size in [const Size(375, 667), const Size(844, 390)]) {
    fixture.widgetTest(
      'Pending Sync Home action remains usable at $size enlarged text',
      (tester) async {
        await fixture.mount(
          tester,
          const SubmissionSuccessScreen(
            referenceNo: 'DEMO-FS04',
            finalStatus: 'Compliant',
            queuedOffline: true,
          ),
          size: size,
          textScale: 1.5,
        );
        await tester.scrollUntilVisible(
          find.text('Back to Home'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await fixture.flush(tester);
        expect(find.text('Back to Home').hitTestable(), findsOneWidget);
        final button = find.ancestor(
          of: find.text('Back to Home'),
          matching: find.byType(ElevatedButton),
        );
        expect(button, findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await fixture.capture(
          tester,
          size.width < 400
              ? 'pending-sync-small-text'
              : 'pending-sync-landscape-text',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
