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
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/compass_preview_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/models/analytics_activity_range.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/dashboard_widgets.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final jobs = [
    for (final status in ['assigned', 'in_progress', 'completed'])
      {
        'id': 'legibility-$status',
        'status': status,
        'assigned_inspector_id': 'legibility-inspector',
        'scheduled_date': status == 'assigned'
            ? ''
            : DateTime.now()
                  .add(const Duration(days: 2))
                  .toIso8601String(),
        'deadline_date': DateTime.now()
            .add(const Duration(days: 10))
            .toIso8601String(),
        'is_self_scheduled': false,
        'created_at': DateTime.now().toIso8601String(),
        'supabase_zoning_applications': {
          'applicant_name': '$status applicant',
          'barangay': 'San Carlos',
          'reference_number': 'LEGIBILITY-001',
        },
      },
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    final sdkFonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = ByteData.sublistView(
      sdkFonts
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
      if (asset.startsWith('assets/branding/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
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
      (_) async => ['wifi'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('hemanthraj/flutter_compass'),
      (_) async => null,
    );
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final schema = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final statement in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(schema)) {
      await db.execute(statement.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = 'legibility-inspector';
    await DBHelper.cacheJobs(jobs);
    await Supabase.initialize(
      url: 'https://legibility.test',
      publishableKey: 'isolated-test-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(jobs),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'isolated-token',
        'refresh_token': 'isolated-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'legibility-inspector',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() async {
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await Supabase.instance.dispose();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child,
    Size size, {
    double scale = 2,
    FakeViewPadding padding = const FakeViewPadding(top: 24, bottom: 24),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    if (child is TasksScreen) {
      for (
        var frame = 0;
        frame < 100 && find.text('Pending').evaluate().isEmpty;
        frame++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        find.text('Pending'),
        findsOneWidget,
        reason: 'Tasks finished loading the real SQLite cache.',
      );
    }
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(360, 800),
    const Size(800, 360),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'All five production Quick Actions keep readable subtitles at $size',
      (tester) async {
        const labels = [
          ('Map', 'Navigate your current location'),
          ('Compass', 'Determine your orientation'),
          ('Analytics overview', 'Track performance metrics'),
          ('Sync history', 'View synchronization activity'),
          ('Edit profile', 'Update your personal details'),
        ];
        String? selected;
        await mount(
          tester,
          Scaffold(
            extendBody: true,
            body: Stack(
              children: [
                const Positioned.fill(child: SizedBox()),
                QuickActionsOverlay(
                  child: QuickActionsSheet(
                    fillAvailableSpace: true,
                    onClose: () {},
                    actions: [
                      for (final (title, subtitle) in labels)
                        QuickAction(
                          icon: Icons.map_outlined,
                          title: title,
                          subtitle: subtitle,
                          onTap: () => selected = title,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: InsightBottomNav(
              currentIndex: 0,
              onTap: (_) {},
              onQuickActionsTap: () {},
              items: const [
                InsightNavItem(icon: Icons.home, label: 'Home'),
                InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
                InsightNavItem(icon: Icons.sync, label: 'Sync'),
                InsightNavItem(icon: Icons.person, label: 'Profile'),
              ],
            ),
          ),
          size,
        );
        expect(tester.takeException(), isNull);
        for (final (title, subtitle) in labels) {
          await tester.ensureVisible(find.text(subtitle));
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(subtitle),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason:
                '$subtitle must wrap rather than disappear behind an ellipsis.',
          );
          await tester.ensureVisible(find.text(title));
          await tester.pumpAndSettle();
          await tester.tap(find.text(title));
          expect(selected, title);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Heatmap numbers fit their cells and weekday labels align at enlarged text',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ActivityHeatmapCard(
                activityRange: AnalyticsActivityRange.month(2026, 8, const {}),
                activeColor: Colors.green,
                inactiveColor: Colors.grey.shade100,
                textColor: Colors.black,
                mutedTextColor: Colors.grey.shade800,
                now: () => DateTime(2026, 8, 15),
              ),
            ),
          ),
        ),
        const Size(320, 640),
      );
      final number = find.text('31');
      final cell = tester.getRect(
        find.ancestor(of: number, matching: find.byType(Container)).first,
      );
      final paragraph = tester.renderObject<RenderParagraph>(number);
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      expect(cell.width, greaterThanOrEqualTo(painter.width + 4));
      expect(
        cell.height,
        greaterThanOrEqualTo(painter.height + 4),
        reason: 'Large day numbers need real cell height, not text clipping.',
      );
      painter.dispose();
      final monday = tester.getRect(find.text('M'));
      expect(
        monday.center.dx,
        closeTo(tester.getRect(find.text('3')).center.dx, 0.1),
      );
      await tester.ensureVisible(find.text('30'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compass metadata keeps whole labels and the complete sensor subtitle',
    (tester) async {
      for (final size in [
        const Size(320, 640),
        const Size(360, 800),
        const Size(800, 360),
      ]) {
        for (final scale in [1.0, 2.0]) {
          await mount(
            tester,
            const StandaloneCompassScreen(),
            size,
            scale: scale,
          );
          await binding.defaultBinaryMessenger.handlePlatformMessage(
            'hemanthraj/flutter_compass',
            const StandardMethodCodec().encodeSuccessEnvelope([
              166.0,
              0.0,
              5.0,
            ]),
            (_) {},
          );
          await tester.pumpAndSettle();
          for (final label in ['Heading', 'Cardinal', 'Accuracy']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(label),
            );
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              ),
              hasLength(1),
              reason: '$label must stay intact at $size / $scale.',
            );
          }
          final sensor = tester.renderObject<RenderParagraph>(
            find.text('Sensor · Live Device Magnetometer'),
          );
          expect(
            sensor.didExceedMaxLines,
            isFalse,
            reason:
                'The sensor description must remain readable at $size / $scale.',
          );
          expect(
            sensor.getBoxesForSelection(
              const TextSelection(baseOffset: 21, extentOffset: 33),
            ),
            hasLength(1),
            reason: 'Magnetometer must fit without splitting the word.',
          );
          if (size.height > size.width) {
            final title = tester.renderObject<RenderParagraph>(
              find.text('Compass'),
            );
            expect(
              title.getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 7),
              ),
              hasLength(1),
            );
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text('Live orientation'))
                  .didExceedMaxLines,
              isFalse,
            );
          }
          expect(tester.takeException(), isNull, reason: '$size / $scale');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  for (final (pageName, label) in [
    ('Tasks', 'Search tasks'),
    ('English Help', 'Search the guide'),
    ('Tagalog Help', 'Maghanap sa gabay'),
  ]) {
    testWidgets('$pageName search retains its accessible name after typing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(
          tester,
          pageName == 'Tasks'
              ? TasksScreen(profile: UserProfile(
                  id: 'legibility-inspector',
                  fullName: 'Test Inspector',
                  role: 'inspector',
                ))
              : const HelpFaqScreen(),
          const Size(390, 844),
          scale: 1,
        );
        if (pageName == 'Tagalog Help') {
          await tester.tap(find.text('Tagalog'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField), 'query');
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(label), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('Tasks categories retain chosen text size and remain tappable', (
    tester,
  ) async {
    await mount(
      tester,
      TasksScreen(
        profile: UserProfile(
          id: 'legibility-inspector',
          fullName: 'Test Inspector',
          role: 'inspector',
        ),
      ),
      const Size(320, 640),
    );
    expect(find.text('Pending'), findsOneWidget);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(editable.preferredLineHeight + 22),
      reason: 'Search text needs its full line height and vertical padding.',
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Completed'),
    );
    final painted = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    expect(
      painted.height,
      closeTo(paragraph.size.height, 0.1),
      reason: 'The category must not scale away the requested font size.',
    );
    await tester.ensureVisible(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('completed applicant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tasks header respects landscape notch and navigation insets', (
    tester,
  ) async {
    await mount(
      tester,
      TasksScreen(
        profile: UserProfile(
          id: 'legibility-inspector',
          fullName: 'Test Inspector',
          role: 'inspector',
        ),
      ),
      const Size(640, 360),
      padding: const FakeViewPadding(left: 32, right: 24, top: 24, bottom: 24),
    );
    expect(tester.takeException(), isNull);
    final filter = tester.getRect(find.byIcon(Icons.tune_rounded));
    expect(filter.right, lessThanOrEqualTo(640 - 24 - 16));
    expect(
      tester.getRect(find.text('My Tasks')).left,
      greaterThanOrEqualTo(32 + 16),
    );
  });

  testWidgets(
    'Scheduling content and confirmation are reachable in short landscape',
    (tester) async {
      await mount(
        tester,
        TasksScreen(
          initialTabIndex: TasksScreen.tabPending,
          profile: UserProfile(
            id: 'legibility-inspector',
            fullName: 'Test Inspector',
            role: 'inspector',
          ),
        ),
        const Size(640, 360),
      );
      await tester.scrollUntilVisible(
        find.text('assigned applicant'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('assigned applicant'));
      await tester.pumpAndSettle();
      expect(find.text('Schedule this task'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Confirm schedule'));
      await tester.pumpAndSettle();
      final confirm = find.text('Confirm schedule');
      final viewport = tester.getRect(find.byType(Scaffold));
      expect(viewport.contains(tester.getCenter(confirm)), isTrue);
      await tester.ensureVisible(find.text('Select a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
