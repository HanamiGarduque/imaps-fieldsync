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
  List<Map<String, Object>>? activityOverride;
  int? completionTotal;
  var completionOverdue = 0;
  DateTime? scheduledOverride;
  Completer<void>? fontGate;
  Completer<void>? activityGate;
  var activityFetches = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    activityFetches = 0;
    await db.delete('local_jobs');
  });

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
      if (asset.startsWith('assets/branding/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
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
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    // Home now caches refreshes. Use its real schema in isolated SQLite, as
    // the offline-reliability fixture does, rather than a partial table stub.
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (local_jobs|pending_actions|local_inspections)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    await DBHelper.createInspectionRetentionTable(db);
    DBHelper.useDatabaseForTesting(db);
    await Supabase.initialize(
      url: 'https://home.test',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/activity_log')) {
          activityFetches++;
          await activityGate?.future;
        }
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
                                ? 'Started scheduled applicant'
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
            : activityOverride ?? [
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
            'deadline_date': DateTime.now().add(Duration(days:
                i % 4 != 3 && i - i ~/ 4 < completionOverdue ? -1 : 2)).toIso8601String(),
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

  group('Home completion and activity', () {
    final captureKey = GlobalKey();

    Future<void> capture(WidgetTester tester, String name) async {
      final output = Platform.environment['IMAPS_HOME_FLOW_VISUAL_DIR'];
      if (output == null) return;
      await tester.runAsync(() => GoogleFonts.pendingFonts());
      await tester.pump();
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        final chart = find.byKey(const ValueKey('completion_chart'));
        if (chart.evaluate().isNotEmpty) {
          final block = tester.getRect(chart);
          File('$output/$name.geometry.json').writeAsStringSync(jsonEncode({
            'evidence': 'SYNTHETIC WIDGET FIXTURE — NOT a genuine User Manual screenshot',
            'fonts': Platform.environment['IMAPS_LAYOUT_FONT_DIR'] == null ? 'SDK substitute fonts' : 'external font fixture',
            'block': [block.width, block.height],
            'origin': [block.left, block.top],
            'tiles': {
              for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed'])
                if (find.byKey(ValueKey('completion_$label')).evaluate().isNotEmpty)
                  label: (() {
                    final tile = tester.getRect(find.byKey(ValueKey('completion_$label')));
                    return [tile.left - block.left, tile.top - block.top, tile.width, tile.height];
                  })(),
            },
            'badge': find.byKey(const ValueKey('completion_overdue')).evaluate().isEmpty
                ? null : tester.getRect(find.byKey(const ValueKey('completion_overdue'))).toString(),
            'content': {
              for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed'])
                if (find.byKey(ValueKey('completion_$label')).evaluate().isNotEmpty)
                  label: {
                    for (final element in find.descendant(of: find.byKey(ValueKey('completion_$label')),
                        matching: find.byType(Text)).evaluate())
                      (element.widget as Text).data!: tester.getRect(find.byWidget(element.widget)).toString(),
                  },
            },
          }));
        }
      });
    }

    Future<void> mount(WidgetTester tester, {
      Size size = const Size(360, 800),
      TextScaler scaler = TextScaler.noScaling,
      bool reducedMotion = false,
      bool settle = true,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => RepaintBoundary(key: captureKey, child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: scaler, disableAnimations: reducedMotion),
          child: child!,
        )),
        home: HomeDashboardScreen(profile: UserProfile(
          id: 'home-inspector', fullName: 'Demonstration Inspector', role: 'inspector')),
      ));
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('completion_chart')).evaluate().isNotEmpty) break;
      }
      await tester.runAsync(() => GoogleFonts.pendingFonts());
      if (settle) await tester.pumpAndSettle();
    }

    /// The block opens on the chart and flips to the tiles, so anything that
    /// reads a tile has to reveal that face first.
    Future<void> showTiles(WidgetTester tester) async {
      final tiles = find.byKey(const ValueKey('completion_Scheduled'));
      if (tiles.evaluate().isNotEmpty) return;
      await tester.tap(find.byKey(const ValueKey('completion_chart')));
      await tester.pumpAndSettle();
      expect(tiles, findsOneWidget, reason: 'Tapping the block must reveal the tiles.');
    }

    /// And the reverse: the chart is the face the Home opens on.
    Future<void> showChart(WidgetTester tester) async {
      final rings = find.byKey(const ValueKey('completion_ring_chart'));
      if (rings.evaluate().isNotEmpty) return;
      await tester.tap(find.byKey(const ValueKey('completion_chart')));
      await tester.pumpAndSettle();
      expect(rings, findsOneWidget, reason: 'Tapping the block must reveal the chart.');
    }

    testWidgets('recent activity rows rise from below in a stagger as the modal opens', (tester) async {
      activityCount = 3;
      addTearDown(() => activityCount = 1);
      await mount(tester);
      await tester.ensureVisible(find.text('Activity 1'));
      await tester.tap(find.text('Activity 1'));
      await tester.pump();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 15));
      }
      final list = find.byKey(const ValueKey('recent_activity_modal_list'));
      final first = find.ancestor(of: find.byKey(const ValueKey('modal_activity-1')),
        matching: find.byType(SlideTransition));
      final second = find.ancestor(of: find.byKey(const ValueKey('modal_activity-2')),
        matching: find.byType(SlideTransition));
      expect(first, findsOneWidget,
        reason: 'the row must move upward, independently of the sheet');
      final firstOffset = tester.widget<SlideTransition>(first).position.value;
      final secondOffset = tester.widget<SlideTransition>(second).position.value;
      expect(firstOffset.dx, 0);
      expect(firstOffset.dy, greaterThan(0));
      expect(secondOffset.dy, greaterThan(firstOffset.dy),
        reason: 'the following row starts later in the upward chain');
      await capture(tester, 'activity-upward-090ms');
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 15));
      }
      expect(tester.widget<SlideTransition>(first).position.value.dy,
        lessThan(firstOffset.dy));
      await capture(tester, 'activity-upward-210ms');
      await tester.pumpAndSettle();
      expect(tester.widget<SlideTransition>(first).position.value, Offset.zero);
      expect(find.descendant(of: list, matching: find.text('Activity 1')).hitTestable(), findsOneWidget);
      await capture(tester, 'activity-upward-settled');
      await tester.tap(find.byTooltip('Close recent activity'));
      await tester.pumpAndSettle();
      // Reopening and quickly closing must cancel delayed work safely.
      await tester.tap(find.text('Activity 1'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced-motion activity history is immediately readable', (tester) async {
      activityCount = 3;
      addTearDown(() => activityCount = 1);
      await mount(tester, reducedMotion: true);
      await tester.ensureVisible(find.text('Activity 1'));
      await tester.tap(find.text('Activity 1'));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('recent_activity_modal_list'));
      expect(find.descendant(of: list, matching: find.byType(SlideTransition)), findsNothing);
      expect(find.descendant(of: list, matching: find.text('Activity 1')).hitTestable(), findsOneWidget);
      expect(find.descendant(of: list, matching: find.text('Activity 2')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder tabs persist and only the category preview opens its history', (tester) async {
      final categories = [
        ('Task', 'inspection_completed'), ('Sync', 'sync_manual'),
        ('Reports', 'diagnostic_report_submitted'), ('Profile', 'profile_updated'),
      ];
      activityOverride = [
        for (final (label, event) in categories)
          for (var i = 0; i < 2; i++) {
            'id': '$event-$i', 'event_type': event,
            'title': '$label ${i == 0 ? 'latest' : 'older'} event',
            'subtitle': 'Demonstration activity',
            'occurred_at': DateTime.now().subtract(Duration(minutes: i)).toIso8601String(),
            'is_read': false,
          },
      ];
      addTearDown(() => activityOverride = null);
      await mount(tester);
      final chips = find.byKey(const ValueKey('activity_category_shortcuts'));
      for (final (label, _) in categories) {
        final chip = find.descendant(of: chips, matching: find.text(label));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing,
            reason: 'A Home chip selects; the preview alone opens history.');
        expect(find.descendant(of: chips, matching: find.byType(InkWell)), findsNWidgets(4));
        expect(find.descendant(of: chips, matching: find.text('All')), findsNothing);
        expect(find.text('$label latest event'), findsOneWidget);
        expect(find.text('View 2 activities'), findsOneWidget);
        expect(find.text('$label older event'), findsNothing);
        for (final (other, _) in categories.where((item) => item.$1 != label)) {
          expect(find.text('$other latest event'), findsNothing);
        }
        final preview = find.text('$label latest event');
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        await capture(tester, 'home-activity-${label.toLowerCase()}');
        await tester.tap(preview);
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text('$label · 2 events')), findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text('$label older event')), findsOneWidget);
        if (label == 'Task') await capture(tester, 'activity-modal-task');
        final filters = find.byKey(const ValueKey('modal_activity_filters'));
        for (final filter in ['All', ...categories.map((item) => item.$1)]) {
          expect(find.descendant(of: filters, matching: find.text(filter)), findsOneWidget);
        }
        // Switching in the sheet must not require returning to Home.
        await tester.tap(find.descendant(of: filters, matching: find.text('All')));
        await tester.pumpAndSettle();
        expect(find.descendant(of: sheet, matching: find.text('All · 8 events')), findsOneWidget);
        await tester.tap(find.byTooltip('Close recent activity'));
        await tester.pumpAndSettle();
        expect(find.text('$label latest event'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder tabs stay connected and readable on narrow landscape and enlarged text', (tester) async {
      final categories = [
        ('tasks', 'Task', 'inspection_completed', 'Inspection completed'),
        ('sync', 'Sync', 'sync_manual', 'Sync completed'),
        ('reports', 'Reports', 'diagnostic_report_submitted', 'Diagnostic report submitted'),
        ('profile', 'Profile', 'profile_updated', 'Profile updated'),
      ];
      activityOverride = [
        for (final (_, label, event, title) in categories)
          for (var i = 0; i < 2; i++) {
            'id': '$event-$i', 'event_type': event,
            'title': i == 0 ? title : 'Older $label activity',
            'subtitle': 'Saved activity details.',
            'occurred_at': DateTime.now().subtract(Duration(days: i + 1)).toIso8601String(),
            'is_read': false,
          },
      ];
      addTearDown(() => activityOverride = null);
      final semantics = tester.ensureSemantics();
      try {
      for (final size in [const Size(320, 640), const Size(360, 800), const Size(390, 844),
        const Size(640, 320), const Size(844, 390), const Size(768, 1024)]) {
        for (final scaler in [TextScaler.noScaling, const TextScaler.linear(1.3), const TextScaler.linear(2), const _Android200TextScaler()]) {
          await mount(tester, size: size, scaler: scaler);
          final folder = find.byKey(const ValueKey('recent_activity_folder'));
          expect(folder, findsOneWidget, reason: 'The tabs and preview belong to one folder surface.');
          final tabs = find.byKey(const ValueKey('activity_category_shortcuts'));
          final fetchesBeforeSwitching = activityFetches;
          for (final (key, label, _, title) in categories) {
            final tab = find.byKey(ValueKey('activity_folder_tab_$key'));
            final word = find.descendant(of: tab, matching: find.text(label));
            await tester.ensureVisible(word);
            await tester.tap(word);
            await tester.pumpAndSettle();
            final tabRect = tester.getRect(tab);
            final body = tester.getRect(find.byKey(const ValueKey('activity_folder_body')));
            final first = tester.getRect(find.byKey(const ValueKey('folder_tab_position_tasks')));
            final second = tester.getRect(find.byKey(const ValueKey('folder_tab_position_sync')));
            expect(first.right - second.left, inInclusiveRange(6, 10),
                reason: 'Folder sheets should overlap gently, not hide the next tab.');
            expect(tabRect.bottom, closeTo(body.top, 0.01), reason: 'An active folder tab must touch its panel.');
            expect(tabRect.height, greaterThanOrEqualTo(48));
            expect(tabRect.width, greaterThanOrEqualTo(64));
            expect(tester.getSemantics(tab).flagsCollection.isSelected, ui.Tristate.isTrue);
            expect(tester.getSemantics(tab).flagsCollection.isButton, isTrue);
            expect(tester.getSemantics(tab).getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
            expect(tester.widget<Text>(word).style!.fontSize, 13,
                reason: 'Tabs scroll instead of reducing the text style to squeeze in.');
            final paragraph = tester.renderObject<RenderParagraph>(word);
            final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length));
            expect(boxes, hasLength(1));
            final glyphLeft = paragraph.localToGlobal(Offset(boxes.single.left, 0)).dx;
            final glyphRight = paragraph.localToGlobal(Offset(boxes.single.right, 0)).dx;
            final viewport = tester.getRect(tabs);
            expect(glyphLeft, greaterThanOrEqualTo(viewport.left - 0.5));
            expect(glyphRight, lessThanOrEqualTo(viewport.right + 0.5));
            expect(find.text(title), findsOneWidget);
            expect(find.text('Older $label activity'), findsNothing);
            expect(find.text('View 2 activities'), findsOneWidget);
            expect(find.descendant(of: folder, matching: find.text('1d ago')), findsOneWidget);
            expect(find.descendant(of: folder, matching: find.byType(RawScrollbar)), findsNothing);
            if (size.width == 360 && scaler == TextScaler.noScaling) {
              expect(tester.getSize(folder).height, lessThanOrEqualTo(204),
                  reason: 'Normal-size folders stay compact rather than adding oversized padding.');
            }
            await Scrollable.ensureVisible(tester.element(folder), alignment: 0.1);
            await tester.pumpAndSettle();
            if (scaler is! _Android200TextScaler) {
              await capture(tester, 'folder-$key-${size.width.toInt()}-${scaler.scale(13).round()}');
            }
            expect(tester.takeException(), isNull);
          }
          expect(activityFetches, fetchesBeforeSwitching,
              reason: 'Category switches must work with the already-loaded records and need no network.');
          final action = find.text('View 2 activities');
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(find.text('Profile · 2 events'), findsOneWidget);
          await capture(tester, 'folder-modal-${size.width.toInt()}-${scaler.scale(13).round()}');
          await tester.tap(find.byTooltip('Close recent activity'));
          await tester.pumpAndSettle();
          expect(find.text('Profile updated'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('folder tabs and history action work with keyboard focus at enlarged text', (tester) async {
      await mount(tester, size: const Size(320, 640), scaler: const TextScaler.linear(2), reducedMotion: true);
      final tabs = find.byKey(const ValueKey('activity_category_shortcuts'));
      final task = find.descendant(of: tabs, matching: find.text('Task'));
      await tester.ensureVisible(task);
      Focus.of(tester.element(task)).requestFocus();
      await tester.pumpAndSettle();
      for (final label in ['Sync', 'Reports', 'Profile']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final word = find.descendant(of: tabs, matching: find.text(label));
        expect(Focus.of(tester.element(word)).hasPrimaryFocus, isTrue,
            reason: 'Focus should follow the visual tab order, even as the active sheet moves.');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('No ${label.toLowerCase()} activity yet.'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(word.hitTestable(), findsOneWidget, reason: 'Keyboard traversal reveals offscreen tabs.');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Profile · 0 events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder keeps category selection through loading and exposes the real preview afterwards', (tester) async {
      activityGate = Completer<void>();
      activityOverride = [{
        'id': 'real-sync-record', 'event_type': 'sync_manual',
        'title': 'Queued changes synchronized', 'subtitle': 'Saved on this device.',
        'occurred_at': DateTime.now().toIso8601String(), 'is_read': false,
      }];
      addTearDown(() {
        if (!activityGate!.isCompleted) activityGate!.complete();
        activityGate = null;
        activityOverride = null;
      });
      await mount(tester, settle: false);
      final folder = find.byKey(const ValueKey('recent_activity_folder'));
      expect(folder, findsOneWidget);
      final sync = find.descendant(of: folder, matching: find.text('Sync'));
      await tester.ensureVisible(sync);
      await tester.tap(sync);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('activity_folder_loading')), findsOneWidget);
      expect(find.text('Queued changes synchronized'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      await capture(tester, 'folder-loading');
      activityGate!.complete();
      for (var frame = 0; frame < 20; frame++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Queued changes synchronized').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.text('Queued changes synchronized'), findsOneWidget);
      expect(find.text('View 1 activity'), findsOneWidget);
      await tester.ensureVisible(find.text('View 1 activity'));
      await tester.tap(find.text('View 1 activity'));
      await tester.pumpAndSettle();
      expect(find.text('Sync · 1 event'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('modal filters use the phone width so Profile is fully reachable', (tester) async {
      for (final width in [320.0, 360.0, 390.0]) {
      await mount(tester, size: Size(width, 800));
      await tester.ensureVisible(find.text('Inspection completed'));
      await tester.tap(find.text('Inspection completed'));
      await tester.pumpAndSettle();
      final filters = find.byKey(const ValueKey('modal_activity_filters'));
      final viewport = tester.getRect(filters);
      for (final label in ['All', 'Task', 'Sync', 'Reports', 'Profile']) {
        final chip = find.ancestor(
          of: find.descendant(of: filters, matching: find.text(label)),
          matching: find.byType(InkWell));
        final bounds = tester.getRect(chip);
        expect(bounds.left, greaterThanOrEqualTo(viewport.left));
        expect(bounds.right, lessThanOrEqualTo(viewport.right), reason: '$label must be fully visible without swiping.');
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.width, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.descendant(of: filters, matching: find.text('Profile')));
      await tester.pumpAndSettle();
      expect(find.text('Profile · 0 events'), findsOneWidget);
      tester.view.physicalSize = Size(width + 40, 800);
      await tester.pumpAndSettle();
      expect(find.text('Profile · 0 events'), findsOneWidget,
          reason: 'Resizing the sheet must preserve its chosen filter.');
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Divider)), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('status tiles keep counts prominent with aligned vector icons and readable contrast', (tester) async {
      await mount(tester, size: const Size(360, 800));
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await showTiles(tester);
      for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
        final tile = find.byKey(ValueKey('completion_$label'));
        final labelFinder = find.descendant(of: tile, matching: find.text(label));
        final countFinder = find
            .descendant(of: tile, matching: find.byType(Text))
            .evaluate()
            .map((e) => e.widget as Text)
            .firstWhere((t) => t.data != label);
        final tileRect = tester.getRect(tile);
        final countFinderFinal = find.byWidget(countFinder);
        final icon = find.byKey(ValueKey('completion_icon_$label'));
        expect(icon, findsOneWidget, reason: '$label needs its own recognizable vector icon.');
        final iconRect = tester.getRect(icon);
        final word = tester.getRect(labelFinder);
        final count = tester.getRect(countFinderFinal);
        expect(iconRect.width, inInclusiveRange(16, 24));
        expect(iconRect.height, iconRect.width);
        expect(word.top - iconRect.bottom, inInclusiveRange(2, 6));
        expect(count.top - word.bottom, inInclusiveRange(0, 4));
        expect(word.left - tileRect.left, inInclusiveRange(8, 12));
        expect(count.left, closeTo(word.left, 0.5));
        expect(iconRect.left, closeTo(word.left, 0.5));
        expect(labelFinder.hitTestable(), findsOneWidget);
        expect(count.height, greaterThanOrEqualTo(28));
        expect(count.height, greaterThan(word.height * 1.6),
            reason: 'The actual count, not the icon, leads each tile.');
        final background = (tester.widget<Container>(tile).decoration! as BoxDecoration).color!;
        for (final foreground in [tester.widget<Text>(labelFinder).style!.color!, countFinder.style!.color!]) {
          // Check the flat fill and the subtle, composited corner accent.
          for (final surface in [background, Color.alphaBlend(foreground.withValues(alpha: 0.06), background)]) {
            final luminances = [foreground.computeLuminance(), surface.computeLuminance()]..sort();
            expect((luminances.last + 0.05) / (luminances.first + 0.05), greaterThanOrEqualTo(4.5),
                reason: '$label must remain readable on the fill and its accent.');
          }
        }
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['IMAPS_HOME_FLOW_VISUAL_DIR'] != null) {
        await capture(tester, 'completion-placement');
      }
    });

    testWidgets('back-face content stays inside fixed tiles on narrow landscape and 200 percent text', (tester) async {
      for (final size in [const Size(320, 640), const Size(360, 800), const Size(390, 844),
        const Size(640, 320), const Size(844, 390), const Size(1280, 800)]) {
        for (final scaler in [TextScaler.noScaling, const TextScaler.linear(1.3), const TextScaler.linear(2), const _Android200TextScaler()]) {
          await mount(tester, size: size, scaler: scaler);
          final chart = find.byKey(const ValueKey('completion_chart'));
          await Scrollable.ensureVisible(tester.element(chart), alignment: 0.2);
          await tester.pumpAndSettle();
          final front = tester.getRect(chart);
          await showTiles(tester);
          expect(tester.getRect(chart), front, reason: 'Adaptive content must never resize the flip card.');
          expect(front.height, 220);
          if (scaler is! _Android200TextScaler) {
            await capture(tester, 'responsive-${size.width.toInt()}-${scaler.scale(14).round()}');
          }
          final badge = tester.getRect(find.byKey(const ValueKey('completion_overdue')));
          for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
            final tile = find.byKey(ValueKey('completion_$label'));
            final inset = tester.getRect(tile).deflate(7.5);
            final content = find.descendant(of: tile, matching: find.byType(Text));
            final icon = tester.getRect(find.byKey(ValueKey('completion_icon_$label')));
            expect(inset.contains(icon.topLeft) && inset.contains(icon.bottomRight), isTrue);
            final textRects = <Rect>[];
            for (final element in content.evaluate()) {
              final text = element.widget as Text;
              final finder = find.byWidget(text);
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.data!.length));
              expect(boxes, hasLength(1), reason: '$label and its count must stay complete.');
              final glyphs = Rect.fromPoints(
                paragraph.localToGlobal(Offset(boxes.single.left, boxes.single.top)),
                paragraph.localToGlobal(Offset(boxes.single.right, boxes.single.bottom)));
              expect(glyphs.left >= inset.left && glyphs.top >= inset.top &&
                  glyphs.right <= inset.right && glyphs.bottom <= inset.bottom, isTrue,
                  reason: '$label ${text.data} glyphs $glyphs must remain inside $inset at $size with $scaler.');
              final rect = tester.getRect(finder);
              expect(rect.overlaps(badge), isFalse);
              expect(rect.overlaps(icon), isFalse);
              textRects.add(rect);
            }
            expect(textRects.first.overlaps(textRects.last), isFalse,
                reason: '$label text rectangles $textRects overlap at $size with $scaler.');
            final wordRect = tester.getRect(find.descendant(of: tile, matching: find.text(label)));
            final numberRect = textRects.firstWhere((rect) => rect != wordRect);
            expect(numberRect.height, greaterThan(wordRect.height * 1.35),
                reason: '$label count must remain the primary information at $size with $scaler.');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });

    testWidgets('completion block matches the height of an assignment card', (tester) async {
      await mount(tester, size: const Size(360, 800));
      await tester.ensureVisible(find.byKey(const ValueKey('assignments_section')));
      await tester.pumpAndSettle();
      final assignment = tester.getSize(find.byType(ActiveAssignmentsFolderCard).first).height;
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      final completion = tester.getSize(chart).height;
      expect(completion, closeTo(assignment, 8),
          reason: 'The two Home sections must read as one scale, not a hero card next to a list row.');
      // Flipping must not change the reserved height.
      await tester.tap(chart);
      await tester.pumpAndSettle();
      expect(tester.getSize(chart).height, closeTo(completion, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('overdue notch never clips a status word, only the middle gap', (tester) async {
      await mount(tester, size: const Size(360, 800));
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await showTiles(tester);
      final badge = tester.getRect(find.byKey(const ValueKey('completion_overdue')));
      final block = tester.getRect(chart);
      // The badge sits in the horizontal middle of the block by design.
      expect(badge.center.dx, closeTo(block.center.dx, 2),
          reason: 'Overdue belongs in the dedicated centre gap, not beside a corner.');
      expect(find.text('1 Overdue'), findsOneWidget);
      for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
        final word = tester.getRect(find.descendant(
          of: find.byKey(ValueKey('completion_$label')),
          matching: find.text(label),
        ));
        final hitsBadge = word.bottom > badge.top &&
            word.top < badge.bottom &&
            word.right > badge.left &&
            word.left < badge.right;
        expect(hitsBadge, isFalse,
            reason: "$label must stay legible; only the gap between tiles is carved out.");
        // And it must stay inside its own tile.
        final tile = tester.getRect(find.byKey(ValueKey('completion_$label')));
        expect(word.left, greaterThanOrEqualTo(tile.left - 0.5));
        expect(word.right, lessThanOrEqualTo(tile.right + 0.5));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the centre gap is reserved even when no task is overdue', (tester) async {
      // Zero overdue is the normal case, and the block must not shrink or
      // reflow around a badge that isn't there.
      completionTotal = 4;
      addTearDown(() => completionTotal = null);
      await mount(tester, size: const Size(360, 800));
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await showTiles(tester);
      expect(find.byKey(const ValueKey('completion_overdue')), findsNothing,
          reason: 'No overdue task means no badge; the dedicated gap is still empty.');
      final baseline = tester.getSize(chart);
      // The framework keeps its carved centre even with nothing to put there:
      // the four tiles must still read as four, joined by a cross-shaped gap.
      final scheduled = tester.getRect(find.byKey(const ValueKey('completion_Scheduled')));
      final pending = tester.getRect(find.byKey(const ValueKey('completion_Pending')));
      final ongoing = tester.getRect(find.byKey(const ValueKey('completion_Ongoing')));
      expect(pending.left - scheduled.right, greaterThan(4.0),
          reason: 'The vertical centre gap is reserved regardless of overdue state.');
      expect(ongoing.top - scheduled.bottom, greaterThan(4.0),
          reason: 'The horizontal centre gap is reserved regardless of overdue state.');
      await capture(tester, 'completion-no-overdue');
      for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
        expect(find.byKey(ValueKey('completion_$label')), findsOneWidget,
            reason: '$label must still render without the badge.');
      }
      // And the block keeps the same footprint it has when a badge is present.
      await tester.pumpWidget(const SizedBox.shrink());
      completionTotal = null;
      await mount(tester, size: const Size(360, 800));
      await tester.ensureVisible(find.byKey(const ValueKey('completion_chart')));
      await tester.pumpAndSettle();
      await showTiles(tester);
      expect(find.text('1 Overdue'), findsOneWidget,
          reason: 'This fixture has one overdue task, proving the badge is data-driven.');
      expect(tester.getSize(find.byKey(const ValueKey('completion_chart'))), baseline,
          reason: 'A badge must not change the block height.');
      await capture(tester, 'completion-with-overdue');
    });

    testWidgets('no count collides with the Overdue badge that shares its corner', (tester) async {
      await mount(tester, size: const Size(360, 800));
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await showTiles(tester);
      final badge = tester.getRect(find.byKey(const ValueKey('completion_overdue')));
      for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
        final countFinder = find
            .descendant(of: find.byKey(ValueKey('completion_$label')), matching: find.byType(Text))
            .evaluate()
            .map((e) => e.widget as Text)
            .firstWhere((t) => t.data != label);
        final count = tester.getRect(find.byWidget(countFinder));
        final overlapsX = count.right > badge.left && count.left < badge.right;
        final overlapsY = count.bottom > badge.top && count.top < badge.bottom;
        expect(overlapsX && overlapsY, isFalse,
            reason: "$label's count must stay clear of the centre badge.");
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiles keep an inset from the white container on every side', (tester) async {
      await mount(tester, size: const Size(360, 800));
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await showTiles(tester);
      // The white card that visually owns the four tiles.
      final surface = find.ancestor(
        of: chart,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == InsightTheme.surface &&
              (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(20),
        ),
      ).first;
      final card = tester.getRect(surface);
      for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
        final tile = tester.getRect(find.byKey(ValueKey('completion_$label')));
        expect(tile.left - card.left, greaterThanOrEqualTo(7.0),
            reason: '$label needs an inset so the white card stays visible.');
        expect(card.right - tile.right, greaterThanOrEqualTo(7.0));
        expect(tile.top - card.top, greaterThanOrEqualTo(7.0));
        expect(card.bottom - tile.bottom, greaterThanOrEqualTo(7.0));
      }
      // Still large — the tiles fill the card rather than floating in a void.
      final scheduled = tester.getRect(find.byKey(const ValueKey('completion_Scheduled')));
      expect(scheduled.width, greaterThanOrEqualTo(card.width * 0.4));
      expect(tester.getSize(chart).height, lessThanOrEqualTo(card.height));
      expect(tester.takeException(), isNull);
      if (Platform.environment['IMAPS_HOME_FLOW_VISUAL_DIR'] != null) {
        await capture(tester, 'completion-inset');
      }
    });

    testWidgets('empty categories still open the history filters at enlarged text', (tester) async {
      activityOverride = [];
      addTearDown(() => activityOverride = null);
      await mount(tester, size: const Size(320, 640), scaler: const TextScaler.linear(2));
      final chips = find.byKey(const ValueKey('activity_category_shortcuts'));
      final sync = find.descendant(of: chips, matching: find.text('Sync'));
      await tester.ensureVisible(sync);
      await tester.tap(sync);
      await tester.pumpAndSettle();
      final empty = find.text('No sync activity yet.');
      await tester.ensureVisible(empty);
      await tester.pumpAndSettle();
      await capture(tester, 'folder-empty-200');
      await tester.tap(empty);
      await tester.pumpAndSettle();
      expect(find.text('Sync · 0 events'), findsOneWidget);
      final filters = find.byKey(const ValueKey('modal_activity_filters'));
      for (final label in ['All', 'Task', 'Sync', 'Reports', 'Profile']) {
        final chip = find.descendant(of: filters, matching: find.text(label));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.text('$label · 0 events'), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(chip);
        expect(paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length)), hasLength(1));
      }
      await capture(tester, 'folder-modal-empty-200');
      expect(tester.takeException(), isNull);
    });

    testWidgets('completion gutters stay compact with zero one and many overdue and multi-digit counts', (tester) async {
      completionTotal = 321;
      addTearDown(() {
        completionTotal = null;
        completionOverdue = 0;
      });
      for (final width in [320.0, 360.0, 390.0]) {
        for (final scaler in [TextScaler.noScaling, const TextScaler.linear(1.3), const TextScaler.linear(2), const _Android200TextScaler()]) {
          Rect? initialTile;
          for (final overdue in [0, 1, 12]) {
            completionOverdue = overdue;
            await mount(tester, size: Size(width, 844), scaler: scaler, reducedMotion: true);
            final chart = find.byKey(const ValueKey('completion_chart'));
            await Scrollable.ensureVisible(tester.element(chart), alignment: 0.2);
            await tester.pumpAndSettle();
            await showTiles(tester);
            final block = tester.getRect(chart);
            final scheduled = tester.getRect(find.byKey(const ValueKey('completion_Scheduled')));
            final pending = tester.getRect(find.byKey(const ValueKey('completion_Pending')));
            final ongoing = tester.getRect(find.byKey(const ValueKey('completion_Ongoing')));
            final relativeTile = scheduled.shift(-block.topLeft);
            initialTile ??= relativeTile;
            expect(relativeTile, initialTile, reason: 'Badge text must not control tile size.');
            expect(pending.left - scheduled.right, closeTo(16, 0.01));
            expect(ongoing.top - scheduled.bottom, closeTo(16, 0.01));
            expect(block.height, 220);
            final badgeFinder = find.byKey(const ValueKey('completion_overdue'));
            if (overdue == 0) {
              expect(badgeFinder, findsNothing);
            } else {
              expect(find.text('$overdue Overdue'), findsOneWidget);
              final badge = tester.getRect(badgeFinder);
              expect(block.contains(badge.topLeft) && block.contains(badge.bottomRight), isTrue);
              for (final label in ['Scheduled', 'Pending', 'Ongoing', 'Completed']) {
                final tile = find.byKey(ValueKey('completion_$label'));
                for (final text in find.descendant(of: tile, matching: find.byType(Text)).evaluate()) {
                  expect(tester.getRect(find.byWidget(text.widget)).overlaps(badge), isFalse);
                }
                expect(tester.getRect(find.byKey(ValueKey('completion_icon_$label'))).overlaps(badge), isFalse);
              }
            }
            for (final (label, count) in [('Scheduled', 81), ('Pending', 80), ('Ongoing', 80), ('Completed', 80)]) {
              final tile = find.byKey(ValueKey('completion_$label'));
              for (final text in [label, '$count']) {
                final finder = find.descendant(of: tile, matching: find.text(text));
                expect(finder, findsOneWidget);
                final paragraph = tester.renderObject<RenderParagraph>(finder);
                final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
                expect(boxes, hasLength(1));
                final glyphs = Rect.fromPoints(
                  paragraph.localToGlobal(Offset(boxes.single.left, boxes.single.top)),
                  paragraph.localToGlobal(Offset(boxes.single.right, boxes.single.bottom)));
                final inset = tester.getRect(tile).deflate(7.5);
                expect(inset.contains(glyphs.topLeft) && inset.contains(glyphs.bottomRight), isTrue,
                    reason: '$label $text must remain inside its tile at $width / $scaler.');
              }
              final word = tester.getRect(find.descendant(of: tile, matching: find.text(label)));
              final number = tester.getRect(find.descendant(of: tile, matching: find.text('$count')));
              expect(number.height, greaterThan(word.height * 1.35));
            }
            await capture(tester, 'compact-${width.toInt()}-${scaler.runtimeType}-${scaler.scale(14).round()}-overdue-$overdue');
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    });

    testWidgets('the chart opens the block and flips to one equally sized tile grid', (tester) async {
      for (final size in [const Size(320, 640), const Size(360, 800), const Size(390, 844), const Size(844, 390)]) {
        await mount(tester, size: size);
        final chart = find.byKey(const ValueKey('completion_chart'));
        await tester.ensureVisible(chart);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(chart);
        // The Home opens on the chart; the tiles are the face you flip to.
        final arcs = find.descendant(of: chart, matching: find.byType(CircularProgressIndicator));
        expect(arcs, findsNWidgets(4), reason: 'One combined chart has exactly four concentric arcs.');
        expect(find.byKey(const ValueKey('completion_Scheduled')), findsNothing);
        expect(tester.getSize(arcs.first).width,
            greaterThanOrEqualTo(tester.getSize(chart).height * 0.85),
            reason: 'The chart uses the block height it was given, not a shrunken fixed size.');
        for (final (index, fraction) in [4 / 6, 1 / 6, 0.0, 1 / 6].indexed) {
          expect(tester.widget<CircularProgressIndicator>(arcs.at(index)).value, closeTo(fraction, 0.001));
        }
        await capture(tester, size.width == 360 ? 'completion-chart-face' : 'completion-chart-${size.width.toInt()}');
        // A point near the outer edge must flip the whole group too.
        await tester.tapAt(Offset(bounds.left + 12, bounds.center.dy));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(tester.getSize(chart), bounds.size);
        if (size.width == 360) await capture(tester, 'completion-mid-flip');
        await tester.pumpAndSettle();
        final scheduled = tester.getRect(find.byKey(const ValueKey('completion_Scheduled')));
        final pending = tester.getRect(find.byKey(const ValueKey('completion_Pending')));
        final ongoing = tester.getRect(find.byKey(const ValueKey('completion_Ongoing')));
        final completed = tester.getRect(find.byKey(const ValueKey('completion_Completed')));
        expect(scheduled.left, closeTo(bounds.left, 1));
        expect(pending.right, closeTo(bounds.right, 1));
        expect(scheduled.top, closeTo(pending.top, 0.01));
        expect(ongoing.left, closeTo(scheduled.left, 0.01));
        expect(completed.right, closeTo(pending.right, 0.01));
        expect(ongoing.top, greaterThan(scheduled.bottom));
        expect(find.text('1 Overdue'), findsOneWidget);
        expect(tester.getSize(chart), bounds.size,
            reason: 'Neither face may shift the layout when it is revealed.');
        await capture(tester, size.width == 360 ? 'completion-tiles-face' : 'completion-tiles-${size.width.toInt()}');
        await tester.tap(chart);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('completion_ring_chart')), findsOneWidget);
        expect(tester.getSize(chart), bounds.size);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('manual flip gives a full eighteen seconds before automatic alternation', (tester) async {
      await mount(tester);
      final chart = find.byKey(const ValueKey('completion_chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('completion_ring_chart')), findsOneWidget,
          reason: 'The opening chart must not flip at the former ten-second interval.');
      final tappedAt = tester.binding.clock.now();
      await showTiles(tester);
      expect(find.byKey(const ValueKey('completion_Scheduled')), findsOneWidget);
      await tester.pump(tappedAt.add(const Duration(milliseconds: 17999))
          .difference(tester.binding.clock.now()));
      expect(find.byKey(const ValueKey('completion_Scheduled')), findsOneWidget,
          reason: 'A manual flip restarts the full interval.');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completion_ring_chart')), findsOneWidget);
      await tester.pump(tappedAt.add(const Duration(seconds: 36))
          .difference(tester.binding.clock.now()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completion_Scheduled')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion keeps both faces readable at enlarged text without auto-flipping', (tester) async {
      completionTotal = 321;
      addTearDown(() => completionTotal = null);
      await mount(tester, size: const Size(320, 640),
          scaler: const TextScaler.linear(2), reducedMotion: true);
      final chart = find.byKey(const ValueKey('completion_chart'));
      await Scrollable.ensureVisible(tester.element(chart), alignment: 0.2);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      // Reduced motion means no auto-flip: thirty seconds on, still the chart.
      expect(find.byKey(const ValueKey('completion_ring_chart')), findsOneWidget);
      final frontSize = tester.getSize(chart);
      await showTiles(tester);
      await capture(tester, 'completion-large-text');
      for (final (label, count) in [('Scheduled', 81), ('Pending', 80), ('Ongoing', 80), ('Completed', 80)]) {
        final tile = find.byKey(ValueKey('completion_$label'));
        expect(find.descendant(of: tile, matching: find.text('$count')), findsOneWidget);
        expect(tester.getRect(tile).left, greaterThanOrEqualTo(tester.getRect(chart).left - 0.01));
        expect(tester.getRect(tile).right, lessThanOrEqualTo(tester.getRect(chart).right + 0.01));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: tile, matching: find.text(label)));
        final glyphs = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length));
        expect(glyphs, hasLength(1));
        // Allow half a logical pixel for glyph overhang beyond the line box.
        expect(paragraph.localToGlobal(Offset(glyphs.single.right, 0)).dx,
            lessThanOrEqualTo(tester.getRect(tile).right - 7.5),
            reason: '$label must remain a whole word inside its tile at 200% text.');
      }
      expect(tester.getSize(chart), frontSize);
      await showChart(tester);
      final arcs = tester.widgetList<CircularProgressIndicator>(
          find.descendant(of: chart, matching: find.byType(CircularProgressIndicator))).toList();
      expect(arcs, hasLength(4));
      for (final (index, count) in [81, 80, 80, 80].indexed) {
        expect(arcs[index].value, closeTo(count / 321, 0.001));
      }
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('completion_ring_chart')), findsOneWidget);
      expect(find.descendant(of: chart, matching: find.text('321')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
    // The tiles are the face you flip to; the chart opens the block.
    await tester.ensureVisible(find.byKey(const ValueKey('completion_chart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completion_chart')));
    await tester.pumpAndSettle();
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

  testWidgets('Completion counts and reverse chart retain all fractions under nonlinear scaling', (tester) async {
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
          // The block opens on the chart; the tiles are the flip side.
          final arcs = tester.widgetList<CircularProgressIndicator>(find.descendant(of: chart,
            matching: find.byType(CircularProgressIndicator))).toList();
          expect(arcs, hasLength(4));
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
          await tester.tap(chart);
          await tester.pumpAndSettle();
          for (final (i, label) in ['Scheduled', 'Pending', 'Ongoing', 'Completed'].indexed) {
            final row = find.byKey(ValueKey('completion_$label'));
            expect(find.descendant(of: row, matching: find.text('${counts[i]}')), findsOneWidget);
            expect(find.descendant(of: row, matching: find.text(label)), findsOneWidget);
            expect(tester.getRect(row).right, lessThanOrEqualTo(tester.getRect(chart).right));
          }
          expect(find.byKey(const ValueKey('completion_overdue')), findsNothing);
          await tester.tap(chart);
          await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.byKey(const ValueKey('calendar_lanyard_clip')));
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
    await tester.ensureVisible(find.byTooltip('Hide full calendar'));
    await tester.pumpAndSettle();
    final restStrap = pivot(tester);
    final restCard = cardFoot(tester);
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
    const Size(320, 568),
    const Size(320, 640),
    const Size(360, 640),
    const Size(360, 800),
    const Size(390, 640),
    const Size(390, 844),
    const Size(412, 640),
    const Size(412, 915),
    const Size(844, 390),
    const Size(430, 640),
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
          final insets = size.width == 412
              ? const FakeViewPadding(top: 32, bottom: 48)
              : const FakeViewPadding(top: 24, bottom: 24);
          tester.view.padding = insets;
          tester.view.viewPadding = insets;
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
          if (scale == 1 &&
              size.width < size.height &&
              size.width <= 430 &&
              size.height >= 800) {
            final page = tester.state<ScrollableState>(find.byWidgetPredicate(
                (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).first).position;
            expect(page.pixels, 0, reason: 'First-assignment clearance is measured before any page scrolling.');
            final card = tester.getRect(find.byType(ActiveAssignmentsFolderCard).first);
            expect(card.width, greaterThanOrEqualTo(size.width * 0.8),
                reason: 'The assignment carousel keeps its original full-bleed card width.');
            final trigger = tester.getRect(find.byWidgetPredicate(
                (widget) => widget is Semantics && widget.properties.label == 'Quick actions'));
            expect(card.bottom, lessThanOrEqualTo(trigger.top - 8),
                reason: 'The first assignment must be fully visible before scrolling, above the floating nav controls.');
            if (size == const Size(360, 800)) {
              debugPrint('QA-01 360x800 / 1x: first assignment bottom=${card.bottom}; maximum=${trigger.top - 8}; scroll=${page.pixels}');
            }
          }
          await tester.ensureVisible(find.byTooltip('Show Time and Date'));
          await tester.pumpAndSettle();
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
            lessThan(tester.getRect(assignmentSection).top),
          );
          expect(
            tester.getRect(assignmentSection).bottom,
            lessThan(tester.getRect(calendarSection).top),
          );
          expect(tester.getRect(calendarSection).bottom,
              lessThan(tester.getRect(find.text('Task completion flow')).top));
          expect(tester.getRect(find.byKey(const ValueKey('completion_chart'))).bottom,
              lessThan(tester.getRect(find.text('Recent activity')).top));
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
            find.descendant(of: notes, matching: find.text('Started scheduled applicant')),
            findsNothing,
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
            find.descendant(of: calendar, matching: find.text('Started scheduled applicant')),
            findsNothing,
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
            find.descendant(of: calendar, matching: find.text('Started scheduled applicant')),
            findsOneWidget,
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
          final chart = find.byKey(const ValueKey('completion_chart'));
          await tester.ensureVisible(chart);
          await tester.pumpAndSettle();
          // The block opens on the ring chart; each status owns one arc.
          final statusColors = {
            'Scheduled': const Color(0xFFD97706),
            'Pending': const Color(0xFF60A5FA),
            'Ongoing': const Color(0xFF2563EB),
            'Completed': const Color(0xFF16A34A),
          };
          final arcs = tester
              .widgetList<CircularProgressIndicator>(
                find.descendant(
                  of: chart,
                  matching: find.byType(CircularProgressIndicator),
                ),
              )
              .toList();
          expect(arcs, hasLength(4));
          for (final (index, entry) in statusColors.entries.indexed) {
            expect(arcs[index].valueColor!.value, entry.value);
          }
          // A tap flips the block to the approved tile grid and its notch badge.
          await tester.tap(chart);
          await tester.pumpAndSettle();
          expect(find.text('1 Overdue'), findsOneWidget,
              reason: 'The fixture carries exactly one overdue task.');
          final completionBounds = tester.getRect(find
              .ancestor(
                of: chart,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container &&
                      widget.decoration is BoxDecoration &&
                      (widget.decoration! as BoxDecoration).borderRadius ==
                          BorderRadius.circular(20),
                ),
              )
              .first);
          expect(completionBounds.left, closeTo(pageBounds.left, 0.01));
          expect(completionBounds.right, closeTo(pageBounds.right, 0.01));
          final block = tester.getRect(chart);
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
          // The approved reference is one equally sized 2x2 tile grid.
          expect(scheduled.top, closeTo(pending.top, 0.01));
          expect(ongoing.top, closeTo(completed.top, 0.01));
          expect(ongoing.left, closeTo(scheduled.left, 0.01));
          expect(completed.left, closeTo(pending.left, 0.01));
          expect(ongoing.top, greaterThan(scheduled.bottom));
          final badge = tester.getRect(
            find.byKey(const ValueKey('completion_overdue')),
          );
          expect(badge.center.dx, closeTo(block.center.dx, 2),
              reason: 'The badge lives in the reserved centre gap.');
          for (final entry in statusColors.entries) {
            final cell = find.byKey(ValueKey('completion_${entry.key}'));
            final background =
                (tester.widget<Container>(cell).decoration! as BoxDecoration)
                    .color!;
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
              reason: 'The full status word fits inside its own tile.',
            );
            final foreground = tester.widget<Text>(labelFinder).style!.color!;
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
          // The approved folder: one connected surface with four category tabs;
          // history stays in the modal behind the preview.
          final folder = find.byKey(const ValueKey('recent_activity_folder'));
          expect(folder, findsOneWidget);
          final folderBounds = tester.getRect(folder);
          expect(folderBounds.left, closeTo(pageBounds.left, 0.01));
          expect(folderBounds.right, closeTo(pageBounds.right, 0.01));
          final folderTabs = find.byKey(
            const ValueKey('activity_category_shortcuts'),
          );
          expect(
            find.descendant(of: folderTabs, matching: find.text('All')),
            findsNothing,
            reason: 'All lives inside the history modal, not on Home.',
          );
          final folderBody = find.byKey(const ValueKey('activity_folder_body'));
          for (final (key, label) in [
            ('tasks', 'Task'),
            ('sync', 'Sync'),
            ('reports', 'Reports'),
            ('profile', 'Profile'),
          ]) {
            final tab = find.byKey(ValueKey('activity_folder_tab_$key'));
            final word = find.descendant(of: tab, matching: find.text(label));
            await tester.ensureVisible(word);
            await tester.pumpAndSettle();
            await tester.tap(word);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(tab).bottom,
              closeTo(tester.getRect(folderBody).top, 0.01),
              reason: 'The selected tab must stay welded to its panel.',
            );
            expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(tab).width, greaterThanOrEqualTo(64));
            expect(
              tester.getSemantics(tab).flagsCollection.isSelected,
              ui.Tristate.isTrue,
            );
            expect(tester.widget<Text>(word).style!.fontSize, 13,
                reason: 'Tabs keep their size instead of shrinking to fit.');
            final paragraph = tester.renderObject<RenderParagraph>(word);
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              ),
              hasLength(1),
              reason: 'Category names must not split inside their tab.',
            );
            if (label == 'Task') {
              expect(find.text('Inspection completed'), findsOneWidget);
            } else {
              expect(
                find.text('No ${label.toLowerCase()} activity yet.'),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          }
          // The preview alone opens history; the modal carries All and the four
          // categories.
          final taskTab = find.descendant(
            of: folderTabs,
            matching: find.text('Task'),
          );
          await tester.ensureVisible(taskTab);
          await tester.pumpAndSettle();
          await tester.tap(taskTab);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Inspection completed'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Inspection completed'));
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          final modalFilters = find.byKey(
            const ValueKey('modal_activity_filters'),
          );
          for (final label in ['All', 'Task', 'Sync', 'Reports', 'Profile']) {
            expect(
              find.descendant(of: modalFilters, matching: find.text(label)),
              findsOneWidget,
            );
          }
          final item = find.descendant(
            of: sheet,
            matching: find.text('Inspection completed'),
          );
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: sheet,
              matching: find.byIcon(Icons.schedule_rounded),
            ),
            findsOneWidget,
            reason: 'Expanded activity timestamps wrap inside narrow cards.',
          );
          await tester.tap(find.byTooltip('Close recent activity'));
          await tester.pumpAndSettle();
          expect(find.text('Inspection completed'), findsOneWidget);
          expect(tester.takeException(), isNull);
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
      await tester.ensureVisible(find.byTooltip('Show Time and Date'));
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
    scroll.position.jumpTo(scroll.position.minScrollExtent);
    await tester.pump();
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
    'Home recent activity keeps one preview while the modal reaches the full category history',
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
      expect(find.text('Activity 1'), findsOneWidget);
      expect(find.text('Activity 7'), findsNothing);
      expect(find.text('Activity 8'), findsNothing);
      await tester.ensureVisible(find.text('Activity 1'));
      await tester.tap(find.text('Activity 1'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(find.text('Task · 10 events'), findsOneWidget);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Activity 1')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.byIcon(Icons.schedule_rounded)), findsOneWidget);
      final list = find.descendant(
          of: find.byKey(const ValueKey('recent_activity_modal_list')),
          matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text('Activity 10'), 160, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text('Activity 10').hitTestable(), findsOneWidget);
      final filters = find.byKey(const ValueKey('modal_activity_filters'));
      for (final (label, count) in [('Sync', 5), ('All', 15), ('Task', 10)]) {
        final tab = find.descendant(of: filters, matching: find.text(label));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.text('$label · $count events'), findsOneWidget);
        final last = find.text(label == 'Task' ? 'Activity 10' : 'Activity 15');
        await tester.scrollUntilVisible(last, 160, scrollable: list);
        await tester.pumpAndSettle();
        expect(last.hitTestable(), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Close recent activity'));
      await tester.pumpAndSettle();
      expect(find.text('Activity 1'), findsOneWidget);
      expect(find.text('Activity 10'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Home recent activity shows an empty category or exactly its latest event', (
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
        find.text(count == 0 ? 'No task activity yet.' : 'Activity 1'),
        findsOneWidget,
      );
      expect(find.text('Activity 7'), findsNothing);
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
