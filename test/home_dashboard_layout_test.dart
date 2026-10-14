import 'dart:async';
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
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Same AOSP 200% curve used by the Site Verification layout proof.
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  var noJobs = false;
  var activityCount = 1;
  int? completionTotal;
  DateTime? scheduledOverride;
  Completer<void>? fontGate;

  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    for (final family in ['Inter', 'Urbanist', 'OpenSans']) {
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
      if (asset.startsWith('Inter-')) await fontGate?.future;
      final realFonts = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return realFonts == null
          ? bytes
          : ByteData.sublistView(
              File(
                '$realFonts/${asset.split('-').first}.ttf',
              ).readAsBytesSync(),
            );
    });
    final icons = FontLoader('MaterialIcons')..addFont(Future.value(
      ByteData.sublistView(File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync()),
    ));
    await icons.load();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    sqfliteFfiInit();
    // Layout tests run under a fake clock; keep SQLite in-process while using
    // the real schema, including the owner-scoped drafts read by the cards.
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    final schema = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final table in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(schema)) {
      await db.execute(table.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    await Supabase.initialize(
      url: 'https://home.test',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final today = DateTime.now().toIso8601String();
        final rows = request.url.path.endsWith('/field_jobs')
            ? noJobs
                  ? []
                  : [
                      for (final status in [
                        'assigned',
                        'in_progress',
                        'completed',
                      ])
                        {
                          'id': 'job-$status',
                          'status': status,
                           'scheduled_date': status == 'assigned' && scheduledOverride != null
                               ? scheduledOverride!.toIso8601String()
                               : status == 'in_progress'
                              ? DateTime.now()
                                    .add(const Duration(days: 1))
                                    .toIso8601String()
                              : today,
                          'deadline_date': today,
                          'is_self_scheduled': true,
                          'created_at': today,
                          'supabase_zoning_applications': {
                            'applicant_name': status == 'in_progress'
                                ? 'PO due today'
                                : status == 'completed'
                                ? 'Completed applicant'
                                : 'Test applicant',
                            'barangay': 'San Carlos',
                            'reference_number': 'TEST-001',
                          },
                        },
                      {
                        'id': 'job-tomorrow',
                        'status': 'assigned',
                        'scheduled_date': DateTime.now()
                            .add(const Duration(days: 1))
                            .toIso8601String(),
                        'deadline_date': today,
                        'is_self_scheduled': true,
                        'created_at': today,
                        'supabase_zoning_applications': {
                          'applicant_name': 'Tomorrow applicant',
                          'barangay': 'San Carlos',
                          'reference_number': 'TOMORROW-001',
                        },
                      },
                      {
                        'id': 'job-po-due',
                        'status': 'assigned',
                        'scheduled_date': DateTime.now()
                            .add(const Duration(days: 1))
                            .toIso8601String(),
                        'deadline_date': today,
                        'is_self_scheduled': false,
                        'created_at': today,
                        'supabase_zoning_applications': {
                          'applicant_name': 'Available PO due today',
                          'barangay': 'San Carlos',
                          'reference_number': 'PO-DUE-001',
                        },
                      },
                      {
                        'id': 'job-overdue',
                        'status': 'assigned',
                        'scheduled_date': DateTime.now()
                            .subtract(const Duration(days: 1))
                            .toIso8601String(),
                        'deadline_date': DateTime.now()
                            .subtract(const Duration(days: 1))
                            .toIso8601String(),
                        'is_self_scheduled': true,
                        'created_at': today,
                        'supabase_zoning_applications': {
                          'applicant_name': 'Overdue applicant',
                          'barangay': 'San Carlos',
                          'reference_number': 'OVERDUE-001',
                        },
                      },
                    ]
            : [
                for (var i = 0; i < activityCount; i++)
                  {
                    'id': 'activity-${i + 1}',
                    'event_type': i < 10
                        ? 'inspection_completed'
                        : 'sync_manual',
                    'title': activityCount == 1
                        ? 'Inspection completed'
                        : 'Activity ${i + 1}',
                    'subtitle': 'Site inspection submitted.',
                    'occurred_at': today,
                    'is_read': false,
                  },
              ];
        if (request.url.path.endsWith('/field_jobs') && completionTotal != null) {
          rows.clear();
          rows.addAll(<Map<String, Object>>[for (var i = 0; i < completionTotal!; i++) {
            'id': 'completion-fixture-$i',
            'status': ['assigned', 'assigned', 'in_progress', 'completed'][i % 4],
            'is_self_scheduled': i % 4 == 0,
            'scheduled_date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            'deadline_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
            'created_at': today,
            'supabase_zoning_applications': {'applicant_name': 'Demonstration task $i', 'barangay': 'Rosario'},
          }]);
        }
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-${rows.length - 1}/${rows.length}',
          },
        );
      }),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'home-inspector',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    await SupabaseService.fetchMyJobs();
  });

  tearDownAll(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await Supabase.instance.dispose();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    for (final channel in ['connectivity', 'connectivity_status']) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/$channel'),
        null,
      );
    }
  });

  testWidgets('Completion labels remain inside their cards after delayed font loading', (tester) async {
    final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
    if (folder != null) {
      final fallback = FontLoader('Inter')..addFont(Future.value(
          ByteData.sublistView(File('$folder/Urbanist.ttf').readAsBytesSync())));
      await tester.runAsync(fallback.load);
    }
    fontGate = Completer<void>();
    addTearDown(() {
      if (!fontGate!.isCompleted) fontGate!.complete();
      fontGate = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)), child: child!),
      home: HomeDashboardScreen(profile: UserProfile(id: 'home-inspector',
          fullName: 'Maria Dela Cruz', role: 'inspector')),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    fontGate!.complete();
    await tester.runAsync(() => GoogleFonts.pendingFonts());
    await tester.pump();
    await tester.pump();
    for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
      final cell = find.byKey(ValueKey('completion_$label'));
      final text = find.descendant(of: cell, matching: find.text(label));
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final glyphs = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length));
      expect(paragraph.localToGlobal(Offset(glyphs.single.right, 0)).dx,
          lessThanOrEqualTo(tester.getRect(cell).right - 6),
          reason: 'The actual font must fit without waiting for a parent refresh.');
    }
    if (folder != null) {
      expect(tester.getRect(find.byKey(const ValueKey('completion_Completed'))).right,
          lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('completion_chart'))).right),
          reason: 'Once the real font fits, the legend must not retain a wider fallback-font viewport.');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Full calendar fits every weekday and date together on phones and keeps dotted-day tasks', (tester) async {
    final now = DateTime.now();
    scheduledOverride = DateTime(now.year, now.month, 2);
    addTearDown(() => scheduledOverride = null);
    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
        id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector',
      ))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Show full calendar'));
      await tester.tap(find.byTooltip('Show full calendar'));
      await tester.pumpAndSettle();
      final calendar = find.byKey(const ValueKey('full_calendar'));
      // Measure the month card itself, not its full-width Padding wrapper.
      final monthCard = find.byKey(const ValueKey('calendar_month_card'));
      expect(monthCard, findsOneWidget);
      final bounds = tester.getRect(monthCard);
      expect(bounds.left, greaterThanOrEqualTo(20.0),
          reason: 'The month must retain the Home gutter even on a 360dp phone.');
      expect(width - bounds.right, greaterThanOrEqualTo(20.0));
      final strip = tester.getRect(find.byKey(const ValueKey('calendar_section')));
      expect(bounds.left, closeTo(strip.left, 0.5));
      expect(bounds.right, closeTo(strip.right, 0.5));
      for (final weekday in ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']) {
        final label = find.descendant(of: calendar, matching: find.text(weekday));
        expect(tester.getRect(label).left, greaterThanOrEqualTo(bounds.left));
        expect(tester.getRect(label).right, lessThanOrEqualTo(bounds.right),
            reason: '$weekday must fit in the same frame as all other weekdays.');
      }
      for (var day = 1; day <= DateTime(now.year, now.month + 1, 0).day; day++) {
        final tile = find.byKey(ValueKey('calendar_day_$day'));
        expect(tile, findsOneWidget);
        expect(tester.getRect(tile).left, greaterThanOrEqualTo(bounds.left));
        expect(tester.getRect(tile).right, lessThanOrEqualTo(bounds.right),
            reason: 'Date $day must fit without horizontal scrolling.');
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(tile).width, greaterThanOrEqualTo(width == 320 ? 39 : 44),
            reason: 'Only the narrow phone needs the approved compact-width exception.');
      }
      final plainDay = DateTime(now.year, now.month, 2).weekday == DateTime.sunday ? 3 : 1;
      final firstNumber = find.descendant(of: find.byKey(ValueKey('calendar_day_$plainDay')),
          matching: find.text('$plainDay'));
      final dottedNumber = find.descendant(of: find.byKey(const ValueKey('calendar_day_2')),
          matching: find.text('2'));
      expect(tester.getRect(firstNumber).center.dy, closeTo(tester.getRect(dottedNumber).center.dy, 0.1),
          reason: 'Task dots must not shift a date number off its week baseline.');
      expect(find.descendant(of: find.byKey(const ValueKey('calendar_section')),
          matching: calendar), findsNothing,
          reason: 'The full month must not share the sliding calendar surface.');
      final day2 = find.byKey(const ValueKey('calendar_day_2'));
      await tester.ensureVisible(day2);
      await tester.pumpAndSettle();
      await tester.tap(day2);
      await tester.pumpAndSettle();
      expect(find.descendant(of: calendar, matching: find.text('Test applicant')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Full month card is content-sized with a compact selected date plate', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
      id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector',
    ))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('calendar_month_card'));
    final cardRect = tester.getRect(card);
    final firstTile = find.byKey(const ValueKey('calendar_day_1'));
    final first = tester.getRect(firstTile);
    final eighth = tester.getRect(find.byKey(const ValueKey('calendar_day_8')));
    expect(eighth.top - first.top, closeTo(first.height, 0.5),
        reason: 'Week rows must sit flush; decorative gaps are wasted height.');
    // Selected-day task detail is real content, so judge the month itself.
    final summary = find.descendant(of: card, matching: find.textContaining('Tasks for'));
    final summaryHeight = summary.evaluate().isEmpty
        ? 0.0
        : tester.getSize(
            find.ancestor(of: summary, matching: find.byType(Container)).first,
          ).height + 8; // Include the task detail's separating gap.
    final month = DateTime.now();
    final days = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((DateTime(month.year, month.month).weekday % 7 + days) / 7).ceil();
    expect(cardRect.height - summaryHeight, lessThanOrEqualTo(86 + weeks * 44),
        reason: 'Only the weeks this month needs may add to its compact height.');
    final selectedPlate =
        find.byKey(ValueKey('calendar_day_plate_${DateTime.now().day}'));
    expect(selectedPlate, findsOneWidget,
        reason: 'The selected date needs its own quieter visual plate.');
    expect(tester.getSize(selectedPlate).shortestSide, lessThanOrEqualTo(36));
    expect(tester.getSize(firstTile).shortestSide, greaterThanOrEqualTo(44),
        reason: 'The compact month keeps a full-cell target around the smaller plate.');
    final selectedDate = find.byKey(const ValueKey('calendar_selected_date'));
    expect(selectedDate, findsOneWidget,
        reason: 'The month header states the selected date.');
    expect(tester.getRect(selectedDate).top, lessThan(first.top),
        reason: 'The selected date belongs in the header, not the grid.');
    final output = Platform.environment['IMAPS_HOME_VISUAL_DIR'];
    if (output != null) {
      Future<void> capture(String name) async {
        final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(output).createSync(recursive: true);
          File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await capture('home-calendar-portrait');
      await tester.ensureVisible(find.byKey(const ValueKey('calendar_day_2')));
      await tester.tap(find.byKey(const ValueKey('calendar_day_2')));
      await tester.pumpAndSettle();
      await capture('home-calendar-task-day');
      await tester.ensureVisible(find.byTooltip('Hide full calendar'));
      await tester.tap(find.byTooltip('Hide full calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await capture('home-calendar-closing');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show full calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await capture('home-calendar-opening');
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Calendar audit renders the real Home viewport and measures responsive month shapes', (tester) async {
    final output = Platform.environment['IMAPS_CALENDAR_AUDIT_DIR'];
    final captureKey = GlobalKey();
    final metrics = <Map<String, Object>>[];
    final layoutErrors = <String>[];
    if (output != null) {
      Directory(output).createSync(recursive: true);
      File('$output/layout-errors.txt').writeAsStringSync('');
    }
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (output != null) {
        File('$output/layout-errors.txt').writeAsStringSync(details.toString(), mode: FileMode.append);
      }
      reportError?.call(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
    scheduledOverride = DateTime(2026, 10, 15);
    addTearDown(() => scheduledOverride = null);
    addTearDown(tester.view.reset);
    Future<void> capture(String name) async {
      if (output == null) return;
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        expect(image.width, tester.view.physicalSize.width * 2);
        expect(image.height, tester.view.physicalSize.height * 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(output).createSync(recursive: true);
        File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    for (final scenario in const [
      (name: 'portrait', size: Size(390, 844), scaler: TextScaler.noScaling),
      (name: 'phone-360', size: Size(360, 800), scaler: TextScaler.noScaling),
      (name: 'small-phone', size: Size(320, 568), scaler: TextScaler.noScaling),
      (name: 'landscape', size: Size(844, 390), scaler: TextScaler.noScaling),
      (name: 'small-phone-130', size: Size(320, 568), scaler: TextScaler.linear(1.3)),
      (name: 'phone-360-130', size: Size(360, 800), scaler: TextScaler.linear(1.3)),
      (name: 'portrait-200', size: Size(390, 844), scaler: TextScaler.linear(2)),
      (name: 'phone-360-200', size: Size(360, 800), scaler: TextScaler.linear(2)),
      (name: 'small-phone-200', size: Size(320, 568), scaler: TextScaler.linear(2)),
      (name: 'landscape-200', size: Size(844, 390), scaler: TextScaler.linear(2)),
      (name: 'android-200', size: Size(320, 568), scaler: _Android200TextScaler()),
      (name: 'tablet', size: Size(800, 1280), scaler: TextScaler.noScaling),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: const ColorScheme.light(
          primary: InsightTheme.blue1, secondary: InsightTheme.blue2,
          surface: InsightTheme.surface, error: InsightTheme.red)),
        builder: (context, child) => RepaintBoundary(key: captureKey, child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scenario.scaler), child: child!)),
        home: Scaffold(extendBody: true,
          bottomNavigationBar: InsightBottomNav(currentIndex: 0, items: const [
            InsightNavItem(icon: Icons.home, label: 'Home'),
            InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
            InsightNavItem(icon: Icons.sync, label: 'Updates'),
            InsightNavItem(icon: Icons.person, label: 'Profile'),
          ], onTap: (_) {}, onQuickActionsTap: () {}),
          body: HomeDashboardScreen(profile: UserProfile(id: 'home-inspector',
            fullName: 'Maria Dela Cruz', role: 'inspector'))),
      ));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await GoogleFonts.pendingFonts();
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Show full calendar'));
      await tester.tap(find.byTooltip('Show full calendar'));
      await tester.pumpAndSettle();
      final calendar = find.byKey(const ValueKey('full_calendar'));
      final card = find.byKey(const ValueKey('calendar_month_card'));
      var displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
      Future<void> browse(DateTime target) async {
        while (displayedMonth != target) {
          final next = displayedMonth.isBefore(target);
          await tester.ensureVisible(find.byTooltip(next ? 'Next month' : 'Previous month'));
          await tester.tap(find.byTooltip(next ? 'Next month' : 'Previous month'));
          await tester.pumpAndSettle();
          displayedMonth = DateTime(displayedMonth.year, displayedMonth.month + (next ? 1 : -1));
        }
        await tester.ensureVisible(find.byKey(const ValueKey('calendar_day_8')));
        await tester.tap(find.byKey(const ValueKey('calendar_day_8')));
        await tester.pumpAndSettle();
      }
      for (final month in [DateTime(2026, 10), DateTime(2026, 2), DateTime(2026, 8)]) {
        await browse(month);
        final days = DateTime(month.year, month.month + 1, 0).day;
        final weeks = ((DateTime(month.year, month.month).weekday % 7 + days) / 7).ceil();
        final first = tester.getRect(find.byKey(const ValueKey('calendar_day_1')));
        final eighth = tester.getRect(find.byKey(const ValueKey('calendar_day_8')));
        expect(eighth.top - first.top, closeTo(first.height, 0.01));
        final cardRect = tester.getRect(card);
        for (var column = 0; column < 7; column++) {
          final heading = find.descendant(of: find.byKey(ValueKey('calendar_weekday_$column')),
              matching: find.byType(Text));
          final rect = tester.getRect(heading);
          expect(rect.left, greaterThanOrEqualTo(cardRect.left));
          expect(rect.right, lessThanOrEqualTo(cardRect.right));
        }
        for (var day = 1; day <= days; day++) {
          final tile = find.byKey(ValueKey('calendar_day_$day'));
          final tileRect = tester.getRect(tile);
          expect(tileRect.left, greaterThanOrEqualTo(cardRect.left));
          expect(tileRect.right, lessThanOrEqualTo(cardRect.right));
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
          expect(tileRect.width, greaterThanOrEqualTo(scenario.size.width == 320 ? 39 : 44));
          final label = find.descendant(of: tile, matching: find.text('$day'));
          final paragraph = tester.renderObject<RenderParagraph>(label);
          final glyphs = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: '$day'.length));
          expect(glyphs, hasLength(1), reason: 'Two-digit dates must remain on one line.');
          final plate = tester.getRect(find.byKey(ValueKey('calendar_day_plate_$day')));
          expect(paragraph.localToGlobal(Offset(glyphs.single.left, 0)).dx, greaterThanOrEqualTo(plate.left));
          expect(paragraph.localToGlobal(Offset(glyphs.single.right, 0)).dx, lessThanOrEqualTo(plate.right));
          expect(tester.widget<Text>(label).style!.fontSize, greaterThanOrEqualTo(12.5),
              reason: 'Grid fitting must not be achieved by shrinking date text.');
          final column = DateTime(month.year, month.month, day).weekday % 7;
          final heading = find.byKey(ValueKey('calendar_weekday_$column'));
          expect(tileRect.center.dx, closeTo(tester.getRect(heading).center.dx, 0.01),
              reason: 'Every date must align with its weekday column.');
        }
        final cardSize = tester.getSize(card);
        metrics.add({
          'scenario': scenario.name, 'month': '${month.year}-${month.month}',
          'viewport': [scenario.size.width, scenario.size.height],
          'card': [cardSize.width, cardSize.height], 'weeks': weeks,
          'rowHeight': first.height, 'rowGap': eighth.top - first.bottom,
          'gridWidth': first.width * 7,
          'allColumnsFitTogether': true,
          'weekdayLabels': [for (var column = 0; column < 7; column++)
            tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('calendar_weekday_$column')),
                matching: find.byType(Text))).data!],
          'compactCard': [tester.getSize(find.byKey(const ValueKey('calendar_section'))).width,
            tester.getSize(find.byKey(const ValueKey('calendar_section'))).height],
          'lanyardHeight': tester.getSize(find.byKey(const ValueKey('calendar_lanyard'))).height,
        });
        if (output != null) {
          File('$output/metrics.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
        }
        final name = '${scenario.name}-$weeks-weeks';
        await tester.ensureVisible(find.byKey(const ValueKey('calendar_section')));
        await tester.pumpAndSettle();
        await capture('$name-context');
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await capture('$name-month');
        if (scenario.name == 'small-phone-200' && month == DateTime(2026, 10)) {
          final taskDate = find.byKey(const ValueKey('calendar_day_15'));
          await tester.ensureVisible(taskDate);
          await tester.tap(taskDate);
          await tester.pumpAndSettle();
          expect(find.descendant(of: calendar, matching: find.text('Test applicant')), findsOneWidget);
          await capture('small-phone-200-task-selected');
          await tester.ensureVisible(find.text('Tasks for 15 Oct'));
          await tester.pumpAndSettle();
          await capture('small-phone-200-task-detail');
        }
        // Vertical scrolling may be necessary; every weekday remains in frame.
        final last = find.byKey(ValueKey('calendar_day_$days'));
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(const ValueKey('calendar_selected_date'))).data,
            contains(' $days '));
        final error = tester.takeException();
        if (error != null) layoutErrors.add('${scenario.name}: $error');
      }
      final lastWeek = find.byKey(const ValueKey('calendar_day_28'));
      await tester.ensureVisible(lastWeek);
      await tester.pumpAndSettle();
      expect(tester.getRect(lastWeek).bottom,
          lessThan(tester.getRect(find.byType(InsightBottomNav)).top),
          reason: 'Vertical scrolling must clear the fixed nav, including its middle columns.');
      await tester.tap(lastWeek);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('calendar_selected_date'))).data, contains(' 28 '));
      if (scenario.name.contains('landscape') || scenario.name == 'small-phone-200') {
        await capture('${scenario.name}-last-week-reachable');
      }
      if (scenario.name == 'portrait') {
        await browse(DateTime(2026, 10));
        await tester.ensureVisible(find.byKey(const ValueKey('calendar_day_15')));
        await tester.tap(find.byKey(const ValueKey('calendar_day_15')));
        await tester.pumpAndSettle();
        expect(find.descendant(of: calendar, matching: find.text('Test applicant')), findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await capture('portrait-task-selected');
        await tester.ensureVisible(find.byTooltip('Hide full calendar'));
        await tester.tap(find.byTooltip('Hide full calendar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        await capture('portrait-closing-90ms');
        // Interrupt the reverse animation, then interrupt the subsequent reveal.
        await tester.tap(find.byTooltip('Show full calendar'));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(find.byTooltip('Hide full calendar'));
        await tester.pumpAndSettle();
        expect(calendar, findsNothing);
        await capture('portrait-collapsed');
        await tester.tap(find.byTooltip('Show full calendar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        await capture('portrait-opening-90ms');
        await tester.pumpAndSettle();
        expect(calendar, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
    if (output != null) {
      File('$output/metrics.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
    }
    expect(layoutErrors, isEmpty,
        reason: 'Complete Home errors remain failures; inspect layout-errors.txt for their owning widget.');
  });

  testWidgets('Completion readout and direct legend retain all counts under nonlinear scaling', (tester) async {
    final captureKey = GlobalKey();
    addTearDown(() => completionTotal = null);
    addTearDown(tester.view.reset);
    final output = Platform.environment['IMAPS_UI_CAPTURE_DIR'];
    for (final (total, counts) in [(0, [0, 0, 0, 0]), (24, [6, 6, 6, 6]), (321, [81, 80, 80, 80])]) {
      completionTotal = total;
      for (final scale in [TextScaler.noScaling, const TextScaler.linear(2), const _Android200TextScaler()]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: scale),
            child: RepaintBoundary(key: captureKey, child: child!)),
          home: HomeDashboardScreen(profile: UserProfile(id: 'home-inspector', fullName: 'Demonstration Inspector', role: 'inspector')),
        ));
        for (var frame = 0; frame < 40; frame++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byKey(const ValueKey('completion_chart')).evaluate().isNotEmpty ||
              find.text('No tasks yet.').evaluate().isNotEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Task completion flow'));
        await tester.pumpAndSettle();
        final chart = find.byKey(const ValueKey('completion_chart'));
        if (total == 0) {
          expect(find.text('No tasks yet.'), findsOneWidget);
        } else {
          for (final (i, label) in ['Scheduled', 'Pending', 'Ongoing', 'Completed'].indexed) {
            final row = find.byKey(ValueKey('completion_$label'));
            expect(find.descendant(of: row, matching: find.text('${counts[i]}')), findsOneWidget);
            expect(find.descendant(of: row, matching: find.text(label)), findsOneWidget);
            expect(tester.getRect(row).right, lessThanOrEqualTo(tester.getRect(chart).right));
          }
          final arcs = tester.widgetList<CircularProgressIndicator>(find.descendant(of: chart,
            matching: find.byType(CircularProgressIndicator))).toList();
          for (var i = 0; i < 4; i++) {
            expect(arcs[i].value, closeTo(counts[i] / total, 0.001));
          }
          final readout = find.byKey(const ValueKey('completion_readout'));
          final face = find.byKey(const ValueKey('completion_rings'));
          final tasks = tester.renderObject<RenderParagraph>(
            find.descendant(of: readout, matching: find.text('Tasks')));
          expect(tasks.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 5)),
            hasLength(1), reason: 'The center label must remain a whole word with the actual inherited font.');
          expect(tester.getRect(face).contains(tester.getRect(readout).topLeft), isTrue);
          expect(tester.getRect(face).contains(tester.getRect(readout).bottomRight), isTrue);
        }
        if (output != null) {
          final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$output/home-completion-$total-${scale.runtimeType}-${scale.scale(12).round()}.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('Lanyard clip is painted over the month card edge', (tester) async {
    final captureKey = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => RepaintBoundary(key: captureKey, child: child!),
      home: HomeDashboardScreen(profile: UserProfile(id: 'home-inspector',
          fullName: 'Maria Dela Cruz', role: 'inspector'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    final clip = tester.getRect(find.byKey(const ValueKey('calendar_lanyard_clip')));
    final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixel = boundary.globalToLocal(Offset(clip.center.dx, clip.bottom - 2));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final index = (pixel.dy.floor() * image.width + pixel.dx.floor()) * 4;
      expect(Color.fromARGB(rgba.getUint8(index + 3), rgba.getUint8(index),
          rgba.getUint8(index + 1), rgba.getUint8(index + 2)), InsightTheme.ink3,
          reason: 'Geometric overlap alone is insufficient: the card must not paint over its clip.');
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Expanded dates announce full date selection and real task count', (tester) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.now();
    final day = now.day < 20 ? 25 : 5; // Distinct from today's other fixture jobs.
    scheduledOverride = DateTime(now.year, now.month, day);
    addTearDown(() => scheduledOverride = null);
    try {
    await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
      id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    for (final (index, weekday) in const ['Sunday', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'].indexed) {
      expect(tester.getSemantics(find.byKey(ValueKey('calendar_weekday_$index'))).label, weekday);
    }
    final date = find.byKey(ValueKey('calendar_day_$day'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(date);
    expect(node.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains('${DateTime.now().year}'));
    expect(node.label, contains('1 task'));
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    expect(find.descendant(of: find.byKey(const ValueKey('full_calendar')),
        matching: find.text('Test applicant')), findsOneWidget);
    final another = tester.getSemantics(find.byKey(const ValueKey('calendar_day_3')));
    binding.performSemanticsAction(ui.SemanticsActionEvent(type: ui.SemanticsAction.tap,
        viewId: tester.view.viewId, nodeId: another.id));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(date).flagsCollection.isSelected, ui.Tristate.isFalse);
    expect(tester.widget<Text>(find.byKey(const ValueKey('calendar_selected_date'))).data, contains(' 3 '));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Calendar hangs from an attached lanyard and reverses on close', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
      id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector',
    ))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    final strap = find.byKey(const ValueKey('calendar_lanyard'));
    final card = find.byKey(const ValueKey('calendar_month_card'));
    expect(strap, findsOneWidget);
    final clip = find.byKey(const ValueKey('calendar_lanyard_clip'));
    expect(clip, findsOneWidget,
        reason: 'A lanyard needs a visible clip and slot, not floating lines.');
    final strapRect = tester.getRect(strap);
    final cardRect = tester.getRect(card);
    final clipRect = tester.getRect(clip);
    expect(clipRect.bottom, greaterThan(cardRect.top + 2),
        reason: 'The clip must grip the card edge, not hover above it.');
    expect(clipRect.width, lessThanOrEqualTo(16),
        reason: 'A clip is hardware-sized, not a floating panel.');
    expect(strapRect.width, greaterThanOrEqualTo(56),
        reason: 'A strap wide enough to read as a strap, not two hairlines.');
    expect(strapRect.center.dx, closeTo(cardRect.center.dx, 1.0),
        reason: 'The strap hangs from the centre of the card it carries.');
    // Measure real points, not rotated bounding boxes: a rotated box's AABB grows
    // even when the widget itself has not moved.
    Offset pivot(WidgetTester tester) =>
        (tester.renderObject<RenderBox>(strap)).localToGlobal(
          Offset(tester.getSize(strap).width / 2, 0),
        );
    Offset cardFoot(WidgetTester tester) =>
        tester.renderObject<RenderBox>(card).localToGlobal(
          Offset(tester.getSize(card).width / 2, tester.getSize(card).height),
        );
    final restStrap = pivot(tester);
    final restCard = cardFoot(tester);
    await tester.ensureVisible(find.byTooltip('Hide full calendar'));
    await tester.tap(find.byTooltip('Hide full calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midStrap = pivot(tester);
    final midCard = cardFoot(tester);
    expect(midStrap.dx, closeTo(restStrap.dx, 0.5),
        reason: 'The strap top is the single shared hanging pivot.');
    expect((midCard.dx - restCard.dx).abs(), greaterThan(0.5),
        reason: 'The card must swing about that pivot while closing.');
    expect((midStrap.dy - restStrap.dy).abs(), lessThan(0.5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('full_calendar')), findsNothing);
    expect(find.byKey(const ValueKey('calendar_lanyard')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reduced motion reveals the calendar without a swing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    Widget screen() => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: HomeDashboardScreen(profile: UserProfile(
        id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector',
      )),
    );
    await tester.pumpWidget(screen());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pump();
    final strap = find.byKey(const ValueKey('calendar_lanyard'));
    final card = find.byKey(const ValueKey('calendar_month_card'));
    final first = tester.getRect(card);
    final firstStrap = tester.getRect(strap).topCenter;
    await tester.tap(find.byTooltip('Hide full calendar'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pump();
    expect(tester.getRect(card), first,
        reason: 'Reduced motion presents the calendar immediately.');
    expect(tester.getRect(strap).topCenter, firstStrap);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Full calendar keeps two-digit task dates intact at enlarged text', (tester) async {
    scheduledOverride = DateTime(DateTime.now().year, DateTime.now().month, 20);
    addTearDown(() => scheduledOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)), child: child!),
      home: HomeDashboardScreen(profile: UserProfile(id: 'home-inspector',
          fullName: 'Maria Dela Cruz', role: 'inspector')),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('calendar_day_20'));
    final number = find.descendant(of: tile, matching: find.text('20'));
    final paragraph = tester.renderObject<RenderParagraph>(number);
    expect(paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 2)),
        hasLength(1), reason: 'A day number is one intact label, including dates with task dots.');
    final card = find.byKey(const ValueKey('calendar_month_card'));
    expect(tester.getSize(tile).width, lessThanOrEqualTo(tester.getSize(card).width / 7),
        reason: 'Enlarged text must not widen the seven-column grid beyond its card.');
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final plate = tester.getRect(find.byKey(const ValueKey('calendar_day_plate_20')));
    final label = tester.getRect(number);
    expect(label.left - plate.left, greaterThanOrEqualTo(2),
        reason: 'Large selected digits need breathing room inside the colored plate.');
    expect(plate.right - label.right, greaterThanOrEqualTo(2));
    expect(label.top - plate.top, greaterThanOrEqualTo(4));
    expect(find.descendant(of: find.byKey(const ValueKey('full_calendar')),
        matching: find.text('Test applicant')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Full calendar highlights the clamped date after month-end browsing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
        id: 'home-inspector', fullName: 'Maria Dela Cruz', role: 'inspector'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Show full calendar'));
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    final month = DateTime.now();
    for (var next = month.month; next < 13; next++) {
      await tester.ensureVisible(find.byTooltip('Next month'));
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const ValueKey('calendar_day_31')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar_day_31')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final lastDay = DateTime(month.year + 1, 3, 0).day;
    final tile = find.byKey(ValueKey('calendar_day_$lastDay'));
    final surface = tester.widget<Container>(find.descendant(of: tile, matching: find.byType(Container)).first);
    expect((surface.decoration! as BoxDecoration).color, const Color(0xFF2563EB));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(844, 390),
    const Size(430, 932),
    const Size(932, 430),
    const Size(800, 1280),
    const Size(1280, 800),
    const Size(640, 360),
    const Size(740, 320),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Home $size at $scale text keeps calendar and sections usable', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.reset);
          final tabs = <int>[];
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                extendBody: true,
                bottomNavigationBar: InsightBottomNav(
                  currentIndex: 0,
                  items: const [
                    InsightNavItem(icon: Icons.home, label: 'Home'),
                    InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
                    InsightNavItem(icon: Icons.sync, label: 'Sync'),
                    InsightNavItem(icon: Icons.person, label: 'Profile'),
                  ],
                  onTap: tabs.add,
                  onQuickActionsTap: () {},
                ),
                body: HomeDashboardScreen(
                  profile: UserProfile(
                    id: 'home-inspector',
                    fullName: 'Maria Isabella Dela Cruz',
                    role: 'inspector',
                  ),
                  onNavigateToTab: tabs.add,
                ),
              ),
            ),
          );
          // SQLite FFI runs outside Flutter's fake clock; finish the data load
          // before waiting for the entrance/loading animations to settle.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('calendar_preview')), findsOneWidget);
          if (size.height < 600 || scale > 1) {
            await tester.ensureVisible(find.byTooltip('Show Time and Date'));
            await tester.pumpAndSettle();
          }
          final initialCalendarButton = tester.getRect(find.ancestor(
            of: find.text('Calendar'), matching: find.byType(TextButton),
          ));
          final initialPager = tester.getRect(find.byKey(const ValueKey('home_calendar_pager')));
          expect(initialCalendarButton.center.dx, closeTo(initialPager.center.dx, 0.1));
          expect(initialCalendarButton.top, closeTo(initialPager.bottom, 0.1));
          await tester.tap(find.byTooltip('Show Time and Date'));
          await tester.pumpAndSettle();
          final timeCalendarButton = tester.getRect(find.ancestor(
            of: find.text('Calendar'), matching: find.byType(TextButton),
          ));
          expect(timeCalendarButton, initialCalendarButton,
            reason: 'Switching main views must not move the Calendar row or the next section.');
          final layoutError = tester.takeException();
          expect(
            layoutError,
            isNull,
            reason: layoutError is FlutterError
                ? layoutError.toStringDeep()
                : null,
          );
          expect(find.text('Maria Isabella Dela Cruz'), findsOneWidget);
          expect(find.text('Test applicant'), findsWidgets);
          final inspectorSection = find.byKey(
            const ValueKey('inspector_section'),
          );
          final calendarSection = find.byKey(
            const ValueKey('calendar_section'),
          );
          final assignmentSection = find.byKey(
            const ValueKey('assignments_section'),
          );
          expect(
            tester.getRect(inspectorSection).bottom,
            lessThan(tester.getRect(calendarSection).top),
          );
          expect(
            tester.getRect(calendarSection).bottom,
            lessThan(tester.getRect(assignmentSection).top),
          );
          expect(
            tester.getSize(find.text('FieldSync')).height,
            lessThanOrEqualTo(scale * 16 * 1.2 + 2),
            reason:
                'The app name must remain readable on one line inside the page gutters.',
          );
          final identity = tester.getRect(find.text('FieldSync'));
          final online = tester.getRect(find.text('Online'));
          expect(online.top, greaterThanOrEqualTo(identity.bottom + 4));
          expect(online.left, greaterThanOrEqualTo(identity.left));
          final notification = tester.getRect(
            find.byIcon(Icons.notifications_outlined),
          );
          if (notification.top >= online.bottom) {
            expect(notification.top, greaterThanOrEqualTo(online.bottom + 8));
          } else {
            expect(notification.left, greaterThan(identity.right + 16));
          }
          final clock = tester.getRect(
            find.byKey(const ValueKey('clock_date_card')),
          );
          expect(
            clock.top - tester.getRect(calendarSection).top,
            greaterThanOrEqualTo(12),
          );
          final dateTile = tester.getRect(
            find.bySemanticsLabel("Show today's tasks"),
          );
          expect(dateTile.top - clock.top, greaterThanOrEqualTo(8));
          expect(clock.bottom - dateTile.bottom, greaterThanOrEqualTo(8));
          final pageBounds = tester.getRect(inspectorSection);
          expect(pageBounds.left, greaterThanOrEqualTo(20));
          expect(pageBounds.right, lessThanOrEqualTo(size.width - 20));
          for (final section in [calendarSection, assignmentSection]) {
            final bounds = tester.getRect(section);
            expect(bounds.left, closeTo(pageBounds.left, 0.01));
            expect(bounds.right, closeTo(pageBounds.right, 0.01));
          }
          if (scale == 1 &&
              size.width < size.height &&
              size.width <= 430 &&
              size.height >= 800) {
            final card = tester.getRect(
              find.byType(ActiveAssignmentsFolderCard).first,
            );
            expect(
              card.width,
              greaterThanOrEqualTo(size.width * 0.8),
              reason:
                  'The assignment carousel keeps its original full-bleed card width.',
            );
            final trigger = tester.getRect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == 'Quick actions',
              ),
            );
            expect(
              card.bottom,
              lessThanOrEqualTo(trigger.top - 8),
              reason:
                  'The first assignment must be fully visible before scrolling, above the floating nav controls.',
            );
          }
          expect(find.byKey(const ValueKey('full_calendar')), findsNothing);
          await tester.ensureVisible(
            find.bySemanticsLabel("Show today's tasks"),
          );
          await tester.tap(find.bySemanticsLabel("Show today's tasks"));
          // Check intermediate frames too: a settled frame alone misses
          // unbounded viewports or overflows during the sliding tile animation.
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 60));
            expect(tester.takeException(), isNull);
          }
          await tester.pumpAndSettle();
            final notes = find.byKey(const ValueKey('today_tasks'));
            expect(notes, findsOneWidget);
            expect(tester.getSize(notes).height, greaterThanOrEqualTo(scale * 50),
              reason: 'Today notes keep a readable viewport above the Calendar control.');
          await tester.ensureVisible(notes);
          expect(
            find.descendant(of: notes, matching: find.text('Test applicant')),
            findsOneWidget,
          );
          await tester.drag(notes, const Offset(0, -160));
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: notes, matching: find.text('PO due today')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: notes,
              matching: find.text('Available PO due today'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: notes,
              matching: find.text('Completed applicant'),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: notes,
              matching: find.text('Tomorrow applicant'),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: notes,
              matching: find.text('Overdue applicant'),
            ),
            findsNothing,
          );
          await tester.ensureVisible(
            find.bySemanticsLabel('Show clock and date'),
          );
          await tester.tap(find.bySemanticsLabel('Show clock and date'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('today_tasks')), findsNothing);
          await tester.ensureVisible(find.byTooltip('Show full calendar'));
          await tester.tap(find.byTooltip('Show full calendar'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('full_calendar')), findsOneWidget);
          expect(tester.takeException(), isNull);
          final calendar = find.byKey(const ValueKey('full_calendar'));
          expect(
            find.descendant(
              of: calendar,
              matching: find.text('Test applicant'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: calendar, matching: find.text('PO due today')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: calendar,
              matching: find.text('Tomorrow applicant'),
            ),
            findsNothing,
          );
          final tomorrow = DateTime.now().add(const Duration(days: 1));
          if (tomorrow.month != DateTime.now().month) {
            await tester.tap(find.byTooltip('Next month'));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(
            find.byKey(ValueKey('calendar_day_${tomorrow.day}')),
          );
          await tester.tap(
            find.byKey(ValueKey('calendar_day_${tomorrow.day}')),
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: calendar,
              matching: find.text('Tomorrow applicant'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: calendar, matching: find.text('PO due today')),
            findsNothing,
          );
          await tester.ensureVisible(find.byTooltip('Hide full calendar'));
          await tester.tap(find.byTooltip('Hide full calendar'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('full_calendar')), findsNothing);
          await tester.ensureVisible(find.text('See All'));
          // Selecting another calendar date must not turn Today into tomorrow.
          await tester.ensureVisible(
            find.bySemanticsLabel("Show today's tasks"),
          );
          await tester.tap(find.bySemanticsLabel("Show today's tasks"));
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: notes, matching: find.text('Test applicant')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: notes,
              matching: find.text('Tomorrow applicant'),
            ),
            findsNothing,
          );
          await tester.ensureVisible(find.text('See All'));
          await tester.tap(find.text('See All'));
          await tester.ensureVisible(find.text('More details'));
          await tester.tap(find.text('More details'));
          expect(tabs, [1, 1]);
          expect(find.text('1 Overdue'), findsOneWidget);
          final completionBounds = tester.getRect(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('completion_chart')),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(completionBounds.left, closeTo(pageBounds.left, 0.01));
          expect(completionBounds.right, closeTo(pageBounds.right, 0.01));
          final scheduled = tester.getRect(
            find.byKey(const ValueKey('completion_Scheduled')),
          );
          final pending = tester.getRect(
            find.byKey(const ValueKey('completion_Pending')),
          );
          final ongoing = tester.getRect(
            find.byKey(const ValueKey('completion_Ongoing')),
          );
          final completed = tester.getRect(
            find.byKey(const ValueKey('completion_Completed')),
          );
          // The approved unified reference uses four direct label/count rows.
          expect(pending.top, greaterThanOrEqualTo(scheduled.bottom));
          expect(ongoing.top, greaterThanOrEqualTo(pending.bottom));
          expect(completed.top, greaterThanOrEqualTo(ongoing.bottom));
          expect(pending.left, scheduled.left);
          final chart = find.byKey(const ValueKey('completion_chart'));
          final arcs = tester
              .widgetList<CircularProgressIndicator>(
                find.descendant(
                  of: chart,
                  matching: find.byType(CircularProgressIndicator),
                ),
              )
              .toList();
          final statusColors = {
            'Scheduled': const Color(0xFFD97706),
            'Pending': const Color(0xFF60A5FA),
            'Ongoing': const Color(0xFF2563EB),
            'Completed': const Color(0xFF16A34A),
          };
          for (final (index, entry) in statusColors.entries.indexed) {
            final cell = find.byKey(ValueKey('completion_${entry.key}'));
            final background =
                (tester.widget<Container>(cell).decoration! as BoxDecoration)
                    .color!;
            expect(background, InsightTheme.surface);
            final dot = tester.widget<Container>(find.byKey(ValueKey('completion_color_${entry.key}')));
            expect((dot.decoration! as BoxDecoration).color, entry.value);
            expect(arcs[index].valueColor!.value, entry.value);
            final labelFinder = find.descendant(
              of: cell,
              matching: find.text(entry.key),
            );
            final labelParagraph = tester.renderObject<RenderParagraph>(
              labelFinder,
            );
            final glyphs = labelParagraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: entry.key.length),
            );
            expect(glyphs, hasLength(1));
            expect(
              labelParagraph.localToGlobal(Offset(glyphs.single.right, 0)).dx,
              lessThanOrEqualTo(tester.getRect(cell).right - 6),
              reason: 'The full status word fits inside its direct legend row.',
            );
            final foreground = tester
                .widget<Text>(
                  find.descendant(of: cell, matching: find.text(entry.key)),
                )
                .style!
                .color!;
            final luminances = [
              background.computeLuminance(),
              foreground.computeLuminance(),
            ]..sort();
            expect(
              (luminances.last + 0.05) / (luminances.first + 0.05),
              greaterThanOrEqualTo(4.5),
            );
          }
          if (scale == 1) {
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('completion_chart')))
                  .height,
              lessThanOrEqualTo(230),
            );
          }
          await tester.ensureVisible(find.text('Recent activity'));
          await tester.pumpAndSettle();
          expect(find.text('Inspection completed'), findsOneWidget);
          final timeline = find.byKey(const ValueKey('list_all'));
          final marker = find.descendant(
            of: timeline,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).shape == BoxShape.circle,
            ),
          );
          final connector = find.descendant(
            of: timeline,
            matching: find.byType(Positioned),
          );
          expect(
            tester.getRect(marker).center.dx,
            closeTo(tester.getRect(connector).center.dx, 0.1),
            reason:
                'The straight timeline connector is centered on its circular node.',
          );
          final filters = find.byKey(const ValueKey('activity_filters'));
          final activityBounds = tester.getRect(
            find.ancestor(of: filters, matching: find.byType(Container)).last,
          );
          expect(activityBounds.left, closeTo(pageBounds.left, 0.01));
          expect(activityBounds.right, closeTo(pageBounds.right, 0.01));
          expect(
            find.descendant(of: filters, matching: find.byType(Icon)),
            findsNothing,
          );
          expect(
            find.descendant(of: filters, matching: find.byType(FittedBox)),
            findsNothing,
          );
          // Owner-approved white parent and quiet hairline; timeline tiles stay intact.
          final sectionCard = find.ancestor(
            of: find.text('Recent activity'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).borderRadius ==
                      BorderRadius.circular(20),
            ),
          );
          expect(sectionCard, findsOneWidget);
          final decoration =
              tester.widget<Container>(sectionCard).decoration! as BoxDecoration;
          expect(decoration.color, InsightTheme.surface,
              reason: 'The approved Recent Activity parent uses one white surface.');
          final border = decoration.border! as Border;
          expect(border.top.color, InsightTheme.line,
              reason: 'The container needs the app hairline gray to stay readable.');
          for (final label in ['Tasks', 'Sync', 'Reports', 'Profile', 'All']) {
            final tab = find.descendant(
              of: filters,
              matching: find.text(label),
            );
            await tester.ensureVisible(tab);
            await tester.tap(tab);
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(tab);
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              ),
              hasLength(1),
              reason:
                  'Activity filter names must not split across lines inside the gutters.',
            );
            final target = find.ancestor(
              of: tab,
              matching: find.byType(InkWell),
            );
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
            final textBounds = tester.getRect(tab);
            final touchBounds = tester.getRect(target);
            expect(textBounds.center.dx, closeTo(touchBounds.center.dx, 0.1));
            expect(textBounds.center.dy, closeTo(touchBounds.center.dy, 0.1));
            if (label == 'All' || label == 'Tasks') {
              expect(find.text('Inspection completed'), findsOneWidget);
            } else {
              expect(find.text('Inspection completed'), findsNothing);
              expect(
                find.text('No ${label.toLowerCase()} activity yet.'),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          }
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Inspection completed'));
          await tester.tap(find.text('Inspection completed'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'Expanded activity timestamps wrap inside narrow cards.',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'Long inspector names keep Calendar centered below both views',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: InsightBottomNav(
              currentIndex: 0,
              items: const [
                InsightNavItem(icon: Icons.home, label: 'Home'),
                InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
                InsightNavItem(icon: Icons.sync, label: 'Sync'),
                InsightNavItem(icon: Icons.person, label: 'Profile'),
              ],
              onTap: (_) {},
              onQuickActionsTap: () {},
            ),
            body: HomeDashboardScreen(
              profile: UserProfile(
                id: 'home-inspector',
                fullName: 'Gabriela Isabella Dela Cruz Fernandez',
                role: 'inspector',
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final pager = tester.getRect(find.byKey(const ValueKey('home_calendar_pager')));
      final button = find.ancestor(of: find.text('Calendar'), matching: find.byType(TextButton));
      final original = tester.getRect(button);
      expect(original.center.dx, closeTo(180, 0.1));
      expect(original.top, closeTo(pager.bottom, 0.1));
      expect(original.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip('Show Time and Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel("Show today's tasks"));
      await tester.pumpAndSettle();
      expect(tester.getRect(button), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Swiping date tiles browses dates without changing the main view', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeDashboardScreen(profile: UserProfile(
      id: 'home-inspector', fullName: 'Maria Isabella Dela Cruz', role: 'inspector',
    ))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final dates = find.byKey(const ValueKey('calendar_preview_days'));
    expect(dates, findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.descendant(of: dates, matching: find.byType(Scrollable)));
    final before = scroll.position.pixels;
    await tester.drag(dates, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(before));
    expect(find.byTooltip('Show Time and Date'), findsOneWidget,
      reason: 'A day-row drag belongs to the dates, not the enclosing view pager.');
    final visibleDays = find.descendant(of: dates, matching: find.byWidgetPredicate(
      (widget) => widget is InkWell,
    )).evaluate().where((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return tester.getRect(dates).contains(rect.center);
    }).toList();
    expect(visibleDays.length, greaterThanOrEqualTo(3));
    final chosen = visibleDays[visibleDays.length ~/ 2].widget as InkWell;
    final chosenLabel = tester.widget<Semantics>(find.ancestor(
      of: find.byWidget(chosen), matching: find.byType(Semantics),
    ).first).properties.label;
    await tester.tap(find.byWidget(chosen));
    await tester.pumpAndSettle();
    final chosenSemantics = tester.widget<Semantics>(find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == chosenLabel,
    ));
    expect(chosenSemantics.properties.selected, isTrue);
    await tester.tap(find.byTooltip('Show full calendar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('full_calendar')), findsOneWidget);
    final pager = tester.getRect(find.byKey(const ValueKey('home_calendar_pager')));
    await tester.dragFrom(tester.getTopLeft(find.byKey(const ValueKey('calendar_preview_header'))) + const Offset(70, 32), const Offset(-220, 0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(find.byKey(const ValueKey('home_calendar_pager'))), pager);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Calendar preview'), findsOneWidget);
    expect(find.byKey(const ValueKey('full_calendar')), findsOneWidget);
    await tester.tap(find.byTooltip('Hide full calendar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('full_calendar')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('The selected calendar view survives refresh and reopen for that user', (tester) async {
    Widget screen({String name = 'Maria Isabella Dela Cruz', String id = 'home-inspector'}) =>
      MaterialApp(home: HomeDashboardScreen(profile: UserProfile(id: id, fullName: name, role: 'inspector')));
    await tester.pumpWidget(screen());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Time and Date'), findsOneWidget);
    await tester.tap(find.byTooltip('Show Time and Date'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Calendar preview'), findsOneWidget);
    await tester.pumpWidget(screen(name: 'Maria Isabella Dela Cruz Fernandez'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Calendar preview'), findsOneWidget,
      reason: 'Profile/activity refresh must not reset the manually selected main view.');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Calendar preview'), findsOneWidget);
    await tester.tap(find.byTooltip('Show Calendar preview'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Time and Date'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen(id: 'another-inspector'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Time and Date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Activity reveal shows seven, reveals the remainder, and resets on a new filter',
    (tester) async {
      final captureKey = GlobalKey();
      Future<void> captureActivity(String name) async {
        final output = Platform.environment['IMAPS_UI_CAPTURE_DIR'];
        if (output == null) return;
        final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/$name.png')..parent.createSync(recursive: true);
          file.writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      activityCount = 15;
      addTearDown(() => activityCount = 1);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => RepaintBoundary(key: captureKey, child: child!),
          home: HomeDashboardScreen(
            profile: UserProfile(
              id: 'home-inspector',
              fullName: 'Maria Isabella Dela Cruz',
              role: 'inspector',
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Activity 7'), findsOneWidget);
      expect(find.text('Activity 8'), findsNothing);
      await tester.ensureVisible(find.text('Recent activity'));
      await tester.pumpAndSettle();
      await captureActivity('home-activity-preview');
      await tester.ensureVisible(find.text('Activity 1'));
      await tester.tap(find.text('Activity 1'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      await tester.ensureVisible(find.text('See more (8)'));
      await tester.tap(find.text('See more (8)'));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.text('Activity 15'), findsOneWidget);
      expect(
        find.byIcon(Icons.schedule_rounded),
        findsOneWidget,
        reason:
            'Revealing more rows preserves the expanded details of existing activities.',
      );
      await tester.ensureVisible(find.text('See less'));
      await tester.pumpAndSettle();
      await captureActivity('home-activity-expanded');
      await tester.tap(find.text('See less'));
      await tester.pumpAndSettle();
      expect(find.text('Activity 8'), findsNothing);
      await tester.ensureVisible(find.text('See more (8)'));
      await tester.tap(find.text('See more (8)'));
      await tester.pumpAndSettle();
      final filters = find.byKey(const ValueKey('activity_filters'));
      for (final label in ['Tasks', 'Sync', 'All']) {
        final tab = find.descendant(of: filters, matching: find.text(label));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        if (label == 'Tasks') {
          expect(find.text('Activity 7'), findsOneWidget);
          expect(find.text('Activity 8'), findsNothing);
          expect(find.text('See more (3)'), findsOneWidget);
        } else if (label == 'Sync') {
          expect(find.text('Activity 11'), findsOneWidget);
          expect(find.text('Activity 15'), findsOneWidget);
          expect(find.textContaining('See more'), findsNothing);
        } else {
          expect(find.text('Activity 7'), findsOneWidget);
          expect(find.text('Activity 8'), findsNothing);
          expect(find.text('See more (8)'), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Seven or fewer activities have no unnecessary reveal control', (
    tester,
  ) async {
    addTearDown(() => activityCount = 1);
    for (final count in [0, 7]) {
      activityCount = count;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeDashboardScreen(
            key: ValueKey(count),
            profile: UserProfile(
              id: 'home-inspector',
              fullName: 'Maria Isabella Dela Cruz',
              role: 'inspector',
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('See more'), findsNothing);
      expect(find.text('See less'), findsNothing);
      expect(
        find.text(count == 0 ? 'No recent activity yet.' : 'Activity 7'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Today shows a clear empty state when there are no calendar tasks',
    (tester) async {
      noJobs = true;
      addTearDown(() => noJobs = false);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeDashboardScreen(
              profile: UserProfile(
                id: 'home-inspector',
                fullName: 'Maria Isabella Dela Cruz',
                role: 'inspector',
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Show Time and Date'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel("Show today's tasks"));
        await tester.pumpAndSettle();
        expect(find.text('No tasks or PO due dates today.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );
}
