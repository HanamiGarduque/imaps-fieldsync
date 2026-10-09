import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  var noJobs = false;
  var activityCount = 1;
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
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE local_jobs (id TEXT, status TEXT, inspector_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE pending_actions (job_id TEXT, type TEXT, status TEXT)',
    );
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

  testWidgets('Full calendar exposes every weekday and date on phones and keeps dotted-day tasks', (tester) async {
    final now = DateTime.now();
    scheduledOverride = DateTime(now.year, now.month, 2);
    addTearDown(() => scheduledOverride = null);
    for (final width in [360.0, 390.0]) {
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
      final monthCard = find.descendant(
        of: calendar,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(16),
        ),
      );
      expect(monthCard, findsOneWidget);
      final bounds = tester.getRect(monthCard);
      // The month must never run into the phone edges, and it must keep the
      // page margin where the seven 48px day targets physically allow it.
      expect(bounds.left, greaterThanOrEqualTo(8.0),
          reason: 'The full calendar must keep a visible margin at ${width}px.');
      expect(width - bounds.right, greaterThanOrEqualTo(8.0),
          reason: 'The full calendar must keep a visible margin at ${width}px.');
      if (width >= 376) {
        final strip = tester.getRect(find.byKey(const ValueKey('calendar_section')));
        expect(bounds.left, closeTo(strip.left, 0.5),
            reason: 'Wide screens align with the day-strip card at ${width}px.');
        expect(bounds.right, closeTo(strip.right, 0.5),
            reason: 'Wide screens align with the day-strip card at ${width}px.');
      }
      for (final weekday in ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']) {
        final label = find.descendant(of: calendar, matching: find.text(weekday));
        expect(tester.getRect(label).left, greaterThanOrEqualTo(bounds.left));
        expect(tester.getRect(label).right, lessThanOrEqualTo(bounds.right),
            reason: '$weekday must fit without panning the month at ${width}px.');
      }
      for (var day = 1; day <= DateTime(now.year, now.month + 1, 0).day; day++) {
        final tile = find.byKey(ValueKey('calendar_day_$day'));
        expect(tile, findsOneWidget);
        // A day target may sit flush against the card's 1.2px border, which
        // is part of the visible card, so allow that and nothing more.
        expect(tester.getRect(tile).left, greaterThanOrEqualTo(bounds.left - 1.5));
        expect(tester.getRect(tile).right, lessThanOrEqualTo(bounds.right + 1.5),
            reason: 'Date $day must be inside the visible month.');
        expect(tester.getSize(tile).shortestSide, greaterThanOrEqualTo(48));
      }
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
    expect(tester.getSize(tile).width, greaterThanOrEqualTo(48));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
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
          expect(scheduled.top, pending.top);
          expect(ongoing.top, completed.top);
          expect(ongoing.top, greaterThan(scheduled.bottom));
          expect(pending.left, greaterThan(scheduled.right));
          for (final label in ['Ongoing', 'Completed']) {
            final cell = find.byKey(ValueKey('completion_$label'));
            final texts = find.descendant(
              of: cell,
              matching: find.byType(Text),
            );
            expect(
              tester.getTopLeft(texts.first).dy,
              lessThan(
                tester
                    .getTopLeft(
                      find.descendant(of: cell, matching: find.text(label)),
                    )
                    .dy,
              ),
              reason:
                  'Lower-row counts sit above their labels in the supplied v3 reference.',
            );
          }
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
            expect(background, entry.value);
            expect(arcs[index].valueColor!.value, background);
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
              reason: 'The full status word fits inside its colored card.',
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
          // Recent Activity reads as quiet list content on the page surface:
          // its containers take the page background and rely on a gray border,
          // never a colored fill, so the tiles stop shouting next to the cards.
          // Recent Activity sits on the page itself: the container takes the page
          // background and is defined by a gray hairline, not a colored fill.
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
          expect(decoration.color, InsightTheme.bg,
              reason: 'The Recent Activity container must match the page background.');
          final border = decoration.border! as Border;
          expect(border.top.color, InsightTheme.lineStrong,
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
      activityCount = 15;
      addTearDown(() => activityCount = 1);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
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
      expect(find.text('Activity 7'), findsOneWidget);
      expect(find.text('Activity 8'), findsNothing);
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
