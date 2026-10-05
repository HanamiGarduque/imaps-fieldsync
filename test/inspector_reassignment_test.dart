import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/inspection_start_service.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const inspectorA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const inspectorB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const jobX = '11111111-1111-4111-8111-111111111111';
const jobY = '22222222-2222-4222-8222-222222222222';

Future<void> signInInspector(String id) =>
    SupabaseService.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-token-$id',
      'refresh_token': 'isolated-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Map<String, dynamic> remote;
  final requests = <http.Request>[];
  Object? lookupError;
  int? lookupStatus;
  Object? malformedRow;
  bool missing = false;
  Completer<void>? lookupGate;
  Future<void> Function()? afterRead;
  // Byte-for-byte local_jobs snapshot: a denial must leave the cached job
  // exactly as the refresh left it, not merely keep the same status value.
  late List<Map<String, Object?>> cachedBefore;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fontBytes = ByteData.sublistView(fonts.listSync().whereType<File>()
        .firstWhere((f) => f.path.endsWith('.ttf')).readAsBytesSync());
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Poppins', 'Urbanist', 'JetBrainsMono', 'Roboto']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Light']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [{'asset': asset}];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (m) async {
      final asset = const StringCodec().decodeMessage(m)!;
      if (asset == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(manifest);
      return asset.endsWith('.ttf') ? fontBytes : null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'), (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'), (_) async => null,
    );
    await Supabase.initialize(
      url: 'https://assignment.test', publishableKey: 'isolated-test-key',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/v1/logout') return http.Response('{}', 200, request: request);
        expect(request.url.host, 'assignment.test');
        expect(request.url.path, '/rest/v1/field_jobs');
        final query = request.url.queryParameters;
        // HTTP boundary models the catalog-proven RLS policy. Production query,
        // result interpretation, SQLite persistence and UI are all real.
        final uid = request.headers['Authorization']?.split('isolated-token-').last;
        if (request.method == 'GET' && query.containsKey('id')) {
          expect(query['id'], 'eq.$jobX');
          if (lookupGate != null) await lookupGate!.future;
          if (lookupError != null) throw lookupError!;
          if (lookupStatus != null) {
            return http.Response(jsonEncode({'message': 'fixture refusal',
              'code': lookupStatus == 401 ? 'PGRST301' : 'XX000'}), lookupStatus!, request: request);
          }
        }
        var visible = !missing && remote['assigned_inspector_id'] == uid;
        if (query['assigned_inspector_id'] != null) {
          visible = visible && query['assigned_inspector_id'] == 'eq.${remote['assigned_inspector_id']}';
        }
        if (request.method == 'PATCH') {
          if (query['status'] == 'eq.assigned') visible = visible && remote['status'] == 'assigned';
          if (query['status'] == 'neq.completed') visible = visible && remote['status'] != 'completed';
          if (query['updated_at'] != null) visible = visible && query['updated_at'] == 'eq.${remote['updated_at']}';
          if (visible) remote.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          if (request.headers['Accept'] == 'application/vnd.pgrst.object+json') {
            return http.Response(jsonEncode(visible ? remote : {
              'code': 'PGRST116', 'message': 'JSON object requested',
              'details': 'Results contain 0 rows',
            }), visible ? 200 : 406, request: request);
          }
          return http.Response(jsonEncode(visible ? [remote] : []), 200, request: request);
        }
        final result = visible ? [malformedRow ?? Map<String, dynamic>.of(remote)] : [];
        if (afterRead != null) await afterRead!();
        return http.Response(jsonEncode(result), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    remote = {'id': jobX, 'assigned_inspector_id': inspectorA,
      'status': 'assigned', 'current_step': 0, 'updated_at': '2026-10-05T00:00:00Z'};
    lookupError = null;
    lookupStatus = null;
    malformedRow = null;
    lookupGate = null;
    afterRead = null;
    missing = false;
    await signInInspector(inspectorA);
    await DBHelper.cacheJobs([remote, {'id': jobY, 'status': 'assigned'}]);
    cachedBefore = await db.query('local_jobs');
    requests.clear();
    InspectionProgress.instance.reset();
  });

  tearDown(() async {
    InspectionProgress.instance.reset();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> expectNoStart() async {
    for (final table in ['inspection_job_retention', 'local_inspections', 'local_photos', 'pending_actions']) {
      expect(await db.query(table), isEmpty, reason: 'denial must not write $table');
    }
    expect(await db.query('local_jobs'), cachedBefore);
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    expect(remote['status'], 'assigned');
    expect(remote['current_step'], 0);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  test('owned exact job is authorized without writes, then A may retain', () async {
    expect(await InspectionStartService.verifyCurrentInspectorMayStartJob(jobX),
      InspectionStartResult.authorized);
    await expectNoStart();
    expect(requests.single.url.queryParameters['id'], 'eq.$jobX');
    expect(requests.single.url.queryParameters['assigned_inspector_id'], 'eq.$inspectorA');
    // Privacy-critical projection: no owner name, profile join or applicant data.
    expect(requests.single.url.queryParameters['select'], 'id,assigned_inspector_id');
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authorized);
    expect((await db.query('inspection_job_retention')).single['job_id'], jobX);
    expect(await db.query('local_inspections'), isEmpty);
    expect(await db.query('pending_actions'), isEmpty);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });

  for (final hidden in ['reassigned', 'unassigned', 'missing']) {
    test('$hidden has the same unavailable result and no partial start', () async {
      if (hidden == 'reassigned') remote['assigned_inspector_id'] = inspectorB;
      if (hidden == 'unassigned') remote['assigned_inspector_id'] = null;
      missing = hidden == 'missing';
      expect(await InspectionStartService.prepareJob(jobX),
        InspectionStartResult.notAssignedOrUnavailable);
      await expectNoStart();
    });
  }

  test('no auth denies before any request or mutation', () async {
    await SupabaseService.client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authRequired);
    expect(requests, isEmpty);
    await expectNoStart();
  });

  for (final failure in ['offline', 'timeout', 'server', 'malformed', 'wrong id', 'wrong owner', 'unexpected']) {
    test('$failure verification fails closed without partial start', () async {
      switch (failure) {
        case 'offline': lookupError = const SocketException('fixture offline');
        case 'timeout': lookupError = TimeoutException('fixture timeout');
        case 'server': lookupStatus = 503;
        case 'malformed': malformedRow = {'id': jobX};
        case 'wrong id': malformedRow = {...remote, 'id': jobY};
        case 'wrong owner': malformedRow = {...remote, 'assigned_inspector_id': inspectorB};
        case 'unexpected': lookupError = StateError('fixture structural failure');
      }
      expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.offlineOrUnverifiable);
      await expectNoStart();
    });
  }

  for (final status in [401, 403]) {
    test('server-rejected auth $status uses session-expired result', () async {
      lookupStatus = status;
      expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authRequired);
      await expectNoStart();
    });
  }

  test('empty job id never reaches the network and cannot start', () async {
    expect(await InspectionStartService.prepareJob(''), InspectionStartResult.notAssignedOrUnavailable);
    expect(requests, isEmpty);
    expect(await db.query('inspection_job_retention'), isEmpty);
  });

  test('no retention while authoritative read is outstanding', () async {
    lookupGate = Completer<void>();
    final attempt = InspectionStartService.prepareJob(jobX);
    // Wait for the actual request, not an arbitrary wall-clock delay.
    while (requests.isEmpty) { await Future<void>.delayed(Duration.zero); }
    await expectNoStart();
    remote['assigned_inspector_id'] = inspectorB;
    lookupGate!.complete();
    expect(await attempt, InspectionStartResult.notAssignedOrUnavailable);
    await expectNoStart();
  });

  test('unanswered read reaches bounded timeout without late retention', () async {
    lookupGate = Completer<void>();
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.offlineOrUnverifiable);
    await expectNoStart();
    lookupGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await expectNoStart();
  });

  test('session changes during lookup cannot authorize a different inspector', () async {
    afterRead = () => signInInspector(inspectorB);
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authRequired);
    await expectNoStart();
  });

  test('account switch cannot consume A-owned local cache even after reassignment', () async {
    await signInInspector(inspectorB);
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.notAssignedOrUnavailable);
    await expectNoStart();
    remote['assigned_inspector_id'] = inspectorB;
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.notAssignedOrUnavailable);
    expect(await db.query('inspection_job_retention'), isEmpty);
    expect((await db.query('local_jobs', where:'id = ?', whereArgs:[jobX])).single['inspector_id'], inspectorA);
  });

  test('ordinary refresh prunes A pre-start row and supplies same job to B', () async {
    // Unrelated legitimate started work remains protected during both refreshes.
    await DBHelper.retainInspectionJob(jobY);
    remote['assigned_inspector_id'] = inspectorB;
    await DBHelper.cacheJobs(await SupabaseService.fetchMyJobs());
    expect((await DBHelper.getCachedJobs()).map((r) => r['id']), [jobY]);
    await signInInspector(inspectorB);
    final jobs = await SupabaseService.fetchMyJobs();
    expect(jobs.single['id'], jobX);
    await DBHelper.cacheJobs(jobs);
    expect((await DBHelper.getCachedJobs()).map((r) => r['id']), [jobX]);
    expect((await db.query('local_jobs', where:'id = ?', whereArgs:[jobY])).single['inspector_id'], inspectorA);
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authorized);
  });

  for (final evidence in ['retention', 'saved draft']) {
    test('$evidence preserves offline continuation and exact local evidence', () async {
      if (evidence == 'retention') {
        await DBHelper.retainInspectionJob(jobX);
      } else {
        await DBHelper.saveInspectionLocally(jobId: jobX, actualLandUse: 'fixture',
          notes: 'Keep my field work', isCompliant: true, inspectionResult: 'Compliant',
          checklist: {}, boundaryStatus: 'Compliant', currentStep: 2);
      }
      await DBHelper.savePhotoLocally(photoId: 'photo-x', jobId: jobX,
        photoPath: '/fixture/photo.jpg', notes: 'Keep evidence', latitude: 0, longitude: 0);
      final drafts = await db.query('local_inspections');
      final photos = await db.query('local_photos');
      remote['assigned_inspector_id'] = inspectorB;
      lookupError = const SocketException('offline');
      expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authorized);
      expect(requests, isEmpty);
      expect(await db.query('local_inspections'), drafts);
      expect(await db.query('local_photos'), photos);
      // Existing offline continuation still queues the existing status operation.
      await SyncOutboxService.enqueueMarkOngoing(jobId: jobX);
      expect((await DBHelper.getActionableActions()).single['type'], 'mark_ongoing');
      expect((await DBHelper.getCachedJobs()).firstWhere((r) => r['id'] == jobX)['status'], 'in_progress');
    });
  }

  test('post-check reassignment blocks later authenticated server writes', () async {
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authorized);
    remote['assigned_inspector_id'] = inspectorB;
    final before = Map<String, dynamic>.of(remote);
    await SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 1);
    await SupabaseService.markJobOngoing(jobX);
    expect(await SupabaseService.conditionalOutboxUpdate(jobX,
      remote['updated_at'] as String, 'assigned', {'status': 'in_progress'}), isNull);
    final updates = requests.where((r) => r.method == 'PATCH').toList();
    expect(updates, hasLength(3));
    for (final update in updates) {
      expect(update.url.queryParameters['assigned_inspector_id'], 'eq.$inspectorA');
      expect(update.url.queryParameters['id'], 'eq.$jobX');
      expect(update.headers['Authorization'], 'Bearer isolated-token-$inspectorA');
    }
    expect(remote, before);
    // Explicit residual: local retention is not a distributed server lease.
    expect((await db.query('inspection_job_retention')).single['job_id'], jobX);
  });

  test('authorized progress and status writes still perform real operations', () async {
    expect(await InspectionStartService.prepareJob(jobX), InspectionStartResult.authorized);
    await SupabaseService.advanceJobInspectionProgress(jobId: jobX, currentStep: 1);
    expect(remote['current_step'], 1);
    expect(await SupabaseService.markJobOngoing(jobX), InspectionStartResult.authorized);
    expect(remote['status'], 'in_progress');
    expect(remote['started_at'], isNotNull);
  });

  testWidgets('stale PRE-START screen denies hidden assignment before any local start', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = InspectionProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: provider,
      child: MaterialApp(home: ParcelDetailScreen(task: TaskItem.fromJob(remote)))));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    // Reassignment occurs AFTER the real overview has loaded.
    remote['assigned_inspector_id'] = inspectorB;
    await tester.tap(find.text('Site Verification'));
    await pumpUntil(tester, find.textContaining('no longer available to start'));
    await tester.runAsync(expectNoStart);
    expect(find.byType(SiteMapScreen), findsNothing);
    expect(find.textContaining('no longer available to start'), findsOneWidget);
    expect(InspectionProgress.instance.highestCompleted, 0);
    expect(provider.capturedPhotos, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('offline PRE-START screen shows actionable denial without navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = InspectionProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: provider,
      child: MaterialApp(home: ParcelDetailScreen(task: TaskItem.fromJob(remote)))));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    lookupError = const SocketException('offline');
    await tester.tap(find.text('Site Verification'));
    await pumpUntil(tester, find.textContaining('Connect to verify'));
    await tester.runAsync(expectNoStart);
    expect(find.byType(SiteMapScreen), findsNothing);
    expect(find.textContaining('Connect to verify'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  for (final retained in [false, true]) {
    testWidgets('real Step 1 entry retained=$retained permits authorized continuation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      if (retained) {
        await tester.runAsync(() => DBHelper.retainInspectionJob(jobX));
        lookupError = const SocketException('offline');
        remote['assigned_inspector_id'] = inspectorB;
      }
      final provider = InspectionProvider();
      await tester.pumpWidget(ChangeNotifierProvider.value(value: provider,
        child: MaterialApp(home: ParcelDetailScreen(task: TaskItem.fromJob(remote)))));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Site Verification'));
      await pumpUntil(tester, find.byType(SiteMapScreen));
      expect(find.byType(SiteMapScreen), findsOneWidget);
      await tester.runAsync(() async {
        expect((await db.query('inspection_job_retention')).single['job_id'], jobX);
        expect(await db.query('local_inspections'), isEmpty);
        expect(await db.query('pending_actions'), isEmpty);
      });
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      if (retained) expect(requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      provider.dispose();
    });
  }
}
