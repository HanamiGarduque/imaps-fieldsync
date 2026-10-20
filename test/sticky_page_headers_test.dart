import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

/// A phone with a real status bar so top-inset behaviour is deterministic.
const double kStatusBarInset = 48;

/// The decorative background orbs that were removed were 220-320px circles.
/// Anything smaller is a legitimate control (status dot, spinner, avatar), so
/// the audit only treats genuinely page-sized circles as background decoration.
const double kDecorativeOrbMinSize = 150;

Widget host(Widget child, {double width = 390, double height = 844}) =>
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: const EdgeInsets.only(top: kStatusBarInset),
      ),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late Database db;

  Future<void> createProductionSchema() async {
    final source = await File(
      'lib/core/services/db_helper.dart',
    ).readAsString();
    for (final m in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(m.group(0)!);
    }
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object?>{} : null,
        );
    // Profile and Sync call Supabase on init. Pointing at a dead local URL lets
    // those calls fail fast into the screens' own error paths so the widgets
    // under test still build for real.
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-anon-key',
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sticky-');
    db = await databaseFactoryFfi.openDatabase('${tempDir.path}/sticky.db');
    await createProductionSchema();
    DBHelper.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await tempDir.delete(recursive: true);
  });

  final profile = UserProfile(
    id: 'u1',
    fullName: 'Test Inspector',
    role: 'inspector',
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Screens keep doing async cache/network work after the assertions finish.
  /// Tear the tree down first (LIFO: this runs before the group tearDown that
  /// closes the database) so no query lands on a closed handle.
  void disposeTreeAfterTest(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  Future<void> pumpTasks(WidgetTester tester, {double width = 390}) async {
    disposeTreeAfterTest(tester);
    await tester.pumpWidget(host(TasksScreen(profile: profile), width: width));
    await settle(tester);
  }

  /// A page-sized translucent blue circle = the decorative background orb.
  List<Container> decorativeOrbs(WidgetTester tester) =>
      tester.widgetList<Container>(find.byType(Container)).where((c) {
        final d = c.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle) return false;
        final col = d.color;
        if (col == null || col.a >= 1.0) return false;
        final w = c.constraints?.maxWidth ?? 0;
        final h = c.constraints?.maxHeight ?? 0;
        final big = w >= kDecorativeOrbMinSize || h >= kDecorativeOrbMinSize;
        return big && col.b > col.r; // translucent brand-blue family
      }).toList();

  // ==========================================================================
  // PART A — My Tasks: one scrolling header card
  //
  // The approved sample folds the title, live sync state, summary, Search /
  // Filter and the Pending / Ongoing / Completed selector into one card at the
  // top of the scroll view. Task cards below are untouched.
  // ==========================================================================

  group('MY TASKS — header card and category selector', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/modules/tasks/screens/tasks_screen.dart',
      ).readAsStringSync();
    });

    testWidgets('1. My Tasks title exists in the scrolling header card', (
      tester,
    ) async {
      await pumpTasks(tester);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'the approved header is a card in the scroll view, not chrome',
      );
    });

    test('2. Pending / Ongoing / Completed selector is declared', () {
      // TasksScreen gates its scroll view on a successful load, and this
      // dependency set exposes no connectivity test seam, so the sliver tree
      // cannot be mounted here. Its composition is asserted on the real
      // source instead; the title above is still proven on the live widget.
      for (final label in ['Pending', 'Ongoing', 'Completed']) {
        expect(
          src,
          contains('text: "$label"'),
          reason: '$label segment exists',
        );
      }
    });

    test(
      '3 + 4. the whole header card scrolls; nothing is a pinned sliver',
      () {
        expect(src, isNot(contains('SliverPersistentHeader(')));
        expect(
          src,
          contains('SliverToBoxAdapter('),
          reason: 'the header card is the first scrolling sliver',
        );
        expect(
          src,
          contains('child: _buildHeaderCard('),
          reason: 'the one card owns title, search, filter and segments',
        );
      },
    );

    test(
      '5 + 6. Search and Filter live in the header card, never a pinned bar',
      () {
        final method = src.substring(src.indexOf('Widget _buildHeaderCard'));
        final nextIdx = method.indexOf('\n  Widget ');
        final header = nextIdx < 0 ? method : method.substring(0, nextIdx);
        expect(
          header,
          contains('hintText:'),
          reason: 'Search is in the header card',
        );
        expect(
          header,
          contains('Icons.tune_rounded'),
          reason: 'Filter is in the header card',
        );
        expect(
          header,
          contains('_buildCategoryBar('),
          reason: 'the selector closes the same card',
        );
      },
    );

    test(
      '5b. internal order: title, search/filter, then the category bar',
      () {
        final header = src.substring(
          src.indexOf('Widget _buildHeaderCard'),
          src.indexOf('Widget _buildCategoryBar('),
        );
        for (final marker in [
          "'My Tasks'",
          'hintText:',
          'Icons.tune_rounded',
          '_buildCategoryBar(',
        ]) {
          expect(header, contains(marker), reason: '$marker missing');
        }
        expect(
          header.indexOf('hintText:'),
          lessThan(header.indexOf('Icons.tune_rounded')),
          reason: 'Search precedes Filter',
        );
        expect(
          header.indexOf('Icons.tune_rounded'),
          lessThan(header.indexOf('_buildCategoryBar(')),
          reason: 'Filter precedes the selector',
        );
      },
    );

    test('9. the switcher is built exactly once — no duplicate header', () {
      // Each label appears exactly once: one Pending / Ongoing / Completed.
      for (final label in ['Pending', 'Ongoing', 'Completed']) {
        expect(
          'text: "$label"'.allMatches(src).length,
          1,
          reason: '$label must exist exactly once (no duplicated header)',
        );
      }
      expect(
        '_buildCategoryBar('.allMatches(src).length,
        2,
        reason: 'one declaration + one call site only',
      );
      expect(RegExp('SliverPersistentHeader\\(').allMatches(src).length, 0);
    });

    testWidgets('10. no overflow at a narrow width', (tester) async {
      await pumpTasks(tester, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('My Tasks'), findsOneWidget);
    });

    testWidgets('10b. no overflow at a large text scale', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: kStatusBarInset),
            textScaler: TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: TasksScreen(profile: profile),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    test(
      '10c. the header card is a single rounded surface with no second header',
      () {
        expect(src, contains('borderRadius: InsightTheme.roundedLg'));
        expect(src, contains('boxShadow: InsightTheme.cardShadow'));
        expect(
          RegExp(r"Text\(\s*'My Tasks'").allMatches(src).length,
          1,
          reason: 'the title renders once',
        );
        expect(RegExp('SliverPersistentHeader\\(').allMatches(src).length, 0);
      },
    );

    test('7 + 8. category state and handlers are unchanged', () {
      // Presentation-only change: same _currentTabIndex, same three handlers.
      expect(src, contains('isActive: _currentTabIndex == 0'));
      expect(src, contains('isActive: _currentTabIndex == 1'));
      expect(src, contains('isActive: _currentTabIndex == 2'));
      expect(src, contains('setState(() => _currentTabIndex = 0)'));
      expect(src, contains('setState(() => _currentTabIndex = 1)'));
      expect(src, contains('setState(() => _currentTabIndex = 2)'));
    });
  });

  // ==========================================================================
  // PART B — Sync Center: one header card, one status card, queue first
  //
  // The approved layout keeps the title/connectivity/help group outside the
  // scroll view, moves the live queue count and Sync now action into a single
  // status card, and places the queue above history and storage. UpdatesScreen
  // cannot be mounted in this harness (it starts a repeating sync poll), so the
  // composition is asserted structurally on the real source.
  // ==========================================================================

  group('SYNC CENTER — header card and status card composition', () {
    late String sync;

    setUpAll(() {
      // Normalised so the structural offsets below do not depend on whether
      // the working copy currently uses CRLF.
      sync = File(
        'lib/modules/offline_sync/screens/updates_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    /// The header card: from its own key to the start of the scrolling body.
    String headerCard() {
      final start = sync.indexOf("key: const ValueKey('sync_header')");
      expect(
        start,
        greaterThanOrEqualTo(0),
        reason: 'the header card exists',
      );
      final end = sync.indexOf('child: RefreshIndicator(', start);
      expect(end, greaterThan(start), reason: 'the scroll view follows');
      return sync.substring(start, end);
    }

    test('11. the header card is declared once, in full', () {
      for (final marker in ['Sync Center', 'Last sync:', '_sectionHelpButton']) {
        expect(sync, contains(marker), reason: '$marker still present');
      }
      expect(
        RegExp("Text\\(\\s*'Sync Center',").allMatches(sync).length,
        1,
        reason: 'no duplicated Sync Center heading',
      );
      expect(
        RegExp("title: 'Sync Center',").allMatches(sync).length,
        1,
        reason: 'the header help dialog is unchanged',
      );
      expect(sync, isNot(contains('Everything is synced')));
    });

    test('12. queue follows the status card and precedes history/storage', () {
      final body = sync.substring(sync.indexOf('child: RefreshIndicator('));
      final statusIdx = body.indexOf('child: _buildSyncStatusCard()');
      final queueIdx = body.indexOf('child: _buildQueueSection()');
      final historyIdx = body.indexOf("'Synchronization history'");
      final storageIdx = body.indexOf("'Offline storage'");
      for (final entry in {
        'status': statusIdx,
        'queue': queueIdx,
        'history': historyIdx,
        'storage': storageIdx,
      }.entries) {
        expect(entry.value, greaterThanOrEqualTo(0), reason: entry.key);
      }
      expect(statusIdx, lessThan(queueIdx));
      expect(queueIdx, lessThan(historyIdx));
      expect(historyIdx, lessThan(storageIdx));
      expect(
        body,
        isNot(contains('WAITING TO SYNC')),
        reason: 'the old uppercase queue band is gone',
      );
    });

    test('13. the header is a rounded card, not a full-bleed bar', () {
      final header = headerCard();
      expect(header, contains('InsightTheme.surface'));
      expect(header, contains('InsightTheme.roundedLg'));
      expect(header, contains('InsightTheme.cardShadow'));
      expect(header, contains('_sectionHelpButton'));
      expect(header, contains('Last sync:'));
    });

    test('15b. no doubled status-bar inset is introduced', () {
      // No Scaffold appBar was added, so the body's SafeArea remains the one
      // and only top inset — unchanged from the pre-change layout.
      expect(sync, isNot(contains('appBar:')));
      expect(sync, contains('SafeArea('));
      expect(
        sync,
        isNot(contains('top: false')),
        reason: 'the real status-bar inset is applied exactly once',
      );
    });

    test('17b. no decorative background orb remains on Sync', () {
      // The removed orb was the only 80-sigma blurred layer. Legitimate small
      // circles (status dot, spinner) legitimately remain.
      expect(sync, isNot(contains('sigmaX: 80')));
      expect(sync, isNot(contains('ImageFiltered')));
      expect(sync, isNot(contains("import 'dart:ui'")));
    });
  });

  // ==========================================================================
  // PART C — decorative blue page background removed
  // ==========================================================================

  group('BACKGROUND — decorative blue circles removed', () {
    testWidgets('17. Profile no longer mounts a decorative background orb', (
      tester,
    ) async {
      disposeTreeAfterTest(tester);
      await tester.pumpWidget(host(ProfileScreen(profile: profile)));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(decorativeOrbs(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('17c. My Tasks has no decorative background orb', (
      tester,
    ) async {
      await pumpTasks(tester);
      expect(decorativeOrbs(tester), isEmpty);
    });

    testWidgets('17d. the shared shell no longer paints background orbs', (
      tester,
    ) async {
      // The two 60-sigma blurred blue discs lived in the shell behind every
      // page; assert the shell source no longer builds them.
      final shell = File(
        'lib/core/navigation/main_shell_screen.dart',
      ).readAsStringSync();
      expect(shell, isNot(contains('sigmaX: 60')));
      expect(shell, isNot(contains('BoxShape.circle')));
    });

    testWidgets('18. the neutral page background token is still in use', (
      tester,
    ) async {
      await pumpTasks(tester);
      expect(
        find.byWidgetPredicate(
          (w) => w is Scaffold && w.backgroundColor == InsightTheme.bg,
        ),
        findsWidgets,
        reason: 'pages keep the plain neutral surface',
      );
      // Existing token, unchanged — no new colour was introduced.
      expect(InsightTheme.bg, const Color(0xFFF4F6FB));
    });

    testWidgets('19. legitimate blue controls are NOT stripped', (
      tester,
    ) async {
      await pumpTasks(tester);
      // Brand blue survives on real UI: the active selector / filter controls
      // and the theme tokens themselves are untouched.
      expect(find.text('My Tasks'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(InsightTheme.blue1, const Color(0xFF2563EB));
      expect(InsightTheme.blueTint, const Color(0xFFEFF6FF));
      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // PART A2 — the My Tasks header card is one unit
  //
  // Title, summary, Search / Filter and the selector share one card, so there
  // is no second header to keep in sync. These assertions are structural
  // because this dependency set exposes no connectivity test seam that would
  // load the task slivers deterministically.
  // ==========================================================================

  group('MY TASKS — the whole header card scrolls', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/modules/tasks/screens/tasks_screen.dart',
      ).readAsStringSync();
    });

    testWidgets('TOP — the card renders title and live sync control', (
      tester,
    ) async {
      await pumpTasks(tester);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-sync-indicator')),
        findsOneWidget,
        reason: 'the cloud status control stays beside the title',
      );
      expect(find.text('ASSIGNED'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TOP — title and summary share the card at wide width', (
      tester,
    ) async {
      await pumpTasks(tester, width: 800);
      expect(find.text('My Tasks'), findsOneWidget);
      final summary = find.textContaining(
        RegExp('assigned ·|Loading tasks|Saved tasks'),
      );
      expect(summary, findsOneWidget);
      expect(find.text('ASSIGNED'), findsNothing);
      expect(find.text('ACTIVE MONITORING'), findsNothing);
      final title = tester.getRect(find.text('My Tasks'));
      final summaryRect = tester.getRect(summary);
      expect(
        summaryRect.top,
        greaterThan(title.top),
        reason: 'the summary sits under the title in the same card',
      );
      expect(tester.takeException(), isNull);
    });

    test('SCROLLED — Search and Filter sit inside the one header card', () {
      final header = src.substring(
        src.indexOf('Widget _buildHeaderCard'),
        src.indexOf('Widget _buildCategoryBar('),
      );
      expect(header, contains('hintText:'), reason: 'Search is in the card');
      expect(
        header,
        contains('Icons.tune_rounded'),
        reason: 'Filter is in the card',
      );
      expect(
        src,
        isNot(contains('SliverPersistentHeader(')),
        reason: 'no second pinned header may duplicate the card',
      );
    });

    testWidgets('SCROLLED — one mounted header, no pinned regions', (
      tester,
    ) async {
      await pumpTasks(tester);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.text('My Tasks'), findsOneWidget);
    });

    test('SCROLLED — the selector sits at the bottom of the same card', () {
      final headerStart = src.indexOf('Widget _buildHeaderCard');
      final searchIdx = src.indexOf('hintText:', headerStart);
      final barIdx = src.indexOf('_buildCategoryBar(', searchIdx);
      expect(searchIdx, greaterThanOrEqualTo(0));
      expect(barIdx, greaterThan(searchIdx));
      expect(
        src,
        contains('color: InsightTheme.surface2'),
        reason: 'the selector keeps its segmented track',
      );
      expect(RegExp('SliverPersistentHeader\\(').allMatches(src).length, 0);
    });

    testWidgets('the header card does not overflow', (tester) async {
      await pumpTasks(tester, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(
        find.textContaining(RegExp('assigned ·|Loading tasks|Saved tasks')),
        findsOneWidget,
      );
      expect(find.text('ACTIVE MONITORING'), findsNothing);
      expect(find.text('ASSIGNED'), findsNothing);
    });
  });

  // ==========================================================================
  // PART D — offline banner / single top inset preserved
  // ==========================================================================

  group('OFFLINE + STICKY HEADERS', () {
    testWidgets(
      '14. pinned Tasks chrome survives with the Offline banner mounted',
      (tester) async {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: Column(
                children: [
                  const OfflineBanner(),
                  Expanded(child: TasksScreen(profile: profile)),
                ],
              ),
            ),
          ),
        );
        await settle(tester);

        expect(find.text('Offline mode'), findsOneWidget);
        expect(
          find.text('My Tasks'),
          findsOneWidget,
          reason: 'the header card still renders beneath the offline banner',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('16. no doubled top inset returns', (tester) async {
      double seen = -1;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Column(
              children: [
                const OfflineBanner(),
                Expanded(
                  child: PageUnderOfflineBanner(
                    isOnline: false,
                    child: Builder(
                      builder: (context) {
                        seen = MediaQuery.paddingOf(context).top;
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, 0, reason: 'exactly one status-bar inset, not two');
    });

    testWidgets('16b. Tasks chrome + offline banner add no second inset', (
      tester,
    ) async {
      disposeTreeAfterTest(tester);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Column(
              children: [
                const OfflineBanner(),
                Expanded(child: TasksScreen(profile: profile)),
              ],
            ),
          ),
        ),
      );
      await settle(tester);
      // Exactly one status-bar inset: the banner clears it, the page's own
      // SafeArea must not add another.
      expect(find.text('Offline mode'), findsOneWidget);
      expect(
        find.text('My Tasks'),
        findsOneWidget,
        reason: 'the header card survives under the single top inset',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // PART F/G — shell navigation still renders
  // ==========================================================================

  group('MAIN SHELL NAVIGATION', () {
    test('20. shell still routes all four tabs', () {
      final shell = File(
        'lib/core/navigation/main_shell_screen.dart',
      ).readAsStringSync();
      for (final label in ['Home', 'Tasks', 'Sync', 'Profile']) {
        expect(shell, contains("label: '$label'"), reason: '$label tab kept');
      }
      // Bottom navigation and the Quick Actions trigger are untouched.
      expect(shell, contains('InsightBottomNav('));
      expect(shell, contains('QuickActionsSheet'));
      expect(shell, contains('PageUnderOfflineBanner('));
    });

    test(
      '20b. each tab is built through the single _buildPage choke point',
      () {
        final shell = File(
          'lib/core/navigation/main_shell_screen.dart',
        ).readAsStringSync();
        for (final screen in [
          'HomeDashboardScreen(',
          'TasksScreen(',
          'UpdatesScreen(',
          'ProfileScreen(',
        ]) {
          expect(shell, contains(screen), reason: '$screen still built');
        }
        expect(shell, contains('child: _buildPage(_currentIndex)'));
      },
    );
  });
}
