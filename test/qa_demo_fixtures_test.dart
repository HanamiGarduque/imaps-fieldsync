import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/models/activity_event_category.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/qa/demo_fixtures.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late DemoFixtures demo;
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    // Only the isolated test database is cleared; the initializer itself must
    // refuse an unrecognized populated sandbox rather than clear one.
    await fixture.db.delete('local_jobs');
    await fixture.client.auth.setInitialSession(
      jsonEncode(DemoFixtures.session()),
    );
    demo = DemoFixtures.forTesting(verifyIdentity: () async => true);
  });
  tearDown(() async {
    ReportQueueService.connectivityOverride = null;
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  void routeFixtureRequestsToDemo() {
    // Adapt only the existing test fixture's fictional origin. The production
    // demo handler itself never redirects or forwards any request.
    fixture.requestOverride = (req) {
      final local = http.Request(
        req.method,
        req.url.replace(scheme: 'http', host: '127.0.0.1', port: 54321),
      );
      local.headers.addAll(req.headers);
      local.bodyBytes = req.bodyBytes;
      return demo.handle(local);
    };
  }

  test(
    'connected Step 2 uses only the validated local distance calculation',
    () async {
      await demo.initialize(documents: fixture.directory);
      routeFixtureRequestsToDemo();
      final meters = await SupabaseService.getDistanceToParcelBoundary(
        parcelId: DemoFixtures.parcelId(8),
        latitude: 0.00012,
        longitude: -139.99989,
      );
      expect(meters, inExclusiveRange(10, 25));
      for (final body in [
        {'parcel_id': 'unknown-parcel', 'lat': 0.00012, 'lng': -139.99989},
        {'parcel_id': DemoFixtures.parcelId(8), 'lat': 14.5, 'lng': 121.0},
        {
          'parcel_id': DemoFixtures.parcelId(8),
          'lat': 0.00012,
          'lng': -139.99989,
          'owner': 'other',
        },
      ]) {
        expect(
          (await request(
            demo,
            'POST',
            '/rest/v1/rpc/distance_to_parcel_boundary',
            body: body,
          )).statusCode,
          403,
        );
      }
      expect(fixture.remoteWrites, 0);
    },
  );

  test(
    'existing Activity and job readers consume the same local fixture collection',
    () async {
      await demo.initialize(documents: fixture.directory);
      routeFixtureRequestsToDemo();
      expect(await SupabaseService.fetchRecentActivity(), hasLength(8));
      expect(await SupabaseService.fetchUnreadActivityCount(), 4);
      await SupabaseService.markActivityRead(DemoFixtures.activityId(1));
      expect(await SupabaseService.fetchUnreadActivityCount(), 3);
      await SupabaseService.deleteActivity(DemoFixtures.activityId(2));
      expect(await SupabaseService.fetchRecentActivity(), hasLength(7));
      final detail = (await SupabaseService.fetchJobDetail(
        DemoFixtures.jobId(8),
      ))!;
      expect(detail['current_step'], 5);
      expect(detail['field_job_photos'], hasLength(4));
      expect(detail['inspection_result'], 'Compliant');
      expect(detail['inspector_notes'], contains('DEMO'));
      expect(await SupabaseService.fetchMyJobs(), hasLength(9));
      await SupabaseService.markAllActivityRead();
      expect(await SupabaseService.fetchUnreadActivityCount(), 0);
      await SupabaseService.clearAllActivity();
      expect(await SupabaseService.fetchRecentActivity(), isEmpty);
      expect(fixture.remoteWrites, 0);
    },
  );

  test(
    'nine owned jobs derive the documented Home and My Tasks buckets',
    () async {
      await demo.initialize(documents: fixture.directory);
      final snapshot = await DBHelper.getTaskPresentationSnapshot();
      final tasks = snapshot.jobs.map(TaskItem.fromCachedJob).toList();
      expect(tasks, hasLength(9));
      expect(snapshot.jobs.map((r) => r['inspector_id']).toSet(), {
        DemoFixtures.owner,
      });
      expect(tasks.map((t) => t.id).toSet(), {
        for (var i = 1; i <= 9; i++)
          '22222222-2222-4222-8222-${i.toString().padLeft(12, '0')}',
      });
      final home = <String?, int>{};
      final myTasks = <String, int>{};
      for (final task in tasks) {
        home.update(
          homeDashboardTaskPresentationCategory(task),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        myTasks.update(task.category, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(home, {
        'Scheduled': 5,
        'Pending': 2,
        'Ongoing': 1,
        'Completed': 1,
      });
      expect(myTasks, {'Pending': 7, 'Ongoing': 1, 'Completed': 1});
      final byId = {for (final t in tasks) t.id: t};
      expect(
        [
          for (var i = 1; i <= 5; i++)
            byId[DemoFixtures.jobId(i)]!.scheduledDate,
        ],
        ['2026-11-07', '2026-10-30', '2026-10-29', '2026-10-28', '2026-10-25'],
      );
      expect(byId[DemoFixtures.jobId(6)]!.scheduledDate, isEmpty);
      expect(byId[DemoFixtures.jobId(6)]!.deadlineDate, '2026-10-26');
      expect(byId[DemoFixtures.jobId(7)]!.scheduledDate, isEmpty);
      expect(
        byId[DemoFixtures.jobId(9)]!.submittedAt,
        '2026-10-24T02:00:00.000Z',
      );
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (final task in tasks) {
        expect(uuid.hasMatch(task.id), isTrue);
        expect(uuid.hasMatch(task.supabaseApplicationId!), isTrue);
        expect(uuid.hasMatch(task.parcelId!), isTrue);
        expect(task.name, contains('Synthetic'));
      }
    },
  );

  test(
    'restart preserves user edits, Activity deletion and cleared Sync history',
    () async {
      await demo.initialize(documents: fixture.directory);
      await fixture.db.update(
        'local_jobs',
        {'scheduled_date': '2026-11-05'},
        where: 'id = ?',
        whereArgs: [DemoFixtures.jobId(1)],
      );
      await request(
        demo,
        'PATCH',
        '/rest/v1/activity_log',
        query: {'id': 'eq.${DemoFixtures.activityId(1)}'},
        body: {'is_read': true},
      );
      await request(
        demo,
        'DELETE',
        '/rest/v1/activity_log',
        query: {
          'id': 'eq.${DemoFixtures.activityId(2)}',
          'inspector_id': 'eq.${DemoFixtures.owner}',
        },
      );
      await DBHelper.clearSyncLogEntries();
      await fixture.restartDatabase();
      demo = DemoFixtures.forTesting(verifyIdentity: () async => true);
      await demo.initialize(documents: fixture.directory);
      expect(
        (await DBHelper.getCachedJob(DemoFixtures.jobId(1)))!['scheduled_date'],
        '2026-11-05',
      );
      final response = await request(
        demo,
        'GET',
        '/rest/v1/activity_log',
        query: {'inspector_id': 'eq.${DemoFixtures.owner}'},
      );
      final rows = (jsonDecode(response.body) as List).cast<Map>();
      expect(rows, hasLength(7));
      expect(
        rows.singleWhere(
          (r) => r['id'] == DemoFixtures.activityId(1),
        )['is_read'],
        isTrue,
      );
      expect(rows.any((r) => r['id'] == DemoFixtures.activityId(2)), isFalse);
      // The production reader may backfill cleared history from the existing
      // queue, but initialization must never resurrect the 24 fixture log rows.
      expect(await fixture.db.query('sync_log_entries'), isEmpty);
      expect(
        await DBHelper.getLocalPhotos(DemoFixtures.jobId(8)),
        hasLength(4),
      );
    },
  );

  test(
    'activity categories, paginated Sync history and draft use real contracts',
    () async {
      await demo.initialize(documents: fixture.directory);
      final activity =
          jsonDecode(
                (await request(
                  demo,
                  'GET',
                  '/rest/v1/activity_log',
                  query: {
                    'inspector_id': 'eq.${DemoFixtures.owner}',
                    'order': 'occurred_at.desc',
                    'limit': '50',
                  },
                )).body,
              )
              as List;
      final categories = <String, int>{};
      for (final row in activity) {
        categories.update(
          ActivityEventCategory.categoryFor(row['event_type'] as String),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      expect(categories, {'tasks': 4, 'sync': 2, 'reports': 1, 'profile': 1});
      expect(activity.map((r) => r['occurred_at']).toSet(), hasLength(8));
      final page1 = await DBHelper.getSyncLogEntries();
      final page2 = await DBHelper.getSyncLogEntries(offset: 20);
      expect(page1, hasLength(20));
      expect(page2, hasLength(4));
      expect([...page1, ...page2].map((r) => r['result']).toSet(), {
        'info',
        'success',
        'warning',
        'error',
      });
      expect(
        [
          ...page1,
          ...page2,
        ].every((r) => (r['message'] as String).contains('DEMO')),
        isTrue,
      );
      final job = (await DBHelper.getCachedJob(DemoFixtures.jobId(8)))!;
      final provider = InspectionProvider();
      addTearDown(provider.dispose);
      await provider.startInspection(TaskItem.fromCachedJob(job));
      expect(provider.completedFlexibleSteps, {3, 4, 5});
      expect(InspectionProgress.instance.currentStep, 6);
      expect(InspectionProgress.instance.isLocked(6), isFalse);
      expect(provider.assessmentValidationMessage, isNull);
      expect(provider.structuredAnswers, isNotEmpty);
      expect(provider.gpsVerification, isNotNull);
      expect(provider.realPhotoCount, 3);
      expect(provider.hasLocationReference, isTrue);
      for (final photo in provider.capturedPhotos) {
        expect(
          img.decodeImage(File(photo['photoPath'] as String).readAsBytesSync()),
          isNotNull,
        );
        expect(photo['notes'], contains('DEMO'));
      }
      final reference = provider.capturedPhotos.singleWhere(
        isLocationReferencePhoto,
      );
      expect(
        provider.capturedPhotos
            .where((p) => !isLocationReferencePhoto(p))
            .every((p) => p['id'] != reference['id']),
        isTrue,
      );
      final actions = await fixture.db.query('pending_actions');
      expect(actions.map((r) => r['status']).toSet(), {
        'pending',
        'failed',
        'conflict',
        'synced',
      });
      final submission = actions.singleWhere(
        (r) => r['type'] == 'submit_inspection',
      );
      expect(submission['job_id'], DemoFixtures.jobId(9));
      expect(
        (jsonDecode(submission['payload'] as String) as Map)['photosData'],
        hasLength(4),
      );
      final history = actions.singleWhere((r) => r['status'] == 'synced');
      expect(history['payload'], contains('SIMULATED'));
    },
  );

  test(
    'transport refuses unexpected origin, path, method, owner and mutation',
    () async {
      await demo.initialize(documents: fixture.directory);
      for (final uri in [
        Uri.parse('https://production.example.invalid/rest/v1/activity_log'),
        Uri.parse('http://127.0.0.1:54322/rest/v1/activity_log'),
        Uri.parse('http://127.0.0.1:54321/rest/v1/unknown'),
        Uri.parse(
          'http://127.0.0.1:54321/rest/v1/activity_log?inspector_id=eq.other',
        ),
        Uri.parse(
          'http://127.0.0.1:54321/rest/v1/activity_log?inspector_id=eq.${DemoFixtures.owner}&or=(is_read.eq.false)',
        ),
      ]) {
        expect(
          (await demo.transport.get(uri, headers: authHeaders)).statusCode,
          403,
        );
      }
      for (final method in ['POST', 'PUT', 'HEAD']) {
        expect(
          (await request(
            demo,
            method,
            '/rest/v1/activity_log',
            query: {'inspector_id': 'eq.${DemoFixtures.owner}'},
          )).statusCode,
          403,
        );
      }
      expect(
        (await request(
          demo,
          'PATCH',
          '/rest/v1/activity_log',
          query: {'id': 'eq.${DemoFixtures.activityId(1)}'},
          body: {'inspector_id': 'other'},
        )).statusCode,
        403,
      );
      expect(
        (await request(
          demo,
          'GET',
          '/rest/v1/field_jobs',
          query: {'id': 'eq.unknown'},
        )).statusCode,
        403,
      );
      expect(
        (await demo.transport.get(
          Uri.parse('http://127.0.0.1:54321/rest/v1/activity_log'),
          headers: {'authorization': 'Bearer other'},
        )).statusCode,
        403,
      );
      SyncOutboxService.hasConnectionOverride = () async => false;
      ReportQueueService.connectivityOverride = () async => false;
      routeFixtureRequestsToDemo();
      // Manual drain bypasses connectivity; the deny-only mutation transport is
      // the independent safeguard. No newly attempted action may become synced.
      await SyncOutboxService.drain(trigger: 'manual');
      final actions = await fixture.db.query('pending_actions');
      expect(actions.where((r) => r['status'] == 'synced'), hasLength(1));
      expect(fixture.remoteWrites, 0);
    },
  );

  test(
    'wrong trust or owner cannot initialize or overwrite a populated sandbox',
    () async {
      final untrusted = DemoFixtures.forTesting(
        verifyIdentity: () async => false,
      );
      await expectLater(
        untrusted.initialize(documents: fixture.directory),
        throwsStateError,
      );
      expect(await DBHelper.getCachedJobs(), isEmpty);
      await fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session()),
      );
      await expectLater(
        demo.initialize(documents: fixture.directory),
        throwsStateError,
      );
      await fixture.client.auth.setInitialSession(
        jsonEncode(DemoFixtures.session()),
      );
      await DBHelper.cacheJobs([
        {'id': 'unrecognized-existing-demo-work', 'status': 'assigned'},
      ]);
      await expectLater(
        demo.initialize(documents: fixture.directory),
        throwsStateError,
      );
      expect(
        (await DBHelper.getCachedJobs()).single['id'],
        'unrecognized-existing-demo-work',
      );
    },
  );
}

Map<String, String> get authHeaders => {
  'authorization': 'Bearer ${DemoFixtures.accessToken}',
  'apikey': 'demo-fictional-local-only',
  'content-type': 'application/json',
};

Future<http.Response> request(
  DemoFixtures demo,
  String method,
  String path, {
  Map<String, String> query = const {},
  Map<String, Object?>? body,
}) async {
  final req = http.Request(
    method,
    Uri.parse('http://127.0.0.1:54321$path').replace(queryParameters: query),
  );
  req.headers.addAll(authHeaders);
  if (body != null) req.body = jsonEncode(body);
  return http.Response.fromStream(await demo.transport.send(req));
}
