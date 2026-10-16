// test/offline_first_task_loading_test.dart
//
// FS-04 Phase A — offline-first page loading for My Tasks and Home.
//
// Defect this guards: both screens awaited an UNBOUNDED remote fetch behind an
// OS connectivity check before rendering anything. On a weak / captive /
// hanging network that left an indefinite spinner while legitimate cached
// assignments sat unread, and a failed fetch produced a raw exception (My
// Tasks) or a false empty list (Home).
//
// Contract asserted here: the authenticated owner-scoped cache renders
// immediately and independently of connectivity, the remote refresh is bounded
// and ordered (a late answer from a previous account is discarded), and the
// screen says what it is showing instead of claiming there is nothing.
//
// Real screens, real SQLite, real cache/ownership code. Only the platform and
// HTTP boundaries are fake: no device, no credentials, no live backend.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/widgets/imaps_loading_indicator.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// The honest no-cache failure state. It must never carry the raw exception.
const noCacheFailureText =
    'Could not load your tasks. Check your connection and try again.';

/// The honest no-cache offline state: an empty device is not proof that the
/// inspector has no work.
const noCacheOfflineText =
    'You are offline and no saved tasks are on this device yet. Connect to the internet to load your assignments.';

/// A cached assignment this device legitimately holds, written through the
/// same `cacheJobs` path production uses.
Map<String, dynamic> cachedAssignment(String id, String applicant) => {
      'id': id,
      'status': 'in_progress',
      'scheduled_date': '2026-10-20',
      'supabase_zoning_applications': {
        'applicant_name': applicant,
        'barangay': 'Fixture Barangay',
        'reference_number': 'FS04-CACHED',
      },
    };

