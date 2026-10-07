import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'inspector_reassignment_test.dart' show signInInspector, inspectorA, inspectorB, jobX;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> remote;
  bool zeroRows = false;
  bool offline = false;
  final requests = <http.Request>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://authority.test', publishableKey: 'fixture',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/auth/v1/logout') return http.Response('{}', 200, request: r);
        if (offline) throw const SocketException('isolated offline');
        if (r.url.path == '/rest/v1/activity_log') return http.Response('', 201, request: r);
        expect(r.url.path, '/rest/v1/field_jobs');
        final q = r.url.queryParameters;
        final owner = remote['assigned_inspector_id'] == inspectorA && q['assigned_inspector_id'] == 'eq.$inspectorA';
        if (r.method == 'PATCH') {
          var matched = owner && !zeroRows;
          final statusFilter = q['status'];
          if (statusFilter != null && statusFilter.startsWith('in.(')) {
            matched &= statusFilter
                .replaceFirst('in.(', '')
                .replaceFirst(RegExp(r'\)$'), '')
                .split(',')
                .map((v) => v.trim().replaceAll('"', ''))
                .contains(remote['status']);
          }
          if (statusFilter == 'eq.assigned') matched &= remote['status'] == 'assigned';
          if (q['status'] == 'neq.completed') matched &= remote['status'] != 'completed';
          if (q['current_step'] != null) matched &= (remote['current_step'] as int) < int.parse(q['current_step']!.substring(3));
          if (matched) remote.addAll(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(matched ? [remote] : []), 200, request: r);
        }
        return http.Response(jsonEncode(owner ? [remote] : []), 200, request: r);
      }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() async {
    await signInInspector(inspectorA);
    remote = {'id': jobX, 'assigned_inspector_id': inspectorA, 'status': 'assigned', 'current_step': 0};
    requests.clear(); zeroRows = false; offline = false;
  });

  test('ongoing update proves authorized row', () async {
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.authorized);
    expect(remote['status'], 'in_progress');
  });
  test('ongoing zero rows no visible owner is unavailable, not success', () async {
    remote['assigned_inspector_id'] = inspectorB;
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.notAssignedOrUnavailable);
    expect(remote['status'], 'assigned');
  });
  test('ongoing missing session is auth required without request', () async {
    await SupabaseService.client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.authRequired);
    expect(requests, isEmpty);
  });
  test('ongoing transport failure is unverifiable', () async {
    offline = true;
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.offlineOrUnverifiable);
  });
  test('ongoing already in progress remains authorized without rewriting start', () async {
    remote.addAll({'status': 'in_progress', 'started_at': '2026-01-01'});
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.authorized);
    expect(remote['started_at'], '2026-01-01');
  });
  test('self-scheduled pending task starts instead of failing forever', () async {
    remote.addAll({'status': 'pending', 'is_self_scheduled': true, 'started_at': null});
    expect(await SupabaseService.markJobOngoing(jobX), InspectionAuthorityResult.authorized);
    expect(remote['status'], 'in_progress');
    expect(remote['started_at'], isNotNull);
  });

  test('legacy pending spelling is also startable', () async {
    remote['status'] = 'Pending';
    expect(await SupabaseService.markJobOngoing(jobX), InspectionAuthorityResult.authorized);
    expect(remote['status'], 'in_progress');
  });

  test('completed task is never restarted from the startable set', () async {
    remote.addAll({'status': 'completed', 'current_step': 6, 'submitted_at': '2026-01-01'});
    expect(await SupabaseService.markJobOngoing(jobX), InspectionAuthorityResult.authorized);
    expect(remote['status'], 'completed');
    expect(remote['started_at'], isNull, reason: 'a finished round keeps its original start');
  });

  test('wrong-inspector pending task is still denied', () async {
    remote.addAll({'status': 'pending', 'assigned_inspector_id': inspectorB});
    expect(await SupabaseService.markJobOngoing(jobX), InspectionAuthorityResult.notAssignedOrUnavailable);
    expect(remote['status'], 'pending');
  });

  test('progress update proves authorized row', () async {
    final Future<dynamic> result = SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 2);
    expect(await result, InspectionStartResult.authorized);
    expect(remote['current_step'], 2);
  });
  test('already-ahead progress zero rows is authorized no-op only while owned', () async {
    remote['current_step'] = 4;
    final Future<dynamic> result = SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 2);
    expect(await result, InspectionStartResult.authorized);
    expect(remote['current_step'], 4);
  });
  test('progress zero rows authority lost is unavailable', () async {
    remote['assigned_inspector_id'] = inspectorB;
    final Future<dynamic> result = SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 2);
    expect(await result, InspectionStartResult.notAssignedOrUnavailable);
  });
  test('unexplained zero rows under assigned owner is not success', () async {
    zeroRows = true;
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.offlineOrUnverifiable);
  });
  test('completed progress no-op preserves terminal lifecycle and original submission', () async {
    remote.addAll({'status': 'completed', 'current_step': 6, 'submitted_at': '2026-01-01'});
    final Future<dynamic> result = SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 3);
    expect(await result, InspectionStartResult.authorized);
    expect(remote['submitted_at'], '2026-01-01');
    expect(remote['current_step'], 6);
  });
  test('final submit zero rows cannot prove completion', () async {
    remote['assigned_inspector_id'] = inspectorB;
    final Future<dynamic> result = SupabaseService.submitInspection(jobId: jobX, findings: 'preserved',
      isCompliant: false, inspectionResult: 'For Review');
    expect(await result, InspectionStartResult.notAssignedOrUnavailable);
    expect(remote['status'], 'assigned');
  });
}
