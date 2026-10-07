// Application Support task population: online refresh, offline cache fallback,
// exact identity, and selection retention.
//
// Pure data + the real `local_jobs` cache against an isolated temporary
// database. No network.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/reportable_tasks.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';

const _app = 'app-uuid-1';
const _source = 'rosario-imaps-local-0921-a';

Map<String, dynamic> remoteJob(String id, {String? appId, String? source}) => {
  'id': id,
  'status': 'assigned',
  'local_inspection_id': null,
  'scheduled_date': '2026-10-01',
  'deadline_date': null,
  'is_self_scheduled': false,
  'supabase_parcel_id': null,
  'supabase_application_id': appId,
  'bridge_source_id': source,
  'application_type': 'New Application',
  'supabase_zoning_applications': {
    'reference_number': 'APP-2026-00030',
    'applicant_name': 'Dela Cruz, Juan',
    'barangay': 'Poblacion',
    'application_type': 'New Application',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late Database db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fieldsync-tasks-');
    db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/tasks.db',
      options: OpenDatabaseOptions(
        // The current schema version and its round/reinspection context columns:
        // cacheJobs() writes them, so a stale fixture column list would fail the
        // write and empty the very cache path under test.
        version: 18,
        onCreate: (database, _) async {
          await database.execute('''
          CREATE TABLE local_jobs(
            id TEXT PRIMARY KEY,
            local_inspection_id INTEGER,
            inspection_round_number INTEGER,
            previous_site_inspection_id INTEGER,
            reinspection_reason TEXT,
            reinspection_reviewed_at TEXT,
            status TEXT,
            scheduled_date TEXT,
            deadline_date TEXT,
            is_self_scheduled INTEGER DEFAULT 0,
            supabase_parcel_id TEXT,
            applicant_name TEXT,
            barangay TEXT,
            reference_number TEXT,
            application_type TEXT,
            assignment_instructions TEXT,
            assigned_by_imaps_user_id TEXT,
            assigned_by_name TEXT,
            planning_review TEXT,
            submitted_at TEXT,
            cached_updated_at TEXT,
            rework_started_at TEXT,
            parcel_lat REAL,
            parcel_lng REAL,
            lot_area_sqm REAL,
            declared_land_use TEXT,
            parcel_address TEXT,
            supabase_application_id TEXT,
            bridge_source_id TEXT,
            inspector_id TEXT
          )
        ''');
          // cacheJobs() reads both of these through the existing retention and
          // outbox paths.
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
            updated_at TEXT NOT NULL,
            inspector_id TEXT
          )
        ''');
          await database.execute('''
          CREATE TABLE inspection_job_retention(
            job_id TEXT PRIMARY KEY,
            retained_at TEXT NOT NULL,
            inspector_id TEXT
          )
        ''');
        },
      ),
    );
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
    ReportableTasks.resetTestHooks();
    ReportQueueService.resetTestHooks();
  });

  tearDown(() async {
    ReportableTasks.resetTestHooks();
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the handle briefly; harmless for a temp dir.
      }
    }
  });

  Future<void> cacheRow(Map<String, dynamic> row) async {
    await db.insert('local_jobs', {
      'id': row['id'],
      'status': row['status'],
      'scheduled_date': row['scheduled_date'],
      'deadline_date': null,
      'is_self_scheduled': 0,
      'supabase_parcel_id': null,
      'applicant_name': 'Dela Cruz, Juan',
      'barangay': 'Poblacion',
      'reference_number': 'APP-2026-00030',
      'application_type': 'New Application',
      'supabase_application_id': row['supabase_application_id'],
      'bridge_source_id': row['bridge_source_id'],
      'inspector_id': ownerFixture,
    });
  }

  group('online task source', () {
    test(
      'uses the inspector-scoped reads and writes through the cache path',
      () async {
        var assignedCalls = 0;
        var completedCalls = 0;
        ReportableTasks.onlineOverride = () async => true;
        ReportableTasks.assignedJobsOverride = () async {
          assignedCalls++;
          return [remoteJob('job-online', appId: _app, source: _source)];
        };
        ReportableTasks.completedJobsOverride = () async {
          completedCalls++;
          return [
            {
              ...remoteJob('job-done', appId: 'app-uuid-2', source: _source),
              'status': 'completed',
            },
          ];
        };

        final tasks = await ReportableTasks.loadForInspector();
        expect(assignedCalls, 1);
        expect(completedCalls, 1);
        expect(tasks.map((t) => t.fieldJobId).toSet(), {
          'job-online',
          'job-done',
        });

        // Written through the EXISTING local_jobs cache path, so the identity is
        // available offline afterwards.
        final cached = await ReportableTasks.loadForInspector();
        ReportableTasks.onlineOverride = () async => false;
        final offline = await ReportableTasks.loadForInspector();
        expect(
          offline.map((t) => t.fieldJobId).toSet(),
          cached.map((t) => t.fieldJobId).toSet(),
        );
      },
    );

    test(
      'a failed refresh falls back to the cache instead of emptying it',
      () async {
        await cacheRow(remoteJob('job-cached', appId: _app, source: _source));
        ReportableTasks.onlineOverride = () async => true;
        ReportableTasks.assignedJobsOverride = () async =>
            throw Exception('network down');
        ReportableTasks.completedJobsOverride = () async => const [];

        final tasks = await ReportableTasks.loadForInspector();
        expect(
          tasks.map((t) => t.fieldJobId),
          ['job-cached'],
          reason: 'a failed refresh must never hide a usable cached population',
        );
      },
    );
  });

  group('offline task source', () {
    test('uses cached local_jobs only and performs no remote read', () async {
      await cacheRow(remoteJob('job-offline', appId: _app, source: _source));
      var remoteReads = 0;
      ReportableTasks.onlineOverride = () async => false;
      ReportableTasks.assignedJobsOverride = () async {
        remoteReads++;
        return const [];
      };

      final tasks = await ReportableTasks.loadForInspector();
      expect(remoteReads, 0, reason: 'offline must not touch the network');
      expect(tasks.single.fieldJobId, 'job-offline');
    });

    test(
      'an upgraded v14 row with NULL identity is readable but ineligible',
      () async {
        await cacheRow(remoteJob('job-legacy'));
        ReportableTasks.onlineOverride = () async => false;

        final task = (await ReportableTasks.loadForInspector()).single;
        expect(task.fieldJobId, 'job-legacy');
        expect(task.supabaseApplicationId, isNull);
        expect(task.bridgeSourceId, isNull);
        expect(task.identityComplete, isFalse);
      },
    );
  });

  group('exact identity', () {
    test('is carried verbatim from the job row, never inferred', () {
      final task = ReportableTask.fromRow(
        remoteJob('job-x', appId: 'app-uuid-9', source: 'some-other-source'),
      );
      expect(task.fieldJobId, 'job-x');
      expect(task.supabaseApplicationId, 'app-uuid-9');
      expect(task.bridgeSourceId, 'some-other-source');
      expect(task.identityComplete, isTrue);
    });

    test('a partial identity is never completed from anything else', () {
      final onlyApp = ReportableTask.fromRow(
        remoteJob('job-y', appId: 'app-uuid-9'),
      );
      expect(onlyApp.supabaseApplicationId, 'app-uuid-9');
      expect(onlyApp.bridgeSourceId, isNull);
      expect(onlyApp.identityComplete, isFalse);

      final onlySource = ReportableTask.fromRow(
        remoteJob('job-z', source: 'some-other-source'),
      );
      expect(onlySource.identityComplete, isFalse);
    });

    test('display text never leaks a raw UUID', () {
      final task = ReportableTask.fromRow(
        remoteJob('job-d', appId: 'app-uuid-9', source: 'src-uuid-9'),
      );
      expect(task.displayTitle, contains('APP-2026-00030'));
      expect(task.displayTitle, isNot(contains('app-uuid-9')));
      expect(task.displayTitle, isNot(contains('job-d')));
      expect(task.displayTitle, isNot(contains('src-uuid-9')));
    });

    test('the PostgREST FK-alias embed is read like the plain one', () {
      final row = remoteJob('job-alias', appId: _app, source: _source)
        ..remove('supabase_zoning_applications');
      row['supabase_zoning_applications!field_jobs_supabase_application_id_fkey'] =
          {
            'reference_number': 'APP-2026-00077',
            'applicant_name': 'Santos, Maria',
            'barangay': 'Bagong Silang',
          };
      final task = ReportableTask.fromRow(row);
      expect(task.referenceNumber, 'APP-2026-00077');
      expect(task.applicantName, 'Santos, Maria');
      expect(task.barangay, 'Bagong Silang');
    });
  });

  group('selection retention', () {
    final population = [
      ReportableTask.fromRow(remoteJob('job-1', appId: _app, source: _source)),
      ReportableTask.fromRow(
        remoteJob('job-2', appId: 'app-uuid-2', source: _source),
      ),
    ];

    test('survives a rebuild with the same population', () {
      final selected = population.first;
      final kept = ReportableTasks.retainSelection(population, selected);
      expect(kept?.fieldJobId, 'job-1');
      expect(kept?.supabaseApplicationId, _app);
      expect(kept?.bridgeSourceId, _source);
    });

    test('survives an async refresh that reorders the population', () {
      final selected = population.first;
      final reordered = population.reversed.toList();
      final kept = ReportableTasks.retainSelection(reordered, selected);
      expect(
        kept?.fieldJobId,
        'job-1',
        reason: 'retention is by exact field_job_id, not list position',
      );
    });

    test('re-binds to the refreshed authoritative identity', () {
      final stale = ReportableTask.fromRow(
        remoteJob('job-1', appId: 'app-old', source: 'source-old'),
      );
      final refreshed = ReportableTask.fromRow(
        remoteJob('job-1', appId: _app, source: _source),
      );
      final kept = ReportableTasks.retainSelection([refreshed], stale);
      expect(kept?.supabaseApplicationId, _app);
      expect(kept?.bridgeSourceId, _source);
    });

    test('is dropped when the task left the authorized population', () {
      final selected = population.first;
      expect(
        ReportableTasks.retainSelection([population[1]], selected),
        isNull,
      );
    });

    test('is dropped when the task lost the identity a report needs', () {
      final selected = population.first;
      final degraded = [
        ReportableTask.fromRow(remoteJob('job-1', appId: _app)),
      ];
      expect(ReportableTasks.retainSelection(degraded, selected), isNull);
    });

    test('a null selection stays null', () {
      expect(ReportableTasks.retainSelection(population, null), isNull);
    });
  });

  group('submit validation', () {
    final valid = ReportableTask.fromRow(
      remoteJob('job-1', appId: _app, source: _source),
    );

    test('a valid exact task, category and description passes', () {
      expect(
        ApplicationSupportValidation.errorFor(
          task: valid,
          supportCategory: 'clarification_request',
          description: 'Land use does not match the signage.',
        ),
        isNull,
      );
    });

    test('"Choose the task this concerns." is reachable only with no task', () {
      expect(
        ApplicationSupportValidation.errorFor(
          task: null,
          supportCategory: 'other',
          description: 'x',
        ),
        'Choose the task this concerns.',
      );
      // ...and never once a valid task is held.
      expect(
        ApplicationSupportValidation.errorFor(
          task: valid,
          supportCategory: 'other',
          description: 'x',
        ),
        isNull,
      );
    });

    test('an identity-incomplete task is blocked with its own message', () {
      final incomplete = ReportableTask.fromRow(
        remoteJob('job-1', appId: _app),
      );
      final message = ApplicationSupportValidation.errorFor(
        task: incomplete,
        supportCategory: 'other',
        description: 'x',
      );
      expect(message, isNot('Choose the task this concerns.'));
      expect(message, contains('Refresh this task online'));
    });

    test('category and description are each required', () {
      expect(
        ApplicationSupportValidation.errorFor(
          task: valid,
          supportCategory: null,
          description: 'x',
        ),
        'Choose a support category.',
      );
      expect(
        ApplicationSupportValidation.errorFor(
          task: valid,
          supportCategory: 'other',
          description: '   ',
        ),
        'Describe the concern.',
      );
    });
  });

  group('screen contract: no duplicated fields, no raw error leakage', () {
    // One long device screenshot appeared to show these three fields twice.
    // Each is declared exactly once in the real widget tree, so the duplication
    // was a scrolling-screenshot stitching artifact, not a duplicated widget.
    final source = File(
      'lib/modules/profile_settings/screens/application_support_screen.dart',
    ).readAsStringSync();
    final techSource = File(
      'lib/modules/profile_settings/screens/technical_issue_screen.dart',
    ).readAsStringSync();

    test('each logical field label appears exactly once', () {
      for (final label in [
        'Affected information',
        'Requested correction or clarification',
        'Does this block your inspection?',
      ]) {
        expect(
          RegExp("'$label").allMatches(source),
          hasLength(1),
          reason: '$label must be declared exactly once',
        );
      }
    });

    test('the screen declares exactly three free-text fields', () {
      expect(
        RegExp('TextField\\(').allMatches(source),
        hasLength(3),
        reason: 'Description, Affected information, Requested change',
      );
    });

    test('neither form leaks raw exception text to the inspector', () {
      // Precise assertion: no catch block may assign a raw stringified
      // exception into the visible error field.
      for (final source in [source, techSource]) {
        expect(source, isNot(contains(r'_error = e.toString()')));
        expect(source, isNot(contains(r'_error = error.toString()')));
        expect(source, isNot(contains('_error = e.')));
        expect(source, contains('userFacingMessage'));
      }
    });
  });
}
