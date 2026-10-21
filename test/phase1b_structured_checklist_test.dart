import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/structured_checklist.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// CE-05 — Step 4 Project Status / Zoning Observations.
///
/// This file keeps the local persistence, rework, ownership and R1/R2 proof.
/// CE-05T owns the serialized remote contract and its default-off transmission
/// gate in `ce05t_structured_transmission_test.dart`.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Map<String, dynamic> storedChecklist(Map<String, dynamic> row) =>
      jsonDecode(row['checklist_json'] as String) as Map<String, dynamic>;

  Map<String, String> storedStructured(Map<String, dynamic> row) =>
      (storedChecklist(row)[StructuredChecklist.jsonKey] as Map?)
          ?.cast<String, String>() ??
      {};

  Future<Map<String, dynamic>> checklistAction() async {
    final rows = await fixture.db.query(
      'pending_actions',
      where: 'job_id = ? AND type = ?',
      whereArgs: [offlineJob, 'checklist_update'],
    );
    return jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
  }

  group('structured model', () {
    test('unanswered is not No and both are distinguishable', () {
      expect(StructuredChecklist.activeAnswers(const {}), isEmpty);
      expect(
        StructuredChecklist.reviewRows(const {}).first.value,
        'Not recorded',
      );
      expect(
        StructuredChecklist.reviewRows(const {
          StructuredChecklist.existingDevelopment: StructuredChecklist.no,
        }).first.value,
        'No',
      );
    });

    test('all supported states round-trip; unknown tokens are dropped', () {
      for (final option in StructuredChecklist.triStateLabels.keys) {
        final decoded = StructuredChecklist.decode({
          StructuredChecklist.existingDevelopment: option,
          'unknown.key': option,
          StructuredChecklist.mojonObserved: 'checked',
        });
        expect(
          decoded[StructuredChecklist.existingDevelopment],
          option,
          reason: 'tri-state option $option must survive',
        );
        expect(decoded.containsKey('unknown.key'), isFalse);
        expect(
          decoded.containsKey(StructuredChecklist.mojonObserved),
          isFalse,
          reason: 'a boolean-style token is not a structured answer',
        );
      }
      expect(
        StructuredChecklist.decode(const {
          StructuredChecklist.extensionOfExisting:
              StructuredChecklist.notApplicable,
        })[StructuredChecklist.extensionOfExisting],
        StructuredChecklist.notApplicable,
      );
      expect(
        StructuredChecklist.decode(const {
          StructuredChecklist.treesPresent: StructuredChecklist.notApplicable,
        }),
        isEmpty,
        reason: 'Not Applicable is offered only for the extension question',
      );
    });

    test('conditional children are active only while the parent is Yes', () {
      final answers = <String, String?>{
        StructuredChecklist.existingDevelopment: StructuredChecklist.no,
        StructuredChecklist.existingUse: 'Stale declared use',
        StructuredChecklist.proposalStage: StructuredChecklist.no,
        StructuredChecklist.treesPresent: StructuredChecklist.yes,
        StructuredChecklist.canalWaterway: StructuredChecklist.no,
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.mojonObserved: StructuredChecklist.unable,
      };
      final active = StructuredChecklist.activeAnswers(answers);
      expect(active.containsKey(StructuredChecklist.existingUse), isFalse);
      expect(active.containsKey(StructuredChecklist.treesPresent), isFalse);
      expect(active.containsKey(StructuredChecklist.canalWaterway), isFalse);
      expect(
        active[StructuredChecklist.extensionOfExisting],
        StructuredChecklist.notApplicable,
      );
      expect(
        active[StructuredChecklist.mojonObserved],
        StructuredChecklist.unable,
      );
    });

    test('review rows follow the agreed order and hide inactive children', () {
      final rows = StructuredChecklist.reviewRows({
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: 'Fictional clinic',
        StructuredChecklist.extensionOfExisting: StructuredChecklist.no,
        StructuredChecklist.proposalStage: StructuredChecklist.yes,
        StructuredChecklist.treesPresent: StructuredChecklist.yes,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: StructuredChecklist.no,
      });
      expect(rows.map((row) => row.label).toList(), [
        'Existing project or development on site',
        "Existing project's declared use",
        'Extension of an existing structure',
        'Still at the project proposal stage',
        'Trees present on the lot',
        'Canal or waterway on or adjoining the lot',
        'Existing mojon or property marker observed',
      ]);
      expect(rows.map((row) => row.value).toList(), [
        'Yes',
        'Fictional clinic',
        'No',
        'Yes',
        'Yes',
        'Unable to Verify',
        'No',
      ]);
    });
  });

  test(
    'every recorded state persists, restores after restart and keeps legacy counts',
    () async {
      fixture.provider.setSiteCondition('Structure matches declared use', true);
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingUse,
        '  Fictional residential  ',
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.extensionOfExisting,
        StructuredChecklist.notApplicable,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.proposalStage,
        StructuredChecklist.no,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.treesPresent,
        StructuredChecklist.yes,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        StructuredChecklist.unable,
      );

      expect(await fixture.provider.saveStepChecklist(), isTrue);

      final checklist = storedChecklist(
        (await DBHelper.getLocalInspection(offlineJob))!,
      );
      expect(checklist[StructuredChecklist.jsonKey], {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: 'Fictional residential',
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.proposalStage: StructuredChecklist.no,
        StructuredChecklist.mojonObserved: StructuredChecklist.unable,
      });
      expect(checklist['Structure matches declared use'], isTrue);

      final payload = await checklistAction();
      expect(payload['checklistCompletedCount'], 1);
      expect(payload['checklistTotalCount'], 5);
      final data = payload['checklistData'] as List;
      expect(data, hasLength(5));
      for (final entry in data) {
        expect(
          (entry as Map).keys.toSet(),
          {'item', 'checked'},
          reason: 'the remote checklist contract stays legacy-only',
        );
      }
      expect(jsonEncode(data), isNot(contains('_structured')));

      await fixture.restartDatabase();
      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);

      expect(
        restored.structuredAnswers[StructuredChecklist.existingDevelopment],
        StructuredChecklist.yes,
      );
      expect(
        restored.structuredAnswers[StructuredChecklist.existingUse],
        'Fictional residential',
      );
      expect(
        restored.structuredAnswers[StructuredChecklist.extensionOfExisting],
        StructuredChecklist.notApplicable,
      );
      expect(
        restored.structuredAnswers[StructuredChecklist.proposalStage],
        StructuredChecklist.no,
      );
      expect(
        restored.structuredAnswers[StructuredChecklist.mojonObserved],
        StructuredChecklist.unable,
      );
      expect(restored.siteCondition['Structure matches declared use'], isTrue);
    },
  );

  test(
    'hidden conditional answers stay in memory but are never persisted or submitted',
    () async {
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingUse,
        'Fictional shop',
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.proposalStage,
        StructuredChecklist.no,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.treesPresent,
        StructuredChecklist.yes,
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);

      var checklist = storedChecklist(
        (await DBHelper.getLocalInspection(offlineJob))!,
      );
      expect(
        (checklist[StructuredChecklist.jsonKey] as Map).containsKey(
          StructuredChecklist.treesPresent,
        ),
        isFalse,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.treesPresent],
        StructuredChecklist.yes,
        reason: 'the in-session edit is preserved for re-selection',
      );
      expect(
        jsonEncode((await checklistAction())['checklistData']),
        isNot(contains('trees')),
      );

      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.no,
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      checklist = storedChecklist(
        (await DBHelper.getLocalInspection(offlineJob))!,
      );
      final structured = (checklist[StructuredChecklist.jsonKey] as Map?)
          ?.cast<String, String>();
      expect(
        structured?.containsKey(StructuredChecklist.existingUse),
        isFalse,
        reason: 'a hidden declared use must not survive in the draft',
      );
    },
  );

  test(
    'a pre-CE05 checklist restores unchanged and saves back as legacy',
    () async {
      await DBHelper.saveInspectionLocally(
        jobId: offlineJob,
        expectedInspectorId: offlineInspector,
        actualLandUse: 'Single-detached residential',
        notes: 'Legacy notes',
        isCompliant: false,
        inspectionResult: '',
        checklist: const {
          'Structure matches declared use': true,
          'Setback distances compliant': false,
          'Accessibility & road frontage': false,
          'Surrounding developments noted': false,
          'Signage / commercial activity present': false,
        },
        boundaryStatus: 'Not recorded',
        currentStep: 4,
        findings: const {
          'discrepancies': '',
          'recommendations': '',
          'observations': 'Legacy observation',
        },
      );

      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(offlineTask);

      expect(restored.siteCondition['Structure matches declared use'], isTrue);
      expect(restored.structuredAnswers, isEmpty);
      expect(await restored.saveStepChecklist(), isTrue);

      final checklist = storedChecklist(
        (await DBHelper.getLocalInspection(offlineJob))!,
      );
      expect(checklist.containsKey(StructuredChecklist.jsonKey), isFalse);
      expect(
        checklist[DBHelper.inspectionDraftFindingsKey],
        isNotNull,
        reason: 'legacy findings are preserved',
      );
      final payload = await checklistAction();
      expect(payload['checklistCompletedCount'], 1);
      expect(payload['checklistTotalCount'], 5);
    },
  );

  test(
    'another inspector sees no structured answers and cannot write them',
    () async {
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        StructuredChecklist.yes,
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);

      DBHelper.inspectorIdForTesting = otherOfflineInspector;
      try {
        expect(fixture.provider.structuredAnswers, isEmpty);
        expect(
          () => fixture.provider.setStructuredAnswer(
            StructuredChecklist.mojonObserved,
            StructuredChecklist.no,
          ),
          throwsStateError,
        );
        expect(await DBHelper.getLocalInspection(offlineJob), isNull);
      } finally {
        DBHelper.inspectorIdForTesting = null;
      }
    },
  );

  test('R1 and R2 drafts keep their own structured answers', () async {
    fixture.provider.setStructuredAnswer(
      StructuredChecklist.existingDevelopment,
      StructuredChecklist.yes,
    );
    expect(
      await fixture.provider.saveAllInspectionState(syncOnline: false),
      isTrue,
    );

    final round2 = InspectionProvider();
    addTearDown(round2.dispose);
    await round2.startInspection(
      TaskItem(
        id: offlineRound2,
        parcelId: 'fictional-parcel-2',
        name: 'Fictional round 2',
        location: 'Isolated fixture only',
        parcels: '1',
        status: 'assigned',
        inspectionNo: 'DEMO-FS04-R2',
      ),
    );
    expect(round2.structuredAnswers, isEmpty);
    round2.setStructuredAnswer(
      StructuredChecklist.existingDevelopment,
      StructuredChecklist.no,
    );
    round2.setStructuredAnswer(
      StructuredChecklist.mojonObserved,
      StructuredChecklist.unable,
    );
    expect(await round2.saveAllInspectionState(syncOnline: false), isTrue);

    final round1 = storedStructured(
      (await DBHelper.getLocalInspection(offlineJob))!,
    );
    final round2Stored = storedStructured(
      (await DBHelper.getLocalInspection(offlineRound2))!,
    );
    expect(
      round1[StructuredChecklist.existingDevelopment],
      StructuredChecklist.yes,
    );
    expect(
      round2Stored[StructuredChecklist.existingDevelopment],
      StructuredChecklist.no,
    );
    expect(round1.containsKey(StructuredChecklist.mojonObserved), isFalse);
    expect(
      round2Stored[StructuredChecklist.mojonObserved],
      StructuredChecklist.unable,
    );
  });

  test(
    'rework reset exposes no prior answers, then restores this job local draft',
    () async {
      fixture.provider.setSiteCondition('Structure matches declared use', true);
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingUse,
        'Fictional clinic',
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);

      final completed = TaskItem(
        id: offlineJob,
        parcelId: 'fictional-parcel',
        name: 'Fictional site',
        location: 'Isolated fixture only',
        parcels: '1',
        status: 'completed',
        inspectionNo: 'DEMO-FS04',
        inspectionResult: 'For Review',
        checklistData: [
          {'item': 'Structure matches declared use', 'checked': true},
          {'item': 'Accessibility & road frontage', 'checked': false},
        ],
      );
      fixture.provider.hydrateForRework(completed);
      expect(
        fixture.provider.structuredAnswers,
        isEmpty,
        reason: 'another session must not leak before the owned draft is read',
      );
      expect(
        fixture.provider.siteCondition['Structure matches declared use'],
        isTrue,
      );

      await fixture.provider.restoreStructuredChecklist();
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist
            .existingDevelopment],
        StructuredChecklist.yes,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        'Fictional clinic',
      );

      final round1 = storedStructured(
        (await DBHelper.getLocalInspection(offlineJob))!,
      );
      expect(
        round1[StructuredChecklist.existingUse],
        'Fictional clinic',
        reason: 'completed local evidence is preserved across rework hydration',
      );
    },
  );

  test('structured remote transmission stays disabled after CE-06', () {
    expect(StructuredChecklist.remoteTransmissionEnabled, isFalse);
    expect(StructuredChecklist.isRemoteTransmissionEnabled, isFalse);

    final payload = StructuredChecklist.remoteChecklist(
      legacy: const {'Legacy question': true},
      answers: const {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
      },
    );
    expect(payload, [
      {'item': 'Legacy question', 'checked': true},
    ]);
  });

  Future<void> chooseOption(
    WidgetTester tester,
    String key,
    String label,
  ) async {
    final field = find.byKey(ValueKey('structured_$key'));
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await fixture.flush(tester);
  }

  fixture.widgetTest(
    'Step 4 conditional questions flow through Steps 5 and 6',
    (tester) async {
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        initialStep: 3,
      );
      await fixture.mount(tester, InspectionChecklistScreen(task: offlineTask));

      expect(
        find.byKey(const ValueKey('structured_existing_use_input')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('structured_project_status.trees_present')),
        findsNothing,
      );

      await chooseOption(
        tester,
        StructuredChecklist.existingDevelopment,
        'Yes',
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist
            .existingDevelopment],
        StructuredChecklist.yes,
        reason: 'current answers: ${fixture.provider.structuredAnswers}',
      );
      expect(
        find.byKey(const ValueKey('structured_existing_use_input')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('structured_existing_use_input')),
        'Fictional residential',
      );
      await tester.pump();

      await chooseOption(
        tester,
        StructuredChecklist.extensionOfExisting,
        'Not Applicable',
      );
      await chooseOption(tester, StructuredChecklist.proposalStage, 'Yes');
      expect(
        find.byKey(const ValueKey('structured_project_status.trees_present')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('structured_project_status.canal_waterway')),
        findsOneWidget,
      );

      await chooseOption(tester, StructuredChecklist.treesPresent, 'Yes');
      await chooseOption(tester, StructuredChecklist.canalWaterway, 'No');
      await chooseOption(
        tester,
        StructuredChecklist.mojonObserved,
        'Unable to Verify',
      );

      await tester.tap(find.text('Continue to Findings'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.flush(tester);
      expect(find.byType(FieldFindingsScreen), findsOneWidget);
      Finder inFindings(String text) => find.descendant(
        of: find.byType(FieldFindingsScreen),
        matching: find.text(text),
      );
      expect(inFindings('Site conditions & project status'), findsOneWidget);
      expect(inFindings('Not Applicable'), findsOneWidget);
      expect(inFindings('Unable to Verify'), findsOneWidget);
      expect(
        inFindings(
          'A marker observation does not certify cadastral boundaries.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Continue to Review'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.flush(tester);
      expect(find.byType(ReviewSubmitScreen), findsOneWidget);
      Finder inReview(String text) => find.descendant(
        of: find.byType(ReviewSubmitScreen),
        matching: find.text(text),
      );
      expect(inReview('Project status & zoning observations'), findsOneWidget);
      expect(inReview('Not Applicable'), findsOneWidget);
      expect(inReview('Unable to Verify'), findsOneWidget);
      expect(inReview("Existing project's declared use"), findsOneWidget);
      expect(inReview('Fictional residential'), findsOneWidget);
    },
  );

  fixture.widgetTest(
    'back navigation keeps Step 4 answers and the local draft',
    (tester) async {
      InspectionProgress.instance.ensureActiveInspection(
        offlineJob,
        initialStep: 3,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      );
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.existingUse,
        'Fictional clinic',
      );
      await fixture.mount(tester, InspectionChecklistScreen(task: offlineTask));
      expect(find.text('Fictional clinic'), findsOneWidget);

      await tester.tap(find.text('Continue to Findings'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.flush(tester);
      expect(find.byType(FieldFindingsScreen), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await fixture.flush(tester);

      expect(find.byType(FieldFindingsScreen), findsNothing);
      expect(find.byType(InspectionChecklistScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InspectionChecklistScreen),
          matching: find.text('Fictional clinic'),
        ),
        findsOneWidget,
      );

      final row = await tester.runAsync(
        () => DBHelper.getLocalInspection(offlineJob),
      );
      final checklist = storedChecklist(row!);
      expect(
        (checklist[StructuredChecklist.jsonKey]
            as Map)[StructuredChecklist.existingUse],
        'Fictional clinic',
        reason: 'navigating back must not lose the durable draft',
      );
    },
  );
}
