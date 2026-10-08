import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/models/activity_event_category.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inspector_reassignment_test.dart'
    show signInInspector, inspectorA, inspectorB, jobX, jobY;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late InspectionProvider provider;
  late Map<String, dynamic> remote;
  final activity = <String, Map<String, dynamic>>{};
  final evidenceWrites = <Map<String, dynamic>>[];
  var online = true;
  var activityFailures = 0;
  var loseActivityResponse = false;
  var markerFailures = 0;
  var loseMarkerResponse = false;
  var disconnectAfterActivity = false;
  const submittedAt = '2026-09-22T11:38:54.944788+00:00';

  List<Map<String, dynamic>> findingsActivity() => activity.values
      .where((row) => row['event_type'] == 'field_findings_updated')
      .toList();
  List<Map<String, dynamic>> reworkActivity() => activity.values
      .where((row) => row['event_type'] == 'rework_started')
      .toList();

  Future<List<Map<String, Object?>>> queued() => db.query('pending_actions');
  void edit(String notes) => provider.updateFindings(
    actualLandUse: provider.actualLandUse,
    boundaryStatus: provider.boundaryStatus,
    notes: notes,
    discrepancies: provider.discrepancies,
    recommendations: provider.recommendations,
  );

  void expectCompleted() {
    expect(remote['id'], jobX);
    expect(remote['local_inspection_id'], 26);
    expect(remote['inspection_round_number'], 1);
    expect(remote['assigned_inspector_id'], inspectorA);
    expect(remote['status'], 'completed');
    expect(remote['current_step'], 6);
    expect(remote['submitted_at'], submittedAt);
    expect(remote['inspection_result'], 'Compliant');
    expect(TaskItem.fromJob(remote).category, 'Completed');
    expect(TaskItem.fromJob(remote).derivedHighestStep, 6);
  }

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final fontBytes = ByteData.sublistView(
      Directory(
            '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
          )
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{
      for (final family in ['Inter', 'Poppins', 'Urbanist', 'JetBrainsMono'])
        for (final weight in [
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
        ])
          '$family-$weight.ttf': [
            {'asset': '$family-$weight.ttf'},
          ],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final asset = const StringCodec().decodeMessage(message)!;
          if (asset == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage(manifest);
          }
          return asset.endsWith('.ttf') ? fontBytes : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('screen_protector'),
          (_) async => true,
        );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://findings.fixture.test',
      publishableKey: 'isolated-fixture',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (!online) throw const SocketException('isolated offline');
        final q = request.url.queryParameters;
        http.Response reply(Object rows) => http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path == '/rest/v1/field_jobs') {
          final owned =
              SupabaseService.client.auth.currentUser?.id ==
                  remote['assigned_inspector_id'] &&
              (q['assigned_inspector_id'] == null ||
                  q['assigned_inspector_id'] ==
                      'eq.${remote['assigned_inspector_id']}');
          if (request.method == 'GET') {
            final object =
                request.headers['Accept']?.contains(
                  'application/vnd.pgrst.object+json',
                ) ??
                false;
            if (object) return reply(owned ? remote : {});
            return reply(owned ? [remote] : []);
          }
          expect(request.method, 'PATCH');
          if (q['rework_started_at'] == 'is.null' && markerFailures > 0) {
            markerFailures--;
            return http.Response(
              jsonEncode({'code': '503', 'message': 'isolated marker failure'}),
              503,
              request: request,
            );
          }
          var matches = owned && q['id'] == 'eq.$jobX';
          if (q['rework_started_at'] == 'is.null') {
            matches &= remote['rework_started_at'] == null;
          }
          if (q['status'] == 'eq.completed') {
            matches &= remote['status'] == 'completed';
          }
          if (q['updated_at'] != null) {
            matches &= q['updated_at'] == 'eq.${remote['updated_at']}';
          }
          if (matches) {
            final values = Map<String, dynamic>.from(jsonDecode(request.body));
            if (values.containsKey('inspector_notes')) {
              evidenceWrites.add(values);
            }
            remote.addAll(values);
            remote['updated_at'] = DateTime.now().toUtc().toIso8601String();
            if (loseMarkerResponse && values.containsKey('rework_started_at')) {
              loseMarkerResponse = false;
              // PostgreSQL serializes timestamptz as +00:00, not the request's
              // Z spelling. Reconciliation must compare the accepted instant.
              remote['rework_started_at'] =
                  (values['rework_started_at'] as String).replaceFirst(
                    'Z',
                    '+00:00',
                  );
              throw const SocketException(
                'isolated lost marker acknowledgement',
              );
            }
          }
          // Guarded writes use maybeSingle(): PostgREST returns an object for
          // this Accept header, rather than the list used by select() writes.
          if (request.headers['Accept']?.contains(
                'application/vnd.pgrst.object+json',
              ) ??
              false) {
            if (matches) return reply(remote);
            return http.Response(
              jsonEncode({
                'code': 'PGRST116',
                'message': 'JSON object requested',
                'details': 'The result contains 0 rows',
              }),
              406,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return reply(matches ? [remote] : []);
        }
        expect(request.url.path, '/rest/v1/activity_log');
        if (request.method == 'GET') {
          expect(q['inspector_id'], 'eq.$inspectorA');
          return reply(activity.values.toList().reversed.toList());
        }
        expect(request.method, 'POST');
        final row = Map<String, dynamic>.from(jsonDecode(request.body));
        expect(row['inspector_id'], inspectorA);
        if (row['event_type'] == 'field_findings_updated') {
          // Activity delivery is downstream of an accepted findings mutation.
          expect(remote['inspector_notes'], isNot('Original notes'));
          if (activityFailures > 0) {
            activityFailures--;
            return http.Response(
              jsonEncode({
                'code': '503',
                'message': 'isolated temporary failure',
              }),
              503,
              request: request,
            );
          }
        }
        final id = row['id'] as String;
        if (activity.containsKey(id)) {
          if (request.headers['prefer']?.contains(
                'resolution=ignore-duplicates',
              ) ??
              false) {
            return http.Response('', 201, request: request);
          }
          return http.Response(
            jsonEncode({'code': '23505', 'message': 'activity_log_pkey'}),
            409,
            request: request,
          );
        }
        activity[id] = {...row, 'occurred_at': '2026-10-09T01:00:00Z'};
        if (disconnectAfterActivity &&
            row['event_type'] == 'field_findings_updated') {
          disconnectAfterActivity = false;
          online = false;
        }
        if (loseActivityResponse &&
            row['event_type'] == 'field_findings_updated') {
          loseActivityResponse = false;
          throw const SocketException('isolated lost activity acknowledgement');
        }
        return http.Response('', 201, request: request);
      }),
    );
  });

  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() async {
    await signInInspector(inspectorA);
    online = true;
    activityFailures = 0;
    loseActivityResponse = false;
    markerFailures = 0;
    loseMarkerResponse = false;
    disconnectAfterActivity = false;
    activity.clear();
    evidenceWrites.clear();
    SyncOutboxService.resetRecoverySessionForTesting();
    SyncOutboxService.hasConnectionOverride = () async => online;
    remote = {
      'id': jobX,
      'local_inspection_id': 26,
      'inspection_round_number': 1,
      'assigned_inspector_id': inspectorA,
      'status': 'completed',
      'current_step': 6,
      'submitted_at': submittedAt,
      'updated_at': '2026-10-08T01:00:00Z',
      'rework_started_at': null,
      'observations': 'Original observed use and GPS boundary evidence',
      'inspector_notes': 'Original notes',
      'discrepancies': null,
      'recommendations': null,
      'inspection_result': 'Compliant',
      'is_compliant': true,
      'supabase_zoning_applications': {
        'reference_number': 'APP-FIXTURE-26',
        'applicant_name': 'Isolated applicant',
        'barangay': 'Fixture barangay',
      },
      'supabase_parcels': {'land_use_class': 'Residential'},
    };
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await DBHelper.cacheJobs([remote]);
    provider = InspectionProvider()..hydrateForRework(TaskItem.fromJob(remote));
    InspectionProgress.instance.unlockAllForReview(jobX);
    completedDetailFetcherOverride = (_) async => Map.of(remote);
  });

  tearDown(() async {
    completedDetailFetcherOverride = null;
    SyncOutboxService.hasConnectionOverride = null;
    SyncOutboxService.resetRecoverySessionForTesting();
    provider.dispose();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    // Real async (loopback HTTP, sqflite) only progresses inside runAsync.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    // Save also reads its durable pending baseline after the drain closes.
    // Keep real SQLite IO progressing until both engine and Save UI finish.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (SyncOutboxService.isDraining ||
        find
            .byWidgetPredicate((w) => w is FieldPrimaryButton && w.busy)
            .evaluate()
            .isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('Save did not finish');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Mounts a clean fixture root with the Findings step ready to open, so a
  /// revisit is a real fresh navigation rather than a leftover route stack.
  Future<void> pumpRoot(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            FieldFindingsScreen(task: TaskItem.fromJob(remote)),
                      ),
                    ),
                child: const Text('Open findings fixture'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openFindings(WidgetTester tester) async {
    await pumpRoot(tester);
    await tester.tap(find.text('Open findings fixture'));
    await settle(tester);
  }

  testWidgets(
    'Edit then Back retains a draft across re-entry without evidence or update activity',
    (tester) async {
      await openFindings(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Unsaved draft notes',
      );
      await tester.tap(find.byTooltip('Exit inspection'));
      await settle(tester);
      expect(provider.notes, 'Unsaved draft notes');
      expect(remote['inspector_notes'], 'Original notes');
      expect(evidenceWrites, isEmpty);
      expect(await tester.runAsync(queued), isEmpty);
      expect(findingsActivity(), isEmpty);
      provider.hydrateForRework(TaskItem.fromJob(remote));
      expect(provider.notes, 'Unsaved draft notes');
      // Re-entering the step must restore the in-memory draft, not the
      // persisted text — Back never wrote anything.
      await pumpRoot(tester);
      await tester.tap(find.text('Open findings fixture'));
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Unsaved draft notes',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(remote['inspector_notes'], 'Unsaved draft notes');
      expect(findingsActivity(), hasLength(1));
      expectCompleted();
    },
  );

  testWidgets(
    'real Save updates evidence, summary Modified and the Task activity feed once',
    (tester) async {
      await openFindings(tester);
      await tester.enterText(find.byType(TextField).first, 'Saved correction');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(evidenceWrites, hasLength(1));
      expect(evidenceWrites.single.keys.toSet(), {
        'observations',
        'discrepancies',
        'recommendations',
        'inspector_notes',
      });
      expect(
        remote['observations'],
        'Actual land use: Residential. Boundary status: Compliant.',
      );
      expect(remote['inspector_notes'], 'Saved correction');
      expect(findingsActivity(), hasLength(1));
      expect(remote['rework_started_at'], isNotNull);
      expectCompleted();
      final recent = await tester.runAsync(SupabaseService.fetchRecentActivity);
      final event = recent!.firstWhere(
        (row) => row['event_type'] == 'field_findings_updated',
      );
      expect(event['title'], 'Field Findings updated');
      expect(event['subtitle'], 'Fixture barangay');
      expect(
        ActivityEventCategory.categoryFor(event['event_type'] as String),
        'tasks',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: CompletedInspectionDetailScreen(
              task: TaskItem.fromJob(remote),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Modified'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Field Findings'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.tap(find.text('Field Findings'));
      await settle(tester);
      expect(find.text('Saved correction'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unchanged Save performs no evidence or marker mutation and no activity',
    (tester) async {
      await openFindings(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(findingsActivity(), isEmpty);
      expect(evidenceWrites, isEmpty);
      expect(remote['rework_started_at'], isNull);
      expect(await tester.runAsync(queued), isEmpty);
      expectCompleted();
    },
  );

  test(
    'repeated rework visits log once on the first marker transition and preserve it',
    () async {
      for (var i = 0; i < 3; i++) {
        await SupabaseService.reopenForRework(
          jobId: jobX,
          locationLabel: 'Fixture barangay',
        );
      }
      expect(reworkActivity(), isEmpty);
      edit('First real edit');
      await provider.saveStepFindings(isExplicitSave: true);
      final marker = remote['rework_started_at'];
      expect(marker, isNotNull);
      expect(reworkActivity(), hasLength(1));
      for (var i = 0; i < 3; i++) {
        await SupabaseService.reopenForRework(jobId: jobX);
        provider.hydrateForRework(TaskItem.fromJob(remote));
      }
      edit('Second real edit');
      await provider.saveStepFindings(isExplicitSave: true);
      expect(remote['rework_started_at'], marker);
      expect(reworkActivity(), hasLength(1));
      expect(findingsActivity(), hasLength(2));
      expectCompleted();
    },
  );

  test(
    'offline Save keeps normal pending findings intent and emits only after replay',
    () async {
      online = false;
      edit('Offline correction');
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      final action = (await queued()).single;
      expect(action['type'], 'findings_update');
      expect(action['status'], 'pending');
      final payload = jsonDecode(action['payload'] as String) as Map;
      final activityId = payload['activityId'];
      expect(activityId, isA<String>());
      expect(findingsActivity(), isEmpty);
      expect(remote['inspector_notes'], 'Original notes');
      expect(evidenceWrites, isEmpty);
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      expect(
        jsonDecode((await queued()).single['payload'] as String)['activityId'],
        activityId,
      );
      online = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['inspector_notes'], 'Offline correction');
      expect(remote['rework_started_at'], isNotNull);
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], activityId);
      expect((await queued()).single['status'], 'synced');
      await SyncOutboxService.drain(trigger: 'manual');
      expect(findingsActivity(), hasLength(1));
      expectCompleted();
    },
  );

  test(
    'restart after an accepted evidence write delivers the same queued event without evidence replay',
    () async {
      online = false;
      edit('Recovered correction');
      await provider.saveStepFindings(isExplicitSave: true);
      final action = (await queued()).single;
      final payload = jsonDecode(action['payload'] as String) as Map;
      remote.addAll({
        'observations': payload['observations'],
        'discrepancies': payload['discrepancies'],
        'recommendations': payload['recommendations'],
        'inspector_notes': payload['inspectorNotes'],
        'updated_at': '2026-10-09T01:00:00Z',
      });
      await DBHelper.markActionSyncing(action['id'] as String);
      SyncOutboxService.resetRecoverySessionForTesting();
      online = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], payload['activityId']);
      expect(evidenceWrites, isEmpty);
      expect((await queued()).single['status'], 'synced');
      // Simulate the second crash window: activity succeeded, local ack did not.
      await db.update(
        'pending_actions',
        {'status': 'syncing'},
        where: 'id = ?',
        whereArgs: [action['id']],
      );
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect(findingsActivity(), hasLength(1));
      expect(evidenceWrites, isEmpty);
      expectCompleted();
    },
  );

  test(
    'failed activity delivery remains retryable after findings succeeded',
    () async {
      activityFailures = 1;
      edit('Activity retry correction');
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      expect(remote['inspector_notes'], 'Activity retry correction');
      expect(findingsActivity(), isEmpty);
      final failed = (await queued()).single;
      expect(failed['status'], 'failed');
      final eventId = jsonDecode(failed['payload'] as String)['activityId'];
      // The retry must know the evidence write already landed. The device's own
      // write bumped the server's updated_at, which is exactly the situation the
      // _knownGoodUpdatedAt map exists for; a fresh session starts without it.
      await SyncOutboxService.drain(trigger: 'manual');
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], eventId);
      expect(evidenceWrites, hasLength(1));
      expect((await queued()).single['status'], 'synced');
      expectCompleted();
    },
  );

  test(
    'lost activity acknowledgement then retry cannot insert a duplicate',
    () async {
      loseActivityResponse = true;
      edit('Lost response correction');
      await provider.saveStepFindings(isExplicitSave: true);
      expect(findingsActivity(), hasLength(1));
      expect((await queued()).single['status'], 'failed');
      await SyncOutboxService.drain(trigger: 'manual');
      expect(findingsActivity(), hasLength(1));
      expect(evidenceWrites, hasLength(1));
      expect((await queued()).single['status'], 'synced');
    },
  );

  test(
    'distinct actual saves of previously used text each have their own activity identity',
    () async {
      for (final text in ['Correction A', 'Correction B', 'Correction A']) {
        edit(text);
        expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      }
      expect(findingsActivity(), hasLength(3));
      expect(evidenceWrites, hasLength(3));
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      expect(findingsActivity(), hasLength(3));
      expect(evidenceWrites, hasLength(3));
    },
  );

  test(
    'later offline Save cannot replace an earlier logical save or its event identity',
    () async {
      online = false;
      edit('Offline A');
      await provider.saveStepFindings(isExplicitSave: true);
      edit('Offline B');
      await provider.saveStepFindings(isExplicitSave: true);
      expect(await queued(), hasLength(2));
      online = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['inspector_notes'], 'Offline B');
      expect(findingsActivity(), hasLength(2));
      expectCompleted();
    },
  );

  test(
    'failed local enqueue never claims a remote save and leaves the draft available',
    () async {
      await db.execute('DROP TABLE pending_actions');
      edit('Locally unaccepted correction');
      expect(await provider.saveStepFindings(isExplicitSave: true), isFalse);
      expect(provider.notes, 'Locally unaccepted correction');
      expect(remote['inspector_notes'], 'Original notes');
      expect(evidenceWrites, isEmpty);
      expect(findingsActivity(), isEmpty);
    },
  );

  test(
    'same-job draft is inspector scoped and does not leak into another round',
    () async {
      online = false;
      edit('Private inspector A draft');
      provider.hydrateForRework(TaskItem.fromJob({...remote, 'id': jobY}));
      expect(provider.notes, 'Original notes');
      edit('Other round draft');
      await signInInspector(inspectorB);
      expect(provider.notes, isEmpty);
      provider.hydrateForRework(TaskItem.fromJob(remote));
      expect(provider.notes, 'Original notes');
      expect(findingsActivity(), isEmpty);
    },
  );

  test(
    'R1 activity 503 after accepted evidence survives process restart',
    () async {
      activityFailures = 1;
      edit('R1 saved correction');
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      final action = (await queued()).single;
      expect(action['status'], 'failed');
      expect(remote['inspector_notes'], 'R1 saved correction');
      expect(findingsActivity(), isEmpty);
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await queued()).single['status'], 'synced');
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], action['id']);
      expect(evidenceWrites, hasLength(1));
      expectCompleted();
    },
  );

  test(
    'R1 lost activity acknowledgement survives restart without duplicate',
    () async {
      loseActivityResponse = true;
      edit('R1 lost response correction');
      await provider.saveStepFindings(isExplicitSave: true);
      final action = (await queued()).single;
      expect(action['status'], 'failed');
      expect(findingsActivity(), hasLength(1));
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await queued()).single['status'], 'synced');
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], action['id']);
      expect(evidenceWrites, hasLength(1));
      expectCompleted();
    },
  );

  test('R2 failed A activity cannot conflict distinct Save B', () async {
    activityFailures = 1;
    edit('R2 correction A');
    await provider.saveStepFindings(isExplicitSave: true);
    expect((await queued()).single['status'], 'failed');
    online = false;
    edit('R2 correction B');
    await provider.saveStepFindings(isExplicitSave: true);
    final actions = await queued();
    expect(actions, hasLength(2));
    online = true;
    await SyncOutboxService.drain(trigger: 'manual');
    expect((await queued()).every((row) => row['status'] == 'synced'), isTrue);
    expect(remote['inspector_notes'], 'R2 correction B');
    expect(evidenceWrites.map((row) => row['inspector_notes']).toList(), [
      'R2 correction A',
      'R2 correction B',
    ]);
    expect(
      findingsActivity().map((row) => row['id']).toSet(),
      actions.map((row) => row['id']).toSet(),
    );
    expect(findingsActivity(), hasLength(2));
    expectCompleted();
  });

  testWidgets('R3 pending Save survives recreated provider and UI re-entry', (
    tester,
  ) async {
    await openFindings(tester);
    online = false;
    await tester.enterText(
      find.byType(TextField).first,
      'R3 pending correction',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);
    final action = (await tester.runAsync(queued))!.single;
    expect(remote['inspector_notes'], 'Original notes');
    expect(evidenceWrites, isEmpty);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    provider = InspectionProvider()..hydrateForRework(TaskItem.fromJob(remote));
    // Connectivity permits the existing read-only rework entry check. The
    // queued save has not drained, so authoritative remote text is still old.
    online = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: CompletedInspectionDetailScreen(task: TaskItem.fromJob(remote)),
        ),
      ),
    );
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Field Findings'),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.tap(find.text('Field Findings'));
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Rework this step'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.tap(find.text('Rework this step'));
    await settle(tester);
    await tester.tap(find.text('Rework'));
    await settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'R3 pending correction',
    );
    online = false;
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await tester.runAsync(queued))!.single['id'], action['id']);
    expect(evidenceWrites, isEmpty);
    expect(findingsActivity(), isEmpty);
    expect(remote['rework_started_at'], isNull);
    online = true;
    await tester.runAsync(() => SyncOutboxService.drain(trigger: 'manual'));
    expect(findingsActivity(), hasLength(1));
    expect(findingsActivity().single['id'], action['id']);
    expect(evidenceWrites, hasLength(1));
    expectCompleted();
  });

  test(
    'R4 marker 503 prevents activity and final acknowledgement until retry',
    () async {
      markerFailures = 1;
      edit('R4 marker retry correction');
      await provider.saveStepFindings(isExplicitSave: true);
      final action = (await queued()).single;
      expect(action['status'], isNot('synced'));
      expect(remote['inspector_notes'], 'R4 marker retry correction');
      expect(remote['rework_started_at'], isNull);
      expect(findingsActivity(), isEmpty);
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['rework_started_at'], isNotNull);
      expect((await queued()).single['status'], 'synced');
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], action['id']);
      expect(evidenceWrites, hasLength(1));
      expectCompleted();
    },
  );

  test(
    'R5 lost marker response reconciles one marker and one rework event',
    () async {
      loseMarkerResponse = true;
      edit('R5 ambiguous marker correction');
      await provider.saveStepFindings(isExplicitSave: true);
      final marker = remote['rework_started_at'];
      expect(marker, isNotNull);
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['rework_started_at'], marker);
      expect(reworkActivity(), hasLength(1));
      expect(findingsActivity(), hasLength(1));
      expect((await queued()).single['status'], 'synced');
      expect(evidenceWrites, hasLength(1));
      await SupabaseService.reopenForRework(jobId: jobX);
      await SyncOutboxService.drain(trigger: 'manual');
      expect(reworkActivity(), hasLength(1));
      expectCompleted();
    },
  );

  test(
    'R6 interrupted claim after evidence and marker resumes activity only',
    () async {
      activityFailures = 1;
      edit('R6 interrupted accepted correction');
      await provider.saveStepFindings(isExplicitSave: true);
      final action = (await queued()).single;
      final marker = remote['rework_started_at'];
      expect(marker, isNotNull);
      expect(findingsActivity(), isEmpty);
      // Model a death before the local failure/ack was committed: the durable
      // component payload survives but the action is still claimed at startup.
      await db.update(
        'pending_actions',
        {'status': 'syncing'},
        where: 'id = ?',
        whereArgs: [action['id']],
      );
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await queued()).single['status'], 'synced');
      expect(evidenceWrites, hasLength(1));
      expect(remote['rework_started_at'], marker);
      expect(reworkActivity(), hasLength(1));
      expect(findingsActivity(), hasLength(1));
      expect(findingsActivity().single['id'], action['id']);
      expectCompleted();
    },
  );

  test(
    'R7 offline A then B retain revisions and order across restart',
    () async {
      online = false;
      edit('R7 offline A');
      await provider.saveStepFindings(isExplicitSave: true);
      edit('R7 offline B');
      await provider.saveStepFindings(isExplicitSave: true);
      final actions = await queued();
      expect(actions, hasLength(2));
      online = true;
      disconnectAfterActivity = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['inspector_notes'], 'R7 offline A');
      expect((await queued()).first['status'], 'synced');
      expect(evidenceWrites, hasLength(1));
      SyncOutboxService.resetRecoverySessionForTesting();
      online = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['inspector_notes'], 'R7 offline B');
      expect(
        (await queued()).every((row) => row['status'] == 'synced'),
        isTrue,
      );
      expect(evidenceWrites.map((row) => row['inspector_notes']).toList(), [
        'R7 offline A',
        'R7 offline B',
      ]);
      expect(findingsActivity(), hasLength(2));
      expect(
        findingsActivity().map((row) => row['id']).toList(),
        actions.map((row) => row['id']).toList(),
      );
      expectCompleted();
    },
  );

  test(
    'R2 accepted B stays visible while older A activity remains pending',
    () async {
      activityFailures = 1;
      edit('R2 older A');
      await provider.saveStepFindings(isExplicitSave: true);
      edit('R2 accepted B');
      await provider.saveStepFindings(isExplicitSave: true);
      expect(remote['inspector_notes'], 'R2 accepted B');
      expect(provider.notes, 'R2 accepted B');
      expect((await queued()).first['status'], 'failed');
      expect((await queued()).last['status'], 'synced');
      SyncOutboxService.resetRecoverySessionForTesting();
      await SyncOutboxService.drain(trigger: 'manual');
      expect(remote['inspector_notes'], 'R2 accepted B');
      expect(evidenceWrites, hasLength(2));
      expect(findingsActivity(), hasLength(2));
      expectCompleted();
    },
  );

  test(
    'R3 accepted pending Save yields to fresh remote findings on re-entry',
    () async {
      online = false;
      edit('R3 pending A');
      await provider.saveStepFindings(isExplicitSave: true);
      online = true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect((await queued()).single['status'], 'synced');
      remote.addAll({
        'inspector_notes': 'R3 newer remote findings',
        'updated_at': '2026-10-10T01:00:00Z',
      });
      provider.hydrateForRework(TaskItem.fromJob(remote));
      await provider.restorePendingFindings();
      expect(provider.notes, 'R3 newer remote findings');
      expect(await provider.saveStepFindings(isExplicitSave: true), isTrue);
      expect(evidenceWrites, hasLength(1));
      expect(findingsActivity(), hasLength(1));
      expectCompleted();
    },
  );
}
