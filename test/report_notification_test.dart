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
import 'package:imaps_fieldsync/modules/profile_settings/screens/notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Exercises the existing consumer, unread query, and mark-read path. No live URL,
// credentials, device database, push service, or response-body copy is involved.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const inspector = '40000000-0000-4000-8000-000000000001';
  const foreign = '40000000-0000-4000-8000-000000000002';
  late Database db;
  var rows = <Map<String, dynamic>>[];
  final patches = <Uri>[];
  final deletes = <Uri>[];

  Map<String, dynamic> activity(
    String id,
    String event,
    String title, {
    String recipient = inspector,
  }) => {
    'id': id,
    'inspector_id': recipient,
    'field_job_id': null,
    'event_type': event,
    'title': title,
    'subtitle':
        'MPDO responded to DR-2026-0007. View the official response in My Reports.',
    'occurred_at': '2026-10-04T00:00:00Z',
    'created_at': '2026-10-04T00:00:00Z',
    'is_read': false,
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final bytes = ByteData.sublistView(
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
      return asset.endsWith('.ttf') ? bytes : null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      (_) async => null,
    );
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE pending_actions (id TEXT, updated_at TEXT, inspector_id TEXT)');
    DBHelper.useDatabaseForTesting(db);
    await Supabase.initialize(
      url: 'https://notification.test',
      publishableKey: 'isolated-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.host, 'notification.test');
        expect(request.url.path, '/rest/v1/activity_log');
        final query = request.url.queryParameters;
        if (request.method == 'GET') {
          expect(query['inspector_id'], 'eq.$inspector');
          var result = rows.where((row) => row['inspector_id'] == inspector);
          if (query['is_read'] == 'eq.false') {
            result = result.where((row) => row['is_read'] == false);
          }
          return http.Response(
            jsonEncode(result.toList()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }
        if (request.method == 'DELETE') {
          expect(query['inspector_id'], 'eq.$inspector');
          deletes.add(request.url);
          rows.removeWhere((row) => row['inspector_id'] == inspector &&
              (query['id'] == null || query['id'] == 'eq.${row['id']}'));
          return http.Response('', 204, request: request);
        }
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {'is_read': true});
        patches.add(request.url);
        for (final row in rows.where(
          (row) => row['inspector_id'] == inspector,
        )) {
          if (query['id'] == 'eq.${row['id']}' ||
              (query['inspector_id'] == 'eq.$inspector' &&
                  query['is_read'] == 'eq.false')) {
            row['is_read'] = true;
          }
        }
        return http.Response('', 204, request: request);
      }),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await SupabaseService.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'isolated-token',
        'refresh_token': 'isolated-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': inspector,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });

  setUp(() {
    patches.clear();
    deletes.clear();
    rows = [
      activity('event-resolved', 'report_resolved', 'Report resolved'),
      activity(
        'event-wont-fix',
        'report_wont_fix',
        "Report closed — Won't fix",
      ),
      activity(
        'foreign-event',
        'report_resolved',
        'Other inspector',
        recipient: foreign,
      ),
    ];
  });

  tearDownAll(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await Supabase.instance.dispose();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      null,
    );
  });

  test(
    'terminal events use inspector-scoped feed and exact unread/read queries',
    () async {
      final feed = await SupabaseService.fetchRecentActivity(limit: 50);
      expect(feed.map((row) => row['event_type']), [
        'report_resolved',
        'report_wont_fix',
      ]);
      expect(await SupabaseService.fetchUnreadActivityCount(), 2);
      await SupabaseService.markActivityRead('event-resolved');
      expect(patches.single.queryParameters['id'], 'eq.event-resolved');
      expect(await SupabaseService.fetchUnreadActivityCount(), 1);
      await SupabaseService.markAllActivityRead();
      expect(patches.last.queryParameters['inspector_id'], 'eq.$inspector');
      expect(patches.last.queryParameters['is_read'], 'eq.false');
      expect(await SupabaseService.fetchUnreadActivityCount(), 0);
      expect(rows.last['is_read'], false);
    },
  );

  for (final title in ['Report resolved', "Report closed — Won't fix"]) {
    testWidgets(
      '$title opens existing detail sheet and marks exactly that event read',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
        await tester.runAsync(() async {
          await DBHelper.getSyncLogEntries();
        });
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('Other inspector'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('unread-filter')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text(
            'MPDO responded to DR-2026-0007. View the official response in My Reports.',
          ),
          findsWidgets,
        );
        expect(find.text('Close'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('unread-filter')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(patches, hasLength(1));
        final id = title == 'Report resolved'
            ? 'event-resolved'
            : 'event-wont-fix';
        expect(patches.single.queryParameters['id'], 'eq.$id');
        expect(await SupabaseService.fetchUnreadActivityCount(), 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(patches, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('long old-date notification retains details read swipe and scoped Clear All at enlarged text', (tester) async {
    const title = 'Fictional inspection report received an official response';
    const subtitle = 'The planning officer reviewed the fictional inspection report. Open My Reports to read the response and the next action.';
    rows[0] = {...rows[0], 'title': title, 'subtitle': subtitle};
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)), child: child!),
      home: const NotificationsScreen(),
    ));
    await tester.runAsync(() async => DBHelper.getSyncLogEntries());
    await tester.pumpAndSettle();
    expect(find.text('Other inspector'), findsNothing);
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text(subtitle)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Received: 2026-10-04')), findsOneWidget);
    final close = find.descendant(of: sheet, matching: find.text('Close'));
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(patches, hasLength(1));
    expect(patches.single.queryParameters['id'], 'eq.event-resolved');
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.dragFrom(tester.getCenter(find.text(title)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(deletes, hasLength(1));
    expect(deletes.single.queryParameters['id'], 'eq.event-resolved');
    expect(rows.any((row) => row['id'] == 'foreign-event'), isTrue);
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all notifications?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletes, hasLength(1));
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Clear All')));
    await tester.pumpAndSettle();
    expect(deletes, hasLength(2));
    expect(deletes.last.queryParameters['inspector_id'], 'eq.$inspector');
    expect(deletes.last.queryParameters.containsKey('id'), isFalse);
    expect(rows.single['id'], 'foreign-event');
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
