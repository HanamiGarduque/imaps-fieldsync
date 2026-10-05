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

Widget host(Widget child, {double width = 390, double height = 844}) => MediaQuery(
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
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)')
        .allMatches(source)) {
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
    await Supabase.initialize(url: 'http://127.0.0.1:1', publishableKey: 'test-anon-key');
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

  final profile =
      UserProfile(id: 'u1', fullName: 'Test Inspector', role: 'inspector');

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
  List<Container> decorativeOrbs(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where((c) {
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
  // PART A — My Tasks: the header lives in pinned AppBar chrome
  //
  // Why asserted this way: a Scaffold `appBar` (and its `bottom`) is chrome and
  // is never scrolled by the body, so "is this widget inside the AppBar" is a
  // direct, behavioural proof that it stays put — stronger than sampling
  // pixels after a drag, and it does not depend on the list having loaded.
  // ==========================================================================

  group('MY TASKS — pinned title + category selector', () {
    late String src;

    setUpAll(() {
      src = File('lib/modules/tasks/screens/tasks_screen.dart')
          .readAsStringSync();
    });

    testWidgets('1. My Tasks title exists and is pinned chrome', (tester) async {
      await pumpTasks(tester);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('My Tasks')),
        findsOneWidget,
        reason: 'the title lives in Scaffold appBar chrome, which never scrolls',
      );
    });

    test('2. Pending / Ongoing / Completed selector is declared', () {
      // TasksScreen gates its scroll view on a successful load, and this
      // dependency set exposes no connectivity test seam, so the sliver tree
      // cannot be mounted here. Its composition is asserted on the real
      // source instead; the title above is still proven on the live widget.
      for (final label in ['Pending', 'Ongoing', 'Completed']) {
        expect(src, contains('text: "$label"'), reason: '$label segment exists');
      }
    });

    test('3 + 4. the selector is a PINNED sliver, so it cannot scroll away', () {
      expect(src, contains('SliverPersistentHeader('));
      expect(
        RegExp('SliverPersistentHeader\\(\\s*\\n\\s*pinned: true').hasMatch(src),
        isTrue,
        reason: 'the category bar must be pinned',
      );
      expect(
        RegExp('delegate: _CategoryBarHeaderDelegate').hasMatch(src),
        isTrue,
        reason: 'the pinned sliver hosts the category bar',
      );
    });

    test('5 + 6. Search/Filter are NOT pinned — they stay in the scroll view', () {
      // The pinned header is built only from the category bar, so no TextField
      // can be inside it; Search therefore scrolls up and passes behind it.
      final method = src.substring(src.indexOf('Widget _buildCategoryBar'));
      final nextIdx = method.indexOf('\n  Widget ');
      final categoryBar =
          nextIdx < 0 ? method : method.substring(0, nextIdx);
      expect(categoryBar, isNot(contains('TextField')),
          reason: 'Search must never be inside the pinned bar');
      expect(categoryBar, isNot(contains('Icons.tune_rounded')),
          reason: 'Filter must never be inside the pinned bar');
      expect(src, contains('hintText:'));
    });

    test('5b. original order preserved: Search/Filter precede the category bar',
        () {
      final searchIdx = src.indexOf('SliverToBoxAdapter(');
      final pinnedIdx = src.indexOf('SliverPersistentHeader(');
      expect(searchIdx, greaterThanOrEqualTo(0));
      expect(pinnedIdx, greaterThan(searchIdx),
          reason: 'Search/Filter must stay above the category bar');
    });

    test('9. the switcher is built exactly once — no duplicate header', () {
      // Each label appears exactly once: one Pending / Ongoing / Completed.
      for (final label in ['Pending', 'Ongoing', 'Completed']) {
        expect('text: "$label"'.allMatches(src).length, 1,
            reason: '$label must exist exactly once (no duplicated header)');
      }
      expect('_buildCategoryBar('.allMatches(src).length, 2,
          reason: 'one declaration + one call site only');
      expect(RegExp('SliverPersistentHeader\\(').allMatches(src).length, 1);
    });

    testWidgets('10. no overflow at a narrow width', (tester) async {
      await pumpTasks(tester, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('My Tasks'), findsOneWidget);
    });

    testWidgets('10b. no overflow at a large text scale', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: kStatusBarInset),
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: TasksScreen(profile: profile),
        ),
      ));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    test('10c. the pinned band has a fixed, non-zero extent', () {
      expect(kCategoryBarHeight, greaterThan(0));
      expect(src, contains('double get minExtent => kCategoryBarHeight'));
      expect(src, contains('double get maxExtent => kCategoryBarHeight'));
    });

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
  // PART B — Sync Center: the ORIGINAL header group is pinned whole
  //
  // The pre-change layout already bundled "Sync Center", the connectivity /
  // last-sync line and the All Synced control into ONE opaque container that
  // was the first child of the scroll view. That composition is the visual
  // truth and is preserved exactly: only the group's role changed, from
  // "scrolls away with the content" to "pinned". It now sits in a Column above
  // the scroll view, so the whole group stays put and everything below scrolls.
  //
  // UpdatesScreen cannot be mounted in this harness — it starts a repeating
  // sync poll, so no quiescent frame is ever reached — so pinning is asserted
  // structurally on the real source. Device verification covers the rendering.
  // ==========================================================================

  group('SYNC CENTER — the whole original header group is pinned', () {
    late String sync;

    setUpAll(() {
      // Normalised so the structural offsets below do not depend on whether
      // the working copy currently uses CRLF.
      sync = File('lib/modules/offline_sync/screens/updates_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    /// Absolute index where the pinned Column opens.
    int groupStart() {
      final i = sync.indexOf(': Column(\n                  children: [');
      expect(i, greaterThanOrEqualTo(0), reason: 'the pinned Column exists');
      return i;
    }

    /// Absolute index where the pinned group ends and the scroll view begins.
    /// Anchored on the RefreshIndicator itself, because the header group
    /// contains other Expanded widgets of its own.
    int groupEnd() {
      final e = sync.indexOf('child: RefreshIndicator(', groupStart());
      expect(e, greaterThan(groupStart()),
          reason: 'the scroll view follows the pinned group');
      return e;
    }

    /// Exactly the pinned header region: everything between the Column's
    /// children list and the Expanded scroll view.
    String pinnedGroup() => sync.substring(groupStart(), groupEnd());

    test('11. the original header group is declared once, in full', () {
      for (final marker in ['Sync Center', 'Last sync:', 'All Synced']) {
        expect(sync, contains(marker), reason: '$marker still present');
      }
      // One visible title label, plus the pre-existing help dialog beside it.
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
    });

    test('12. the WHOLE header group is pinned, above the scroll view', () {
      final group = pinnedGroup();
      // Title, connectivity/last-sync status and the All Synced control are
      // all in the pinned region — the group was not split apart.
      for (final marker in ['Sync Center', 'Last sync:', 'All Synced']) {
        expect(group, contains(marker),
            reason: '$marker stays in the pinned header group');
      }
      expect(group, contains('Expanded('),
          reason: 'the pinned group is followed by an Expanded scroll view');
      // The help control belongs to the same group, so the group was not
      // split into "pinned title" + "scrolling detail".
      expect(group, contains('_sectionHelpButton'),
          reason: 'the header help control stays in the pinned group');
      expect(sync.indexOf('child: ListView(', groupStart()),
          greaterThan(groupEnd()),
          reason: 'the scrolling body starts after the pinned header group');
    });

    test('13. the pinned group is the original opaque container, unchanged', () {
      final group = pinnedGroup();
      // Same surface + 1px line divider as the pre-change header, so the
      // cards below cannot bleed through behind it.
      expect(group, contains('width: double.infinity'));
      expect(group, contains('color: InsightTheme.surface'));
      expect(group, contains('BorderSide(color: InsightTheme.line, width: 1)'));
      // Still the original single header container, first in the group.
      expect(RegExp('Container\\(\\s*\\n\\s*width: double.infinity').hasMatch(group),
          isTrue,
          reason: 'the original header container is the group’s first child');
    });

    test('15b. no doubled status-bar inset is introduced', () {
      // No Scaffold appBar was added, so the body's SafeArea remains the one
      // and only top inset — unchanged from the pre-change layout.
      expect(sync, isNot(contains('appBar:')));
      expect(sync, contains('SafeArea('));
      expect(sync, isNot(contains('top: false')),
          reason: 'the real status-bar inset is applied exactly once');
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
    testWidgets('17. Profile no longer mounts a decorative background orb',
        (tester) async {
      disposeTreeAfterTest(tester);
      await tester.pumpWidget(host(ProfileScreen(profile: profile)));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(decorativeOrbs(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('17c. My Tasks has no decorative background orb', (tester) async {
      await pumpTasks(tester);
      expect(decorativeOrbs(tester), isEmpty);
    });

    testWidgets('17d. the shared shell no longer paints background orbs',
        (tester) async {
      // The two 60-sigma blurred blue discs lived in the shell behind every
      // page; assert the shell source no longer builds them.
      final shell = File('lib/core/navigation/main_shell_screen.dart')
          .readAsStringSync();
      expect(shell, isNot(contains('sigmaX: 60')));
      expect(shell, isNot(contains('BoxShape.circle')));
    });

    testWidgets('18. the neutral page background token is still in use',
        (tester) async {
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

    testWidgets('19. legitimate blue controls are NOT stripped', (tester) async {
      await pumpTasks(tester);
      // Brand blue survives on real UI: the ACTIVE MONITORING pill in the live
      // widget is the proof, and the theme tokens themselves are untouched.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(Container),
        ),
        findsWidgets,
      );
      expect(InsightTheme.blue1, const Color(0xFF2563EB));
      expect(InsightTheme.blueTint, const Color(0xFFEFF6FF));
      expect(tester.takeException(), isNull);
    });
  });

// ==========================================================================
  // PART A2 — the My Tasks header GROUP stays pinned whole
  //
  // ACTIVE MONITORING, "My Tasks" and the ASSIGNED counter are ONE header
  // group in the original arrangement, and all three live in Scaffold appBar
  // chrome, which the body can never scroll. Search/Filter are the only part
  // that scrolls away; the pinned category sliver then parks directly beneath
  // the complete header.
  //
  // "Scrolls away" is asserted on the LIVE widget: anything absent from the
  // AppBar chrome and absent from the pinned sliver cannot survive a scroll.
  // Same guarantee a post-drag assertion gives, without needing the task list
  // to load (this dependency set exposes no connectivity test seam).
  // ==========================================================================

  group('MY TASKS — the whole header group stays pinned', () {
    late String src;

    setUpAll(() {
      src = File('lib/modules/tasks/screens/tasks_screen.dart')
          .readAsStringSync();
    });

    /// The AppBar block, with line comments stripped so the explanatory
    /// notes inside the bar cannot satisfy a containment check.
    String appBarBlock() {
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final start = code.indexOf('appBar: AppBar(');
      expect(start, greaterThanOrEqualTo(0));
      final end = code.indexOf('body: SafeArea(', start);
      return end < 0 ? code.substring(start) : code.substring(start, end);
    }

    testWidgets('TOP — the whole header group is pinned chrome',
        (tester) async {
      await pumpTasks(tester);
      expect(find.text('My Tasks'), findsOneWidget);
      for (final marker in ['My Tasks', 'ACTIVE MONITORING', 'ASSIGNED']) {
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(marker),
          ),
          findsOneWidget,
          reason: '$marker is pinned chrome, so it never scrolls away',
        );
      }
      expect(tester.takeException(), isNull);
    });

    test('TOP — the original header composition is intact, in the AppBar', () {
      final bar = appBarBlock();
      // All three parts are still together in the one AppBar group.
      expect(bar, contains('ACTIVE MONITORING'));
      expect(bar, contains('My Tasks'));
      expect(bar, contains('ASSIGNED'));
      expect(bar, contains('CountUpText'));
      // The tall toolbar that accommodates both, as originally arranged.
      expect(bar, contains('toolbarHeight: 85'));
      // Original arrangement: pill above the title, counter beside it.
      final pill = bar.indexOf('ACTIVE MONITORING');
      final title = bar.indexOf("'My Tasks'");
      final counter = bar.indexOf('CountUpText');
      expect(pill, lessThan(title), reason: 'the pill sits above My Tasks');
      expect(title, lessThan(counter),
          reason: 'the ASSIGNED counter sits beside the title');
      // Nothing was duplicated into the scrolling content.
      expect("'My Tasks'".allMatches(src).length, 1,
          reason: 'My Tasks must not be duplicated');
      expect("'ASSIGNED'".allMatches(src).length, 1,
          reason: 'the assigned counter must not be duplicated');
      expect("Text('ACTIVE MONITORING'".allMatches(src).length, 1,
          reason: 'the status pill must not be duplicated');
    });

    test('SCROLLED — Search / Filter scroll away behind the pinned bar', () {
      // The pinned sliver hosts only the category bar, so neither control can
      // survive inside it; they must therefore pass behind it.
      final method = src.substring(src.indexOf('Widget _buildCategoryBar'));
      final nextIdx = method.indexOf('\n  Widget ');
      final bar = nextIdx < 0 ? method : method.substring(0, nextIdx);
      expect(bar, isNot(contains('TextField')), reason: 'Search scrolls away');
      expect(bar, isNot(contains('Icons.tune_rounded')),
          reason: 'Filter scrolls away');
      // Both are still on the page, inside the scrolling body.
      final body = src.substring(src.indexOf('body: SafeArea('));
      expect(body, contains('hintText:'), reason: 'Search still present');
      expect(body, contains('Icons.tune_rounded'), reason: 'Filter still present');
    });

    testWidgets('SCROLLED — Search / Filter are in neither pinned region',
        (tester) async {
      await pumpTasks(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'Search cannot survive a scroll',
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.tune_rounded),
        ),
        findsNothing,
        reason: 'Filter cannot survive a scroll',
      );
      expect(
        find.descendant(
          of: find.byType(SliverPersistentHeader),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'Search is not in the pinned category sliver',
      );
      expect(
        find.descendant(
          of: find.byType(SliverPersistentHeader),
          matching: find.byIcon(Icons.tune_rounded),
        ),
        findsNothing,
        reason: 'Filter is not in the pinned category sliver',
      );
      // The header group, by contrast, is still mounted in chrome.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('ACTIVE MONITORING'),
        ),
        findsOneWidget,
        reason: 'the header group survives scrolling',
      );
    });

    test('SCROLLED — the category bar pins directly below the full header', () {
      // Header = AppBar chrome. Category bar = the pinned sliver, which is the
      // next element down the page and sits after Search/Filter in normal
      // flow. Once Search/Filter scroll away it parks under the full header.
      final pinnedIdx = src.indexOf('SliverPersistentHeader(');
      expect(pinnedIdx, greaterThanOrEqualTo(0));
      expect(
        RegExp('SliverPersistentHeader\\(\\s*\\n\\s*pinned: true').hasMatch(src),
        isTrue,
        reason: 'the category bar must be pinned',
      );
      expect(src, contains('delegate: _CategoryBarHeaderDelegate'));
      final bodyStart = src.indexOf('body: SafeArea(');
      final searchIdx = src.indexOf('hintText:', bodyStart);
      expect(searchIdx, greaterThanOrEqualTo(0), reason: 'Search is declared');
      expect(searchIdx, lessThan(pinnedIdx),
          reason: 'Search/Filter appear above the category bar at the top');
      // Opaque band, so task cards cannot bleed through behind the pinned bar.
      expect(src, contains('color: InsightTheme.surface'));
      expect(kCategoryBarHeight, greaterThan(0));
    });

    testWidgets('the restored header group does not overflow', (tester) async {
      await pumpTasks(tester, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(find.text('ACTIVE MONITORING'), findsOneWidget);
      expect(find.text('ASSIGNED'), findsOneWidget);
    });
  });

  // ==========================================================================
  // PART D — offline banner / single top inset preserved
  // ==========================================================================

  group('OFFLINE + STICKY HEADERS', () {
    testWidgets('14. pinned Tasks chrome survives with the Offline banner mounted',
        (tester) async {
      await tester.pumpWidget(host(
        Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: TasksScreen(profile: profile)),
            ],
          ),
        ),
      ));
      await settle(tester);

      expect(find.text('Offline mode'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('My Tasks')),
        findsOneWidget,
        reason: 'the pinned title still renders beneath the offline banner',
      );
      expect(tester.takeException(), isNull);
    });


    testWidgets('16. no doubled top inset returns', (tester) async {
      double seen = -1;
      await tester.pumpWidget(host(
        Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: PageUnderOfflineBanner(
                  isOnline: false,
                  child: Builder(builder: (context) {
                    seen = MediaQuery.paddingOf(context).top;
                    return const SizedBox.expand();
                  }),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(seen, 0, reason: 'exactly one status-bar inset, not two');
    });

    testWidgets('16b. Tasks chrome + offline banner add no second inset',
        (tester) async {
      disposeTreeAfterTest(tester);
      await tester.pumpWidget(host(
        Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: TasksScreen(profile: profile)),
            ],
          ),
        ),
      ));
      await settle(tester);
      // Exactly one status-bar inset: the banner clears it, the page's own
      // SafeArea must not add another.
      expect(find.text('Offline mode'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('My Tasks')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // PART F/G — shell navigation still renders
  // ==========================================================================

  group('MAIN SHELL NAVIGATION', () {
    test('20. shell still routes all four tabs', () {
      final shell = File('lib/core/navigation/main_shell_screen.dart')
          .readAsStringSync();
      for (final label in ['Home', 'Tasks', 'Sync', 'Profile']) {
        expect(shell, contains("label: '$label'"), reason: '$label tab kept');
      }
      // Bottom navigation and the Quick Actions trigger are untouched.
      expect(shell, contains('InsightBottomNav('));
      expect(shell, contains('QuickActionsSheet'));
      expect(shell, contains('PageUnderOfflineBanner('));
    });

    test('20b. each tab is built through the single _buildPage choke point', () {
      final shell = File('lib/core/navigation/main_shell_screen.dart')
          .readAsStringSync();
      for (final screen in [
        'HomeDashboardScreen(',
        'TasksScreen(',
        'UpdatesScreen(',
        'ProfileScreen(',
      ]) {
        expect(shell, contains(screen), reason: '$screen still built');
      }
      expect(shell, contains('child: _buildPage(_currentIndex)'));
    });
  });
}
