import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

/// Stands in for a device status bar so the inset arithmetic can be asserted
/// deterministically instead of depending on the host's own insets.
const double kStatusBarInset = 48;

/// The exact orange the Tasks dot paints (`InsightBottomNav._orange`).
const Color kDotOrange = Color(0xFFF59E0B);

/// Two different inspectors on one shared device.
const inspectorA = 'uuid-inspector-a';
const inspectorB = 'uuid-inspector-b';

/// Finds the real production badge - a small orange circle. Matching on the
/// actual decoration means this breaks if the dot's colour or presence changes,
/// rather than quietly asserting against a stand-in.
Finder get tasksDot => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration as BoxDecoration).color == kDotOrange,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;

  /// Builds the REAL production schema straight from the source, so these
  /// tests can never drift from what actually ships.
  Future<void> createProductionSchema() async {
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final m in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(m.group(0)!);
    }
  }

  /// Seeds one cached assignment owned by the signed-in inspector, exactly as
  /// `cacheJobs` writes it. Seed the row owner-less and the owner-scoped read
  /// below cannot see it.
  Future<void> seedJob(String id, String status) => db.insert('local_jobs', {
        'id': id,
        'status': status,
        'scheduled_date': '2026-10-01',
        'inspector_id': DBHelper.inspectorIdForTesting,
      });

  Future<void> removeJob(String id) =>
      db.delete('local_jobs', where: 'id = ?', whereArgs: [id]);

  /// The awaiting assignment ids, computed exactly the way the shell computes
  /// them: read the real cache, keep only statuses that mean work is waiting.
  Future<Set<String>> awaitingIds() async {
    final rows = await DBHelper.getCachedJobs();
    return rows
        .where((r) => r['id'] != null)
        .where((r) => kAwaitingTaskStatuses.contains(r['status']))
        .map((r) => r['id'].toString())
        .toSet();
  }

  /// The full badge decision, using the two real production units the shell
  /// composes: the cache read above, the persisted acknowledgement set, and the
  /// shipped set-difference rule.
  Future<bool> dotOn(String inspector) async {
    final acknowledged = await SecurePrefsService.getAcknowledgedTaskIds(
      inspector,
    );
    return shouldShowTasksAttentionDot(
      awaitingTaskIds: await awaitingIds(),
      acknowledgedTaskIds: acknowledged,
    );
  }

  /// What the shell does when the inspector opens the Tasks tab.
  Future<void> openTasks(String inspector) async =>
      SecurePrefsService.acknowledgeTasks(inspector, await awaitingIds());

  /// Simulates a cold start: the widget state is gone, only the persisted
  /// acknowledgement and the cache survive.
  Future<bool> coldStartDot(String inspector) => dotOn(inspector);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object?>{} : null,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nav-dot-');
    db = await databaseFactoryFfi.openDatabase('${tempDir.path}/nav.db');
    await createProductionSchema();
    DBHelper.useDatabaseForTesting(db);
    // The cache is owner-scoped: `getCachedJobs` reads only the signed-in
    // inspector's rows, so without an authenticated owner every read matches
    // `inspector_id = NULL` - which is no row at all, and the dot could never
    // turn on for a seeded assignment.
    DBHelper.inspectorIdForTesting = inspectorA;
    // Fresh keystore per test: the persisted store must not leak between them.
    SecurePrefsService.useStorageForTesting({});
  });

  tearDown(() async {
    DBHelper.inspectorIdForTesting = null;
    SecurePrefsService.useStorageForTesting(null);
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Widget withStatusBar(Widget child) => MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: kStatusBarInset),
        ),
        child: child,
      );

  // ==========================================================================
  // ISSUE 1 - Tasks orange dot: NEW / UNSEEN ASSIGNMENT
  // ==========================================================================

  group('TASK DOT - locked lifecycle', () {
    test('1. zero assignments -> OFF', () async {
      expect(await dotOn(inspectorA), isFalse);
    });

    test('2. first unseen assignment A -> ON', () async {
      await seedJob('A', 'assigned');
      expect(await dotOn(inspectorA), isTrue);
    });

    test('3. opening Tasks acknowledges A -> OFF', () async {
      await seedJob('A', 'assigned');
      expect(await dotOn(inspectorA), isTrue);

      await openTasks(inspectorA);

      expect(await dotOn(inspectorA), isFalse);
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        {'A'},
        reason: 'the acknowledgement must actually be persisted',
      );
    });

    test('4. cold restart with A still present -> stays OFF', () async {
      await seedJob('A', 'assigned');
      await openTasks(inspectorA);
      expect(await coldStartDot(inspectorA), isFalse,
          reason: 'an old pending task must not resurrect the dot');
    });

    test('5. new assignment B while A is acknowledged -> ON', () async {
      await seedJob('A', 'assigned');
      await openTasks(inspectorA);
      expect(await dotOn(inspectorA), isFalse);

      await seedJob('B', 'assigned');

      expect(await dotOn(inspectorA), isTrue);
      expect(
        unseenTaskIds(
          awaitingTaskIds: await awaitingIds(),
          acknowledgedTaskIds:
              await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        ),
        {'B'},
        reason: 'only the genuinely new assignment is unseen',
      );
    });

    test('6. opening Tasks acknowledges A + B -> OFF', () async {
      await seedJob('A', 'assigned');
      await openTasks(inspectorA);
      await seedJob('B', 'assigned');

      await openTasks(inspectorA);

      expect(await dotOn(inspectorA), isFalse);
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        {'A', 'B'},
      );
    });

    test('7. a completed / removed assignment cannot hold the badge ON',
        () async {
      await seedJob('A', 'assigned');
      await openTasks(inspectorA);
      await seedJob('B', 'assigned');
      expect(await dotOn(inspectorA), isTrue);

      // B is completed server-side and drops out of the cache.
      await db.update(
        'local_jobs',
        {'status': 'completed'},
        where: 'id = ?',
        whereArgs: ['B'],
      );

      expect(await dotOn(inspectorA), isFalse,
          reason: 'work that is no longer awaiting is not news');
    });

    test('7b. an assignment removed from the cache also clears the badge',
        () async {
      await seedJob('A', 'assigned');
      await removeJob('A');
      expect(await dotOn(inspectorA), isFalse);
    });

    test('8. offline alone does not fabricate unseen state', () async {
      // No assignments cached at all: being offline is not a reason to show one.
      expect(await dotOn(inspectorA), isFalse);
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        isEmpty,
        reason: 'nothing may be written for a task that never existed',
      );
    });

    test('9. a cached unseen assignment stays ON offline', () async {
      await seedJob('A', 'assigned');
      // No acknowledgement written: offline changes nothing about the truth.
      expect(await dotOn(inspectorA), isTrue);
    });

    test('10. Inspector A acknowledgement never suppresses Inspector B',
        () async {
      await seedJob('A', 'assigned');

      // Inspector A opens Tasks and acknowledges it.
      await openTasks(inspectorA);
      expect(await dotOn(inspectorA), isFalse);

      // Inspector B logs into the same shared device. The same assignment is
      // NOT acknowledged for B, so B must still be told about it.
      expect(await dotOn(inspectorB), isTrue,
          reason: 'acknowledgement is namespaced per authenticated user');
      expect(await SecurePrefsService.getAcknowledgedTaskIds(inspectorB),
          isEmpty);
    });

    test('10b. the two inspectors keep independent acknowledgement sets',
        () async {
      await seedJob('A', 'assigned');
      await openTasks(inspectorA);

      await seedJob('B', 'assigned');
      await openTasks(inspectorB);

      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        {'A'},
      );
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorB),
        {'A', 'B'},
      );
      // A has still never seen B.
      expect(await dotOn(inspectorA), isTrue);
    });
  });

  group('TASK DOT - acknowledgement storage', () {
    test('unknown inspector -> empty, never a crash', () async {
      expect(await SecurePrefsService.getAcknowledgedTaskIds('nobody'), isEmpty);
    });

    test('empty user id is rejected rather than namespaced', () async {
      await SecurePrefsService.acknowledgeTasks('', {'A'});
      expect(await SecurePrefsService.getAcknowledgedTaskIds(''), isEmpty);
    });

    test('a corrupt stored value degrades to empty, not an exception',
        () async {
      SecurePrefsService.useStorageForTesting({
        'sp_acknowledged_task_ids': 'not json at all',
      });
      expect(await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
          isEmpty);
    });

    test('a value of the wrong shape degrades to empty', () async {
      SecurePrefsService.useStorageForTesting({
        'sp_acknowledged_task_ids': '["a","b"]',
      });
      expect(await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
          isEmpty);
    });

    test('acknowledging is a union - it never drops existing ids', () async {
      await SecurePrefsService.acknowledgeTasks(inspectorA, {'A'});
      await SecurePrefsService.acknowledgeTasks(inspectorA, {'B'});
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        {'A', 'B'},
      );
    });

    test('stale ids are pruned to the current awaiting set', () async {
      await SecurePrefsService.acknowledgeTasks(inspectorA, {'A', 'B', 'C'});
      await SecurePrefsService.setAcknowledgedTaskIds(
        inspectorA,
        {'A', 'B', 'C'},
        pruneTo: {'A'},
      );
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorA),
        {'A'},
        reason: 'acknowledgements for finished work must not pile up',
      );
    });

    test('pruning one inspector never touches another', () async {
      await SecurePrefsService.acknowledgeTasks(inspectorA, {'A'});
      await SecurePrefsService.acknowledgeTasks(inspectorB, {'X', 'Y'});
      await SecurePrefsService.setAcknowledgedTaskIds(
        inspectorA,
        {'A'},
        pruneTo: const {},
      );
      expect(
        await SecurePrefsService.getAcknowledgedTaskIds(inspectorB),
        {'X', 'Y'},
      );
    });
  });

  group('TASK DOT - awaiting definition', () {
    test('only not-yet-started statuses count', () async {
      for (final s in ['completed', 'Completed', 'submitted', 'in_progress',
        'ongoing', 'in-progress']) {
        await seedJob('j-$s', s);
      }
      expect(await awaitingIds(), isEmpty,
          reason: 'the dot is never a historical/ongoing-work indicator');
    });

    test('assigned / Pending / pending all count', () async {
      await seedJob('a', 'assigned');
      await seedJob('b', 'Pending');
      await seedJob('c', 'pending');
      expect(await awaitingIds(), {'a', 'b', 'c'});
    });
  });

  group('TASK DOT - production nav widget', () {
    Widget nav({required bool showBadge, int currentIndex = 0}) =>
        withStatusBar(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: InsightBottomNav(
                currentIndex: currentIndex,
                onTap: (_) {},
                items: [
                  const InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
                  InsightNavItem(
                    icon: Icons.assignment_outlined,
                    label: 'Tasks',
                    showBadge: showBadge,
                  ),
                  const InsightNavItem(icon: Icons.sync_rounded, label: 'Sync'),
                  const InsightNavItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('renders the dot only when the rule says so', (tester) async {
      await tester.pumpWidget(nav(showBadge: true));
      await tester.pumpAndSettle();
      expect(tasksDot, findsOneWidget);

      await tester.pumpWidget(nav(showBadge: false));
      await tester.pumpAndSettle();
      expect(tasksDot, findsNothing);
    });

    testWidgets('a badge keeps the colour its owner gives it', (tester) async {
      // The Sync tab's running-progress dot is blue, not amber: amber means
      // "needs attention" and only the Tasks tab owns that.
      const runningBlue = Color(0xFF2563EB);
      Finder dotWith(Color color) => find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                (w.decoration as BoxDecoration).color == color,
          );

      await tester.pumpWidget(withStatusBar(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: InsightBottomNav(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
              InsightNavItem(
                icon: Icons.assignment_outlined,
                label: 'Tasks',
                showBadge: true,
              ),
              InsightNavItem(
                icon: Icons.sync_rounded,
                label: 'Sync',
                showBadge: true,
                badgeColor: runningBlue,
              ),
              InsightNavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tasksDot, findsOneWidget,
          reason: 'the Tasks dot keeps the amber attention colour');
      expect(dotWith(runningBlue), findsOneWidget,
          reason: 'the running-sync dot is painted blue');
    });

    testWidgets('never replaces the Tasks label (accessibility)',
        (tester) async {
      await tester.pumpWidget(nav(showBadge: true));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget,
          reason: 'the semantic label must survive the badge');
    });

    testWidgets('tab switches neither fabricate nor destroy the dot',
        (tester) async {
      await tester.pumpWidget(nav(showBadge: false, currentIndex: 0));
      await tester.pumpAndSettle();
      expect(tasksDot, findsNothing);
      await tester.pumpWidget(nav(showBadge: false, currentIndex: 2));
      await tester.pumpAndSettle();
      expect(tasksDot, findsNothing);
    });
  });

  group('TASK DOT - shell wiring', () {
    late String src;
    setUpAll(() {
      src = File('lib/core/navigation/main_shell_screen.dart')
          .readAsStringSync();
    });

    test('11a. no SQLite or Supabase schema change', () {
      expect(src, isNot(contains('CREATE TABLE')));
      expect(src, isNot(contains('ALTER TABLE')));
      expect(src, isNot(contains('db_version')));
      expect(src, isNot(contains('migration')));

      final prefs =
          File('lib/modules/auth_startup/services/secure_prefs_service.dart')
              .readAsStringSync();
      expect(prefs, isNot(contains('CREATE TABLE')));
      expect(prefs, isNot(contains('ALTER TABLE')));
    });

    test('11b. the badge comes from the unseen-assignment rule', () {
      expect(src, contains('shouldShowTasksAttentionDot('));
      expect(src, contains('awaitingTaskIds: _awaitingTaskIds'));
      expect(src, contains('acknowledgedTaskIds: _acknowledgedTaskIds'));
      expect(
        src,
        isNot(contains('showBadge: !_tasksVisitedThisSession')),
        reason: 'the old session-only proxy is the stale-dot bug',
      );
    });

    test('11b2. one owner per dot colour', () {
      // Amber means "needs attention" — a new assignment on Tasks. Routine
      // progress (a sync that is running) must not reuse the same amber.
      expect(src, contains('badgeColor: InsightTheme.blue1'),
          reason: 'the running-sync dot uses the app blue');
      expect(
        RegExp(
          r'showBadge: syncProgress != null,[\s\S]{0,240}?badgeColor: InsightTheme\.blue1,',
        ).hasMatch(src),
        isTrue,
        reason: 'the blue badge belongs to the Sync tab',
      );
      expect(
        'badgeColor: InsightTheme.blue1'.allMatches(src).length,
        1,
        reason: 'only the Sync tab overrides the attention colour',
      );
    });

    test('11c. acknowledgement happens when Tasks is opened', () {
      expect(src, contains('_acknowledgeAwaitingTasks()'));
      expect(
        RegExp(
          r'if \(index == 1\)\s*\{\s*_acknowledgeAwaitingTasks\(\);',
        ).hasMatch(src),
        isTrue,
        reason: 'opening the Tasks tab is the acknowledgement gesture',
      );
    });

    test('11d. persistence is namespaced by the authenticated user id', () {
      expect(src, contains('SecurePrefsService.getAcknowledgedTaskIds('));
      expect(src, contains('SecurePrefsService.acknowledgeTasks('));
      expect(src, contains('String get _inspectorId => _currentProfile.id'));
    });

    test('11e. the count is read from the existing cache, not the network', () {
      expect(src, contains('DBHelper.getCachedJobs()'));
      expect(src, contains('kAwaitingTaskStatuses.contains('));
    });
  });

  // ==========================================================================
  // ISSUE 2 - compact offline header
  // ==========================================================================

  group('OFFLINE HEADER - banner', () {
    testWidgets('offline -> banner visible and labelled', (tester) async {
      await tester.pumpWidget(
        withStatusBar(const MaterialApp(home: Scaffold(body: OfflineBanner()))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('preserves the red dot and red tint', (tester) async {
      await tester.pumpWidget(
        withStatusBar(const MaterialApp(home: Scaffold(body: OfflineBanner()))),
      );
      await tester.pumpAndSettle();

      final dot = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == InsightTheme.red,
      );
      expect(dot, findsOneWidget, reason: 'the red status dot must remain');

      final tint = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == InsightTheme.redTint,
      );
      expect(tint, findsOneWidget,
          reason: 'the existing light red background must remain');
    });

    testWidgets('it is ONE compact row', (tester) async {
      await tester.pumpWidget(
        withStatusBar(const MaterialApp(home: Scaffold(body: OfflineBanner()))),
      );
      await tester.pumpAndSettle();

      final text = tester.getRect(find.text('Offline mode'));
      expect(text.height, lessThan(20),
          reason: 'a single line, not a stacked block');

      final banner = tester.getRect(find.byType(OfflineBanner));
      expect(banner.top, 0);
      expect(banner.height, lessThan(kStatusBarInset + 40),
          reason: 'inset plus one row only - no tall container');
    });

    testWidgets('it still clears the status bar', (tester) async {
      await tester.pumpWidget(
        withStatusBar(const MaterialApp(home: Scaffold(body: OfflineBanner()))),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Offline mode')).top,
          greaterThanOrEqualTo(kStatusBarInset),
          reason: 'content must never sit under the system status bar');
    });
  });

  group('OFFLINE HEADER - page inset rule', () {
    /// Stands in for a main page: applies its own `SafeArea(bottom: false)`
    /// exactly like Home, Tasks, Sync and Profile all do.
    Widget fakePage(void Function(double topPadding) report) => Builder(
          builder: (context) {
            report(MediaQuery.paddingOf(context).top);
            return const SafeArea(bottom: false, child: SizedBox.expand());
          },
        );

    testWidgets('offline -> the page does NOT re-apply the inset',
        (tester) async {
      double seen = -1;
      await tester.pumpWidget(
        withStatusBar(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const OfflineBanner(),
                  Expanded(
                    child: PageUnderOfflineBanner(
                      isOnline: false,
                      child: fakePage((v) => seen = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, 0,
          reason: 'the banner already cleared the status bar; a second copy '
              'here is exactly the empty band being reported');
    });

    testWidgets('online -> the page keeps its own single inset',
        (tester) async {
      double seen = -1;
      await tester.pumpWidget(
        withStatusBar(
          MaterialApp(
            home: Scaffold(
              body: PageUnderOfflineBanner(
                isOnline: true,
                child: fakePage((v) => seen = v),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, kStatusBarInset,
          reason: 'online behaviour must be completely untouched');
    });

    testWidgets('offline adds only the banner row, not a second inset',
        (tester) async {
      await tester.pumpWidget(
        withStatusBar(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const OfflineBanner(),
                  Expanded(
                    child: PageUnderOfflineBanner(
                      isOnline: false,
                      child: fakePage((_) {}),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final banner = tester.getRect(find.byType(OfflineBanner));
      final page = tester.getRect(
        find
            .descendant(
              of: find.byType(PageUnderOfflineBanner),
              matching: find.byType(SafeArea),
            )
            .first,
      );

      expect(page.top - banner.bottom, lessThan(2),
          reason: 'no dead space between the banner and the page');
      expect(banner.height - kStatusBarInset, lessThan(kStatusBarInset),
          reason: 'going offline must not cost a whole extra inset');
    });

    testWidgets('online reserves ZERO banner height', (tester) async {
      await tester.pumpWidget(
        withStatusBar(
          const MaterialApp(
            home: Scaffold(
              body: PageUnderOfflineBanner(
                isOnline: true,
                child: OfflineBannerProbe(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Nothing from the banner is in the tree at all, so there is no
      // invisible box or spacer standing in for it.
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.text('Offline mode'), findsNothing);
      expect(find.byType(OfflineBannerProbe), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('OFFLINE HEADER - all four tabs share one rule', () {
    test('the shell routes every tab through the shared wrapper', () {
      final src = File('lib/core/navigation/main_shell_screen.dart')
          .readAsStringSync();
      expect(src, contains('PageUnderOfflineBanner('));
      // Single choke point: all four pages come from _buildPage, which is
      // wrapped once, so no tab can drift.
      expect(src, contains('child: _buildPage(_currentIndex)'));
      expect(
        RegExp('PageUnderOfflineBanner\\(').allMatches(src).length,
        1,
        reason: 'exactly one wrapper, covering all four tabs',
      );
    });

    test('each main page still applies its own SafeArea', () {
      // The fix must not have "resolved" the double inset by deleting the
      // pages' own status-bar handling - that would put content under the
      // status bar when online.
      for (final path in [
        'lib/modules/analytics_dashboard/screens/home_dashboard_screen.dart',
        'lib/modules/tasks/screens/tasks_screen.dart',
        'lib/modules/offline_sync/screens/updates_screen.dart',
        'lib/modules/profile_settings/screens/profile_screen.dart',
      ]) {
        expect(File(path).readAsStringSync(), contains('SafeArea('),
            reason: path);
      }
    });
  });
}

/// Marker child used to assert nothing invisible is mounted when online.
class OfflineBannerProbe extends StatelessWidget {
  const OfflineBannerProbe({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
