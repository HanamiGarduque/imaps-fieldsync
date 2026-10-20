import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/services/supabase_service.dart';

/// PO-deadline scheduling policy — MY_TASKS_FINAL_FLOW_SPEC_20261020 §3.
///
/// Fake transport and fictional rows only. No production service, no real
/// Supabase, no live data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const other = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  const jobX = '11111111-1111-1111-8111-111111111111';

  // A fixed local "today" so every threshold below is deterministic.
  final today = DateTime(2026, 10, 20);
  final tomorrow = DateTime(2026, 10, 21);

  var row = <String, dynamic>{};
  var rowVisible = true;
  var failWrite = false;
  var moveDeadlineOnWrite = false;
  var dropWrite = false;
  Future<void> Function()? afterRead;
  void Function()? beforeWrite;
  var patches = 0;
  final writes = <Map<String, dynamic>>[];
  final filters = <Map<String, String>>[];

  /// Emulates the PostgREST row filters this service uses.
  bool matches(Map<String, String> q) {
    final id = q['id'];
    if (id != null && id.startsWith('eq.')) {
      if (row['id'] != id.substring(3)) return false;
    }
    final assignee = q['assigned_inspector_id'];
    if (assignee != null && assignee.startsWith('eq.')) {
      if (row['assigned_inspector_id'] != assignee.substring(3)) return false;
    }
    final status = q['status'];
    if (status != null && status.startsWith('in.(')) {
      final allowed = status
          .substring(3)
          .replaceAll(RegExp(r'[()"]'), '')
          .split(',');
      if (!allowed.contains(row['status'])) return false;
    }
    final deadline = q['deadline_date'];
    if (deadline != null && deadline.startsWith('gte.')) {
      final bound = deadline.substring(4);
      final current = row['deadline_date'];
      if (current == null) return false; // NULL never satisfies a bound
      if ((current as String).compareTo(bound) < 0) return false;
    }
    return true;
  }

  Future<void> boot() async {
    row = <String, dynamic>{};
    rowVisible = true;
    failWrite = false;
    moveDeadlineOnWrite = false;
    dropWrite = false;
    afterRead = null;
    beforeWrite = null;
    patches = 0;
    writes.clear();
    filters.clear();
    await Supabase.initialize(
      url: 'https://deadline.test',
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
        expect(request.url.host, 'deadline.test');
        expect(request.url.path, '/rest/v1/field_jobs');
        final q = request.url.queryParameters;
        final caller =
            request.headers['Authorization']?.split('isolated-token-').last ?? '';
        final owns =
            rowVisible && row['assigned_inspector_id'] == caller;

        if (request.method == 'PATCH') {
          filters.add(q);
          patches++;
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          beforeWrite?.call();
          if (failWrite) {
            return http.Response(
              jsonEncode({'code': 'XX000', 'message': 'isolated refusal'}),
              500,
              request: request,
            );
          }
          if (moveDeadlineOnWrite) {
            // The PO moved the deadline before the write landed.
            row['deadline_date'] = '2026-10-20';
          }
          if (dropWrite || !owns || !matches(q)) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200,
                request: request);
          }
          row.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode([row]), 200, request: request);
        }

        // Reads (the authoritative deadline read).
        filters.add(q);
        if (!owns || !matches(q)) {
          return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200,
              request: request);
        }
        final response = jsonEncode([row]);
        final callback = afterRead;
        afterRead = null;
        await callback?.call();
        return http.Response(response, 200, request: request);
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
    SharedPreferences.setMockInitialValues({});
    return boot();
  });

  Map<String, dynamic> activeRow({
    String status = 'assigned',
    String? deadline = '2026-10-25',
    String? scheduledDate = '2026-01-01',
    bool selfScheduled = false,
    String assignee = owner,
  }) =>
      {
        'id': jobX,
        'assigned_inspector_id': assignee,
        'status': status,
        'scheduled_date': scheduledDate,
        'is_self_scheduled': selfScheduled,
        'deadline_date': deadline,
        'current_step': 0,
      };

  test('a fresh schedule from an assigned row is accepted', () async {
    row = activeRow();

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 24),
      now: today,
    );

    expect(result, InspectionAuthorityResult.authorized);
    expect(row['scheduled_date'], '2026-10-24');
    expect(row['is_self_scheduled'], isTrue);
    expect(row['status'], 'assigned',
        reason: 'choosing a Visit must not rewrite the raw lifecycle');
  });

  test('REPEAT reschedule of a pending (already scheduled) row is accepted',
      () async {
    row = activeRow(
      status: 'pending',
      scheduledDate: '2026-10-22',
      selfScheduled: true,
    );

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 23),
      now: today,
    );

    expect(result, InspectionAuthorityResult.authorized,
        reason: 'a scheduled assignment is pending; it must be reschedulable');
    expect(row['scheduled_date'], '2026-10-23');
    expect(row['is_self_scheduled'], isTrue);
  });

  test('the same reschedule repeated is idempotent', () async {
    row = activeRow(
      status: 'pending',
      scheduledDate: '2026-10-22',
      selfScheduled: true,
    );

    final first = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 23),
      now: today,
    );
    final second = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 23),
      now: today,
    );

    expect(first, InspectionAuthorityResult.authorized);
    expect(second, InspectionAuthorityResult.authorized);
    expect(row['scheduled_date'], '2026-10-23');
  });

  test('a PO deadline today disables scheduling and writes nothing', () async {
    row = activeRow(deadline: '2026-10-20');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 21),
      now: today,
    );

    expect(result, InspectionAuthorityResult.deadlinePassed);
    expect(patches, 0, reason: 'no write may be attempted');
    expect(row['scheduled_date'], '2026-01-01');
  });

  test('a PO deadline in the past disables scheduling and writes nothing',
      () async {
    row = activeRow(deadline: '2026-10-19');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 21),
      now: today,
    );

    expect(result, InspectionAuthorityResult.deadlinePassed);
    expect(patches, 0);
  });

  test('a visit date later than the PO deadline is refused', () async {
    row = activeRow(deadline: '2026-10-22');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 23),
      now: today,
    );

    expect(result, InspectionAuthorityResult.visitDateNotAllowed);
    expect(patches, 0);
  });

  test('a visit date on the PO deadline itself is allowed', () async {
    row = activeRow(deadline: '2026-10-22');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 22),
      now: today,
    );

    expect(result, InspectionAuthorityResult.authorized);
    expect(row['scheduled_date'], '2026-10-22');
  });

  test('the earliest new visit is tomorrow: today is refused', () async {
    row = activeRow(deadline: '2026-10-25');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: today,
      now: today,
    );

    expect(result, InspectionAuthorityResult.visitDateNotAllowed);
    expect(patches, 0);
  });

  test('a missing PO deadline is refused, never replaced by tomorrow',
      () async {
    row = activeRow(deadline: null);

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: tomorrow,
      now: today,
    );

    expect(result, InspectionAuthorityResult.deadlineUnavailable);
    expect(patches, 0);
  });

  test('an unreadable PO deadline is refused', () async {
    row = activeRow(deadline: 'not-a-date');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: tomorrow,
      now: today,
    );

    expect(result, InspectionAuthorityResult.deadlineUnavailable);
    expect(patches, 0);
  });

  test('a non-string deadline fails closed without an uncaught cast or PATCH', () async {
    row = {...activeRow(), 'deadline_date': 20261025};
    expect(await SupabaseService.scheduleJob(jobId: jobX, date: tomorrow, now: today),
        InspectionAuthorityResult.deadlineUnavailable);
    expect(patches, 0);
  });

  test('a stale card cannot schedule past a deadline the PO already moved',
      () async {
    // The card still shows the old deadline, but the server row is the truth.
    row = activeRow(deadline: '2026-10-20');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 21),
      now: today,
    );

    expect(result, InspectionAuthorityResult.deadlinePassed);
    expect(patches, 0);
  });

  test('a deadline shortened between the read and the write is refused',
      () async {
    row = activeRow(deadline: '2026-10-25');
    moveDeadlineOnWrite = true;

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 24),
      now: today,
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
    expect(result, InspectionAuthorityResult.deadlinePassed);
    expect(patches, 1, reason: 'the write was attempted and refused by the server');
  });

  test('a foreign inspector can never schedule or reschedule', () async {
    row = activeRow(assignee: other);

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 24),
      now: today,
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
    expect(patches, 0);
  });

  test('a completed round is never resurrected by scheduling', () async {
    row = activeRow(status: 'completed', deadline: '2026-10-25');

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 24),
      now: today,
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
    expect(patches, 0);
    expect(row['status'], 'completed');
  });

  test('a server error during the write is not success', () async {
    row = activeRow();
    failWrite = true;

    final result = await SupabaseService.scheduleJob(
      jobId: jobX,
      date: DateTime(2026, 10, 24),
      now: today,
    );

    expect(result, isNot(InspectionAuthorityResult.authorized));
  });

  test('rescheduling preserves started lifecycle, photos and saved evidence', () async {
    row = {
      ...activeRow(status: 'in_progress'),
      'current_step': 3,
      'started_at': '2026-10-19T08:00:00Z',
      'photo_paths': ['fictional/photo.jpg'],
      'findings': 'Fictional saved findings',
    };
    final before = Map<String, dynamic>.from(row);

    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.authorized);
    expect(writes.single.keys,
        unorderedEquals(['scheduled_date', 'is_self_scheduled']));
    expect(row, {...before, 'scheduled_date': '2026-10-21', 'is_self_scheduled': true});
  });

  test('an inspection started during the deadline read is not downgraded', () async {
    row = activeRow();
    beforeWrite = () {
      row['status'] = 'in_progress';
      row['current_step'] = 3;
      row['started_at'] = '2026-10-20T08:00:00Z';
    };

    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.authorized);
    expect(row['status'], 'in_progress');
    expect(row['current_step'], 3);
  });

  for (final invalid in ['2027-02-30', '2026/10/25', '2026-10-25junk', '0000-10-25']) {
    test('malformed calendar deadline $invalid fails closed without PATCH', () async {
      row = activeRow(deadline: invalid);
      expect(await SupabaseService.scheduleJob(
        jobId: jobX, date: tomorrow, now: today,
      ), InspectionAuthorityResult.deadlineUnavailable);
      expect(patches, 0);
    });
  }

  test('a zero-row write needs verified matching scheduling state', () async {
    row = activeRow();
    dropWrite = true;
    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), isNot(InspectionAuthorityResult.authorized));
    expect(row['scheduled_date'], '2026-01-01');
  });

  test('a verified idempotent no-op still checks the current deadline', () async {
    row = activeRow(status: 'in_progress', scheduledDate: '2026-10-21', selfScheduled: true);
    dropWrite = true;
    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.authorized);
    expect(row['status'], 'in_progress');
  });

  test('completion between read and PATCH cannot resurrect the round', () async {
    row = activeRow();
    beforeWrite = () => row['status'] = 'completed';
    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.notAssignedOrUnavailable);
    expect(row['status'], 'completed');
    expect(row['scheduled_date'], '2026-01-01');
  });

  test('sign-out during the deadline read emits no PATCH and requires authentication', () async {
    row = activeRow();
    afterRead = () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.authRequired);
    expect(patches, 0);
  });

  test('an account change after the read cannot reuse the previous owner approval', () async {
    row = activeRow();
    afterRead = () async {
      row['assigned_inspector_id'] = other;
      await Supabase.instance.client.auth.setInitialSession(jsonEncode({
        'access_token': 'isolated-token-$other',
        'refresh_token': 'isolated-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': other, 'email': 'other@example.test', 'aud': 'authenticated',
          'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }));
    };
    expect(await SupabaseService.scheduleJob(
      jobId: jobX, date: tomorrow, now: today,
    ), InspectionAuthorityResult.authRequired);
    expect(patches, 0);
    expect(row['scheduled_date'], '2026-01-01');
  });

  test('a deadline read crossing midnight cannot schedule on the deadline day', () async {
    var clock = DateTime(2026, 10, 20, 23, 59, 59);
    row = activeRow(deadline: '2026-10-21');
    afterRead = () async { clock = DateTime(2026, 10, 21); };
    expect(await SupabaseService.scheduleJob(jobId: jobX, date: tomorrow, clock: () => clock),
        InspectionAuthorityResult.deadlinePassed);
    expect(patches, 0);
  });

  for (final malformed in ['2026-10-25T99:99:99Z', '2026-10-25T10:00:00+99:99']) {
    test('overflowing deadline suffix $malformed fails closed', () async {
      row = activeRow(deadline: malformed);
      expect(await SupabaseService.scheduleJob(jobId: jobX, date: tomorrow, now: today),
          InspectionAuthorityResult.deadlineUnavailable);
      expect(patches, 0);
    });
  }
}
