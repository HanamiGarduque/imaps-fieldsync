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
import 'package:image/image.dart' as image;
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_round_widgets.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'issue_d_round_context_test.dart' show issueDOwner, issueDReason, issueDRound;

const _r1 = '11111111-1111-4111-8111-111111111111';
const _r2 = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _job(int round, String status, {bool scheduled = false,
    String name = 'Ana Li'}) => {
  ...issueDRound(round, status),
  'id': round == 1 ? _r1 : _r2,
  'assigned_inspector_id': issueDOwner,
  'scheduled_date': scheduled ? '2099-01-10' : '',
  'deadline_date': '2099-01-20',
  'is_self_scheduled': scheduled,
  'created_at': '2026-01-01T00:00:00Z',
  'current_step': status == 'completed' ? 6 : (status == 'in_progress' ? 3 : 0),
  'field_job_reviews': round == 1 && status == 'completed'
      ? issueDRound(1, 'completed')['field_job_reviews'] : [],
  'assignment_instructions': 'Verify the assigned application site.',
  'supabase_zoning_applications': {
    'reference_number': 'APP-ISSUE-D', 'applicant_name': name,
    'barangay': 'Alupay', 'contact_number': '09000000000',
    'email': 'applicant@example.test', 'application_type': 'Residential',
  },
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  var jobs = <Map<String, dynamic>>[];
  final launched = <String>[];
  final boundary = GlobalKey();
  var offline = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    final sdkFonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts');
    final font = ByteData.sublistView(sdkFonts.listSync().whereType<File>()
      .firstWhere((file) => file.path.endsWith('.ttf')).readAsBytesSync());
    final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(
      File('${sdkFonts.path}/materialicons-regular.otf').readAsBytesSync())));
    await icons.load();
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Poppins', 'Urbanist', 'JetBrainsMono', 'Roboto']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Light']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [{'asset': asset}];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null ? font : ByteData.sublistView(
        File('$folder/${asset.split('-').first}.ttf').readAsBytesSync());
    });
    for (final weight in [FontWeight.w400, FontWeight.w500, FontWeight.w600,
        FontWeight.w700, FontWeight.w800]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [offline ? 'none' : 'wifi']);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'), (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        }
        throw MissingPluginException(call.method);
      });
    await Supabase.initialize(
      url: 'https://task-card.test', publishableKey: 'isolated-fixture-key',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        if (request.method != 'GET' || request.url.host != 'task-card.test' ||
            request.url.path != '/rest/v1/field_jobs') {
          throw StateError('Unexpected HTTP boundary: ${request.method} ${request.url}');
        }
        return http.Response(jsonEncode(jobs), 200, request: request,
          headers: {'content-type': 'application/json'});
      }));
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'isolated-fixture-token', 'refresh_token': 'isolated-fixture-refresh',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': issueDOwner, 'app_metadata': {}, 'user_metadata': {},
        'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'},
    }));
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final statement in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)')
        .allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(statement.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = issueDOwner;
    InspectionProgress.instance.reset();
    launched.clear();
    offline = false;
    jobs = [_job(1, 'completed'), _job(2, 'assigned')];
    completedDetailFetcherOverride = (id) async => jobs.singleWhere((job) => job['id'] == id);
  });
  tearDown(() async {
    completedDetailFetcherOverride = null;
    DBHelper.inspectorIdForTesting = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> settle(WidgetTester tester) async {
    // Allow real isolated SQLite FFI work to finish outside the fake clock.
    for (var frame = 0; frame < 30; frame++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, {int tab = TasksScreen.tabPending,
      double width = 375, double scale = 1, Widget? screen}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => InspectionProvider(),
      child: MaterialApp(debugShowCheckedModeBanner: false, builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: boundary, child: child!)),
        home: screen ?? TasksScreen(initialTabIndex: tab, profile: UserProfile(
          id: issueDOwner, fullName: 'Fixture Inspector', role: 'inspector')))));
    await settle(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }

  Finder card(String id) => find.byKey(ValueKey(id));
  Finder within(Finder parent, String text) => find.descendant(of: parent, matching: find.text(text));
  Future<void> expand(WidgetTester tester, String id) async {
    final name = jobs.singleWhere((job) => job['id'] == id)['supabase_zoning_applications']['applicant_name'] as String;
    await tester.ensureVisible(within(card(id), name));
    await tester.pumpAndSettle();
    await tester.tap(within(card(id), name));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name, Map<String, Object> measurements,
      {Rect? crop, double pixelRatio = 1}) async {
    final directory = Platform.environment['IMAPS_TASK_CARD_CAPTURE_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await render.toImage(pixelRatio: pixelRatio);
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      screenshot.dispose();
      final png = bytes!.buffer.asUint8List();
      Directory(directory).createSync(recursive: true);
      File('$directory/$name.png').writeAsBytesSync(crop == null ? png : image.encodePng(
        image.copyCrop(image.decodePng(png)!, x: (crop.left * pixelRatio).round(),
          y: (crop.top * pixelRatio).round(), width: (crop.width * pixelRatio).round(),
          height: (crop.height * pixelRatio).round())));
      File('$directory/$name.json').writeAsStringSync(jsonEncode(measurements));
    });
  }

  testWidgets('Header counts only unfinished tasks due today', (tester) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    jobs = [
      {..._job(1, 'completed'), 'deadline_date': today},
      {..._job(2, 'assigned'), 'deadline_date': today},
    ];
    await mount(tester, width: 390);
    expect(find.text('2 assigned · 1 due today'), findsOneWidget);
    for (final label in ['Pending', 'Ongoing', 'Completed']) {
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(370),
        reason: 'All three task tabs fit the normal 390px header without scrolling.');
    }
    expect(tester.takeException(), isNull);
    await capture(tester, 'tasks-header', {'width': 390});
  });

  for (final width in [320.0, 360.0, 390.0]) {
    // Exercise normal and enlarged text; this is not a platform maximum.
    for (final scale in [1.0, 2.0]) {
      testWidgets('All task tabs and counts stay readable at $width / $scale', (tester) async {
        jobs = [
          for (var i = 0; i < 5; i++)
            {..._job(1, 'completed'), 'id': 'tab-completed-$i'},
          for (var i = 0; i < 3; i++)
            {..._job(2, 'assigned'), 'id': 'tab-pending-$i'},
        ];
        await mount(tester, width: width, scale: scale);
        for (final label in ['Pending', 'Ongoing', 'Completed']) {
          final tab = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
          // The bar scrolls sideways when the three tabs do not fit, so the tab
          // is brought into view before it is measured.
          await tester.ensureVisible(tab);
          await tester.pumpAndSettle();
          final pill = tester.getRect(tab);
          final labelRect = tester.getRect(find.text(label));
          // The badge's own chip, not its digits: the chip is the content's
          // right edge.
          final badge = tester.getRect(
              find.descendant(of: tab, matching: find.byType(AnimatedContainer)).last);
          expect(labelRect.left - pill.left, greaterThanOrEqualTo(5.9),
              reason: '$label has breathing room on the left');
          expect(pill.right - badge.right, greaterThanOrEqualTo(5.9),
              reason: '$label has breathing room on the right');
          expect(labelRect.left - pill.left, closeTo(pill.right - badge.right, 1.0),
              reason: 'the content is centred in the tab');
          expect(labelRect.center.dy, closeTo(badge.center.dy, 1.0),
              reason: 'the label and the count share one line');
          expect(pill.height, greaterThanOrEqualTo(48),
              reason: 'the tap target stays 48dp');
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'task-tabs-$width-$scale', {'width': width, 'scale': scale});
        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();
        expect(card('tab-completed-0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('every selected task tab has breathing room and a centred content',
      (tester) async {
    jobs = [
      for (var i = 0; i < 5; i++)
        {..._job(1, 'completed'), 'id': 'tab-completed-$i'},
      for (var i = 0; i < 3; i++)
        {..._job(2, 'assigned'), 'id': 'tab-pending-$i'},
    ];
    await mount(tester, width: 360);
    // The gray container keeps the dimensions it always had.
    final bar = tester.getRect(find.ancestor(
      of: find.text('Pending'),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == InsightTheme.surface2),
    ).first);
    expect(bar.height, 54, reason: 'the bar is not made taller or bulkier');

    for (final (label, count) in [('Pending', '3'), ('Ongoing', '0'), ('Completed', '5')]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final tab =
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final pill = tester.getRect(tab);
      final labelRect = tester.getRect(find.text(label));
      // The badge's own chip, not its digits: the chip is the content's
      // right edge.
      final badge = tester.getRect(
          find.descendant(of: tab, matching: find.byType(AnimatedContainer)).last);
      // The white indicator is the selected tab's own surface.
      final chip = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: find.text(label), matching: find.byType(AnimatedContainer))
            .first,
      );
      expect((chip.decoration! as BoxDecoration).color, InsightTheme.surface,
          reason: '$label is the selected tab');
      expect(labelRect.left - pill.left, greaterThanOrEqualTo(5.9),
          reason: '$label has breathing room on the left');
      expect(pill.right - badge.right, greaterThanOrEqualTo(5.9),
          reason: '$label has breathing room on the right');
      expect(labelRect.left - pill.left, closeTo(pill.right - badge.right, 1.0),
          reason: 'the content is centred in the white pill');
      expect(labelRect.center.dy, closeTo(badge.center.dy, 1.0),
          reason: 'the label and the count share one line');
      expect(pill.height, greaterThanOrEqualTo(48));
      await capture(tester, 'segment-${label.toLowerCase()}', {
        'width': 360,
        'label': label,
        'count': count,
      });
      expect(tester.takeException(), isNull);
    }
  });

  Finder segment(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  Finder indicator(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)).first,
      matching: find.byType(DecoratedBox)).first;
  Finder segmentTrack() => find.ancestor(of: find.text('Pending'),
      matching: find.byWidgetPredicate((w) => w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == InsightTheme.surface2)).first;

  void expectSelectedEdges(WidgetTester tester, String label) {
    final track = tester.getRect(segmentTrack());
    final pill = tester.getRect(indicator(label));
    final labelRect = tester.getRect(find.text(label));
    final badge = tester.getRect(find.descendant(
        of: segment(label), matching: find.byType(AnimatedContainer)).last);
    debugPrint('SELECTOR $label track=$track pill=$pill label=$labelRect badge=$badge');
    expect(pill.left, greaterThanOrEqualTo(track.left + 3.9),
        reason: '$label keeps its full left edge inside the track gutter');
    expect(pill.right, lessThanOrEqualTo(track.right - 3.9),
        reason: '$label keeps its full right edge inside the track gutter');
    expect(pill.top - track.top, closeTo(4, 0.1));
    expect(track.bottom - pill.bottom, closeTo(4, 0.1));
    expect(labelRect.left - pill.left, greaterThanOrEqualTo(11.9));
    expect(pill.right - badge.right, closeTo(labelRect.left - pill.left, 0.1));
    expect(badge.left - labelRect.right, closeTo(6, 0.1));
    expect(labelRect.center.dy, closeTo(badge.center.dy, 0.1));
    expect(tester.getSize(segment(label)).height, greaterThanOrEqualTo(48));
    expect(tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse);
    expect((tester.widget<DecoratedBox>(indicator(label)).decoration as BoxDecoration).color,
        InsightTheme.surface);
    expect(track.height, 54, reason: 'normal track dimensions are preserved');
  }

  Future<void> expectRoundedPaint(WidgetTester tester, String label) async {
    final pill = tester.getRect(indicator(label));
    final pixels = await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await render.toImage(pixelRatio: 3);
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = screenshot.width;
      screenshot.dispose();
      return (bytes!, width);
    });
    int redAt(Offset point) => pixels!.$1.getUint8(
        ((point.dy * 3).floor() * pixels.$2 + (point.dx * 3).floor()) * 4);
    for (final corner in [pill.topLeft + const Offset(1, 1),
        pill.topRight + const Offset(-1, 1), pill.bottomLeft + const Offset(1, -1),
        pill.bottomRight + const Offset(-1, -1)]) {
      expect(redAt(corner), lessThan(250),
          reason: '$label has visible gray around every rounded white corner');
    }
    for (final edge in [pill.centerLeft + const Offset(1, 0),
        pill.centerRight + const Offset(-1, 0)]) {
      expect(redAt(edge), greaterThan(250),
          reason: '$label paints both complete white side edges');
    }
  }

  for (final (width, scale, completedCount) in [
    (320.0, 1.0, 12), (360.0, 1.0, 5), (390.0, 2.0, 12),
  ]) {
    for (final (tab, label) in [(0, 'Pending'), (1, 'Ongoing'), (2, 'Completed')]) {
    testWidgets('initial selected indicator keeps both edges visible: $label at $width / $scale', (tester) async {
      jobs = [
        for (var i = 0; i < 3; i++) {..._job(2, 'assigned'), 'id': 'edge-pending-$i'},
        {..._job(2, 'in_progress'), 'id': 'edge-ongoing'},
        for (var i = 0; i < completedCount; i++) {..._job(1, 'completed'), 'id': 'edge-completed-$i'},
      ];
      await mount(tester, tab: tab, width: width, scale: scale);
      // Deliberately do not call tester.ensureVisible: production owns reveal.
      final track = tester.getRect(segmentTrack());
      final measurements = <String, Object>{'label': label, 'width': width, 'scale': scale,
        'track': track.toString(), 'indicator': tester.getRect(indicator(label)).toString()};
      final name = 'selected-${label.toLowerCase()}-${width.toInt()}-$scale';
      await capture(tester, '$name-screen', measurements);
      await capture(tester, name, measurements,
          crop: track.inflate(12), pixelRatio: 3);
      expectSelectedEdges(tester, label);
      await expectRoundedPaint(tester, label);
      expect(within(segment('Pending'), '3'), findsOneWidget);
      expect(within(segment('Ongoing'), '1'), findsOneWidget);
      expect(within(segment('Completed'), '$completedCount'), findsOneWidget);
      expect(card(tab == 0 ? 'edge-pending-0' : tab == 1 ? 'edge-ongoing' : 'edge-completed-0'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('selecting clipped Completed reveals both edges at $scale without moving page',
        (tester) async {
      jobs = [
        {..._job(2, 'assigned'), 'id': 'edge-pending'},
        for (var i = 0; i < 12; i++) {..._job(1, 'completed'), 'id': 'edge-completed-$i'},
      ];
      await mount(tester, width: 320, scale: scale);
      final page = tester.state<ScrollableState>(find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down).first).position;
      final pageOffset = page.pixels;
      final track = tester.getRect(segmentTrack());
      final horizontal = find.descendant(of: segmentTrack(),
          matching: find.byWidgetPredicate((w) => w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal));
      // A real swipe exposes part of Completed. Tapping that visible part must
      // reveal the whole selected pill, rather than leaving a flat clipped edge.
      await tester.drag(horizontal, Offset(scale == 1 ? -15 : -200, 0));
      await tester.pumpAndSettle();
      final visible = tester.getRect(segment('Completed')).intersect(track.deflate(8));
      expect(visible.width, greaterThan(0));
      await tester.tapAt(visible.center);
      await tester.pumpAndSettle();
      expectSelectedEdges(tester, 'Completed');
      expect(within(segment('Completed'), '12'), findsOneWidget);
      expect(card('edge-completed-0'), findsOneWidget);
      expect(page.pixels, pageOffset, reason: 'revealing a tab must not scroll the page');
      expect(tester.takeException(), isNull);
    });
  }

  for (final state in [
    ('Pending Scheduled', 'assigned', true, TasksScreen.tabPending, 'Reschedule Inspection Date', 'Reschedule this task'),
    ('Pending Available Anytime', 'assigned', false, TasksScreen.tabPending, 'Schedule Inspection Date', 'Schedule this task'),
    ('Scheduled In Progress', 'in_progress', true, TasksScreen.tabPending, 'Reschedule Inspection Date', 'Reschedule this task'),
    ('Ongoing', 'in_progress', false, TasksScreen.tabOngoing, 'Schedule Inspection Date', 'Schedule this task'),
  ]) {
    testWidgets('${state.$1} expanded card has no round sublist and retains its actions', (tester) async {
      jobs = [_job(1, 'completed'), _job(2, state.$2, scheduled: state.$3)];
      await mount(tester, tab: state.$4);
      for (final pair in [('Pending', state.$2 == 'assigned' || state.$3 ? '1' : '0'),
          ('Ongoing', state.$2 == 'in_progress' && !state.$3 ? '1' : '0'), ('Completed', '1')]) {
        final tab = find.ancestor(of: find.text(pair.$1), matching: find.byType(InkWell)).first;
        expect(within(tab, pair.$2), findsOneWidget);
      }
      if (state.$4 == TasksScreen.tabPending) {
        expect(find.text(state.$3 ? 'Scheduled' : 'Available Anytime'), findsOneWidget);
      }
      await expand(tester, _r2);
      final active = card(_r2);
      await capture(tester, 'expanded-${state.$4}-${state.$3}', {'state': state.$1});
      expect(find.descendant(of: active, matching: find.byType(InspectionRoundList)), findsNothing);
      expect(within(active, 'Inspection rounds'), findsNothing);
      expect(find.descendant(of: active, matching: find.byWidgetPredicate((widget) =>
        widget.key is ValueKey<String> && (widget.key as ValueKey<String>).value.startsWith('round-entry-'))), findsNothing);
      for (final label in ['Call', 'SMS', 'Email', 'Application Details', state.$5]) {
        await tester.ensureVisible(within(active, label));
        await tester.pumpAndSettle();
        expect(within(active, label).hitTestable(), findsOneWidget);
      }
      for (final label in ['Call', 'SMS', 'Email']) {
        await tester.tap(within(active, label));
        await settle(tester);
      }
      expect(launched, ['tel:09000000000', 'sms:09000000000',
        'mailto:applicant@example.test?subject=Inspection%20Notification%3A%20APP-ISSUE-D']);
      await tester.tap(within(active, state.$5));
      await tester.pumpAndSettle();
      expect(find.text(state.$6), findsOneWidget);
      await tester.tap(find.text(state.$3 ? '2099-01-10' : 'Select a date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 80));
      await tester.pumpAndSettle();
      await expand(tester, _r2);
      expect(within(active, 'Call').hitTestable(), findsNothing);
      // Merely opening scheduling must not issue a write.
      expect(await tester.runAsync(() => db.query('pending_actions')), isEmpty);
      await expand(tester, _r2);
      await tester.ensureVisible(within(active, 'Application Details'));
      await tester.tap(within(active, 'Application Details'));
      await settle(tester);
      final overview = tester.widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen));
      expect(overview.task.id, _r2);
      expect(overview.task.localInspectionId, 102);
      expect(overview.task.status, state.$2);
      expect(overview.task.isSelfScheduled, state.$3);
      expect(overview.relatedRounds.map((round) => round.id), unorderedEquals([_r1, _r2]));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same application keeps distinct top-level tasks and exact overview identities', (tester) async {
    jobs = [_job(1, 'assigned', name: 'First Applicant'), _job(2, 'assigned', name: 'Second Applicant')];
    await mount(tester);
    for (final id in [_r1, _r2]) {
      expect(card(id), findsOneWidget);
      await expand(tester, id);
      expect(within(card(id), 'Inspection rounds'), findsNothing);
      await tester.ensureVisible(within(card(id), 'Application Details'));
      await tester.tap(within(card(id), 'Application Details'));
      await settle(tester);
      final overview = tester.widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen));
      expect(overview.task.id, id);
      expect(overview.task.localInspectionId, id == _r1 ? 101 : 102);
      expect(overview.relatedRounds.map((round) => round.id), unorderedEquals([_r1, _r2]));
      expect(overview.relatedRounds.map((round) => round.localInspectionId), unorderedEquals([101, 102]));
      final context = find.byType(RoundContextCard);
      expect(find.descendant(of: context, matching: find.text(id == _r1 ? 'Round 1' : 'Round 2')), findsOneWidget);
      expect(find.text(id == _r1 ? 'Original Inspection' : 'Reinspection'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
    }
    expect((await tester.runAsync(DBHelper.getCachedJobs))!.map((row) => row['id']), unorderedEquals([_r1, _r2]));
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 375.0, 414.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final name in ['Ana Li', 'Alexandria Maria Rivera']) {
        testWidgets('name/reference spacing and accessible info: $name at $width / $scale', (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            jobs = [_job(2, 'in_progress', name: name)];
            await mount(tester, tab: TasksScreen.tabOngoing, width: width, scale: scale);
            final active = card(_r2);
            await tester.ensureVisible(within(active, name));
            await tester.pumpAndSettle();
            final title = within(active, name);
            final reference = within(active, 'APP-ISSUE-D');
            final info = find.descendant(of: active, matching: find.byType(FieldInfoButton));
            final chevron = find.descendant(of: active, matching: find.byIcon(Icons.keyboard_arrow_down_rounded));
            final avatar = find.descendant(of: active, matching: find.byWidgetPredicate((widget) =>
              widget is Container && widget.constraints?.maxWidth == 44 && widget.constraints?.maxHeight == 44));
            final chip = find.ancestor(of: reference, matching: find.byType(Container)).first;
            final titleRect = tester.getRect(title);
            final chipRect = tester.getRect(chip);
            final infoRect = tester.getRect(info);
            final chevronRect = tester.getRect(chevron);
            final paragraph = tester.renderObject<RenderParagraph>(title);
            final lines = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: name.length))
              .map((box) => box.top).toSet().length;
            final gap = chipRect.top - titleRect.bottom;
            await capture(tester, 'header-${name.startsWith('Ana') ? 'short' : 'long'}-$width-$scale', {
              'name': name, 'width': width, 'scale': scale, 'title': titleRect.toString(),
              'referenceChip': chipRect.toString(), 'infoTarget': infoRect.toString(),
              'chevron': chevronRect.toString(), 'gap': gap, 'visibleLines': lines,
              'avatar': tester.getRect(avatar).toString(), 'card': tester.getRect(active).toString(),
              'truncated': paragraph.didExceedMaxLines,
              'font': 'deterministic SDK test font (runtime fetching disabled)',
            });
            debugPrint('HEADER name=$name width=$width scale=$scale gap=$gap lines=$lines '
              'title=$titleRect chip=$chipRect info=$infoRect chevron=$chevronRect');
            expect(gap, inInclusiveRange(4.5, 5.5), reason: 'The name-to-reference gap must be content-sized, not the 48dp control row.');
            expect(lines, inInclusiveRange(1, 2));
            expect(tester.widget<Text>(title).maxLines, 2);
            if (name == 'Ana Li') {
              expect(lines, 1);
              expect(paragraph.didExceedMaxLines, isFalse);
            }
            expect(infoRect.size.shortestSide, greaterThanOrEqualTo(48));
            expect(titleRect.right, lessThanOrEqualTo(infoRect.left));
            expect(infoRect.right, lessThanOrEqualTo(chevronRect.left));
            expect(infoRect.center.dy, closeTo(chevronRect.center.dy, 0.5));
            final bounds = tester.getRect(active);
            for (final rect in [titleRect, chipRect, infoRect, chevronRect, tester.getRect(avatar)]) {
              expect(bounds.contains(rect.topLeft), isTrue);
              expect(bounds.contains(rect.bottomRight), isTrue);
            }
            expect(tester.getRect(avatar).right, lessThan(titleRect.left));
            final node = tester.getSemantics(find.descendant(of: info, matching: find.byType(IconButton)));
            expect(node.tooltip, 'About task details for $name');
            expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
            expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            // Keyboard focus and activation must open info, not toggle the card.
            Focus.of(tester.element(find.descendant(of: info, matching: find.byType(Icon)).first)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.text('Task details'), findsOneWidget);
            expect(tester.takeException(), isNull);          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }

  testWidgets('missing contacts retain truthful feedback instead of launching', (tester) async {
    final active = _job(2, 'assigned');
    (active['supabase_zoning_applications'] as Map).remove('contact_number');
    (active['supabase_zoning_applications'] as Map).remove('email');
    jobs = [active];
    await mount(tester);
    await expand(tester, _r2);
    for (final pair in [('Call', 'phone number'), ('SMS', 'phone number'), ('Email', 'email address')]) {
      await tester.tap(within(card(_r2), pair.$1));
      await tester.pumpAndSettle();
      expect(find.text('No ${pair.$2} on file for this applicant.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    }
    expect(launched, isEmpty);
  });

  for (final status in ['assigned', 'in_progress']) {
    testWidgets('completed R1 and $status R2 preserve context, steps and independent progress', (tester) async {
      jobs = [_job(1, 'completed'), _job(2, status)];
      await mount(tester, tab: status == 'assigned' ? TasksScreen.tabPending : TasksScreen.tabOngoing);
      await expand(tester, _r2);
      expect(within(card(_r2), status == 'assigned' ? 'STEP 0/6' : 'STEP 3/6'), findsOneWidget);
      await tester.tap(within(card(_r2), 'Application Details'));
      await settle(tester);
      final overview = tester.widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen));
      expect(overview.task.id, _r2);
      expect(overview.task.previousSiteInspectionId, 101);
      expect(overview.task.inspectionRoundNumber, 2);
      expect(overview.task.planningReview, isNull);
      expect(find.text('Round 2'), findsOneWidget);
      expect(find.text('Reinspection'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Previous inspection: Round 1'), find.byType(ListView), const Offset(0, -200));
      expect(find.text(issueDReason), findsOneWidget);
      expect(find.textContaining('Reviewed:'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final title in ['Site Verification', 'GPS Verification', 'Photographic Evidence',
          'Zoning Checklist', 'Field Findings', 'Review & Submit']) {
        await tester.dragUntilVisible(find.text(title), find.byType(ListView), const Offset(0, -200));
        expect(find.text(title), findsOneWidget);
      }
      expect(InspectionProgress.instance.currentStep, status == 'assigned' ? 1 : 4);
      expect(overview.relatedRounds.singleWhere((round) => round.id == _r1).currentStep, 6);
      expect(await tester.runAsync(() => db.query('pending_actions')), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy offline overview preserves null round metadata without inventing a number', (tester) async {
    final legacy = _job(1, 'assigned');
    for (final field in ['inspection_round_number', 'previous_site_inspection_id',
        'reinspection_reason', 'reinspection_reviewed_at']) {
      legacy.remove(field);
    }
    jobs = [legacy];
    await tester.runAsync(() => DBHelper.cacheJobs(jobs));
    offline = true;
    await mount(tester);
    await expand(tester, _r1);
    await tester.tap(within(card(_r1), 'Application Details'));
    await settle(tester);
    final task = tester.widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen)).task;
    expect(task.inspectionRoundNumber, isNull);
    expect(task.previousSiteInspectionId, isNull);
    expect(task.reinspectionReason, isNull);
    expect(task.reinspectionReviewedAt, isNull);
    expect(task.planningReview, isNull);
    expect(find.text('Inspection'), findsOneWidget);
    expect(find.text('Round 1'), findsNothing);
    expect(find.text('Reinspection'), findsNothing);
    expect(find.text('Planning Review'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical R1 retains findings/photo/review and cannot modify active R2', (tester) async {
    final root = Platform.isWindows
      ? Directory('${Platform.environment['LOCALAPPDATA']}/Temp/opencode') : Directory.systemTemp;
    final directory = root.createTempSync('task-card-history-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final photo = File('${directory.path}/r1.png')
      ..writeAsBytesSync(image.encodePng(image.Image(width: 8, height: 8)));
    jobs = [
      {..._job(1, 'completed'), 'inspector_notes': 'Immutable R1 findings',
        'field_job_photos': [{'photo_url': photo.path, 'notes': 'Immutable R1 photo note'}]},
      _job(2, 'in_progress'),
    ];
    await tester.runAsync(() async {
      await DBHelper.cacheJobs(jobs);
      for (final id in [_r1, _r2]) {
        await db.insert('local_inspections', {'id': id, 'inspector_id': issueDOwner,
          'notes': id == _r1 ? 'Immutable R1 findings' : 'Independent R2 draft',
          'current_step': id == _r1 ? 6 : 3});
      }
      await db.insert('local_photos', {'id': 'r1-photo', 'job_id': _r1,
        'photo_path': photo.path, 'notes': 'Immutable R1 photo note', 'is_synced': 1,
        'inspector_id': issueDOwner});
    });
    await mount(tester, tab: TasksScreen.tabCompleted);
    // The list's expected cache refresh has finished; historical navigation must write nothing.
    Future<Map<String, Object?>> snapshot() async => {
      'jobs': await db.query('local_jobs'), 'drafts': await db.query('local_inspections'),
      'photos': await db.query('local_photos'), 'actions': await db.query('pending_actions'),
      'changes': (await db.rawQuery('SELECT total_changes() AS n')).single['n'],
    };
    final before = await tester.runAsync(snapshot);
    await expand(tester, _r1);
    await tester.tap(within(card(_r1), 'Application Details'));
    await settle(tester);
    final detail = tester.widget<CompletedInspectionDetailScreen>(find.byType(CompletedInspectionDetailScreen));
    expect(detail.task.id, _r1);
    expect(detail.historicalReadOnly, isTrue);
    expect(find.text('Historical inspection — Read only'), findsOneWidget);
    for (final title in ['Photographic Evidence', 'Field Findings']) {
      await tester.dragUntilVisible(find.text(title).first, find.byType(ListView), const Offset(0, -200));
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Immutable R1 photo note'), findsOneWidget);
    expect(find.text('Immutable R1 findings'), findsOneWidget);
    await tester.dragUntilVisible(find.text('PLANNING REVIEW'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('Reinspection Requested'), findsOneWidget);
    expect(find.text(issueDReason), findsOneWidget);
    expect(find.text('Rework this step'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(await tester.runAsync(snapshot), before);
    expect(photo.readAsBytesSync(), image.encodePng(image.Image(width: 8, height: 8)));
    expect(tester.takeException(), isNull);
  });
}
