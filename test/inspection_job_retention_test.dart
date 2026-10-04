import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_completion_persistence_test.dart' show submitFixture;

const jobA = '11111111-1111-4111-8111-111111111111';
const jobB = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> fetchedJob(String id, {String status = 'in_progress'}) => {
  'id': id,
  'status': status,
  'local_inspection_id': 123,
  'supabase_parcel_id': '33333333-3333-4333-8333-333333333333',
  'updated_at': '2026-09-17T00:00:00Z',
  'supabase_zoning_applications': {
    'applicant_name': 'Isolated applicant',
    'barangay': 'Fixture barangay',
    'reference_number': 'FIXTURE-123',
    'application_type': 'Residential',
  },
  'supabase_parcels': {
    'latitude': 14.5,
    'longitude': 121.0,
    'lot_area_sqm': 200.0,
    'declared_land_use': 'Residential',
    'address': 'Isolated address',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temporary;
  late Database db;
  late String path;
  late String source;

  Future<void> reopen() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    db = await databaseFactoryFfi.openDatabase(path);
    DBHelper.useDatabaseForTesting(db);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fieldsync-r2a-');
    path = '${temporary.path}/fixture.db';
    db = await databaseFactoryFfi.openDatabase(path);
    source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temporary.delete(recursive: true);
  });

  for (final resume in [false, true]) {
    testWidgets('real normal ParcelDetail entry with Dashboard payload, resume=$resume', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      // Use an SDK font as an isolated rendering fixture, never fetch fonts.
      final fontDirectory = Directory('${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts');
      final fontFile = fontDirectory.listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.ttf'));
      final fontBytes = ByteData.sublistView(fontFile.readAsBytesSync());
      final manifest = <String, Object>{};
      for (final family in ['Inter', 'Poppins', 'Urbanist', 'JetBrainsMono', 'Roboto']) {
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Light']) {
          final asset = '$family-$weight.ttf';
          manifest[asset] = [{'asset': asset}];
        }
      }
      tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
        final asset = const StringCodec().decodeMessage(message)!;
        if (asset == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(manifest);
        if (asset.endsWith('.ttf')) return fontBytes;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null));
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      final payload = fetchedJob(jobA, status: 'assigned')..['current_step'] = 5;
      // Step 6 is an unlocked normal step on this remotely-progressed fixture;
      // using it avoids unrelated GPS/map platform I/O in this entry test.
      if (resume) {
        await tester.runAsync(() async {
          await DBHelper.saveInspectionLocally(jobId: jobA, actualLandUse: 'Residential',
            notes: 'Unfinished restored notes', isCompliant: true,
            inspectionResult: 'Compliant', checklist: {}, boundaryStatus: 'Compliant', currentStep: 5);
        });
      }
      final provider = InspectionProvider();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(home: ParcelDetailScreen(
          task: TaskItem.fromJob(payload), fetchedJob: payload,
        )),
      ));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(await DBHelper.getCachedJobs(), isEmpty);
        expect(await db.query('inspection_job_retention'), isEmpty);
      });
      if (resume) {
        expect(provider.notes, 'Unfinished restored notes');
      }
      final step = find.text('Review & Submit');
      await tester.ensureVisible(step);
      await tester.tap(step);
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSubmitScreen), findsOneWidget);
      expect(find.byType(TasksScreen), findsNothing);
      await tester.runAsync(() async {
        final row = (await DBHelper.getCachedJobs()).single;
        expect(row['id'], jobA);
        expect(row['status'], 'assigned');
        expect(row['applicant_name'], 'Isolated applicant');
        expect(row['parcel_lat'], 14.5);
        expect(row['local_inspection_id'], 123);
        expect((await db.query('inspection_job_retention')).single['job_id'], jobA);
        await submitFixture(jobA);
        expect((await DBHelper.getCachedJobs()).single['status'], 'completed');
        expect(await db.query('inspection_job_retention'), isEmpty);
        expect((await DBHelper.getActionableActions()).single['job_id'], jobA);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      provider.dispose();
      InspectionProgress.instance.reset();
      await tester.binding.setSurfaceSize(null);
    });
  }

  test('Dashboard forwards actual payload without passive caching; rework excluded', () async {
    final home = await File('lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart').readAsString();
    expect(home, contains("job['id'] as String: job"));
    expect(home, contains('fetchedJob: _entryJobs[_upcomingTasks[index].id]'));
    expect(home, isNot(contains('DBHelper.cacheJobs(')));
    final completed = await File('lib/modules/inspection/screens/completed_inspection_detail_screen.dart').readAsString();
    final provider = await File('lib/modules/inspection/providers/inspection_provider.dart').readAsString();
    expect(completed, isNot(contains('retainInspectionJob')));
    expect(provider, isNot(contains('retainInspectionJob')));
    final review = await File('lib/modules/inspection/screens/review_submit_screen.dart').readAsString();
    expect(review, contains('if (!queuedOffline && !provider.isReworkMode)'));
    expect(review.indexOf('finalizeAcceptedOnlineInspection'), greaterThan(review.indexOf('queuedOffline = true')));
  });

  test('fresh schema and version 9->12 upgrade preserve all prior rows and current metadata', () async {
    final legacyTemp = await Directory.systemTemp.createTemp('legacy-v9-');
    addTearDown(() async {
      if (legacyTemp.existsSync()) {
        await legacyTemp.delete(recursive: true);
      }
    });
    final legacyPath = '${legacyTemp.path}/legacy_v9_upgrade.db';
    Database? legacyDb;
    Database? upgradedDb;
    try {
      legacyDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE local_jobs(
              id TEXT PRIMARY KEY,
              local_inspection_id INTEGER,
              status TEXT,
              scheduled_date TEXT,
              deadline_date TEXT,
              is_self_scheduled INTEGER DEFAULT 0,
              supabase_parcel_id TEXT,
              applicant_name TEXT,
              barangay TEXT,
              reference_number TEXT,
              application_type TEXT,
              cached_updated_at TEXT,
              rework_started_at TEXT,
              parcel_lat REAL,
              parcel_lng REAL,
              lot_area_sqm REAL,
              declared_land_use TEXT,
              parcel_address TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE local_inspections(
              id TEXT PRIMARY KEY,
              actual_land_use TEXT,
              notes TEXT,
              is_compliant INTEGER,
              inspection_result TEXT,
              checklist_json TEXT,
              boundary_status TEXT,
              current_step INTEGER DEFAULT 0,
              step_timestamps TEXT,
              is_synced INTEGER DEFAULT 0,
              updated_at TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE pending_actions(
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              job_id TEXT NOT NULL,
              payload TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              retry_count INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.insert('local_jobs', {
            'id': jobA,
            'status': 'in_progress',
            'scheduled_date': '2026-10-01',
            'supabase_parcel_id': 'parcel-a',
            'applicant_name': 'Legacy applicant',
            'barangay': 'Legacy barangay',
            'reference_number': 'LEG-1',
            'application_type': 'Residential',
          });
          await database.insert('local_inspections', {'id': jobA, 'notes': 'Saved draft'});
          await database.insert('pending_actions', {
            'id': 'prior-action', 'job_id': jobA, 'type': 'mark_ongoing',
            'payload': '{}', 'created_at': 'prior', 'updated_at': 'prior',
          });
        },
      ),
    );
      await legacyDb.close();
      legacyDb = null;

      upgradedDb = await databaseFactoryFfi.openDatabase(legacyPath, options: OpenDatabaseOptions(
        version: 13,
        onUpgrade: (database, oldVersion, newVersion) async {
          expect(oldVersion, 9);
          if (oldVersion < 10) {
            await DBHelper.createInspectionRetentionTable(database);
          }
          if (oldVersion < 11) {
            await database.execute(
              'ALTER TABLE local_jobs ADD COLUMN assignment_instructions TEXT',
            );
            await database.execute(
              'ALTER TABLE local_jobs ADD COLUMN assigned_by_imaps_user_id TEXT',
            );
            await database.execute(
              'ALTER TABLE local_jobs ADD COLUMN assigned_by_name TEXT',
            );
          }
          // Loop 8: an existing v11 install must gain the optional read-only
          // Planning Review cache column without losing any cached task.
          if (oldVersion < 12) {
            await database.execute(
              'ALTER TABLE local_jobs ADD COLUMN planning_review TEXT',
            );
          }
          // Offline/online list parity: the Completed category is sorted by
          // submitted_at, so the cached column must exist after upgrade too.
          if (oldVersion < 13) {
            await database.execute(
              'ALTER TABLE local_jobs ADD COLUMN submitted_at TEXT',
            );
          }
        },
      ));
      DBHelper.useDatabaseForTesting(upgradedDb);

      expect(await upgradedDb.getVersion(), 13);
      expect(await upgradedDb.query('inspection_job_retention'), isEmpty);
      expect((await upgradedDb.query('local_jobs')).single['id'], jobA);
      expect((await upgradedDb.query('local_inspections')).single['notes'], 'Saved draft');
      expect((await upgradedDb.query('pending_actions')).single['id'], 'prior-action');

      final localJobColumns = (await upgradedDb.rawQuery('PRAGMA table_info(local_jobs)'))
          .map((row) => row['name'] as String)
          .toList();
      expect(localJobColumns, containsAll([
        'assignment_instructions',
        'assigned_by_imaps_user_id',
        'assigned_by_name',
        'planning_review',
        'submitted_at',
      ]));

      expect(source, contains('version: 14,'));
      expect(source, contains('if (oldVersion < 10)'));
      expect(source, contains('if (oldVersion < 11)'));
      expect(source, contains('if (oldVersion < 12)'));
      expect(source, contains('if (oldVersion < 13)'));
      expect(source, contains('if (oldVersion < 14)'));
      expect(RegExp(r'ALTER TABLE local_jobs ADD COLUMN assignment_instructions TEXT').allMatches(source), hasLength(1));
      expect(RegExp(r'ALTER TABLE local_jobs ADD COLUMN planning_review TEXT').allMatches(source), hasLength(1));
      expect(RegExp(r'ALTER TABLE local_jobs ADD COLUMN submitted_at TEXT').allMatches(source), hasLength(1));
      expect(RegExp(r'await createInspectionRetentionTable\(db\)').allMatches(source), hasLength(2));
    } finally {
      if (upgradedDb != null && upgradedDb.isOpen) {
        await upgradedDb.close();
      }
      if (legacyDb != null && legacyDb.isOpen) {
        await legacyDb.close();
      }
      DBHelper.useDatabaseForTesting(null);
    }
  });

  test('Tasks cache then repeated entry has one row and one marker', () async {
    await DBHelper.cacheJobs([fetchedJob(jobA, status: 'Pending')]);
    expect(await db.query('inspection_job_retention'), isEmpty);
    await DBHelper.retainInspectionJob(jobA);
    final first = (await db.query('inspection_job_retention')).single;
    await DBHelper.retainInspectionJob(jobA);
    expect((await DBHelper.getCachedJobs()).single['status'], 'Pending');
    expect((await db.query('inspection_job_retention')).single, first);
  });

  test('unfinished retention survives leave restart and omission without lifecycle change', () async {
    await DBHelper.cacheJobs([fetchedJob(jobA), fetchedJob(jobB)]);
    await DBHelper.retainInspectionJob(jobA);
    await reopen();
    await DBHelper.cacheJobs([]);
    expect((await DBHelper.getCachedJobs()).single['id'], jobA);
    expect((await DBHelper.getCachedJobs()).single['status'], 'in_progress');
    expect((await db.query('inspection_job_retention')).single['job_id'], jobA);
  });

  test('active remote metadata updates and canonical completion retires only A', () async {
    await DBHelper.retainInspectionJob(jobA, fetchedJob: fetchedJob(jobA));
    await DBHelper.retainInspectionJob(jobB, fetchedJob: fetchedJob(jobB));
    final updated = fetchedJob(jobA)..['deadline_date'] = '2026-10-01';
    await DBHelper.cacheJobs([updated]);
    expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == jobA)['deadline_date'], '2026-10-01');
    expect(await db.query('inspection_job_retention'), hasLength(2));
    await DBHelper.cacheJobs([fetchedJob(jobA, status: 'completed')]);
    expect((await db.query('inspection_job_retention')).single['job_id'], jobB);
    expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == jobA)['status'], 'completed');
  });

  for (final entry in {'pending_actions': 'INSERT', 'local_jobs': 'UPDATE', 'inspection_job_retention': 'DELETE'}.entries) {
    test('offline failure at ${entry.key} rolls back all three effects', () async {
      await DBHelper.retainInspectionJob(jobA, fetchedJob: fetchedJob(jobA));
      await db.execute('CREATE TRIGGER reject_write BEFORE ${entry.value} ON ${entry.key} '
          "BEGIN SELECT RAISE(ABORT, 'isolated failure'); END");
      await expectLater(submitFixture(jobA), throwsA(isA<DatabaseException>()));
      expect(await DBHelper.getActionableActions(), isEmpty);
      expect((await DBHelper.getCachedJobs()).single['status'], 'in_progress');
      expect((await db.query('inspection_job_retention')).single['job_id'], jobA);
    });
  }

  test('online cleanup is idempotent isolated and failure leaves recovery evidence', () async {
    await DBHelper.retainInspectionJob(jobA, fetchedJob: fetchedJob(jobA));
    await DBHelper.cacheJobs([fetchedJob(jobB)]);
    await db.execute("CREATE TRIGGER reject_cleanup BEFORE DELETE ON inspection_job_retention BEGIN SELECT RAISE(ABORT, 'cleanup failure'); END");
    expect(await DBHelper.finalizeAcceptedOnlineInspection(jobA), isFalse);
    expect((await db.query('inspection_job_retention')).single['job_id'], jobA);
    expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == jobA)['status'], 'in_progress');
    expect(await DBHelper.getActionableActions(), isEmpty);
    await db.execute('DROP TRIGGER reject_cleanup');
    expect(await DBHelper.finalizeAcceptedOnlineInspection(jobA), isTrue);
    expect(await DBHelper.finalizeAcceptedOnlineInspection(jobA), isTrue);
    expect(await db.query('inspection_job_retention'), isEmpty);
    expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == jobB)['status'], 'in_progress');
  });

  test('missing or mismatched UUID rejects entry without marker or fake row', () async {
    await expectLater(DBHelper.retainInspectionJob(jobA), throwsStateError);
    await expectLater(DBHelper.retainInspectionJob(jobA, fetchedJob: fetchedJob(jobB)), throwsStateError);
    expect(await DBHelper.getCachedJobs(), isEmpty);
    expect(await db.query('inspection_job_retention'), isEmpty);
  });

  test('offline completion survives restart by pending protection, then releases', () async {
    await DBHelper.retainInspectionJob(jobA, fetchedJob: fetchedJob(jobA));
    await DBHelper.cacheJobs([fetchedJob(jobB)]);
    expect(await db.query('inspection_job_retention'), hasLength(1));
    await submitFixture(jobA);
    expect(await db.query('inspection_job_retention'), isEmpty);
    final action = (await DBHelper.getActionableActions()).single;
    await reopen();
    await DBHelper.cacheJobs([fetchedJob(jobB)]);
    final cached = await DBHelper.getCachedJobs();
    expect(cached.firstWhere((j) => j['id'] == jobA)['status'], 'completed');
    expect(cached.firstWhere((j) => j['id'] == jobB)['status'], 'in_progress');
    expect((await DBHelper.getActionableActions()).single['id'], action['id']);
    expect(await db.query('inspection_job_retention'), isEmpty);
    await DBHelper.markActionSyncing(action['id'] as String);
    await DBHelper.markActionSynced(action['id'] as String);
    await DBHelper.cacheJobs([fetchedJob(jobA, status: 'completed'), fetchedJob(jobB)]);
    expect((await DBHelper.getCachedJobs()).firstWhere((j) => j['id'] == jobA)['status'], 'completed');
    await DBHelper.cacheJobs([fetchedJob(jobB)]);
    expect((await DBHelper.getCachedJobs()).single['id'], jobB);
  });
}
