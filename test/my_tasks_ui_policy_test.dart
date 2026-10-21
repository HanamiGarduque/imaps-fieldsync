import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final profile = UserProfile(id: offlineInspector, fullName: 'Fixture Inspector', role: 'inspector');
  var jobs = <Map<String, dynamic>>[];
  var patches = 0;
  final now = DateTime.now();
  DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
  String date(int offset) => day(offset).toIso8601String().split('T').first;

  Map<String, dynamic> job({bool scheduled = true, int visit = 1, int? deadline = 5,
      String status = 'in_progress', int step = 3, String id = offlineJob}) => {
    'id': id, 'assigned_inspector_id': offlineInspector, 'status': status,
    'is_self_scheduled': scheduled, 'scheduled_date': date(visit),
    'deadline_date': deadline == null ? null : date(deadline), 'current_step': step,
    'created_at': '2026-01-01T00:00:00Z',
    'supabase_zoning_applications': {'applicant_name': 'Fictional $id',
      'barangay': 'Alupay', 'reference_number': 'TEST-001'},
  };

  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    fixture.online = true;
    fixture.mode = 'success';
    patches = 0;
    jobs = [job()];
    fixture.requestOverride = (request) async {
      if (request.url.path != '/rest/v1/field_jobs') return null;
      final q = request.url.queryParameters;
      final rows = jobs.where((row) => q['id'] == null || q['id'] == 'eq.${row['id']}').toList();
      if (request.method == 'PATCH') {
        patches++;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        for (final row in rows) { row.addAll(payload); }
      }
      return http.Response(jsonEncode(rows), 200, request: request,
          headers: {'content-type': 'application/json'});
    };
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, {bool home = false, double scale = 1,
      Size size = const Size(360, 1000),
      int tab = TasksScreen.tabPending}) async {
    await fixture.mount(tester, home ? HomeDashboardScreen(profile: profile) :
        TasksScreen(profile: profile, initialTabIndex: tab),
        size: size, textScale: scale);
    await settle(tester);
  }

  Finder card() => find.byKey(const ValueKey(offlineJob));
  Finder info() => find.descendant(of: card(), matching: find.byType(FieldInfoButton));
  Finder dialogText(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
  Future<void> openInfo(WidgetTester tester) async {
    await tester.ensureVisible(info());
    await tester.tap(info());
    await settle(tester);
    expect(find.text('Task details'), findsOneWidget);
  }
  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.descendant(of: card(), matching: find.text('Fictional $offlineJob')));
    await settle(tester);
  }

  BoxDecoration decoration(WidgetTester tester) => tester.widgetList<Container>(
      find.descendant(of: card(), matching: find.byType(Container)))
      .map((c) => c.decoration).whereType<BoxDecoration>()
      .firstWhere((d) => d.borderRadius == BorderRadius.circular(14));

  for (final (visit, color) in [(4, InsightTheme.blue1), (3, InsightTheme.orange),
      (2, InsightTheme.orange), (1, InsightTheme.red), (0, InsightTheme.red), (-1, InsightTheme.red)]) {
    fixture.widgetTest('started Scheduled Visit $visit days keeps its border and one info action', (tester) async {
      jobs = [job(visit: visit)];
      await mount(tester);
      expect(card(), findsOneWidget);
      expect((decoration(tester).border! as Border).top.color, color);
      expect(decoration(tester).color, InsightTheme.surface);
      expect(find.descendant(of: card(), matching: find.byType(FieldInfoButton)), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Visit: ${date(visit)}'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget, reason: 'section only, no redundant pill');
      expect(tester.takeException(), isNull);
    });
  }

  for (final deadline in <int?>[0, -1, null]) {
    for (final scheduled in [false, true]) {
      fixture.widgetTest('deadline $deadline closes all scheduling gestures (committed=$scheduled)', (tester) async {
        jobs = [job(deadline: deadline, scheduled: scheduled, status: 'assigned', step: 0)];
        await mount(tester);
        await tester.longPress(find.text('Fictional $offlineJob'));
        await settle(tester);
        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(find.text('Schedule this task'), findsNothing);
        expect(find.text('Reschedule this task'), findsNothing);
        await expand(tester);
        expect(find.text('Schedule Inspection Date'), findsNothing);
        expect(find.text('Reschedule Inspection Date'), findsNothing);
        expect(find.textContaining(deadline == null ? 'could not be verified' : 'today or has passed'), findsWidgets);
        expect(patches, 0);
      });
    }
  }

  fixture.widgetTest('PO Deadline Today is distinct even when Visit is tomorrow', (tester) async {
    jobs = [job(deadline: 0)];
    await mount(tester);
    expect(find.text('PO Deadline Today'), findsOneWidget);
    expect(find.text('For Reschedule'), findsNothing);
    expect(find.textContaining('PO Deadline today. Rescheduling is unavailable'), findsNothing);
    expect(decoration(tester).color, InsightTheme.surface);
    await openInfo(tester);
    expect(dialogText('Scheduled visit tomorrow.'), findsOneWidget);
    expect(dialogText('PO Deadline today. Rescheduling is unavailable; complete your inspection.'), findsOneWidget);
    await fixture.capture(tester, 'my-tasks-visit-tomorrow-deadline-today');
  });

  fixture.widgetTest('only an expired PO deadline tints the entire active card red', (tester) async {
    jobs = [job(deadline: -1)];
    await mount(tester);
    expect(decoration(tester).color, InsightTheme.redTint);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('For Reschedule'), findsNothing);
  });

  fixture.widgetTest('Visit and PO notices remain separate and do not duplicate on rebuild', (tester) async {
    jobs = [job(visit: 2, deadline: 3)];
    await mount(tester);
    for (var i = 0; i < 3; i++) {
      expect(find.byType(AlertDialog), findsNothing, reason: 'no automatic popup on rebuild');
      expect(find.text('Scheduled visit in 2 days — prepare your site inspection.'), findsNothing);
      expect(find.text('PO Deadline in 3 days.'), findsNothing);
      expect(info(), findsOneWidget);
      await openInfo(tester);
      expect(dialogText('Scheduled visit in 2 days — prepare your site inspection.'), findsOneWidget);
      expect(dialogText('PO Deadline in 3 days.'), findsOneWidget);
      expect(dialogText('Visit date'), findsOneWidget);
      expect(dialogText(date(2)), findsOneWidget);
      expect(dialogText('PO Deadline'), findsOneWidget);
      expect(dialogText(date(3)), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester);
      await expand(tester);
    }
    expect(patches, 0);
  });

  for (final (visit, deadline, scheduled, message, color) in [
    (3, 8, true, 'Scheduled visit in 3 days — prepare your site inspection.', InsightTheme.orangeInk),
    (2, 8, true, 'Scheduled visit in 2 days — prepare your site inspection.', InsightTheme.orangeInk),
    (1, 8, true, 'Scheduled visit tomorrow.', InsightTheme.redInk),
    (0, 8, true, 'Scheduled visit today — proceed with the inspection.', InsightTheme.redInk),
    (-1, 8, true, 'You missed your Visit date. Reschedule before the PO Deadline or continue the inspection.', InsightTheme.redInk),
    (0, 3, false, 'PO Deadline in 3 days.', InsightTheme.orangeInk),
    (0, 2, false, 'PO Deadline in 2 days.', InsightTheme.orangeInk),
    (0, 1, false, 'PO Deadline in 1 day.', InsightTheme.redInk),
    (0, 0, false, 'PO Deadline today. Rescheduling is unavailable; complete your inspection.', InsightTheme.redInk),
    (0, -1, false, 'Overdue — the PO deadline has passed.', InsightTheme.redInk),
    (4, 3, true, 'Your Visit date is after the PO Deadline. Coordinate with the Planning Officer; choose a valid Visit only while scheduling is available.', InsightTheme.redInk),
  ]) {
    fixture.widgetTest('contextual notice $message uses highest severity without inline clutter', (tester) async {
      jobs = [job(visit: visit, deadline: deadline, scheduled: scheduled, status: 'assigned', step: 0)];
      await mount(tester);
      expect(info(), findsOneWidget);
      expect(find.text(message), findsNothing);
      final icon = tester.widget<Icon>(find.descendant(of: info(), matching: find.byType(Icon)));
      expect(icon.color, color);
      await openInfo(tester);
      expect(dialogText(message), findsOneWidget);
      expect(dialogText('Next action'), findsOneWidget);
      expect(dialogText('PO Deadline'), findsOneWidget);
      expect(dialogText(date(deadline)), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(message), findsNothing);
      expect(patches, 0);
    });
  }

  fixture.widgetTest('ordinary and Completed cards do not inherit historical warning icons', (tester) async {
    jobs = [job(visit: 4, deadline: 8, status: 'assigned', step: 0)];
    await mount(tester);
    expect(tester.widget<Icon>(find.descendant(of: info(), matching: find.byType(Icon))).color, InsightTheme.blueInk);
    jobs = [job(visit: -4, deadline: -1, status: 'completed', step: 6)];
    await fixture.unmount(tester);
    await mount(tester, tab: TasksScreen.tabCompleted);
    expect((decoration(tester).border! as Border).top.color, InsightTheme.green);
    expect(tester.widget<Icon>(find.descendant(of: info(), matching: find.byType(Icon))).color, InsightTheme.blueInk);
    await openInfo(tester);
    expect(find.textContaining('Overdue'), findsNothing);
    expect(find.textContaining('Scheduled visit'), findsNothing);
  });

  fixture.widgetTest('notice dialog stays scrollable and dismissible at 320px and 200% text', (tester) async {
    jobs = [job(visit: 2, deadline: 3)];
    await mount(tester, scale: 2, size: const Size(320, 568));
    expect(tester.getSize(info()), const Size(48, 48));
    await openInfo(tester);
    expect(dialogText('Scheduled visit in 2 days — prepare your site inspection.'), findsOneWidget);
    expect(dialogText('PO Deadline in 3 days.'), findsOneWidget);
    final close = find.text('Close');
    expect(close.hitTestable(), findsOneWidget);
    await tester.drag(find.descendant(of: find.byType(AlertDialog), matching: find.byType(SingleChildScrollView)), const Offset(0, -600));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(close);
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  fixture.widgetTest('fresh PO placeholder uses Schedule and a tomorrow-only picker', (tester) async {
    jobs = [job(scheduled: false, deadline: 1, status: 'assigned', step: 0)];
    await mount(tester);
    await expand(tester);
    await tester.ensureVisible(find.text('Schedule Inspection Date'));
    await tester.tap(find.text('Schedule Inspection Date'));
    await settle(tester);
    expect(find.text('Schedule this task'), findsOneWidget);
    await tester.tap(find.text('Select a date'));
    await settle(tester);
    final picker = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(picker.firstDate, day(1));
    expect(picker.lastDate, day(1));
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.text('Confirm schedule'));
    await settle(tester);
    expect(patches, 1);
    expect(jobs.single['is_self_scheduled'], isTrue);
    expect(jobs.single['status'], 'assigned');
    expect(find.text('Visit: ${date(1)}'), findsOneWidget);
  });

  fixture.widgetTest('Urgent includes PO reminders but never Overdue', (tester) async {
    jobs = [job(visit: 0, deadline: -1, status: 'assigned', step: 0),
      job(id: offlineRound2, scheduled: false, deadline: 2, status: 'assigned', step: 0)];
    await mount(tester);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.tap(find.text('Urgent'));
    await tester.tap(find.text('Apply Filters'));
    await settle(tester);
    expect(card(), findsNothing);
    expect(find.byKey(const ValueKey(offlineRound2)), findsOneWidget);
  });

  fixture.widgetTest('an open scheduling sheet cannot migrate to another inspector session', (tester) async {
    await mount(tester);
    await tester.longPress(find.text('Fictional $offlineJob'));
    await settle(tester);
    expect(find.text('Confirm reschedule'), findsOneWidget);
    jobs.single['assigned_inspector_id'] = otherOfflineInspector;
    await tester.runAsync(() => fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session(owner: otherOfflineInspector))));
    await settle(tester);
    await tester.tap(find.text('Confirm reschedule'));
    await settle(tester);
    expect(patches, 0);
    expect(jobs.single['scheduled_date'], date(1));
  });

  fixture.widgetTest('date filter uses PO Deadline rather than an uncommitted placeholder', (tester) async {
    jobs = [job(scheduled: false, visit: -100, deadline: 2, status: 'assigned', step: 0)];
    await mount(tester);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.tap(find.text('Last 30 Days'));
    await tester.tap(find.text('Apply Filters'));
    await settle(tester);
    expect(card(), findsOneWidget);
  });

  fixture.widgetTest('Home keeps a started Visit Scheduled with a calm computed reminder', (tester) async {
    jobs = [job(visit: 2, deadline: 3)];
    await mount(tester, home: true);
    expect(find.byType(ActiveAssignmentsFolderCard), findsOneWidget);
    expect(find.text('Visit Date'), findsOneWidget);
    expect(find.textContaining('Scheduled visit in 2 days'), findsOneWidget);
    expect(find.textContaining('PO Deadline in 3 days'), findsOneWidget);
  });

  fixture.widgetTest('Home local final intent is Completed on Device, not an active Visit', (tester) async {
    await DBHelper.cacheJobs(jobs);
    await SyncOutboxService.enqueueSubmitInspection(jobId: offlineJob,
      findings: 'Fictional final evidence', isCompliant: true, inspectionResult: 'Compliant',
      observations: 'Fictional observation', inspectorNotes: 'Fictional note',
      checklistData: const [], checklistCompletedCount: 0, checklistTotalCount: 0, photosData: const []);
    await mount(tester, home: true);
    expect(find.byType(ActiveAssignmentsFolderCard), findsNothing);
    expect(find.textContaining('completed on device'), findsOneWidget);
    expect(find.text('Completed — Synced'), findsNothing);
  });

  for (final step in [3, 6]) {
    for (final offline in [true, false]) {
      fixture.widgetTest('saved Step $step stays visible after ${offline ? 'offline remount' : 'remote refresh'}', (tester) async {
        jobs = [job(step: 0)];
        await DBHelper.cacheJobs(jobs);
        await DBHelper.saveInspectionLocally(jobId: offlineJob, actualLandUse: 'Fictional use',
          notes: 'Fictional saved findings', isCompliant: false, inspectionResult: '',
          checklist: const {}, boundaryStatus: 'Fictional boundary', currentStep: step);
        await DBHelper.savePhotoLocally(photoId: 'fictional-photo', jobId: offlineJob,
          photoPath: '${fixture.directory.path}/fictional.jpg', notes: 'Fictional photo note',
          latitude: 0, longitude: 0);
        await SyncOutboxService.enqueueMarkOngoing(jobId: offlineJob);
        final before = [for (final table in ['local_inspections', 'local_photos', 'pending_actions'])
          await fixture.db.query(table)];
        fixture.online = !offline;
        await mount(tester);
        expect(find.text('STEP $step/6'), findsOneWidget);
        expect(find.text('In Progress'), step == 3 ? findsOneWidget : findsNothing);
        expect(find.text('Scheduled'), findsOneWidget);
        expect([for (final table in ['local_inspections', 'local_photos', 'pending_actions'])
          await tester.runAsync(() => fixture.db.query(table))], before);
        expect((await tester.runAsync(DBHelper.getCachedJobs))!.single['status'], 'in_progress');
      });
    }
  }

  fixture.widgetTest('an unscheduled pending cache row with saved work is Ongoing', (tester) async {
    jobs = [job(scheduled: false, status: 'pending', step: 0)];
    await DBHelper.cacheJobs(jobs);
    await DBHelper.saveInspectionLocally(jobId: offlineJob, actualLandUse: '', notes: 'Saved',
      isCompliant: false, inspectionResult: '', checklist: const {}, boundaryStatus: '', currentStep: 3);
    fixture.online = false;
    await mount(tester, tab: TasksScreen.tabOngoing);
    expect(card(), findsOneWidget);
    expect(find.text('STEP 3/6'), findsOneWidget);
    expect(find.text('In Progress'), findsNothing);
  });

  fixture.widgetTest('a foreign draft never contributes progress to this owner task', (tester) async {
    jobs = [job(step: 0)];
    await DBHelper.cacheJobs(jobs);
    await DBHelper.saveInspectionLocally(jobId: offlineJob, actualLandUse: '',
      notes: 'Fictional foreign draft', isCompliant: false, inspectionResult: '',
      checklist: const {}, boundaryStatus: '', currentStep: 6);
    expect(await fixture.db.update('local_inspections', {'inspector_id': otherOfflineInspector,
      'current_step': 6}, where: 'id = ?', whereArgs: [offlineJob]), 1,
        reason: 'the fixture must contain a foreign draft to exercise isolation');
    fixture.online = false;
    await mount(tester);
    expect(find.text('STEP 6/6'), findsNothing);
    expect(find.text('In Progress'), findsNothing);
  });

  fixture.widgetTest('carousel and calendar keep the stored day of an offset Visit', (tester) async {
    jobs = [{...job(), 'scheduled_date': '2026-10-22T00:30:00+08:00',
      'deadline_date': '2030-10-25'}];
    await mount(tester, home: true);
    final carousel = tester.widget<ActiveAssignmentsFolderCard>(find.byType(ActiveAssignmentsFolderCard));
    expect(carousel.date, 'Oct 22, 2026');
    expect(TaskItem.fromJob(jobs.single).presentation.activeDay, DateTime(2026, 10, 22));
  });
}
