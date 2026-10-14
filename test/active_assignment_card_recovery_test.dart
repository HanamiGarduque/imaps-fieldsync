import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/active_assignments_folder_card.dart';

import 'support/offline_reliability_fixture.dart';

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
  final fixture = OfflineReliabilityFixture();
  const applicant = 'Fictional Round Two Applicant With A Long Name';
  final card = find.byType(ActiveAssignmentsFolderCard);
  Finder textOnCard(String text) => find.descendant(of: card, matching: find.text(text));

  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> cacheAssignments({required String status, bool selfScheduled = false}) async {
    await DBHelper.cacheJobs([
      {'id': offlineJob, 'status': 'completed', 'inspection_round_number': 1,
        'local_inspection_id': 101, 'bridge_source_id': 'fictional-imaps',
        'supabase_application_id': 'fictional-application'},
      {'id': offlineRound2, 'status': status, 'inspection_round_number': 2,
        'local_inspection_id': 102, 'previous_site_inspection_id': 101,
        'bridge_source_id': 'fictional-imaps',
        'supabase_application_id': 'fictional-application',
        'is_self_scheduled': selfScheduled, 'scheduled_date': '2026-10-21',
        'deadline_date': '2026-10-31',
        'supabase_zoning_applications': {'applicant_name': applicant,
          'barangay': 'Fictional Barangay', 'reference_number': 'FIXTURE-R2'}},
    ]);
    await DBHelper.saveInspectionStep(offlineJob, 6, {'6': '2026-10-01T12:00:00Z'}, offlineInspector);
  }

  Future<void> mountHome(WidgetTester tester, {Size size = const Size(390, 844), TextScaler scaler = TextScaler.noScaling}) async {
    // All HTTP still terminates at the fixture; offline tasks must come from SQLite.
    fixture.mode = 'success';
    fixture.requests.clear();
    await fixture.mount(tester, Builder(builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: HomeDashboardScreen(profile: UserProfile(
        id: offlineInspector, fullName: 'Fixture Inspector', role: 'inspector')))), size: size);
    for (var frame = 0; frame < 30 && card.evaluate().isEmpty; frame++) {
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(fixture.requests.where((request) => request.url.path.endsWith('/field_jobs')), isEmpty,
      reason: 'Offline card data must not require a task fetch.');
  }

  fixture.widgetTest('Offline card uses the exact R2 identity, scheduling meaning and overview', (tester) async {
    for (final scenario in [
      (status: 'assigned', scheduled: false, badge: 'PENDING', dateLabel: 'Deadline', date: 'Oct 31, 2026'),
      (status: 'assigned', scheduled: true, badge: 'SCHEDULED', dateLabel: 'Visit Date', date: 'Oct 21, 2026'),
      (status: 'in_progress', scheduled: true, badge: 'ONGOING', dateLabel: 'Deadline', date: 'Oct 31, 2026'),
    ]) {
      await tester.runAsync(() => cacheAssignments(status: scenario.status, selfScheduled: scenario.scheduled));
      await mountHome(tester);
      expect(textOnCard(applicant), findsOneWidget);
      expect(textOnCard('Fictional Barangay'), findsOneWidget);
      expect(textOnCard(scenario.badge), findsOneWidget);
      expect(textOnCard(scenario.dateLabel), findsOneWidget);
      expect(textOnCard(scenario.date), findsOneWidget);
      expect(textOnCard('STEP ${scenario.status == 'in_progress' ? 1 : 0}/6'), findsOneWidget);
      expect(textOnCard('FIXTURE-R2'), findsNothing,
        reason: 'Reference metadata remains in Task Details, not the carousel artwork.');
      await tester.ensureVisible(textOnCard(applicant));
      await tester.tap(textOnCard(applicant));
      await tester.pumpAndSettle();
      final overview = tester.widget<ParcelDetailScreen>(find.byType(ParcelDetailScreen));
      expect(overview.task.id, offlineRound2);
      expect(overview.task.inspectionRoundNumber, 2);
      expect(overview.task.previousSiteInspectionId, 101);
      expect(overview.task.inspectionNo, 'FIXTURE-R2');
      expect(overview.relatedRounds.map((round) => round.id).toSet(), {offlineJob, offlineRound2});
      expect(fixture.remoteWrites, 0);
      expect(tester.takeException(), isNull);
      await fixture.unmount(tester);
    }
  });

  fixture.widgetTest('Reopened SQLite draft drives card progress without completing queued work', (tester) async {
    await tester.runAsync(() async {
      await cacheAssignments(status: 'in_progress');
      await DBHelper.saveInspectionStep(offlineRound2, 5, {'5': '2026-10-14T12:00:00Z'}, offlineInspector);
      await DBHelper.enqueueAction(id: 'fictional-r2-submit', type: 'submit_inspection', jobId: offlineRound2,
        payload: {'inspectorId': offlineInspector, 'currentStep': 5});
      await fixture.restartDatabase();
    });
    for (final scenario in [
      (size: const Size(390, 844), scale: TextScaler.noScaling),
      (size: const Size(320, 568), scale: const TextScaler.linear(2)),
      (size: const Size(844, 390), scale: const TextScaler.linear(2)),
      (size: const Size(320, 568), scale: const _Android200TextScaler()),
    ]) {
      await mountHome(tester, size: scenario.size, scaler: scenario.scale);
      expect(textOnCard('STEP 5/6'), findsOneWidget);
      expect(textOnCard('ONGOING'), findsOneWidget);
      expect(textOnCard('COMPLETED'), findsNothing);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(card);
      for (final label in [applicant, 'Fictional Barangay', 'Deadline', 'Oct 31, 2026', 'STEP 5/6']) {
        final text = textOnCard(label);
        final rect = tester.getRect(text);
        expect(rect.top, greaterThanOrEqualTo(bounds.top), reason: '$label at ${scenario.size}/${scenario.scale}');
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom), reason: '$label at ${scenario.size}/${scenario.scale}');
        await tester.ensureVisible(text);
        await tester.pump();
        expect(text.hitTestable(), findsOneWidget);
      }
      await fixture.capture(tester, 'fs06-card-${scenario.size.width.toInt()}-${scenario.scale.runtimeType}-${scenario.scale.scale(12)}');
      expect(tester.takeException(), isNull);
      await fixture.unmount(tester);
    }
    final actions = (await tester.runAsync(DBHelper.getSyncCenterQueueActions))!
        .where((action) => action['job_id'] == offlineRound2);
    expect(actions.single['id'], 'fictional-r2-submit');
    expect(actions.single['status'], 'pending');
    expect(fixture.remoteWrites, 0);
  });

  fixture.widgetTest('Foreign-owner draft and completed R1 cannot supply R2 card progress', (tester) async {
    await tester.runAsync(() async {
      await cacheAssignments(status: 'assigned');
      await fixture.db.insert('local_inspections', {'id': offlineRound2,
        'inspector_id': otherOfflineInspector, 'current_step': 6});
    });
    await mountHome(tester);
    expect(textOnCard('STEP 0/6'), findsOneWidget);
    expect(textOnCard('STEP 6/6'), findsNothing);
    expect(textOnCard('PENDING'), findsOneWidget);
    expect(await tester.runAsync(() => DBHelper.getLocalInspection(offlineRound2)), isNull);
    expect((await tester.runAsync(() => fixture.db.query('local_inspections',
      where: 'id = ?', whereArgs: [offlineRound2])))!.single['current_step'], 6);
    expect(fixture.remoteWrites, 0);
    expect(tester.takeException(), isNull);
  });
}
