import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

// Widget-level checks for the Notifications page grouping: time sections
// (Today / Yesterday / This week / Earlier) render only for non-empty
// buckets, the All pill is gone (Unread is a both-states filter), and both
// the Activity and Sync lists are sectioned. Follows the isolated
// MockClient + in-memory SQLite pattern from report_notification_test.dart —
// no live URL, credentials, or device data.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const inspector = '40000000-0000-4000-8000-000000000001';
  late Database db;
  var activityRows = <Map<String, dynamic>>[];
  final captureKey = GlobalKey();

  Map<String, dynamic> activity(
    String id,
    String title,
    DateTime at, {
    bool read = false,
  }) => {
    'id': id,
    'inspector_id': inspector,
    'field_job_id': null,
    'event_type': 'gps_confirmed',
    'title': title,
    'subtitle': 'details',
    'occurred_at': at.toUtc().toIso8601String(),
    'created_at': at.toUtc().toIso8601String(),
    'is_read': read,
  };

  Map<String, dynamic> syncEntry(String id, String message, DateTime at) => {
    'id': id,
    'pending_action_id': null,
    'job_id': null,
    'event_type': 'outbox_upload',
    'result': 'success',
    'message': message,
    'technical_details': null,
    'created_at': at.toUtc().toIso8601String(),
    'inspector_id': inspector,
  };

  /// Mid-morning local time on the day [days] before today, so the buckets
  /// are exact regardless of when the suite runs.
  DateTime daysAgo(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days))
        .add(const Duration(hours: 9));
  }

  Future<void> pumpScreen(WidgetTester tester, {int mode = 0}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(home: NotificationsScreen(initialMode: mode)),
      ),
    );
    // The screen loads sync history from the isolate-backed test database;
    // give that real-async roundtrip a slice before settling the tree.
    await tester.runAsync(() async {
      await DBHelper.getSyncLogEntries();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  /// Review artifact only: writes a PNG when IMAPS_NOTIFICATIONS_CAPTURE_DIR
  /// is set, otherwise does nothing.
  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['IMAPS_NOTIFICATIONS_CAPTURE_DIR'];
    if (output == null) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$output/$name.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  }

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
    await db.execute(
      'CREATE TABLE pending_actions (id TEXT, updated_at TEXT, inspector_id TEXT)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_log_entries(
        id TEXT PRIMARY KEY,
        pending_action_id TEXT,
        job_id TEXT,
        event_type TEXT NOT NULL,
        result TEXT NOT NULL,
        message TEXT NOT NULL,
        technical_details TEXT,
        created_at TEXT NOT NULL,
        inspector_id TEXT
      )
    ''');
    DBHelper.useDatabaseForTesting(db);
    await Supabase.initialize(
      url: 'https://notifications-sections.test',
      publishableKey: 'isolated-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.host, 'notifications-sections.test');
        expect(request.url.path, '/rest/v1/activity_log');
        expect(request.method, 'GET');
        expect(request.url.queryParameters['inspector_id'], 'eq.$inspector');
        var result = activityRows.where(
          (row) => row['inspector_id'] == inspector,
        );
        if (request.url.queryParameters['is_read'] == 'eq.false') {
          result = result.where((row) => row['is_read'] == false);
        }
        return http.Response(
          jsonEncode(result.toList()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
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

  setUp(() async {
    activityRows = [];
    await db.delete('sync_log_entries');
  });

  tearDownAll(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await Supabase.instance.dispose();
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      null,
    );
  });

  testWidgets('Activity sections render in time order and the All pill is gone', (
    tester,
  ) async {
    activityRows = [
      activity('t-1', 'Today check-in', daysAgo(0)),
      activity('y-1', 'Yesterday upload', daysAgo(1)),
      activity('w-1', 'This week visit', daysAgo(4)),
      activity('o-1', 'Old record', daysAgo(20)),
    ];
    await pumpScreen(tester);
    for (final label in ['TODAY', 'YESTERDAY', 'THIS WEEK', 'EARLIER']) {
      expect(find.text(label), findsOneWidget, reason: '$label missing');
    }
    for (final title in [
      'Today check-in',
      'Yesterday upload',
      'This week visit',
      'Old record',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '$title missing');
    }
    expect(find.textContaining('All ·'), findsNothing);
    expect(find.text('Unread · 4'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    final tops = ['TODAY', 'YESTERDAY', 'THIS WEEK', 'EARLIER']
        .map((label) => tester.getTopLeft(find.text(label)).dy)
        .toList();
    expect(
      tops[0] < tops[1] && tops[1] < tops[2] && tops[2] < tops[3],
      isTrue,
      reason: 'sections out of order: $tops',
    );
    await capture(tester, 'activity-sections');
  });

  testWidgets('Empty time buckets never render a header', (tester) async {
    activityRows = [
      activity('t-1', 'Today check-in', daysAgo(0)),
      activity('w-1', 'This week visit', daysAgo(3)),
    ];
    await pumpScreen(tester);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsNothing);
    expect(find.text('EARLIER'), findsNothing);
  });

  testWidgets('Unread filter toggles both ways and re-sections the list', (
    tester,
  ) async {
    activityRows = [
      activity('t-1', 'Urgent now', daysAgo(0)),
      activity('y-1', 'Seen yesterday', daysAgo(1), read: true),
      activity('w-1', 'Waiting a while', daysAgo(4)),
    ];
    await pumpScreen(tester);
    expect(find.text('Seen yesterday'), findsOneWidget);
    expect(find.text('Unread · 2'), findsOneWidget);
    await tester.tap(find.text('Unread · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Seen yesterday'), findsNothing);
    expect(find.text('Urgent now'), findsOneWidget);
    expect(find.text('Waiting a while'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsNothing);
    await capture(tester, 'activity-unread-only');
    await tester.tap(find.text('Unread · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Seen yesterday'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
  });

  testWidgets('Sync history is sectioned and still opens from the deep link', (
    tester,
  ) async {
    // SQLite is isolate-backed: writes must run in real-async, outside the
    // test's fake-async zone, or the await would deadlock.
    await tester.runAsync(() async {
      await db.insert(
        'sync_log_entries',
        syncEntry('s-today', 'Synced photo upload', daysAgo(0)),
      );
      await db.insert(
        'sync_log_entries',
        syncEntry('s-week', 'Synced job status', daysAgo(5)),
      );
      await db.insert(
        'sync_log_entries',
        syncEntry('s-old', 'Synced old record', daysAgo(30)),
      );
    });
    await pumpScreen(tester, mode: 1);
    expect(find.text('Synchronization History'), findsOneWidget);
    for (final label in ['TODAY', 'THIS WEEK', 'EARLIER']) {
      expect(find.text(label), findsOneWidget, reason: '$label missing');
    }
    expect(find.text('YESTERDAY'), findsNothing);
    expect(find.text('Synced photo upload'), findsOneWidget);
    expect(find.text('Synced job status'), findsOneWidget);
    expect(find.text('Synced old record'), findsOneWidget);
    expect(find.text('Unread · 3'), findsOneWidget);
    await capture(tester, 'sync-sections');
  });
}
