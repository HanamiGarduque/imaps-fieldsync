import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/local_data_guard_service.dart';
import 'package:imaps_fieldsync/core/services/inspection_ownership_schema.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'inspector_reassignment_test.dart'
    show signInInspector, inspectorA, inspectorB;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://provenance.test',
      publishableKey: 'fixture',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() async {
    final secureValues = <String, String>{'sp_local_data_owner_id': inspectorA};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (call.method == 'read') return secureValues[args['key']];
        if (call.method == 'write') secureValues[args['key']] = args['value'];
        return null;
      },
    );
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final m in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await signInInspector(inspectorA);
    await DBHelper.cacheJobs([
      {'id': 'job', 'status': 'assigned'},
    ]);
  });
  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<void> capture() async {
    await DBHelper.retainInspectionJob('job');
    await DBHelper.saveInspectionLocally(
      jobId: 'job',
      actualLandUse: 'field observation',
      notes: 'original evidence',
      isCompliant: false,
      inspectionResult: 'For Review',
      checklist: {'setback': false},
      boundaryStatus: 'observed',
      currentStep: 3,
    );
    await DBHelper.savePhotoLocally(
      photoId: 'photo',
      jobId: 'job',
      photoPath: '/fixture/photo.jpg',
      notes: 'photo evidence',
      latitude: 1,
      longitude: 2,
    );
    await SyncOutboxService.enqueueMarkOngoing(jobId: 'job');
  }

  test(
    'new inspection, photo, retention and action record creation inspector',
    () async {
      await capture();
      for (final table in [
        'local_jobs',
        'local_inspections',
        'local_photos',
        'inspection_job_retention',
        'pending_actions',
      ]) {
        expect(
          (await db.query(table)).single['inspector_id'],
          inspectorA,
          reason: table,
        );
      }
    },
  );

  test(
    'B cannot read, overwrite, or acknowledge A evidence or queued work',
    () async {
      await capture();
      final before = <String, Object>{};
      for (final t in [
        'local_jobs',
        'local_inspections',
        'local_photos',
        'inspection_job_retention',
        'pending_actions',
      ]) {
        before[t] = await db.query(t);
      }
      await signInInspector(inspectorB);
      expect(await DBHelper.getLocalInspection('job'), isNull);
      expect(await DBHelper.getLocalPhotos('job'), isEmpty);
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect(await DBHelper.getCachedJobs(), isEmpty);
      await expectLater(capture(), throwsStateError);
      await DBHelper.markPhotoSynced('photo');
      await DBHelper.markInspectionSynced('job');
      await DBHelper.markActionSyncing('mark_ongoing_job');
      await DBHelper.markActionSynced('mark_ongoing_job');
      for (final t in before.keys) {
        expect(await db.query(t), before[t], reason: t);
      }
      await signInInspector(inspectorA);
      expect(
        (await DBHelper.getLocalInspection('job'))!['notes'],
        'original evidence',
      );
      expect(await DBHelper.getActionableActions(), hasLength(1));
    },
  );

  test(
    'legacy NULL owner evidence stays stored, hidden, unclaimed on login and drain',
    () async {
      await db.insert('local_inspections', {
        'id': 'legacy',
        'notes': 'do not infer',
      });
      await db.insert('local_photos', {
        'id': 'legacy-photo',
        'job_id': 'legacy',
        'photo_path': '/fixture/legacy.jpg',
      });
      await db.insert('inspection_job_retention', {
        'job_id': 'legacy',
        'retained_at': '2026-01-01',
      });
      await db.insert('pending_actions', {
        'id': 'legacy-action',
        'type': 'mark_ongoing',
        'job_id': 'legacy',
        'payload': '{}',
        'status': 'syncing',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
      });
      await signInInspector(inspectorB);
      expect(await DBHelper.getLocalInspection('legacy'), isNull);
      expect(await DBHelper.getLocalPhotos('legacy'), isEmpty);
      expect(await DBHelper.getActionableActions(), isEmpty);
      await SyncOutboxService.drain();
      expect((await db.query('pending_actions')).single['status'], 'syncing');
      expect(
        (await db.query('pending_actions')).single['inspector_id'],
        isNull,
      );
      expect(
        (await db.query('local_inspections')).single['notes'],
        'do not infer',
      );
    },
  );

  test(
    'account reconciliation preserves foreign draft even with no pending action',
    () async {
      await DBHelper.saveInspectionLocally(
        jobId: 'job',
        actualLandUse: '',
        notes: 'draft only',
        isCompliant: false,
        inspectionResult: 'For Review',
        checklist: {},
        boundaryStatus: '',
      );
      await signInInspector(inspectorB);
      expect(
        await LocalDataGuardService.reconcileLocalDataOwnership(inspectorB),
        LocalDataReconcileResult.ok,
      );
      expect(
        (await db.query('local_inspections')).single['notes'],
        'draft only',
      );
      expect(
        (await db.query('local_inspections')).single['inspector_id'],
        inspectorA,
      );
    },
  );

  test(
    'unproven final submission preserves lifecycle retention and all evidence',
    () async {
      await capture();
      final inspection = await db.query('local_inspections');
      final photos = await db.query('local_photos');
      final retention = await db.query('inspection_job_retention');
      await SyncOutboxService.enqueueSubmitInspection(
        jobId: 'job',
        findings: 'preserved payload',
        isCompliant: false,
        inspectionResult: 'For Review',
        observations: 'observed',
        inspectorNotes: 'notes',
        checklistData: [],
        checklistCompletedCount: 0,
        checklistTotalCount: 0,
        photosData: [],
      );
      expect((await DBHelper.getCachedJobs()).single['status'], 'in_progress');
      expect(await db.query('local_inspections'), inspection);
      expect(await db.query('local_photos'), photos);
      expect(await db.query('inspection_job_retention'), retention);
      expect(
        (await db.query(
          'pending_actions',
          where: "type = 'submit_inspection'",
        )).single['payload'],
        contains('preserved payload'),
      );
      expect(await DBHelper.finalizeAcceptedOnlineInspection('job'), isFalse);
      expect(await db.query('inspection_job_retention'), retention);
    },
  );

  test(
    'in-flight enqueue cannot attribute A payload to the next login',
    () async {
      final future = SyncOutboxService.enqueueFindingsUpdate(
        jobId: 'new-job',
        observations: 'A-only observations',
        discrepancies: null,
        recommendations: null,
        inspectorNotes: 'A-only notes',
      );
      final check = expectLater(future, throwsStateError);
      await signInInspector(inspectorB);
      await check;
      expect(await db.query('pending_actions'), isEmpty);
    },
  );

  test(
    'rework hydration never carries a prior session field observation',
    () async {
      final provider = InspectionProvider();
      await provider.startInspection(
        TaskItem(
          id: 'job',
          name: 'fixture',
          location: 'fixture',
          parcels: 'fixture',
          status: 'in_progress',
          inspectionNo: 'fixture',
        ),
      );
      provider.updateFindings(
        actualLandUse: 'A-only observed land use',
        notes: 'A-only notes',
        discrepancies: 'A-only discrepancy',
        recommendations: '',
        boundaryStatus: 'observed',
      );
      provider.setSiteCondition('Structure matches declared use', false);
      provider.dispose();

      // A partial rework payload (the common case: no stored checklist entries)
      // must start from clean, unchecked defaults — not the previous session's
      // answers and not a pre-checked pass.
      final next = InspectionProvider();
      next.hydrateForRework(
        TaskItem.fromJob({
          'id': 'job-rework',
          'status': 'completed',
          'current_step': 6,
          'checklist_data': <dynamic>[],
        }),
      );
      expect(next.notes, isEmpty);
      expect(next.discrepancies, isEmpty);
      expect(next.actualLandUse, 'Single-detached residential');
      expect(next.siteCondition['Structure matches declared use'], isFalse);
      expect(next.capturedPhotos, isEmpty);
      next.dispose();
    },
  );

  test(
    'rework hydration by another inspector exposes no prior field state',
    () async {
      final provider = InspectionProvider();
      await provider.startInspection(
        TaskItem(
          id: 'job',
          name: 'fixture',
          location: 'fixture',
          parcels: 'fixture',
          status: 'in_progress',
          inspectionNo: 'fixture',
        ),
      );
      provider.updateFindings(
        actualLandUse: 'A-only observed land use',
        notes: 'A-only notes',
        discrepancies: '',
        recommendations: '',
        boundaryStatus: 'observed',
      );
      await signInInspector(inspectorB);
      // B hydrates the same completed job: nothing from A's session may appear.
      provider.hydrateForRework(
        TaskItem.fromJob({
          'id': 'job-rework',
          'status': 'completed',
          'current_step': 6,
          'checklist_data': <dynamic>[],
        }),
      );
      expect(provider.notes, isEmpty);
      expect(provider.discrepancies, isEmpty);
      expect(provider.actualLandUse, 'Single-detached residential');
      provider.dispose();
      await signInInspector(inspectorA);
    },
  );

  test(
    'in-memory draft becomes hidden and non-actionable after account switch',
    () async {
      final provider = InspectionProvider();
      await provider.startInspection(
        TaskItem(
          id: 'job',
          name: 'fixture',
          location: 'fixture',
          parcels: 'fixture',
          status: 'in_progress',
          inspectionNo: 'fixture',
        ),
      );
      provider.updateFindings(
        actualLandUse: 'observed',
        notes: 'A-only draft',
        discrepancies: '',
        recommendations: '',
        boundaryStatus: 'observed',
      );
      await signInInspector(inspectorB);
      expect(provider.notes, isEmpty);
      expect(provider.activeTask, isNull);
      expect(provider.capturedPhotos, isEmpty);
      await expectLater(provider.saveAllInspectionState(), throwsStateError);
      await signInInspector(inspectorA);
      expect(provider.notes, 'A-only draft');
      provider.dispose();
    },
  );

  test(
    'session switch during recovery prevents replay and acknowledgement',
    () async {
      await capture();
      await DBHelper.markActionSyncing('mark_ongoing_job');
      final readStarted = Completer<void>();
      final releaseRead = Completer<Map<String, dynamic>?>();
      SyncOutboxService.resetRecoverySessionForTesting();
      SyncOutboxService.recoveryReadForTesting = (_) {
        readStarted.complete();
        return releaseRead.future;
      };
      var writes = 0;
      SyncOutboxService.recoveryWriteForTesting = (_, _, _, _) async {
        writes++;
        return null;
      };
      final drain = SyncOutboxService.drain();
      await readStarted.future;
      await signInInspector(inspectorB);
      releaseRead.complete({
        'id': 'job',
        'status': 'assigned',
        'updated_at': '2026-01-01',
      });
      await drain;
      expect(writes, 0);
      expect((await db.query('pending_actions')).single['status'], 'syncing');
      expect(
        (await db.query('pending_actions')).single['inspector_id'],
        inspectorA,
      );
      SyncOutboxService.resetRecoverySessionForTesting();
    },
  );

  test(
    'v17 additive upgrade preserves every v16 row and leaves owners NULL',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        final source = File(
          'lib/core/services/db_helper.dart',
        ).readAsStringSync().replaceAll(RegExp(r'\s*,inspector_id TEXT'), '');
        for (final m in RegExp(
          r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
        ).allMatches(source)) {
          await legacy.execute(m.group(0)!);
        }
        await legacy.insert('local_jobs', {
          'id': 'old-job',
          'status': 'in_progress',
        });
        await legacy.insert('local_inspections', {
          'id': 'old-job',
          'notes': 'legacy original',
          'current_step': 3,
        });
        await legacy.insert('local_photos', {
          'id': 'old-photo',
          'job_id': 'old-job',
          'photo_path': '/legacy.jpg',
        });
        await legacy.insert('inspection_job_retention', {
          'job_id': 'old-job',
          'retained_at': '2026-01-01',
        });
        await legacy.insert('pending_actions', {
          'id': 'old-action',
          'type': 'mark_ongoing',
          'job_id': 'old-job',
          'payload': '{}',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        });
        final before = <String, List<Map<String, Object?>>>{};
        for (final t in InspectionOwnershipSchema.tables) {
          before[t] = await legacy.query(t);
        }
        await InspectionOwnershipSchema.applyV17(legacy);
        await InspectionOwnershipSchema.applyV17(legacy);
        for (final t in before.keys) {
          final after = await legacy.query(t);
          expect(
            after,
            before[t]!.map((r) => {...r, 'inspector_id': null}).toList(),
            reason: t,
          );
        }
      } finally {
        await legacy.close();
      }
    },
  );
}
