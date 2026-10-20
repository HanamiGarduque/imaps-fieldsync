import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Map<String, bool> answers(InspectionProvider provider) => {
    ...provider.siteCondition,
    ...provider.zoningObservations,
  };

  void observations() => fixture.provider.updateFindings(
    actualLandUse: 'Fictional observed residential use',
    notes:
        'A fictional workshop occupies the rear room.\nAccess was inspected.',
    discrepancies:
        'The rear room is used as a workshop, unlike the declared residence.',
    recommendations: 'Planning Officer to review the declared use.',
    boundaryStatus: 'Verified on-site — fictional GPS record',
  );

  test('fresh inspection has five unverified criteria and no assessment', () {
    expect(answers(fixture.provider), hasLength(5));
    expect(answers(fixture.provider).values.where((v) => v), isEmpty);
    expect(fixture.provider.inspectionResult, isEmpty);
    expect(
      fixture.provider.discrepancies,
      isEmpty,
      reason: 'unchecked answers never manufacture a discrepancy',
    );
  });

  test(
    'a step-only legacy draft does not invent a discrepancy assessment',
    () async {
      await DBHelper.saveInspectionStep(offlineJob, 3, {
        '3': '2026-10-20T01:00:00Z',
      }, offlineInspector);
      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);
      expect(restored.currentStep, 3);
      expect(restored.inspectionResult, isEmpty);
      expect(restored.discrepancies, isEmpty);
    },
  );

  test(
    'explicit saved assessment and exact boolean/text evidence survive restart',
    () async {
      observations();
      fixture.provider.updateResult('For Review');
      fixture.provider.setSiteCondition('Structure matches declared use', true);
      fixture.provider.setSiteCondition('Setback distances compliant', false);
      fixture.provider.setZoningObservation(
        'Accessibility & road frontage',
        false,
      );
      fixture.provider.setZoningObservation(
        'Surrounding developments noted',
        true,
      );
      fixture.provider.setZoningObservation(
        'Signage / commercial activity present',
        false,
      );
      final expected = Map<String, bool>.of(answers(fixture.provider));
      await fixture.provider.saveAllInspectionState(syncOnline: false);
      await fixture.restartDatabase();
      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);
      expect(answers(restored), expected);
      expect(restored.inspectionResult, 'For Review');
      expect(restored.notes, fixture.provider.notes);
      expect(restored.discrepancies, fixture.provider.discrepancies);
      expect(restored.recommendations, fixture.provider.recommendations);
      expect(restored.observations, fixture.provider.observations);
    },
  );

  for (final result in ['For Review', 'Requires Reinspection']) {
    test(
      'rework preserves $result without inventing a non-compliant boundary',
      () {
        final task = TaskItem(
          id: offlineJob,
          name: 'Fictional site',
          parcels: '1',
          location: 'Fictional location',
          status: 'completed',
          inspectionNo: 'DEMO',
          inspectionResult: result,
          isCompliant: false,
          discrepancies: 'Recorded explanation for a follow-up assessment.',
          observations: 'Preserved opaque GPS/site observations',
          checklistData: const [
            {'item': 'Structure matches declared use', 'checked': false},
            {'item': 'Accessibility & road frontage', 'checked': true},
          ],
        );
        fixture.provider.hydrateForRework(task);
        expect(fixture.provider.inspectionResult, result);
        expect(fixture.provider.boundaryStatus, isNot('Non-compliant'));
        expect(fixture.provider.observations, task.observations);
        expect(
          fixture.provider.siteCondition['Structure matches declared use'],
          false,
        );
        expect(
          fixture.provider.zoningObservations['Accessibility & road frontage'],
          true,
        );
      },
    );
  }

  test(
    'normal Step 4 saves an owner-scoped SQLite snapshot before returning',
    () async {
      fixture.provider.setSiteCondition(
        'Structure matches declared use',
        false,
      );
      fixture.provider.setZoningObservation(
        'Surrounding developments noted',
        true,
      );
      final expected = Map<String, bool>.of(answers(fixture.provider));
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      final saved = await DBHelper.getLocalInspection(offlineJob);
      expect(saved, isNotNull);
      expect(saved!['inspector_id'], offlineInspector);
      final checklist = Map<String, dynamic>.from(
        jsonDecode(saved['checklist_json'] as String),
      );
      for (final entry in expected.entries) {
        expect(checklist[entry.key], entry.value);
      }
      await fixture.restartDatabase();
      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);
      expect(answers(restored), expected);
      expect(restored.inspectionResult, isEmpty);
      expect(fixture.remoteWrites, 0);
    },
  );

  test(
    'normal Step 5 saves complete findings before returning, not only a queue row',
    () async {
      observations();
      expect(await fixture.provider.saveStepFindings(), isTrue);
      final saved = await DBHelper.getLocalInspection(offlineJob);
      expect(saved, isNotNull);
      final snapshot = jsonDecode(saved!['checklist_json'] as String) as Map;
      final findings = snapshot[DBHelper.inspectionDraftFindingsKey] as Map;
      expect(findings['discrepancies'], fixture.provider.discrepancies);
      expect(findings['recommendations'], fixture.provider.recommendations);
      expect(findings['observations'], fixture.provider.observations);
      expect(saved['notes'], fixture.provider.notes);
      await fixture.restartDatabase();
      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);
      expect(restored.notes, fixture.provider.notes);
      expect(restored.discrepancies, fixture.provider.discrepancies);
      expect(restored.recommendations, fixture.provider.recommendations);
      expect(fixture.remoteWrites, 0);
    },
  );

  for (final step in [4, 5]) {
    test(
      'Step $step cannot report durable success when SQLite rejects the snapshot',
      () async {
        observations();
        await fixture.db.execute(
          "CREATE TRIGGER reject_snapshot BEFORE INSERT ON local_inspections BEGIN SELECT RAISE(ABORT, 'isolated disk failure'); END",
        );
        final ok = step == 4
            ? await fixture.provider.saveStepChecklist()
            : await fixture.provider.saveStepFindings();
        expect(ok, isFalse);
        expect(await DBHelper.getLocalInspection(offlineJob), isNull);
        expect(fixture.provider.discrepancies, isNotEmpty);
      },
    );

    fixture.widgetTest(
      'Step $step storage failure keeps the current screen and evidence',
      (tester) async {
        observations();
        await tester.runAsync(
          () => fixture.db.execute(
            "CREATE TRIGGER reject_snapshot BEFORE INSERT ON local_inspections BEGIN SELECT RAISE(ABORT, 'isolated disk failure'); END",
          ),
        );
        InspectionProgress.instance.ensureActiveInspection(
          offlineJob,
          initialStep: step - 1,
        );
        await fixture.mount(
          tester,
          step == 4
              ? InspectionChecklistScreen(task: offlineTask)
              : FieldFindingsScreen(task: offlineTask),
        );
        await tester.tap(
          find.text(step == 4 ? 'Continue to Findings' : 'Continue to Review'),
        );
        await fixture.flush(tester);
        await tester.pump(const Duration(milliseconds: 400));
        await fixture.flush(tester);
        expect(
          find.byType(
            step == 4 ? InspectionChecklistScreen : FieldFindingsScreen,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(step == 4 ? FieldFindingsScreen : ReviewSubmitScreen),
          findsNothing,
        );
        expect(find.textContaining('Could not save'), findsWidgets);
        expect(fixture.provider.discrepancies, isNotEmpty);
        expect(InspectionProgress.instance.highestCompleted, step - 1);
      },
    );
  }

  fixture.widgetTest(
    'Step 5 400 ms autosave persists without lifecycle flush and survives a hard restart',
    (tester) async {
      const typed = 'Fictional draft typed before an abrupt process kill';
      await fixture.mount(tester, FieldFindingsScreen(task: offlineTask));
      Future<String?> draftNotes() async {
        final snapshot = await DBHelper.getLocalInspection(offlineJob);
        return snapshot?['notes'] as String?;
      }

      await tester.enterText(
        find.widgetWithText(TextField, 'Site observations'),
        typed,
      );
      await fixture.flush(tester);
      expect(
        await tester.runAsync(draftNotes),
        isNot(typed),
        reason: 'typing alone must not write before the debounce elapses',
      );

      // The timer is 400 ms. Nothing here pumps a longer frame or sends a
      // lifecycle event, so only the timer itself can make the first write.
      await tester.pump(const Duration(milliseconds: 399));
      await fixture.flush(tester);
      expect(
        await tester.runAsync(draftNotes),
        isNot(typed),
        reason: 'the autosave timer must not fire early',
      );

      await tester.pump(const Duration(milliseconds: 1));
      await fixture.flush(tester);
      await fixture.flush(tester);
      expect(
        await tester.runAsync(draftNotes),
        typed,
        reason: 'the timer must persist the snapshot without dispose/lifecycle',
      );

      // Let the queued findings update finish, then simulate an abrupt kill:
      // the screen is never unmounted and no lifecycle callback is sent. The
      // reopened SQLite file is the only source for the next provider.
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          final rows = await fixture.db.query(
            'pending_actions',
            where: "type = 'findings_update'",
          );
          if (rows.isNotEmpty && !SyncOutboxService.isDraining) return;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.runAsync(fixture.restartDatabase);
      final restored = InspectionProvider();
      await tester.runAsync(() => restored.startInspection(offlineTask));
      expect(restored.notes, typed);
      expect(restored.inspectionResult, isEmpty);
      restored.dispose();
    },
  );

  fixture.widgetTest(
    'Continue waits for the actual SQLite transaction before navigating',
    (tester) async {
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        initialStep: 3,
      );
      await fixture.mount(tester, InspectionChecklistScreen(task: offlineTask));
      late Completer<void> release;
      late Future<void> held;
      await tester.runAsync(() async {
        final entered = Completer<void>();
        release = Completer<void>();
        held = fixture.db.transaction((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
      });
      try {
        await tester.tap(find.text('Continue to Findings'));
        await fixture.flush(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(FieldFindingsScreen),
          findsNothing,
          reason:
              'queued remote work cannot stand in for a completed local transaction',
        );
        expect(InspectionProgress.instance.highestCompleted, 3);
      } finally {
        await tester.runAsync(() async {
          release.complete();
          await held;
        });
      }
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.flush(tester);
      expect(find.byType(FieldFindingsScreen), findsOneWidget);
      expect(
        await tester.runAsync(() => DBHelper.getLocalInspection(offlineJob)),
        isNotNull,
      );
    },
  );
}
