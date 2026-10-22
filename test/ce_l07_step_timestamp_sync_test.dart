import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// The fixture's second inspection round, used to prove that one inspection
/// never writes into another one.
const otherOfflineJob = 'cccccccc-2222-4222-8222-cccccccccccc';

/// A minimal field_jobs server that honours the monotonic
/// `current_step=lt.N` filter exactly like PostgREST does.
class FakeFieldJobs {
  final Map<String, Map<String, dynamic>> rows = {
    offlineJob: {
      'id': offlineJob,
      'assigned_inspector_id': offlineInspector,
      'status': 'in_progress',
      'current_step': 0,
      'step_timestamps': <String, dynamic>{},
      'updated_at': '2026-01-01T00:00:00Z',
    },
    otherOfflineJob: {
      'id': otherOfflineJob,
      'assigned_inspector_id': offlineInspector,
      'status': 'in_progress',
      'current_step': 0,
      'step_timestamps': <String, dynamic>{},
      'updated_at': '2026-01-01T00:00:00Z',
    },
  };
  final List<Map<String, dynamic>> patches = [];
  int revisions = 0;

  /// Simulates another legitimate writer that changes the row between the
  /// read and the write.
  void concurrentWrite(String jobId, Map<String, dynamic> values) {
    final target = rows[jobId]!;
    if (values['step_timestamps'] is Map) {
      // A real writer merges the map; it never drops another writer's keys.
      target['step_timestamps'] = {
        ...(target['step_timestamps'] as Map? ?? const <String, dynamic>{}),
        ...(values['step_timestamps'] as Map),
      };
      values = {...values}..remove('step_timestamps');
    }
    target.addAll(values);
    revisions++;
    target['updated_at'] =
        '2026-01-02T00:00:${revisions.toString().padLeft(2, '0')}Z';
  }

  Map<String, dynamic> row(String id) => rows[id]!;

  Map<String, dynamic> get timestamps =>
      (row(offlineJob)['step_timestamps'] as Map?)?.cast<String, dynamic>() ??
      {};

  http.Response handle(http.Request request) {
    final path = request.url.path;
    if (path == '/rest/v1/activity_log') {
      return http.Response('[]', 201, request: request);
    }
    if (path == '/rest/v1/field_job_photos') {
      return http.Response('[]', 200, request: request);
    }
    if (path != '/rest/v1/field_jobs') {
      return http.Response('[]', 200, request: request);
    }
    final single = request.headers['accept']?.contains(
          'application/vnd.pgrst.object+json',
        ) ??
        false;
    // PostgREST answers a single-object request that matches no row with
    // PGRST116, which the client turns into null for maybeSingle().
    http.Response noRow() => single
        ? http.Response(
            jsonEncode({
              'code': 'PGRST116',
              'message':
                  'JSON object requested, multiple (or no) rows returned',
              'details': 'Results contain 0 rows',
              'hint': null,
            }),
            406,
            request: request,
            headers: {'content-type': 'application/json'},
          )
        : http.Response('[]', 200, request: request);
    // The row filters PostgREST applies before the response is built.
    final idFilter = request.url.queryParameters['id'];
    final id = idFilter != null && idFilter.startsWith('eq.')
        ? idFilter.substring(3)
        : null;
    final ownerFilter = request.url.queryParameters['assigned_inspector_id'];
    final owner = ownerFilter != null && ownerFilter.startsWith('eq.')
        ? ownerFilter.substring(3)
        : null;
    Map<String, dynamic>? match;
    for (final candidate in rows.values) {
      if (id != null && candidate['id'] != id) continue;
      if (owner != null && candidate['assigned_inspector_id'] != owner) continue;
      match = candidate;
      break;
    }
    if (request.method == 'GET') {
      if (match == null) {
        return http.Response(
          single ? 'null' : '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(single ? match : [match]),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches.add({
        ...body,
        'filter_current_step': request.url.queryParameters['current_step'],
      });
      if (match == null) {
        return noRow();
      }
      // PostgREST applies the row filters before the update.
      for (final entry in request.url.queryParameters.entries) {
        final value = entry.value;
        if (value.startsWith('eq.')) {
          if (match[entry.key] != value.substring(3)) {
            return noRow();
          }
        } else if (value.startsWith('neq.')) {
          if (match[entry.key] == value.substring(4)) {
            return noRow();
          }
        } else if (value.startsWith('lt.')) {
          final bound = int.parse(value.substring(3));
          if ((match[entry.key] as int) >= bound) {
            return noRow();
          }
        }
      }
      match.addAll(body);
      revisions++;
      match['updated_at'] = '2026-01-02T00:00:${revisions.toString().padLeft(2, '0')}Z';
      return http.Response(
        jsonEncode(single ? match : [match]),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('[]', 200, request: request);
  }
}

/// Batch 3 follow-up: an independently completed step must keep its real
/// completion time on the remote record, even when it is completed after a
/// later step, and even when the final submission happens offline first.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  void bind(FakeFieldJobs fake) {
    fixture.requestOverride = (request) async => fake.handle(request);
  }

