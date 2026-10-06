import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

/// Regression cover for rescheduling an ONGOING task.
///
/// THE DEFECT THIS PINS
/// --------------------
/// `scheduleJob` filtered `status == 'assigned'`, so an ongoing job
/// (remote status `in_progress`) matched zero rows. `_writeWithAuthority` then
/// re-read the row, found it still owned by the caller, and asked `satisfied`,
/// which asserted the new scheduling values. Those values were absent because
/// the write never happened, so the call returned `offlineOrUnverifiable` and
/// the inspector saw "Connect to verify this job before continuing remote
/// writes." The guard was right to refuse a zero-row write; the filter was
/// wrong to make every reschedule a zero-row write.
///
/// The locked transition: owned + in_progress + chosen future date
///   -> status pending, scheduled_date set, is_self_scheduled true,
///      same inspector, nothing else on the row touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const other = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  const jobX = '11111111-1111-4111-8111-111111111111';

  var row = <String, dynamic>{};
  var visible = true;
  var failWrite = false;
  var stripStatusOnWrite = false;
  var writeStatus = 200;
  final writes = <Map<String, dynamic>>[];
  final filters = <Map<String, String>>[];

  Future<void> boot() async {
    row = <String, dynamic>{};
    visible = true;
    failWrite = false;
    stripStatusOnWrite = false;
    writeStatus = 200;
    writes.clear();
    filters.clear();
    await Supabase.initialize(
      url: 'https://reschedule.test',
      publishableKey: 'isolated-test-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('{}', 200, request: request);
        }
        expect(request.url.host, 'reschedule.test');
        expect(request.url.path, '/rest/v1/field_jobs');
        final q = request.url.queryParameters;
        final caller = request.headers['Authorization']
                ?.split('isolated-token-').last ??
            '';
        final owns = visible && row['assigned_inspector_id'] == caller;
        filters.add(q);

        if (request.method == 'PATCH') {
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (failWrite) {
            return http.Response(
              jsonEncode({'code': 'XX000', 'message': 'isolated refusal'}),
              500,
              request: request,
            );
          }
          // A zero-row update is a legitimate outcome of a mismatched
          // lifecycle predicate; it must never be reported as success.
          var matched = owns;
          final statusFilter = q['status'];
          if (statusFilter != null) {
            final allowed = statusFilter.startsWith('in.')
                ? statusFilter
                    .substring(3)
                    .replaceAll(RegExp(r'[()"]'), '')
                    .split(',')
                : [statusFilter.substring(3)];
            matched = matched && allowed.contains(row['status']);
          }
          if (matched) {
            final applied = jsonDecode(request.body) as Map<String, dynamic>;
            // Simulates a store that accepts the scheduling columns but never
            // performs the lifecycle transition.
            if (stripStatusOnWrite) applied.remove('status');
            row.addAll(applied);
            return http.Response(jsonEncode([row]), writeStatus, request: request);
          }
          return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200,
              request: request);
        }

        return http.Response(
          jsonEncode(owns ? [row] : <Map<String, dynamic>>[]),
          200,
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-token-$owner',
      'refresh_token': 'isolated-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': owner,
        'email': 'inspector@example.test',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
  }

  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() {
    // supabase_flutter reads shared_preferences during initialize even with
    // EmptyLocalStorage; the platform channel has no test implementation.
    SharedPreferences.setMockInitialValues({});
    return boot();
  });

  test('CASE A: an owned assigned task schedules into pending', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'assigned',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
      'current_step': 0,
    };

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 3, 4),
    );

    expect(result, InspectionAuthorityResult.authorized);
    expect(row['status'], 'pending');
    expect(row['scheduled_date'], '2030-03-04');
    expect(row['is_self_scheduled'], isTrue);
  });

  test('CASE B: an owned in_progress task reschedules into pending', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
      'current_step': 3,
    };

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 5, 6),
    );

    expect(result, InspectionAuthorityResult.authorized);
    expect(row['status'], 'pending',
        reason: 'the locked contract moves an ongoing task back to pending');
    expect(row['scheduled_date'], '2030-05-06');
    expect(row['is_self_scheduled'], isTrue);
  });

  test('CASE E: rescheduling mutates only the scheduling fields', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
      'current_step': 4,
      'findings': 'isolated prior findings',
      'is_compliant': false,
      'inspection_result': 'For Review',
    };

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 7, 8),
    );

    expect(result, InspectionAuthorityResult.authorized);
    expect(writes.single.keys,
        unorderedEquals(['scheduled_date', 'is_self_scheduled', 'status']),
        reason: 'progress, findings and assignee must not be written');
    expect(row['assigned_inspector_id'], owner);
    expect(row['current_step'], 4);
    expect(row['findings'], 'isolated prior findings');
    expect(row['is_compliant'], false);
    expect(row['inspection_result'], 'For Review');
  });

  for (final foreignStatus in ['assigned', 'in_progress']) {
    test('CASE C: a foreign inspector cannot reschedule an $foreignStatus job',
        () async {
      row = {
        'id': jobX,
        'assigned_inspector_id': other,
        'status': foreignStatus,
        'scheduled_date': '2026-01-01',
        'is_self_scheduled': false,
      };

      final result = await SupabaseService.scheduleJob(
        jobId: jobX,
        date: DateTime(2030, 9, 10),
      );

      expect(result, isNot(InspectionAuthorityResult.authorized),
          reason: 'a foreign assignee must never be rescheduled');
      expect(row['status'], foreignStatus, reason: 'the remote row is untouched');
      expect(row['scheduled_date'], '2026-01-01',
          reason: 'ownership rejection must leave every column unchanged');
      expect(row['is_self_scheduled'], isFalse);
    });
  }

  test('CASE D: a job that is no longer visible is blocked', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
    };
    visible = false;

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 11, 12),
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
    expect(row['scheduled_date'], '2026-01-01',
        reason: 'an invisible job must not be mutated');
  });

  test('CASE F: a write that returns zero rows is never success', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'completed',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
    };

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 1, 2),
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
    expect(row['status'], 'completed',
        reason: 'a completed job is outside the schedulable lifecycle');
  });

  test('CASE F2: a post-write row without the pending transition is not success',
    () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
    };
    stripStatusOnWrite = true;

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 2, 3),
    );

    expect(result, isNot(InspectionAuthorityResult.authorized),
        reason: 'scheduling without the lifecycle transition is a partial write');
    expect(row['status'], 'in_progress');
  });

  test('a server error during the write is not success', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
    };
    failWrite = true;

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2030, 4, 5),
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
  });

  test('the update filters on the authenticated inspector', () async {
    row = {
      'id': jobX,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'scheduled_date': '2026-01-01',
      'is_self_scheduled': false,
    };

    await SupabaseService.scheduleJob(jobId: jobX, date: DateTime(2030, 6, 7));

    final patch = filters.firstWhere((f) => f.containsKey('id'));
    expect(patch['id'], 'eq.$jobX');
    expect(patch['assigned_inspector_id'], 'eq.$owner',
        reason: 'ownership is never dropped from the authority predicate');
    expect(patch['status'], 'in.("assigned","in_progress")');
  });

  // ── CASE G: the lifecycle mapper already derives the required placement ──
  // No new category and no UI special case: pending + a self-scheduled date
  // must land under Pending -> Scheduled through the existing mapper.
  group('CASE G: lifecycle derivation', () {
    Map<String, dynamic> remoteRow() => {
          'id': jobX,
          'status': 'pending',
          'scheduled_date': '2030-05-06',
          'is_self_scheduled': true,
          'current_step': 0,
        };

    TaskItem taskFrom(Map<String, dynamic> remote) => TaskItem.fromJob({
          ...remote,
          'local_inspection_id': 41,
          'zoning_applications': {'applicant_name': 'Isolated Applicant'},
        });

    test('pending + self-scheduled date lands in Pending -> Scheduled', () {
      final task = taskFrom(remoteRow());

      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
      expect(task.category, 'Pending');
      expect(task.pendingSection, PendingTaskSection.scheduled);
      expect(task.isSelfScheduled, isTrue);
      expect(task.scheduledDate, '2030-05-06');
    });

    test('the same row before rescheduling sat under Ongoing', () {
      final task = taskFrom({...remoteRow(), 'status': 'in_progress'});

      expect(task.lifecycleCategory, TaskLifecycleCategory.ongoing);
      expect(task.category, 'Ongoing');
      expect(task.pendingSection, isNull,
          reason: 'only the pending lifecycle exposes a scheduled subgroup');
    });

    test('a pending job without a chosen date stays Available Anytime', () {
      final task = taskFrom({...remoteRow(), 'is_self_scheduled': false});

      expect(task.lifecycleCategory, TaskLifecycleCategory.pending);
      expect(task.pendingSection, PendingTaskSection.availableAnytime);
    });

    test('the mapper keeps completed out of the schedulable lifecycle', () {
      expect(mapTaskStatusToLifecycle('completed'),
          TaskLifecycleCategory.completed);
      expect(mapTaskStatusToLifecycle('in_progress'),
          TaskLifecycleCategory.ongoing);
      expect(mapTaskStatusToLifecycle('assigned'),
          TaskLifecycleCategory.pending);
    });
  });
}