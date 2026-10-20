import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const job = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
const savedAt = '2026-02-03T04:05:06';
const privateText = 'fictional-private-payload-and-transport-detail';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Map<String, dynamic> remote;
  var online = true;
  var reject = false;
  var patches = 0;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = ByteData.sublistView(
      fonts
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset},
        ];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null
          ? fallback
          : ByteData.sublistView(
              File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
            );
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://sync-presentation.test',
      publishableKey: 'fictional-fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.host != 'sync-presentation.test') {
          throw StateError('External HTTP forbidden');
        }
        http.Response reply(Object? value, [int status = 200]) => http.Response(
          jsonEncode(value),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path == '/auth/v1/logout') return reply({});
        if (request.url.path == '/rest/v1/activity_log') return reply({}, 201);
        if (request.url.path == '/rest/v1/field_job_photos') return reply([]);
        expect(request.url.path, '/rest/v1/field_jobs');
        if (request.method == 'PATCH') {
          patches++;
          if (reject) {
            return reply({'code': '23514', 'message': privateText}, 400);
          }
          expect(
            request.url.queryParameters['assigned_inspector_id'],
            'eq.$owner',
          );
          remote.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          remote['updated_at'] = '2026-02-04T04:05:06Z';
        }
        final object = request.headers.entries.any(
          (entry) =>
              entry.key.toLowerCase() == 'accept' &&
              entry.value.contains('object'),
        );
        return reply(object ? Map.of(remote) : [Map.of(remote)]);
      }),
    );
    sqfliteFfiInit();
  });

  setUp(() async {
    SyncOutboxService.resetRecoverySessionForTesting();
    SharedPreferences.setMockInitialValues({
      'field_sync_last_success': '2030-01-01T00:00:00',
    });
    await SupabaseService.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fictional',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': owner,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final statement in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(statement.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    remote = {
      'id': job,
      'assigned_inspector_id': owner,
      'status': 'in_progress',
      'current_step': 5,
      'updated_at': '2026-01-01T00:00:00Z',
      'submitted_at': null,
      'local_inspection_id': 1,
      'reference_number': 'FICTIONAL-1',
      'rework_started_at': null,
      'photo_paths': [],
      'photo_count': 0,
    };
    await DBHelper.cacheJobs([remote]);
    online = true;
    reject = false;
    patches = 0;
    SyncOutboxService.hasConnectionOverride = () async => online;
  });

  tearDown(() async {
    completedDetailFetcherOverride = null;
    SyncOutboxService.resetRecoverySessionForTesting();
    SyncOutboxService.hasConnectionOverride = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    await Supabase.instance.dispose();
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(MaterialApp(home: screen));
    for (var frame = 0; frame < 30; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  UpdatesScreen syncScreen() => UpdatesScreen(
    profile: UserProfile(
      id: owner,
      fullName: 'Fictional Inspector',
      role: 'inspector',
    ),
  );

  Future<void> showSyncText(WidgetTester tester, Finder target) async {
    final scroll = find.descendant(
      of: find.byKey(const ValueKey('sync_body')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: scroll,
      maxScrolls: 40,
    );
    // A truthful syncing row animates a progress indicator, so settling would
    // never finish; one frame is enough to lay the scrolled target out.
    await tester.pump();
  }

  Future<void> insertAction({
    String id = 'fixture-action',
    String status = 'pending',
    String inspector = owner,
    int retries = 0,
    String? error,
  }) async {
    await db.insert('pending_actions', {
      'id': id,
      'inspector_id': inspector,
      'job_id': job,
      'type': 'submit_inspection',
      'status': status,
      'retry_count': retries,
      'last_error': error,
      'payload': jsonEncode({
        'inspectionResult': 'For Review',
        'isCompliant': false,
        'discrepancies': privateText,
        'photosData': [],
      }),
      'created_at': savedAt,
      'updated_at': savedAt,
    });
  }

  Future<void> queueFinal() => SyncOutboxService.enqueueSubmitInspection(
    jobId: job,
    findings: privateText,
    isCompliant: false,
    inspectionResult: 'For Review',
    observations: 'Fictional observation',
    discrepancies: privateText,
    inspectorNotes: privateText,
    checklistData: const [
      {'item': 'Fictional condition', 'checked': false},
    ],
    checklistCompletedCount: 0,
    checklistTotalCount: 1,
    photosData: const [],
  );

  Future<void> reconnect(WidgetTester tester) async {
    online = true;
    await tester.runAsync(() async {
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.fluttercommunity.plus/connectivity_status',
        const StandardMethodCodec().encodeSuccessEnvelope(['wifi']),
        (_) {},
      );
      for (var frame = 0; frame < 100; frame++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final rows = await db.query('pending_actions');
        if (rows.any(
              (r) => r['status'] == 'synced' || r['status'] == 'paused',
            ) &&
            !SyncOutboxService.isDraining) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'last successful action uses this owner receipt, not the global preference',
    (tester) async {
      await insertAction(status: 'synced');
      await insertAction(
        id: 'other-receipt',
        status: 'synced',
        inspector: 'another-owner',
      );
      await db.update(
        'pending_actions',
        {'updated_at': '2026-10-19T00:00:00'},
        where: 'id = ?',
        whereArgs: ['other-receipt'],
      );
      await open(tester, syncScreen());
      expect(find.text('No queued updates'), findsOneWidget);
      expect(
        find.text('Last successful action: 2026-02-03 04:05:06 (device time)'),
        findsOneWidget,
      );
      await showSyncText(
        tester,
        find.textContaining('FieldSync-Supabase received'),
      );
      expect(
        find.textContaining('Receipt recorded on device: 2026-02-03 04:05:06'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Inspector assessment: For Review'),
        findsOneWidget,
      );
      expect(
        find.textContaining('iMAPS import: Not yet confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining(privateText), findsNothing);
      expect(find.textContaining('2030'), findsNothing);
      expect(find.textContaining('2026-10-19'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty owner history never claims another account success or All Synced',
    (tester) async {
      await insertAction(status: 'synced', inspector: 'another-owner');
      await open(tester, syncScreen());
      expect(find.text('No queued updates'), findsOneWidget);
      expect(find.text('Last successful action: Not recorded'), findsOneWidget);
      expect(find.text('All Synced'), findsNothing);
      await showSyncText(
        tester,
        find.textContaining('No received updates recorded for this account'),
      );
      expect(find.textContaining('FieldSync-Supabase received'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful automatic reconnect immediately leaves a durable final receipt',
    (tester) async {
      online = false;
      await queueFinal();
      await open(tester, syncScreen());
      expect(patches, 0);
      await showSyncText(
        tester,
        find.text('Saved on device — waiting for connection'),
      );
      await reconnect(tester);
      expect((await db.query('pending_actions')).single['status'], 'synced');
      expect(patches, 1);
      expect(find.text('No queued updates'), findsOneWidget);
      await showSyncText(
        tester,
        find.textContaining('FieldSync-Supabase received'),
      );
      expect(
        find.textContaining('Inspector assessment: For Review'),
        findsOneWidget,
      );
      expect(
        find.textContaining('iMAPS import: Not yet confirmed'),
        findsOneWidget,
      );
      final logs = await db.query('sync_log_entries');
      expect(
        logs
            .where((r) => r['event_type'] == 'queue_started')
            .single['technical_details'],
        contains('automatic'),
      );
      expect(
        logs.map((r) => '${r['message']} ${r['technical_details']}').join(),
        isNot(contains(privateText)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, syncScreen());
      expect(find.text('No queued updates'), findsOneWidget);
      await showSyncText(
        tester,
        find.textContaining('Receipt recorded on device:'),
      );
      expect(
        find.textContaining('FieldSync-Supabase received'),
        findsOneWidget,
      );
      expect(
        patches,
        1,
        reason: 'Opening history must not resend the final submission.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  final states = [
    (
      status: 'pending',
      retries: 0,
      error: privateText,
      text: 'Saved on device — waiting to send',
    ),
    (
      status: 'syncing',
      retries: 0,
      error: privateText,
      text: 'Syncing — sending to FieldSync-Supabase',
    ),
    (
      status: 'failed',
      retries: 2,
      error: privateText,
      text: 'Retry waiting — saved on device',
    ),
    (
      status: 'paused',
      retries: 5,
      error: privateText,
      text: 'Paused after 5 attempts',
    ),
    (
      status: 'paused',
      retries: 0,
      error: InspectionAuthorityResult.authRequired.message,
      text: 'Paused — sign in again',
    ),
    (
      status: 'paused',
      retries: 0,
      error: InspectionAuthorityResult.localOwnershipIncomplete.message,
      text: 'Paused — task ownership needs review',
    ),
    (
      status: 'paused',
      retries: 0,
      error: privateText,
      text: 'Paused — saved on device',
    ),
    (
      status: 'conflict',
      retries: 0,
      error: privateText,
      text: 'Conflict — saved on device',
    ),
  ];
  for (final state in states) {
    testWidgets(
      '${state.status}/${state.retries} shows safe guidance without inventing acceptance',
      (tester) async {
        await insertAction(
          status: state.status,
          retries: state.retries,
          error: state.error,
        );
        await open(tester, syncScreen());
        await showSyncText(tester, find.textContaining(state.text));
        expect(find.textContaining(state.text), findsOneWidget);
        expect(find.textContaining(privateText), findsNothing);
        expect(
          find.textContaining('FieldSync-Supabase received'),
          findsNothing,
        );
        expect(find.text('No queued updates'), findsNothing);
        if (state.status == 'paused') {
          expect(find.text('Paused'), findsOneWidget);
          expect(find.textContaining('still syncing'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'permanent rejection remains paused after selective retry, never still syncing',
    (tester) async {
      online = false;
      reject = true;
      await queueFinal();
      final original = (await db.query('pending_actions')).single['payload'];
      await open(tester, syncScreen());
      await reconnect(tester);
      expect((await db.query('pending_actions')).single['status'], 'paused');
      await showSyncText(
        tester,
        find.textContaining('Paused — server rejected this update'),
      );
      expect(find.textContaining(privateText), findsNothing);
      expect(find.textContaining('FieldSync-Supabase received'), findsNothing);
      await showSyncText(tester, find.text('Sync Inspection (1)'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Sync Inspection (1)'));
        for (var frame = 0; frame < 100 && patches < 2; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      for (var frame = 0; frame < 20; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.textContaining('paused — saved on device'), findsOneWidget);
      expect(find.textContaining('still syncing'), findsNothing);
      expect((await db.query('pending_actions')).single['status'], 'paused');
      expect((await db.query('pending_actions')).single['payload'], original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'force overwrite requires confirmation and Cancel leaves the action untouched',
    (tester) async {
      await insertAction(status: 'conflict', error: privateText);
      final before = (await db.query('pending_actions')).single;
      await open(tester, syncScreen());
      await showSyncText(tester, find.text('Force overwrite'));
      await tester.tap(find.text('Force overwrite'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('replace newer server data'), findsOneWidget);
      expect((await db.query('pending_actions')).single, before);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await db.query('pending_actions')).single, before);
      await tester.tap(find.text('Force overwrite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm overwrite'));
      for (var frame = 0; frame < 20; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      final after = (await db.query('pending_actions')).single;
      expect(after['status'], 'pending');
      expect(jsonDecode(after['payload'] as String)['forceSyncAnyway'], isTrue);
      expect(
        patches,
        0,
        reason: 'Confirmation only queues the overwrite for the next drain.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in [
    'Compliant',
    'With Discrepancy',
    'For Review',
    'Requires Reinspection',
    '',
  ]) {
    testWidgets(
      'completed detail preserves "$outcome" without a binary noncompliance inference',
      (tester) async {
        final detail = {
          ...remote,
          'status': 'completed',
          'current_step': 6,
          'inspection_result': outcome,
          'is_compliant': false,
          'discrepancies': 'Fictional assessment explanation',
          'field_job_reviews': [
            {'decision': 'Approved', 'field_job_id': job},
          ],
        };
        completedDetailFetcherOverride = (_) async => detail;
        await open(
          tester,
          CompletedInspectionDetailScreen(
            task: TaskItem.fromJob(detail),
            historicalReadOnly: true,
          ),
        );
        await tester.dragUntilVisible(
          find.text('Review & Submit'),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review & Submit'));
        await tester.pumpAndSettle();
        expect(find.text('INSPECTOR ASSESSMENT'), findsOneWidget);
        expect(
          find.text(outcome.isEmpty ? 'Not recorded' : outcome),
          findsOneWidget,
        );
        expect(find.text('ASSESSMENT EXPLANATION'), findsOneWidget);
        expect(find.text('Fictional assessment explanation'), findsOneWidget);
        expect(find.text('No (Discrepancy Found)'), findsNothing);
        await tester.dragUntilVisible(
          find.text('Planning Review'),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        expect(find.text('Approved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final tagalog in [false, true]) {
    testWidgets(
      'FAQ explains all six steps and receipt/import distinction in ${tagalog ? 'Tagalog' : 'English'}',
      (tester) async {
        await open(tester, const HelpFaqScreen());
        if (tagalog) {
          await tester.tap(find.text('Tagalog'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField), 'What is Sync Center?');
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            ExpansionTile,
            tagalog ? 'Ano ang Sync Center?' : 'What is Sync Center?',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('FieldSync-Supabase'), findsOneWidget);
        expect(find.textContaining('iMAPS'), findsOneWidget);
        expect(find.textContaining('Completed Audit Log'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'Why are there six steps?',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            ExpansionTile,
            tagalog
                ? 'Bakit mayroong anim na hakbang (6 Steps)?'
                : 'Why are there six steps?',
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          '1. Site Verification',
          '2. GPS Verification',
          '3. Photographic Evidence',
          '4. Checklist',
          '5. Field Findings',
          '6. Review & Submit',
        ]) {
          expect(find.textContaining(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
