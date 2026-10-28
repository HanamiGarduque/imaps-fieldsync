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
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Android200TextScaler extends TextScaler {
  const _Android200TextScaler();
  @override
  double get textScaleFactor => 2;
  @override
  double scale(double fontSize) {
    const from = [8.0, 10.0, 12.0, 14.0, 18.0, 20.0, 24.0, 30.0, 100.0];
    const to = [16.0, 20.0, 24.0, 26.0, 30.0, 34.0, 36.0, 38.0, 100.0];
    if (fontSize <= from.first) return fontSize * 2;
    for (var i = 1; i < from.length; i++) {
      if (fontSize <= from[i]) {
        return to[i - 1] + (to[i] - to[i - 1]) *
            (fontSize - from[i - 1]) / (from[i] - from[i - 1]);
      }
    }
    return fontSize;
  }
}

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

  Future<void> pumpScreen(
    WidgetTester tester, {
    int mode = 0,
    Size size = const Size(430, 1400),
    double textScale = 1,
    TextScaler? scaler,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: scaler ?? TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: NotificationsScreen(initialMode: mode),
        ),
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
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null
          ? bytes
          : ByteData.sublistView(
              File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
            );
    });
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    await (FontLoader('MaterialIcons')..addFont(Future.value(
      ByteData.sublistView(File('${fonts.path}/MaterialIcons-Regular.otf')
          .readAsBytesSync()),
    ))).load();
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('unread-filter')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('unread-filter')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('unread-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Seen yesterday'), findsNothing);
    expect(find.text('Urgent now'), findsOneWidget);
    expect(find.text('Waiting a while'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsNothing);
    await capture(tester, 'activity-unread-only');
    await tester.tap(find.byKey(const ValueKey('unread-filter')));
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('unread-filter')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    await capture(tester, 'sync-sections');
  });

  void expectWholeText(WidgetTester tester, Finder text, Rect bounds) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    final value = tester.widget<Text>(text).data!;
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: value.length));
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(bounds.contains(paragraph.localToGlobal(Offset(box.left, box.top))) &&
          bounds.contains(paragraph.localToGlobal(Offset(box.right, box.bottom))), isTrue,
          reason: 'Complete text must remain inset inside its row.');
    }
    expect(tester.getSize(text).height, closeTo(paragraph.size.height, 0.01),
        reason: 'Notification text must wrap, not be force-shrunk.');
  }

  testWidgets('Activity hierarchy keeps long messages dates and unread markers inside grouped rows', (tester) async {
    const title = 'Fictional riverside inspection evidence is ready for review';
    const subtitle = 'Photos and field observations are saved with this inspection record for the planning officer to review.';
    final oldDate = DateTime(2026, 1, 2, 9);
    for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
      for (final scaler in [TextScaler.noScaling, const TextScaler.linear(1.3), const TextScaler.linear(2), const _Android200TextScaler()]) {
        activityRows = [
          {...activity('long-unread', title, oldDate), 'subtitle': subtitle},
          {...activity('long-read', 'Read inspection record', oldDate, read: true), 'subtitle': 'Previously reviewed fictional activity.'},
        ];
        await pumpScreen(tester, size: Size(width, 844), scaler: scaler);
        final row = find.byKey(const ValueKey<dynamic>('long-unread'));
        final rowRect = tester.getRect(row);
        final message = find.descendant(of: row, matching: find.text(subtitle));
        final heading = find.descendant(of: row, matching: find.text(title));
        final timestamp = find.descendant(of: row, matching: find.text('2026-01-02'));
        expect(tester.getRect(timestamp).top, greaterThanOrEqualTo(tester.getRect(message).bottom + 7.9));
        expect(tester.getRect(timestamp).left, closeTo(tester.getRect(heading).left, 0.1));
        for (final text in [heading, message, timestamp]) {
          expectWholeText(tester, text, rowRect.deflate(15.5));
        }
        expect(tester.widget<Text>(heading).style!.fontWeight, FontWeight.w800);
        final readRow = find.byKey(const ValueKey<dynamic>('long-read'));
        expect(tester.widget<Text>(find.descendant(of: readRow,
            matching: find.text('Read inspection record'))).style!.fontWeight, FontWeight.w600);
        Finder dot(Finder parent) => find.descendant(of: parent, matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.constraints?.maxWidth == 8 &&
                widget.decoration is BoxDecoration && (widget.decoration! as BoxDecoration).color == InsightTheme.blue1));
        expect(dot(row), findsOneWidget);
        expect(dot(readRow), findsNothing);
        expect(rowRect.right - tester.getRect(dot(row)).right, closeTo(16, 0.1));
        final divider = tester.widget<Divider>(find.descendant(of: row, matching: find.byType(Divider)));
        expect(divider.indent, 72);
        expect(divider.endIndent, 16);
        await capture(tester, 'long-activity-${width.toInt()}-${scaler.runtimeType}-${scaler.scale(12).round()}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('Sync messages dates result icons and technical details retain aligned grouping', (tester) async {
    final oldDate = DateTime(2026, 1, 2, 9);
    for (final width in [320.0, 360.0, 390.0, 412.0, 430.0]) {
      for (final scaler in [TextScaler.noScaling, const TextScaler.linear(1.3), const TextScaler.linear(2), const _Android200TextScaler()]) {
        await tester.runAsync(() async {
          await db.delete('sync_log_entries');
          for (final result in ['success', 'error', 'warning', 'info']) {
            await db.insert('sync_log_entries', {
              ...syncEntry('result-$result', 'Fictional inspection evidence synchronization result: $result', oldDate),
              'result': result, 'technical_details': jsonEncode({'fixture_code': 'SAFE-7', 'attempt': 2}),
            });
          }
        });
        await pumpScreen(tester, mode: 1, size: Size(width, 844), scaler: scaler);
        for (final (result, icon) in [('success', Icons.check_circle_rounded), ('error', Icons.error_rounded),
            ('warning', Icons.warning_rounded), ('info', Icons.sync_rounded)]) {
          final message = find.text('Fictional inspection evidence synchronization result: $result');
          final entry = find.ancestor(of: message, matching: find.byType(ExpansionTile));
          final tile = tester.widget<ExpansionTile>(entry);
          expect(tile.tilePadding, const EdgeInsets.all(16));
          expect(tile.childrenPadding, const EdgeInsets.fromLTRB(72, 0, 16, 16));
          final timestamp = find.descendant(of: entry, matching: find.text('2026-01-02'));
          expect(tester.getRect(timestamp).top, greaterThanOrEqualTo(tester.getRect(message).bottom + 7.9));
          expect(tester.getRect(timestamp).left, closeTo(tester.getRect(message).left, 0.1));
          expect(find.descendant(of: entry, matching: find.byIcon(icon)), findsOneWidget);
          expectWholeText(tester, message, tester.getRect(entry).deflate(15.5));
          expectWholeText(tester, timestamp, tester.getRect(entry).deflate(15.5));
        }
        final dividers = tester.widgetList<Divider>(find.byType(Divider));
        expect(dividers, hasLength(3));
        for (final divider in dividers) {
          expect(divider.indent, 72);
          expect(divider.endIndent, 16);
        }
        final message = find.text('Fictional inspection evidence synchronization result: success');
        await tester.ensureVisible(message);
        await tester.pumpAndSettle();
        await tester.tap(message);
        await tester.pumpAndSettle();
        expect(find.text('fixture_code: SAFE-7\nattempt: 2'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('unread-filter')), matching: find.text('3')), findsOneWidget);
        await capture(tester, 'sync-details-${width.toInt()}-${scaler.runtimeType}-${scaler.scale(12).round()}');
        await tester.tap(find.byKey(const ValueKey('unread-filter')));
        await tester.pumpAndSettle();
        expect(message, findsNothing);
        await tester.tap(find.byKey(const ValueKey('unread-filter')));
        await tester.pumpAndSettle();
        expect(message, findsOneWidget);
        final stored = await tester.runAsync(() => db.query('sync_log_entries'));
        expect(stored, hasLength(4));
        expect(stored!.every((row) => !row.containsKey('is_read')), isTrue,
            reason: 'Expansion retains the existing local-only read state; it must not invent persisted acknowledgements.');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  for (final size in [
    const Size(320, 568),
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(430, 932),
    const Size(640, 360),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Modes stay readable and tappable at $size / $scale', (
        tester,
      ) async {
        activityRows = [activity('layout', 'Layout check', daysAgo(0))];
        await tester.runAsync(() async {
          await db.insert(
            'sync_log_entries',
            syncEntry('layout-sync', 'Sync layout check', daysAgo(0)),
          );
        });
        await pumpScreen(tester, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        for (final label in ['Notifications', 'Sync history']) {
          final text = find.text(label).last;
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final target = find.ancestor(of: text, matching: find.byType(InkWell)).first;
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$label must remain readable at the chosen text size',
          );
        }
        expect(tester.getSize(find.byKey(const ValueKey('unread-filter'))).height, greaterThanOrEqualTo(48));
        await tester.tap(find.text('Sync history'));
        await tester.pumpAndSettle();
        expect(find.text('Synchronization History'), findsOneWidget);
        expect(find.text('Sync layout check'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Notifications'));
        await tester.pumpAndSettle();
        expect(find.text('Layout check'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