  /// Completes a step the way the app does, through the shared progress.
  Future<void> complete(int step) async {
    InspectionProgress.instance.markStepComplete(step);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  test(
    'a step completed after a later one still reaches the remote timestamps',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      fixture.online = true;
      fixture.mode = 'success';
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );

      await complete(1);
      await complete(2);
      await complete(5);
      expect(fake.row(offlineJob)['current_step'], 5);
      expect(fake.timestamps.keys.toSet(), containsAll(<String>{'1', '2', '5'}));

      // Step 3 is completed after Step 5: the remote is already at 5, so the
      // monotonic progress write cannot carry the new time.
      await complete(3);
      expect(
        fake.timestamps.keys.toSet(),
        containsAll(<String>{'1', '2', '3', '5'}),
        reason: 'the real completion time of step 3 must reach the remote',
      );
      expect(fake.row(offlineJob)['current_step'], 5, reason: 'current_step never moves back');
    },
  );

  test(
    'an offline completion of a later step keeps every timestamp after reconnect',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );

      // Offline: the queue carries the work, nothing reaches the server yet.
      SyncOutboxService.hasConnectionOverride = () async => false;
      await complete(1);
      await complete(2);
      await complete(5);
      await complete(3);
      expect(fake.timestamps, isEmpty, reason: 'nothing is sent while offline');

      // Reconnect and drain.
      SyncOutboxService.hasConnectionOverride = () async => true;
      fixture.online = true;
      fixture.mode = 'success';
      await SyncOutboxService.drain(trigger: 'manual');
      expect(
        fake.timestamps.keys.toSet(),
        containsAll(<String>{'1', '2', '3', '5'}),
      );
      expect(fake.row(offlineJob)['current_step'], 5);
    },
  );

  test(
    'a failed timestamp write stays retryable and is never a false receipt',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );
      // The remote already sits at step 5, so the progress write cannot land
      // the new time; the timestamp-only write is what has to deliver it.
      await complete(1);
      await complete(2);
      fake.row(offlineJob)['current_step'] = 5;
      fake.row(offlineJob)['step_timestamps'] = {'5': '2026-01-01T00:00:00Z'};
      var failTimestamps = true;
      fixture.requestOverride = (request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/rest/v1/field_jobs' &&
            request.body.contains('step_timestamps') &&
            !request.body.contains('current_step')) {
          if (failTimestamps) {
            failTimestamps = false;
            return http.Response(
              jsonEncode({'code': 'fixture', 'message': 'Synthetic refusal'}),
              500,
              request: request,
            );
          }
        }
        return fake.handle(request);
      };

      await complete(3);
      // The first attempt failed: the local record still holds the truth and
      // the remote does not claim it.
      final local = await DBHelper.getLocalInspection(offlineJob);
      final localTimes =
          jsonDecode(local?['step_timestamps'] as String) as Map;
      expect(localTimes.keys.map((key) => key.toString()), contains('3'));
      expect(fake.timestamps.keys.toSet(), isNot(contains('3')));
      // The failure is preserved for retry, never acknowledged as delivered.
      final queued = await fixture.db.query(
        'pending_actions',
        where: 'type = ?',
        whereArgs: ['current_step_update'],
      );
      expect(queued, isNotEmpty);
      expect(
        queued.every((row) => row['status'] != 'synced'),
        isTrue,
        reason: 'a failed timestamp write must not be a false synced receipt',
      );
    },
  );

  test(
    'an offline final submission still delivers every completion time',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );

      // Everything happens offline: step 5 first, then 3, then 4.
      SyncOutboxService.hasConnectionOverride = () async => false;
      await complete(1);
      await complete(2);
      await complete(5);
      await complete(3);
      await complete(4);
      expect(fake.timestamps, isEmpty, reason: 'nothing reaches the server yet');

      // The inspection state is saved and the final submission is queued,
      // exactly as Review & Submit does it while offline.
      await fixture.provider.saveAllInspectionState(syncOnline: false);
      await SyncOutboxService.enqueueSubmitInspection(
        jobId: offlineJob,
        findings: 'Fixture findings',
        isCompliant: true,
        inspectionResult: 'Compliant',
        observations: 'Fixture observations',
        inspectorNotes: 'Fixture notes',
        checklistData: const <Map<String, dynamic>>[],
        checklistCompletedCount: 0,
        checklistTotalCount: 0,
        photosData: const <Map<String, dynamic>>[],
        locationLabel: 'Fixture',
      );

      // Restart the app, then reconnect and deliver.
      await fixture.restartDatabase();
      SyncOutboxService.hasConnectionOverride = () async => true;
      fixture.online = true;
      fixture.mode = 'success';
      await SyncOutboxService.drain(trigger: 'manual');

      expect(
        fake.timestamps.keys.toSet(),
        containsAll(<String>{'1', '2', '3', '4', '5'}),
        reason:
            'the final submission must not swallow the completion times of the '
            'independent steps',
      );
      expect(fake.row(offlineJob)['current_step'], 6);
      expect(fake.row(offlineJob)['status'], 'completed');
    },
  );

  test(
    'every completion order delivers the same complete timeline',
    () async {
      const orders = [
        [3, 4, 5],
        [5, 3, 4],
        [4, 3, 5],
        [3, 5, 4],
      ];
      for (final order in orders) {
        final fake = FakeFieldJobs();
        bind(fake);
        fixture.online = true;
        fixture.mode = 'success';
        InspectionProgress.instance.reset();
        InspectionProgress.instance.ensureActiveInspection(
          offlineJob,
          label: 'Fixture',
          initialStep: 0,
        );
        await complete(1);
        await complete(2);
        for (final step in order) {
          await complete(step);
        }
        expect(
          fake.timestamps.keys.toSet(),
          containsAll(<String>{'1', '2', '3', '4', '5'}),
          reason: 'order $order',
        );
        expect(fake.row(offlineJob)['current_step'], 5, reason: 'order $order');
        // The server never gains a key the inspector never recorded.
        expect(
          fake.timestamps.keys.toSet().difference(<String>{'1', '2', '3', '4', '5'}),
          isEmpty,
          reason: 'order $order',
        );
        fixture.online = false;
      }
    },
  );

  test('a repeated drain neither duplicates nor loses a completion time', () async {
    final fake = FakeFieldJobs();
    bind(fake);
    fixture.online = true;
    fixture.mode = 'success';
    InspectionProgress.instance.ensureActiveInspection(
      offlineJob,
      label: 'Fixture',
      initialStep: 0,
    );
    await complete(1);
    await complete(2);
    await complete(5);
    await complete(3);

    await SyncOutboxService.drain(trigger: 'manual');
    final first = Map<String, dynamic>.from(fake.timestamps);
    await SyncOutboxService.drain(trigger: 'manual');
    expect(fake.timestamps.keys.toSet(), first.keys.toSet());
    expect(fake.timestamps.keys.toSet(), containsAll(<String>{'1', '2', '3', '5'}));
    expect(fake.row(offlineJob)['current_step'], 5);
  });

  test('a revoked assignment is refused and never acknowledged', () async {
    final fake = FakeFieldJobs();
    bind(fake);
    fixture.online = true;
    fixture.mode = 'success';
    InspectionProgress.instance.ensureActiveInspection(
      offlineJob,
      label: 'Fixture',
      initialStep: 0,
    );
    await complete(1);
    await complete(2);
    // The inspection is reassigned to another inspector before step 5.
    fake.row(offlineJob)['assigned_inspector_id'] = otherOfflineInspector;
    await complete(5);

    expect(
      fake.timestamps.keys.toSet(),
      isNot(contains('5')),
      reason: 'a reassigned inspection must not be written by the old owner',
    );
    final queued = await fixture.db.query(
      'pending_actions',
      where: 'type = ?',
      whereArgs: ['current_step_update'],
    );
    expect(
      queued.every((row) => row['status'] != 'synced'),
      isTrue,
      reason: 'an unauthorized write must not produce a synced receipt',
    );
  });

  test('another inspection keeps its own timestamps', () async {
    final fake = FakeFieldJobs();
    bind(fake);
    fixture.online = true;
    fixture.mode = 'success';
    InspectionProgress.instance.ensureActiveInspection(
      offlineJob,
      label: 'Fixture',
      initialStep: 0,
    );
    await complete(1);
    await complete(2);
    await complete(5);
    await complete(3);
    expect(fake.timestamps.keys.toSet(), containsAll(<String>{'1', '2', '3', '5'}));
    expect(
      (fake.row(otherOfflineJob)['step_timestamps'] as Map).isEmpty,
      isTrue,
      reason: 'one inspection never writes into another inspection record',
    );
  });

  test(
    'a completed inspection keeps its lifecycle while taking its times',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      fixture.online = true;
      fixture.mode = 'success';
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );
      await complete(1);
      await complete(2);
      // The inspection is already submitted on the server.
      fake.row(offlineJob)['status'] = 'completed';
      fake.row(offlineJob)['current_step'] = 6;
      fake.row(offlineJob)['step_timestamps'] = {'6': '2026-01-01T00:00:00Z'};
      await complete(5);

      expect(
        fake.row(offlineJob)['status'],
        'completed',
        reason: 'the timestamp write never changes the task status',
      );
      expect(
        fake.row(offlineJob)['current_step'],
        6,
        reason: 'the timestamp write never moves current_step',
      );
      expect(
        fake.timestamps.keys.toSet(),
        containsAll(<String>{'1', '2', '5', '6'}),
        reason: 'the completion times of a submitted inspection are preserved',
      );
    },
  );

  test(
    'a concurrent writer is never overwritten by the timestamp merge',
    () async {
      final fake = FakeFieldJobs();
      bind(fake);
      fixture.online = true;
      fixture.mode = 'success';
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );
      await complete(1);
      await complete(2);
      await complete(5);
      await complete(3);

      // Another writer stores a step of its own after this device read the
      // row and before this device writes.
      var raced = false;
      fixture.requestOverride = (request) async {
        if (!raced &&
            request.method == 'PATCH' &&
            request.url.path == '/rest/v1/field_jobs' &&
            request.url.queryParameters.containsKey('updated_at')) {
          raced = true;
          fake.concurrentWrite(offlineJob, {
            'step_timestamps': {'6': '2026-01-01T00:00:00Z'},
          });
        }
        return fake.handle(request);
      };

      await complete(4);
      expect(
        fake.timestamps.keys.toSet(),
        containsAll(<String>{'1', '2', '3', '4', '5', '6'}),
        reason:
            'the other writer\'s key must survive; the merge is redone on the '
            'new revision instead of overwriting it',
      );
      expect(
        fake.timestamps['6'],
        '2026-01-01T00:00:00Z',
        reason: 'the concurrent writer keeps its own value',
      );
    },
  );

  fixture.widgetTest(
    'the real Step 6 screen refuses a submission while a step is unfinished',
    (tester) async {
      final fake = FakeFieldJobs();
      bind(fake);
      fixture.online = false;
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );
      // Steps 1, 2 and then 5 and 3: Step 4 is still missing.
      for (final step in [1, 2, 5, 3]) {
        InspectionProgress.instance.markStepComplete(step);
        await fixture.flush(tester);
      }
      fixture.provider.updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await fixture.flush(tester);

      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.textContaining('Complete the remaining inspection step'),
        findsWidgets,
      );
      expect(find.textContaining('Step 4'), findsWidgets);
      expect(
        await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['submit_inspection'],
        ),
        isEmpty,
        reason: 'a refused submission is never journaled',
      );
      expect(fake.timestamps, isEmpty);
    },
  );

  fixture.widgetTest(
    'a genuinely completed inspection submits and delivers every step time',
    (tester) async {
      final fake = FakeFieldJobs();
      bind(fake);
      // Everything happens offline first: the steps and the submission are
      // queued, exactly as a field inspector with no signal experiences it.
      fixture.online = false;
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        label: 'Fixture',
        initialStep: 0,
      );
      for (final step in [1, 2, 5, 3, 4]) {
        InspectionProgress.instance.markStepComplete(step);
        await fixture.flush(tester);
      }
      fixture.provider.updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await fixture.flush(tester);

      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.tap(find.text('Confirm & Submit'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['submit_inspection'],
        ),
        hasLength(1),
        reason: 'the finished inspection is journaled exactly once',
      );

      // Delivery of that journal (restart, reconnect, drain) is proven by
      // 'an offline final submission still delivers every completion time';
      // draining real HTTP inside the widget test's fake clock would hang.
    },
  );
}