/// The remote answer for the same inspector, shaped like a `field_jobs` row.
Map<String, dynamic> remoteAssignment(String id, String applicant) => {
      'id': id,
      'assigned_inspector_id': offlineInspector,
      'status': 'in_progress',
      'scheduled_date': '2026-10-21',
      'supabase_zoning_applications': {
        'applicant_name': applicant,
        'barangay': 'Fixture Barangay',
        'reference_number': 'FS04-REMOTE',
      },
    };

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  final profile = UserProfile(
    id: offlineInspector,
    fullName: 'Fixture Inspector',
    role: 'inspector',
  );

  /// Replaces the cache with exactly the rows a case needs.
  Future<void> cacheOnly(
    WidgetTester tester,
    List<Map<String, dynamic>> jobs,
  ) async {
    await tester.runAsync(() async {
      await fixture.db.delete('inspection_job_retention');
      await DBHelper.cacheJobs(jobs);
    });
  }

  /// Real SQLite work needs real event-loop turns; `flush` supplies them.
  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await fixture.flush(tester);
    }
  }

  /// Advances past the refresh bound, so a stalled or failing network reaches
  /// its terminal state deterministically instead of depending on host timing
  /// (the SDK retries a transport failure before it surfaces).
  Future<void> pastRefreshBound(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 12));
    await settle(tester);
  }

  Future<void> expectRefreshFailure(WidgetTester tester) async {
    final cloud = find.byTooltip('Task data: could not check for updates');
    expect(cloud, findsOneWidget);
    await tester.ensureVisible(cloud);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(cloud);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining("Couldn't check for updates."), findsOneWidget);
    expect(find.textContaining('Your saved tasks are still available.'), findsOneWidget);
    expect(find.text('Retry').hitTestable(), findsOneWidget);
  }

  fixture.widgetTest(
      'hanging connectivity: the cached assignment renders, nothing blocks it',
      (tester) async {
    // Android reports online, but the connectivity read never answers — the
    // exact "OS says online, network is dead" shape from the incident.
    fixture.connectivityReply = Completer<List<String>>();
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);

    expect(find.byType(ImapsLoadingIndicator), findsNothing,
        reason: 'an unanswered connectivity read must not hold the screen');
    expect(find.text('Offline Cached Applicant'), findsOneWidget,
        reason: 'the owner-scoped cached assignment is already known locally');
  });

  fixture.widgetTest(
      'captive portal: remote failure keeps the cached list and names the failure',
      (tester) async {
    // Connectivity says online; every transport attempt throws.
    fixture.online = true;
    fixture.mode = 'transport';
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    await pastRefreshBound(tester);

    expect(find.text('Offline Cached Applicant'), findsOneWidget,
        reason: 'a failed refresh must never replace known cached work');
    await expectRefreshFailure(tester);
    expect(find.textContaining('Failed to load tasks:'), findsNothing,
        reason: 'raw exceptions are never shown to the inspector');
  });

  fixture.widgetTest(
      'hanging refresh: the bound ends it, the cache stays and the notice appears',
      (tester) async {
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    expect(find.text('Offline Cached Applicant'), findsOneWidget);

    // Past the refresh bound the screen gives up and says so.
    await tester.pump(const Duration(seconds: 11));
    await settle(tester);

    expect(find.text('Offline Cached Applicant'), findsOneWidget);
    await expectRefreshFailure(tester);
    expect(find.byType(ImapsLoadingIndicator), findsNothing);
  });

  fixture.widgetTest(
      'delayed success: the refreshed assignment replaces the cache and clears the notice',
      (tester) async {
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    fixture.jobsRows = [remoteAssignment('remote-1', 'Remote Fresh Applicant')];
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    expect(find.text('Offline Cached Applicant'), findsOneWidget);

    fixture.resolveHeld();
    await settle(tester);

    expect(find.text('Remote Fresh Applicant'), findsOneWidget);
    expect(find.text('Offline Cached Applicant'), findsNothing);
    expect(find.byTooltip('Task data: up to date'), findsOneWidget);
    expect(find.byTooltip('Task data: could not check for updates'), findsNothing);

    // Ownership evidence: the refresh asked only for this inspector's rows.
    final jobsReads = fixture.requests
        .where((r) => r.url.path.contains('field_jobs'))
        .toList();
    expect(jobsReads, hasLength(1));
    expect(jobsReads.single.url.queryParameters['assigned_inspector_id'],
        'eq.$offlineInspector');
  });

  fixture.widgetTest(
      'a late answer from the previous account is discarded, the cache survives',
      (tester) async {
    fixture.online = true;
    fixture.mode = 'jobs-hold';
    fixture.jobsRows = [remoteAssignment('remote-1', 'Remote Fresh Applicant')];
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    expect(find.text('Offline Cached Applicant'), findsOneWidget);

    // The device changes hands while the answer is still in flight.
    await tester.runAsync(() => fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session(owner: otherOfflineInspector))));
    fixture.resolveHeld();
    await settle(tester);

    expect(find.text('Remote Fresh Applicant'), findsNothing,
        reason: 'another account\'s answer must never become this screen\'s data');
    expect(find.textContaining('Failed to load tasks:'), findsNothing);
    final rows = await tester.runAsync(() => fixture.db.query('local_jobs'));
    expect(rows, isNotNull);
    expect(
      rows!.where((row) => row['applicant_name'] == 'Remote Fresh Applicant'),
      isEmpty,
      reason: 'the discarded answer never reaches the local cache either',
    );
  });

  fixture.widgetTest(
      'empty cache plus failed refresh: an honest state with a working recovery',
      (tester) async {
    fixture.online = true;
    fixture.mode = 'transport';
    await cacheOnly(tester, const []);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);
    await pastRefreshBound(tester);

    expect(find.byType(ImapsLoadingIndicator), findsNothing);
    expect(find.text(noCacheFailureText), findsOneWidget,
        reason: 'nothing is known yet, so the screen must say that honestly');
    expect(find.textContaining('Failed to load tasks:'), findsNothing);

    // Recovery path: the same retry the inspector gets after reconnecting.
    fixture.mode = 'success';
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text(noCacheFailureText), findsNothing);
  });

  fixture.widgetTest(
      'empty cache while offline: says so instead of claiming there is no work',
      (tester) async {
    fixture.online = false;
    await cacheOnly(tester, const []);

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);

    expect(find.byType(ImapsLoadingIndicator), findsNothing);
    expect(find.text(noCacheOfflineText), findsOneWidget);
    expect(find.textContaining('Failed to load tasks:'), findsNothing);
  });

  fixture.widgetTest(
      'restart with the device offline still lists the cached assignments',
      (tester) async {
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);
    await tester.runAsync(fixture.restartDatabase);
    fixture.online = false;

    await fixture.mount(tester, TasksScreen(profile: profile));
    await settle(tester);

    expect(find.text('Offline Cached Applicant'), findsOneWidget);
    expect(find.byType(ImapsLoadingIndicator), findsNothing);
  });

  fixture.widgetTest(
      'Home: a slow network never blocks the carousel and never claims emptiness',
      (tester) async {
    fixture.connectivityReply = Completer<List<String>>();
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, HomeDashboardScreen(profile: profile));
    await settle(tester);

    expect(find.text('Offline Cached Applicant'), findsWidgets,
        reason: 'the cached assignment is shown while the refresh is outstanding');
    expect(find.text('No active assignments.'), findsNothing,
        reason: 'an unknown remote state is never presented as "none"');
  });

  fixture.widgetTest(
      'Home: a failed refresh shows the saved assignment and says it could not refresh',
      (tester) async {
    fixture.online = true;
    fixture.mode = 'transport';
    await cacheOnly(tester, [cachedAssignment('cached-1', 'Offline Cached Applicant')]);

    await fixture.mount(tester, HomeDashboardScreen(profile: profile));
    await settle(tester);
    await pastRefreshBound(tester);

    expect(find.text('Offline Cached Applicant'), findsWidgets);
    expect(find.text('No active assignments.'), findsNothing);
    await expectRefreshFailure(tester);
  });
}
