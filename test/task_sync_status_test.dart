import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/offline_banner.dart';
import 'package:imaps_fieldsync/core/widgets/task_sync_indicator.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

// Real screens, cache transactions and owner transitions. Only HTTP/platform
// boundaries are isolated by the existing FS-04 fixture; no device or backend.
void main() {
  final fixture = OfflineReliabilityFixture();
  final profile = UserProfile.fromMap(offlineProfile);
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Finder getCloud() => find.byKey(const ValueKey('task-sync-indicator'));
  Finder status(String state) => find.byTooltip('Task data: $state');
  Iterable<http.Request> assignmentReads() => fixture.requests.where(
    (r) => r.method == 'GET' && r.url.path == '/rest/v1/field_jobs',
  );

  Map<String, dynamic> job(String name) => {
    'id': offlineJob,
    'assigned_inspector_id': offlineInspector,
    'status': 'in_progress',
    'scheduled_date': '2026-10-20',
    'supabase_zoning_applications': {
      'applicant_name': name,
      'barangay': 'Fictional site',
      'reference_number': 'CLOUD-FIXTURE',
    },
  };

  Future<void> seed(WidgetTester tester, {bool empty = false}) async {
    await tester.runAsync(() async {
      await fixture.db.delete('inspection_job_retention');
      await DBHelper.cacheJobs(empty ? [] : [job('Saved fixture assignment')]);
    });
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> explain(WidgetTester tester) async {
    await tester.ensureVisible(getCloud());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(getCloud());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('app-feedback-popup')).hitTestable(),
      findsOneWidget,
    );
  }

  void succeed() {
    fixture.mode = 'success';
    fixture.requestOverride = (request) async {
      if (request.url.path != '/rest/v1/field_jobs') return null;
      return http.Response(
        jsonEncode([job('Fresh fixture assignment')]),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    };
  }

  Widget screen(bool home) => home
      ? HomeDashboardScreen(profile: profile)
      : TasksScreen(profile: profile);

  // This capture-only case is run against the unchanged production baseline
  // and again after the patch. Same data, fonts, sizes and animation frames.
  testWidgets(
    'capture matched assignment surfaces',
    (tester) async {
      try {
        for (final home in [true, false]) {
          for (final narrow in [false, true]) {
            await seed(tester);
            fixture.online = true;
            fixture.mode = 'jobs-hold';
            await fixture.mount(
              tester,
              screen(home),
              size: narrow ? const Size(320, 640) : const Size(390, 844),
              textScale: narrow ? 2 : 1,
            );
            await frames(tester);
            if (home) {
              await tester.ensureVisible(find.text('Active Assignments'));
              await frames(tester);
            }
            await fixture.capture(
              tester,
              '${home ? 'home' : 'tasks'}-checking-${narrow ? '320-200' : '390-100'}',
            );
            expect(tester.takeException(), isNull);
            await fixture.unmount(tester);
          }
        }
      } finally {
        await fixture.unmount(tester);
      }
    },
    skip: Platform.environment['FS04_EVIDENCE_DIR'] == null,
  );

  for (final home in [true, false]) {
    final page = home ? 'Home' : 'Tasks';

    fixture.widgetTest(
      '$page Checking to Fresh requires an accepted authoritative refresh',
      (tester) async {
        await seed(tester);
        fixture.online = true;
        fixture.mode = 'jobs-hold';
        fixture.jobsRows = [job('Fresh fixture assignment')];
        final attempted = DateTime.now();
        await fixture.mount(tester, screen(home));
        await frames(tester);
        expect(getCloud(), findsOneWidget);
        expect(status('checking for updates'), findsOneWidget);
        expect(find.text('Saved fixture assignment'), findsWidgets);
        expect(
          find.byType(SavedDataNotice),
          findsNothing,
          reason: 'cached cards need the compact heading control, not a banner',
        );
        final state = tester.state(getCloud());
        await explain(tester);
        expect(
          find.textContaining('Your saved tasks are still available'),
          findsOneWidget,
        );
        expect(find.textContaining('Last checked:'), findsNothing);
        expect(assignmentReads(), hasLength(1));
        // A layout rebuild is not a new refresh or a new animation controller.
        tester.view.physicalSize = const Size(400, 850);
        await frames(tester);
        expect(tester.state(getCloud()), same(state));
        expect(assignmentReads(), hasLength(1));
        tester.view.physicalSize = const Size(390, 844);
        await frames(tester);

        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        final answered = DateTime.now();
        fixture.resolveHeld();
        await frames(tester);
        expect(status('up to date'), findsOneWidget);
        expect(find.text('Fresh fixture assignment'), findsWidgets);
        await explain(tester);
        final text = tester
            .widget<Text>(find.textContaining('Last checked:'))
            .data!;
        final match = RegExp(
          r'Last checked: (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)',
        ).firstMatch(text)!;
        final checked = DateTime.parse(match.group(1)!);
        expect(
          checked.isAfter(attempted),
          isTrue,
          reason: 'the timestamp must describe success, not the request start',
        );
        expect(
          checked.isBefore(answered.subtract(const Duration(seconds: 1))),
          isFalse,
        );
        expect(checked.isAfter(DateTime.now()), isFalse);
        expect(assignmentReads(), hasLength(1));
        for (final read in assignmentReads()) {
          expect(
            read.url.queryParameters['assigned_inspector_id'],
            'eq.$offlineInspector',
          );
        }
        await fixture.capture(
          tester,
          '${page.toLowerCase()}-fresh-explanation',
        );
      },
    );

    fixture.widgetTest(
      '$page Offline never presents a saved cache as confirmed Fresh',
      (tester) async {
        await seed(tester);
        await fixture.mount(tester, screen(home));
        await frames(tester);
        expect(status('offline, saved tasks'), findsOneWidget);
        expect(find.text('Saved fixture assignment'), findsWidgets);
        expect(find.byType(SavedDataNotice), findsNothing);
        await explain(tester);
        expect(find.textContaining('Showing saved task data.'), findsOneWidget);
        expect(find.textContaining('Last checked:'), findsNothing);
        expect(assignmentReads(), isEmpty);
        await fixture.capture(
          tester,
          '${page.toLowerCase()}-offline-explanation',
        );
      },
    );

    fixture.widgetTest(
      '$page timeout keeps assignments and Retry performs one bounded refresh',
      (tester) async {
        await seed(tester);
        fixture.online = true;
        fixture.mode = 'jobs-hold';
        await fixture.mount(tester, screen(home));
        await frames(tester);
        await tester.pump(const Duration(seconds: 11));
        await frames(tester);
        expect(status('could not check for updates'), findsOneWidget);
        expect(find.text('Saved fixture assignment'), findsWidgets);
        await explain(tester);
        expect(
          find.textContaining("Couldn't check for updates."),
          findsOneWidget,
        );
        expect(find.textContaining('Last checked:'), findsNothing);
        await fixture.capture(
          tester,
          '${page.toLowerCase()}-failed-explanation',
        );
        succeed();
        await tester.tap(find.byKey(const ValueKey('app-feedback-retry')));
        await frames(tester);
        expect(status('up to date'), findsOneWidget);
        expect(find.text('Fresh fixture assignment'), findsWidgets);
        expect(assignmentReads(), hasLength(2));
        // The timed-out answer arrives after the successful retry: still stale.
        fixture.jobsRows = [job('Late obsolete assignment')];
        fixture.resolveHeld();
        await frames(tester);
        expect(find.text('Late obsolete assignment'), findsNothing);
        expect(status('up to date'), findsOneWidget);
      },
    );

    fixture.widgetTest(
      '$page transport failure is an alert, not normal Offline',
      (tester) async {
        await seed(tester);
        fixture.online = true;
        fixture.mode = 'transport';
        await fixture.mount(tester, screen(home));
        await tester.pump(const Duration(seconds: 12));
        await frames(tester);
        expect(status('could not check for updates'), findsOneWidget);
        expect(status('offline, saved tasks'), findsNothing);
        expect(find.text('Saved fixture assignment'), findsWidgets);
      },
    );

    fixture.widgetTest(
      '$page No Cache explains initial online loading and retains recovery',
      (tester) async {
        await seed(tester, empty: true);
        await fixture.mount(tester, screen(home));
        await frames(tester);
        expect(status('no saved tasks'), findsOneWidget);
        expect(find.textContaining('No active assignments.'), findsNothing);
        await explain(tester);
        expect(
          find.textContaining('No saved tasks are available on this device.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Connect to load your assignments.'),
          findsOneWidget,
        );
        expect(find.textContaining('Last checked:'), findsNothing);
        await fixture.capture(
          tester,
          '${page.toLowerCase()}-no-cache-explanation',
        );
        succeed();
        fixture.online = true;
        await tester.tap(find.byKey(const ValueKey('app-feedback-retry')));
        await frames(tester);
        expect(status('up to date'), findsOneWidget);
        expect(find.text('Fresh fixture assignment'), findsWidgets);
      },
    );

    fixture.widgetTest(
      '$page owner switch clears confirmed time and retires bound Retry',
      (tester) async {
        await seed(tester);
        succeed();
        fixture.online = true;
        await fixture.mount(tester, screen(home));
        await frames(tester);
        expect(status('up to date'), findsOneWidget);
        await explain(tester);
        expect(find.textContaining('Last checked:'), findsOneWidget);
        final rows = await tester.runAsync(
          () => fixture.db.query('local_jobs'),
        );
        await tester.runAsync(
          () => fixture.client.auth.setInitialSession(
            jsonEncode(fixture.session(owner: otherOfflineInspector)),
          ),
        );
        await frames(tester);
        expect(status('inspector session changed'), findsOneWidget);
        expect(
          find.textContaining('Last checked:'),
          findsNothing,
          reason:
              'the old owner timestamp must also retire from the open explanation',
        );
        expect(
          find.text('Fresh fixture assignment', skipOffstage: false),
          findsNothing,
        );
        await explain(tester);
        expect(find.textContaining('Last checked:'), findsNothing);
        expect(find.byKey(const ValueKey('app-feedback-retry')), findsNothing);
        expect(
          await tester.runAsync(() => fixture.db.query('local_jobs')),
          rows,
        );
      },
    );

    fixture.widgetTest(
      '$page stale popup Retry cannot load the next inspector into the old screen',
      (tester) async {
        await seed(tester);
        await fixture.mount(tester, screen(home));
        await frames(tester);
        await explain(tester);
        final retry = tester
            .widget<TextButton>(
              find.byKey(const ValueKey('app-feedback-retry')),
            )
            .onPressed!;
        await tester.runAsync(
          () => fixture.client.auth.setInitialSession(
            jsonEncode(fixture.session(owner: otherOfflineInspector)),
          ),
        );
        succeed();
        fixture.online = true;
        final before = assignmentReads().length;
        retry();
        await frames(tester);
        expect(assignmentReads().length, before);
        expect(status('inspector session changed'), findsOneWidget);
        expect(find.text('Fresh fixture assignment'), findsNothing);
      },
    );

    fixture.widgetTest(
      '$page an old refresh timeout cannot overwrite the retired owner status',
      (tester) async {
        await seed(tester);
        fixture.online = true;
        fixture.mode = 'jobs-hold';
        await fixture.mount(tester, screen(home));
        await frames(tester);
        await tester.runAsync(
          () => fixture.client.auth.setInitialSession(
            jsonEncode(fixture.session(owner: otherOfflineInspector)),
          ),
        );
        await frames(tester);
        expect(status('inspector session changed'), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
        await frames(tester);
        expect(status('inspector session changed'), findsOneWidget);
        expect(status('could not check for updates'), findsNothing);
        expect(
          find.text('Saved fixture assignment', skipOffstage: false),
          findsNothing,
        );
      },
    );

    fixture.widgetTest(
      '$page compact heading stays accessible at 320dp and 200 percent text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await seed(tester);
          await fixture.mount(
            tester,
            screen(home),
            size: const Size(320, 640),
            textScale: 2,
          );
          await frames(tester);
          final heading = find.text(home ? 'Active Assignments' : 'My Tasks');
          await tester.ensureVisible(heading);
          await frames(tester);
          expect(tester.getSize(getCloud()).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(getCloud()).height, greaterThanOrEqualTo(48));
          expect(getCloud().hitTestable(), findsOneWidget);
          final control = tester.getSemantics(getCloud());
          expect(control.tooltip, 'Task data: offline, saved tasks');
          expect(control.flagsCollection.isButton, isTrue);
          expect(
            tester.getRect(getCloud()).left,
            greaterThanOrEqualTo(tester.getRect(heading).right),
          );
          expect(
            tester.getRect(getCloud()).left - tester.getRect(heading).right,
            lessThanOrEqualTo(16),
          );
          expect(tester.takeException(), isNull);
          await explain(tester);
          expect(
            find.byKey(const ValueKey('app-feedback-popup')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await fixture.capture(tester, '${page.toLowerCase()}-320-200-status');
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  fixture.widgetTest(
    'checking animates only during a refresh and respects reduced motion',
    (tester) async {
      final phase = ValueNotifier(TaskRefreshPhase.checking);
      final reduced = ValueNotifier(false);
      addTearDown(phase.dispose);
      addTearDown(reduced.dispose);
      await fixture.mount(
        tester,
        ValueListenableBuilder(
          valueListenable: reduced,
          builder: (context, disabled, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
            child: ValueListenableBuilder(
              valueListenable: phase,
              builder: (context, value, _) => Scaffold(
                body: TaskSyncIndicator(
                  key: const ValueKey('task-sync-indicator'),
                  phase: value,
                  hasSavedTasks: true,
                  lastChecked: DateTime(2026, 10, 16),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.hasRunningAnimations, isTrue);
      phase.value = TaskRefreshPhase.fresh;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      reduced.value = true;
      phase.value = TaskRefreshPhase.checking;
      await tester.pump();
      expect(status('checking for updates'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      reduced.value = false;
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      phase.value = TaskRefreshPhase.failed;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(assignmentReads(), isEmpty);
    },
  );

  fixture.widgetTest(
    'Home and Tasks preserve their own status through supported route navigation',
    (tester) async {
      await seed(tester);
      succeed();
      fixture.online = true;
      await fixture.mount(tester, screen(true));
      await frames(tester);
      await explain(tester);
      final homeMessage = tester
          .widget<Text>(find.textContaining('Last checked:'))
          .data;
      final homeState = tester.state(getCloud());
      await tester.ensureVisible(find.text('See All'));
      await tester.tap(find.text('See All'));
      await frames(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('app-feedback-popup')), findsNothing);
      expect(status('up to date'), findsOneWidget);
      expect(assignmentReads(), hasLength(2));
      Navigator.of(tester.element(getCloud())).pop();
      await frames(tester);
      expect(tester.state(getCloud()), same(homeState));
      await explain(tester);
      expect(find.text(homeMessage!), findsOneWidget);
      expect(
        assignmentReads(),
        hasLength(2),
        reason: 'revealing mounted Home is not another refresh',
      );
    },
  );

  fixture.widgetTest(
    'real shell tab switches start only each existing screen refresh',
    (tester) async {
      await seed(tester);
      succeed();
      fixture.online = true;
      await fixture.mount(tester, MainShellScreen(profile: profile));
      await frames(tester);
      expect(status('up to date'), findsOneWidget);
      final initial = assignmentReads().length;
      Finder tab(IconData icon) => find.descendant(
        of: find.byType(InsightBottomNav),
        matching: find.byIcon(icon),
      );
      await tester.tap(tab(Icons.assignment_outlined));
      await frames(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(status('up to date'), findsOneWidget);
      expect(assignmentReads().length, initial + 1);
      await tester.tap(tab(Icons.home_rounded));
      await frames(tester);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(status('up to date'), findsOneWidget);
      expect(assignmentReads().length, initial + 2);
    },
  );
}
