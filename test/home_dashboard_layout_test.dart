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
      return asset.endsWith('.ttf') ? bytes : null;
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
             ? noJobs ? [] : [
                for (final status in ['assigned', 'in_progress', 'completed'])
                  {
                    'id': 'job-$status',
                    'status': status,
                     'scheduled_date': status == 'in_progress'
                         ? DateTime.now().add(const Duration(days: 1)).toIso8601String()
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
                   'scheduled_date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
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
                   'scheduled_date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
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
                   'scheduled_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                   'deadline_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
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
                {
                  'id': 'activity-1',
                  'event_type': 'inspection_completed',
                  'title': 'Inspection completed',
                  'description': 'Site inspection submitted.',
                  'created_at': today,
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
      testWidgets(
        'Home $size at $scale text keeps calendar and sections usable',
         (tester) async {
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
          expect(tester.takeException(), isNull);
          expect(find.text('Maria Isabella Dela Cruz'), findsOneWidget);
          expect(find.text('Test applicant'), findsWidgets);
           final inspectorSection = find.byKey(const ValueKey('inspector_section'));
           final calendarSection = find.byKey(const ValueKey('calendar_section'));
           final assignmentSection = find.byKey(const ValueKey('assignments_section'));
           expect(tester.getRect(inspectorSection).bottom, lessThan(tester.getRect(calendarSection).top));
           expect(tester.getRect(calendarSection).bottom, lessThan(tester.getRect(assignmentSection).top));
           if (scale == 1 && size.width < size.height && size.width <= 430 && size.height >= 800) {
            final card = tester.getRect(
              find.byType(ActiveAssignmentsFolderCard).first,
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
           await tester.ensureVisible(find.bySemanticsLabel("Show today's tasks"));
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
           await tester.ensureVisible(notes);
           expect(find.descendant(of: notes, matching: find.text('Test applicant')), findsOneWidget);
           await tester.drag(notes, const Offset(0, -160));
           await tester.pumpAndSettle();
           expect(find.descendant(of: notes, matching: find.text('PO due today')), findsOneWidget);
           expect(find.descendant(of: notes, matching: find.text('Available PO due today')), findsOneWidget);
           expect(find.descendant(of: notes, matching: find.text('Completed applicant')), findsNothing);
           expect(find.descendant(of: notes, matching: find.text('Tomorrow applicant')), findsNothing);
           expect(find.descendant(of: notes, matching: find.text('Overdue applicant')), findsNothing);
           await tester.ensureVisible(find.bySemanticsLabel('Show clock and date'));
           await tester.tap(find.bySemanticsLabel('Show clock and date'));
           await tester.pumpAndSettle();
           expect(find.byKey(const ValueKey('today_tasks')), findsNothing);
           await tester.ensureVisible(find.byTooltip('Show full calendar'));
           await tester.tap(find.byTooltip('Show full calendar'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('full_calendar')), findsOneWidget);
          expect(tester.takeException(), isNull);
           final calendar = find.byKey(const ValueKey('full_calendar'));
           expect(find.descendant(of: calendar, matching: find.text('Test applicant')), findsOneWidget);
           expect(find.descendant(of: calendar, matching: find.text('PO due today')), findsOneWidget);
           expect(find.descendant(of: calendar, matching: find.text('Tomorrow applicant')), findsNothing);
           final tomorrow = DateTime.now().add(const Duration(days: 1));
           if (tomorrow.month != DateTime.now().month) {
             await tester.tap(find.byTooltip('Next month'));
             await tester.pumpAndSettle();
           }
           await tester.ensureVisible(find.byKey(ValueKey('calendar_day_${tomorrow.day}')));
           await tester.tap(find.byKey(ValueKey('calendar_day_${tomorrow.day}')));
           await tester.pumpAndSettle();
           expect(find.descendant(of: calendar, matching: find.text('Tomorrow applicant')), findsOneWidget);
           expect(find.descendant(of: calendar, matching: find.text('PO due today')), findsNothing);
           await tester.ensureVisible(find.byTooltip('Hide full calendar'));
           await tester.tap(find.byTooltip('Hide full calendar'));
          await tester.pumpAndSettle();
           expect(find.byKey(const ValueKey('full_calendar')), findsNothing);
           await tester.ensureVisible(find.text('See All'));
           // Selecting another calendar date must not turn Today into tomorrow.
           await tester.ensureVisible(find.bySemanticsLabel("Show today's tasks"));
           await tester.tap(find.bySemanticsLabel("Show today's tasks"));
           await tester.pumpAndSettle();
           expect(find.descendant(of: notes, matching: find.text('Test applicant')), findsOneWidget);
           expect(find.descendant(of: notes, matching: find.text('Tomorrow applicant')), findsNothing);
           await tester.ensureVisible(find.text('See All'));
           await tester.tap(find.text('See All'));
          await tester.ensureVisible(find.text('More details'));
           await tester.tap(find.text('More details'));
           expect(tabs, [1, 1]);
           expect(find.text('1 Overdue'), findsOneWidget);
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
             final texts = find.descendant(of: cell, matching: find.byType(Text));
             expect(tester.getTopLeft(texts.first).dy, lessThan(tester.getTopLeft(find.descendant(of: cell, matching: find.text(label))).dy),
               reason: 'Lower-row counts sit above their labels in the supplied v3 reference.');
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
          final filters = find.byKey(const ValueKey('activity_filters'));
          expect(
            find.descendant(of: filters, matching: find.byType(Icon)),
            findsNothing,
          );
          expect(
            find.descendant(of: filters, matching: find.byType(FittedBox)),
            findsNothing,
          );
          for (final label in ['Tasks', 'Sync', 'Reports', 'Profile', 'All']) {
            final tab = find.descendant(
              of: filters,
              matching: find.text(label),
            );
            await tester.ensureVisible(tab);
            await tester.tap(tab);
            await tester.pumpAndSettle();
            final target = find.ancestor(
              of: tab,
              matching: find.byType(InkWell),
            );
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
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
           await tester.pumpWidget(const SizedBox.shrink());
           } finally {
             semantics.dispose();
           }
        },
      );
    }
  }

  testWidgets('Today shows a clear empty state when there are no calendar tasks', (tester) async {
    noJobs = true;
    addTearDown(() => noJobs = false);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardScreen(profile: UserProfile(
          id: 'home-inspector', fullName: 'Maria Isabella Dela Cruz', role: 'inspector',
        )),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel("Show today's tasks"));
      await tester.pumpAndSettle();
      expect(find.text('No tasks or PO due dates today.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
}
