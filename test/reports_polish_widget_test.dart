import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' show CheckedState;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:imaps_fieldsync/core/services/reportable_tasks.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/application_support_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/technical_issue_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/reports_support_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/report_history_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/services/diagnostics_service.dart';

const task = ReportableTask(
  fieldJobId: 'exact-job',
  supabaseApplicationId: 'exact-app',
  bridgeSourceId: 'exact-source',
  referenceNumber: 'APP-2026-30',
  applicantName: 'Juan Dela Cruz',
  barangay: 'Poblacion',
  applicationType: 'Residential',
  status: 'assigned',
);

LocalReportRow local(
  ReportQueueState state, {
  String? error,
  String? remoteId,
}) => LocalReportRow(
  id: state.dbValue,
  reportType: ReportType.applicationSupport,
  payload: const {
    'title': 'Land use concern',
    'summary': 'Please confirm the land use.',
  },
  queueState: state,
  retryCount: 0,
  lastError: error,
  remoteReportId: remoteId,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
DiagnosticReport remote() => DiagnosticReport(
  id: 'remote',
  referenceCode: 'DR-2026-0001',
  title: 'Land use concern',
  summary: 'Please confirm the land use.',
  status: 'in_review',
  reportType: ReportType.applicationSupport,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Reuse the offline SDK-font fixture from inspection_job_retention_test.
    // These are layout/semantics checks, not pixel-perfect font goldens.
    GoogleFonts.config.allowRuntimeFetching = false;
    final directory = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final bytes = ByteData.sublistView(
      directory
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.ttf'))
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
      if (asset.endsWith('.ttf')) return bytes;
      return null;
    });
  });
  tearDownAll(
    () => binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: InsightTheme.blue1,
            surface: InsightTheme.surface,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'Technical Issue validates beside the first input and preserves text',
    (tester) async {
      await pump(tester, const TechnicalIssueScreen());
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.scrollUntilVisible(
        find.text('Submit report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Give your report a short title.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '   ',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('huge paste is refused without truncating the previous draft', (
    tester,
  ) async {
    await pump(tester, const TechnicalIssueScreen());
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Keep my title');
    await tester.enterText(field, 'x' * 1000000);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Keep my title');
    expect(
      find.text('This entry is too long. Please shorten it.'),
      findsOneWidget,
    );
    await tester.enterText(field, 'Corrected title');
    await tester.pump();
    expect(
      find.text('This entry is too long. Please shorten it.'),
      findsNothing,
    );

    // A merely oversized (not pathological) entry is reported inline beside the
    // field while typing, with no character counter in the UI.
    final summary = find.byType(TextField).at(1);
    await tester.enterText(summary, 'y' * 9000);
    await tester.pump();
    expect(
      find.text('This entry is too long. Please shorten it.'),
      findsOneWidget,
    );
    await tester.enterText(summary, 'Correct description');
    await tester.pump();
    expect(
      find.text('This entry is too long. Please shorten it.'),
      findsNothing,
    );
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(480, 900),
    const Size(844, 390),
  ]) {
    testWidgets('module menu follows input width and wraps at $size, text 2x', (
      tester,
    ) async {
      await pump(tester, const TechnicalIssueScreen(), size: size, scale: 2);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The popup surface is the Material the menu items are painted on; with
      // ButtonTheme.alignedDropdown it must match the input width exactly.
      final menu = find
          .ancestor(of: find.text('Home'), matching: find.byType(Material))
          .last;
      expect(
        tester.getSize(menu).width,
        closeTo(tester.getSize(dropdown).width, 1),
      );
      // Every entry stays reachable: the menu scrolls instead of clipping.
      final menuScroll = find.descendant(
        of: menu,
        matching: find.byType(Scrollable),
      );
      expect(
        tester
            .widget<Scrollable>(menuScroll)
            .controller
            ?.position
            .maxScrollExtent,
        anyOf(0, greaterThan(0)),
      );
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Application Support controls and keyboard-safe submit at $size',
      (tester) async {
        await pump(
          tester,
          ApplicationSupportScreen(loadTasks: () async => [task]),
          size: size,
          scale: 2,
          keyboard: 140,
        );
        await tester.ensureVisible(find.text(task.displayTitle));
        await tester.tap(find.text(task.displayTitle));
        await tester.ensureVisible(find.text('Clarification Needed'));
        await tester.tap(find.text('Clarification Needed'));
        for (var i = 0; i < 3; i++) {
          final field = find.byType(TextField).at(i);
          await tester.ensureVisible(field);
          await tester.enterText(field, 'Filipino 🧭\nSecond line');
        }
        await tester.ensureVisible(find.text('Submit report'));
        await tester.pump();
        expect(
          tester.getRect(find.text('Submit report')).bottom,
          lessThan(size.height - 140),
        );
        expect(find.text('Affected information (optional)'), findsOneWidget);
        expect(
          find.text('Requested correction or clarification (optional)'),
          findsOneWidget,
        );
        expect(find.text('Does this block your inspection?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'selection survives typing, controls, keyboard and a late exact-id refresh',
    (tester) async {
      final refresh = Completer<List<ReportableTask>>();
      var reads = 0;
      await pump(
        tester,
        ApplicationSupportScreen(
          loadTasks: () {
            reads++;
            return reads == 1 ? Future.value([task]) : refresh.future;
          },
        ),
      );
      await tester.tap(find.text(task.displayTitle));
      await tester.ensureVisible(find.text('Clarification Needed'));
      await tester.tap(find.text('Clarification Needed'));
      final pending = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField).at(i), 'Draft $i');
        await tester.pump();
      }
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding();
      refresh.complete([task]);
      await pending;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(task.displayTitle));
      final semantics = tester.ensureSemantics();
      // Selection is exposed as a checked state with a readable label, never by
      // colour alone, and never by the internal job id.
      final node = tester.getSemantics(
        find.byKey(const ValueKey('report-task-exact-job')),
      );
      expect(node.label, contains(task.displayTitle));
      expect(
        node.flagsCollection.isChecked,
        CheckedState.isTrue,
        reason: 'selected task must announce itself as checked',
      );
      expect(node.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(node.label, isNot(contains(task.fieldJobId)));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
      expect(reads, 2, reason: 'typing/rebuilds never reload tasks');
    },
  );

  testWidgets(
    'Support Desk home keeps two report types distinct from My Reports at large text',
    (tester) async {
      await pump(
        tester,
        ReportsSupportScreen(loadLocal: () async => []),
        size: const Size(320, 640),
        scale: 2,
      );
      expect(find.text('Support Desk'), findsOneWidget);
      expect(find.text('Reports & Support'), findsNothing);
      expect(find.text('FILE A REPORT'), findsOneWidget);
      expect(find.text('Technical Issue'), findsOneWidget);
      // SliverList builds lazily, so scroll before asserting later content.
      for (final target in [
        'Application Support',
        'HISTORY & STATUS',
        'My Reports',
      ]) {
        await tester.scrollUntilVisible(
          find.text(target),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(target), findsOneWidget, reason: target);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncertain report retry still requires explicit duplicate-risk confirmation and can be cancelled', (tester) async {
    var sends = 0;
    ReportQueueService.remoteInsertOverride = (_) async {
      sends++;
      return {'id': 'not-dispatched'};
    };
    addTearDown(ReportQueueService.resetTestHooks);
    await pump(tester, ReportHistoryScreen(
      loadLocal: () async => [local(ReportQueueState.deliveryUnknown)],
      loadRemote: () async => [],
    ));
    await tester.scrollUntilVisible(find.text('Try sending again'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Try sending again'));
    await tester.pumpAndSettle();
    expect(find.text('Send this again?'), findsOneWidget);
    expect(find.textContaining('create a duplicate'), findsOneWidget);
    expect(find.text('Send again'), findsOneWidget);
    expect(sends, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Send this again?'), findsNothing);
    expect(find.text('Submission status uncertain'), findsOneWidget);
    expect(sends, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history keeps local rows visible while loading; failure is not empty',
    (tester) async {
      final response = Completer<List<DiagnosticReport>>();
      await pump(
        tester,
        ReportHistoryScreen(
          loadLocal: () async => [local(ReportQueueState.pending)],
          loadRemote: () => response.future,
        ),
      );
      expect(find.text('Pending on this device'), findsOneWidget);
      expect(find.text('Loading reports…'), findsOneWidget);
      expect(find.text('You have not filed any reports yet.'), findsNothing);
      response.completeError(const SocketException('private host'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('You have not filed any reports yet.'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Pending on this device'), findsOneWidget);
    },
  );

  testWidgets(
    'history dedups sent rows and wraps status without raw retry errors',
    (tester) async {
      await pump(
        tester,
        ReportHistoryScreen(
          loadLocal: () async => [
            local(ReportQueueState.sent, remoteId: 'remote'),
            local(
              ReportQueueState.failedRetryable,
              error: 'rejected: DatabaseException ALTER TABLE secret',
            ),
            local(ReportQueueState.deliveryUnknown),
          ],
          loadRemote: () async => [remote()],
        ),
        size: const Size(320, 640),
        scale: 2,
      );
      expect(find.textContaining('DatabaseException'), findsNothing);
      expect(find.textContaining('rejected:'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('DR-2026-0001'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // A confirmed local row and its remote row render once.
      expect(find.text('DR-2026-0001'), findsOneWidget);
      expect(find.text('FILED WITH THE MPDO TEAM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  /// The live Phase 2C fixture shape: a terminal report carrying the official
  /// MPDO response. The stamp is built as a LOCAL DateTime so the rendered
  /// text is deterministic regardless of the test machine's timezone.
  DiagnosticReport responded({
    String status = 'resolved',
    String? message = 'testing. okay na beh',
    String? responder = 'Jyerine Desunia',
    bool omitStamp = false,
  }) => DiagnosticReport(
    id: 'remote',
    referenceCode: 'DR-2026-0005',
    title: 'Additional Site Information',
    summary: 'Please confirm the land use.',
    status: status,
    reportType: ReportType.applicationSupport,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    responseMessage: message,
    respondedByName: responder,
    respondedAt: omitStamp ? null : DateTime(2026, 10, 4, 7, 3),
  );

  const stalePlaceholder =
      'Not yet reviewed by the MPDO team. You\'ll see more detail here once someone looks into it.';

  testWidgets('a resolved report shows the official MPDO response', (
    tester,
  ) async {
    await pump(
      tester,
      ReportDetailScreen(report: responded()),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text('MPDO RESPONSE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MPDO RESPONSE'), findsOneWidget);
    expect(find.text('testing. okay na beh'), findsOneWidget);
    expect(find.text('RESPONDED BY'), findsOneWidget);
    expect(find.text('Jyerine Desunia'), findsOneWidget);
    expect(find.text('RESPONDED AT'), findsOneWidget);
    expect(find.text('Oct 4, 2026, 7:03 AM'), findsOneWidget);
    // The stale placeholder must be gone for a reviewed report.
    expect(find.text(stalePlaceholder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("wont_fix shows the same official response as resolved", (
    tester,
  ) async {
    await pump(
      tester,
      ReportDetailScreen(
        report: responded(status: 'wont_fix', message: 'Not a defect.'),
      ),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text('MPDO RESPONSE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MPDO RESPONSE'), findsOneWidget);
    expect(find.text('Not a defect.'), findsOneWidget);
    expect(find.text('Jyerine Desunia'), findsOneWidget);
    expect(find.text(stalePlaceholder), findsNothing);
  });

  testWidgets('submitted without a response fabricates nothing', (
    tester,
  ) async {
    await pump(
      tester,
      ReportDetailScreen(
        report: responded(
          status: 'submitted',
          message: null,
          responder: null,
          omitStamp: true,
        ),
      ),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text(stalePlaceholder),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MPDO RESPONSE'), findsNothing);
    expect(find.text('RESPONDED BY'), findsNothing);
    expect(find.text('Jyerine Desunia'), findsNothing);
    // Unreviewed behaviour is preserved for a report nobody has answered.
    expect(find.text(stalePlaceholder), findsOneWidget);
  });

  testWidgets('in_review without a terminal response fabricates nothing', (
    tester,
  ) async {
    await pump(
      tester,
      ReportDetailScreen(
        report: responded(
          status: 'in_review',
          message: null,
          responder: null,
          omitStamp: true,
        ),
      ),
      size: const Size(390, 1400),
    );
    expect(find.text('MPDO RESPONSE'), findsNothing);
    expect(find.text('Jyerine Desunia'), findsNothing);
  });

  testWidgets('a multiline response renders as plain text with breaks kept', (
    tester,
  ) async {
    const body = 'Reviewed the sketch.\n\nBoundary corrected.';
    await pump(
      tester,
      ReportDetailScreen(
        report: responded(message: body),
      ),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text('MPDO RESPONSE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(body), findsOneWidget);
    expect(find.textContaining('&lt;'), findsNothing);
  });

  testWidgets('ordinary punctuation and symbols stay plain text', (
    tester,
  ) async {
    const body = 'Width <10m & depth >5m — 100% done (as of 2026-10-04).';
    await pump(
      tester,
      ReportDetailScreen(report: responded(message: body)),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text('MPDO RESPONSE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(body), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a response with no timestamp does not crash the detail', (
    tester,
  ) async {
    await pump(
      tester,
      ReportDetailScreen(report: responded(omitStamp: true)),
      size: const Size(390, 1400),
    );
    await tester.scrollUntilVisible(
      find.text('MPDO RESPONSE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MPDO RESPONSE'), findsOneWidget);
    expect(find.text('Jyerine Desunia'), findsOneWidget);
    expect(find.text('RESPONDED AT'), findsNothing);
    expect(find.text('Oct 4, 2026, 7:03 AM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Support Desk FAQ navigation help is searchable and expands in both languages',
    (tester) async {
      await pump(tester, const HelpFaqScreen());
      await tester.enterText(find.byType(TextField), 'Support Desk');
      await tester.pumpAndSettle();
      expect(find.text('What is Support Desk?'), findsOneWidget);
      await tester.tap(find.text('What is Support Desk?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('two report types'), findsOneWidget);
      expect(find.textContaining('Profile → Support Desk'), findsOneWidget);
      await tester.tap(find.text('Tagalog'));
      await tester.pumpAndSettle();
      expect(find.text('Ano ang Support Desk?'), findsOneWidget);
      await tester.tap(find.text('Ano ang Support Desk?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dalawang uri'), findsOneWidget);
      expect(find.textContaining('Profile → Support Desk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
