import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/structured_checklist.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  const explanation =
      'The rear room contains a fictional workshop rather than the declared residence.';
  void findings(String text) => fixture.provider.updateFindings(
    actualLandUse: fixture.provider.actualLandUse,
    notes: 'Fictional inspector observation',
    discrepancies: text,
    recommendations: 'Planning Officer to assess next steps.',
    boundaryStatus: fixture.provider.boundaryStatus,
  );
  Future<void> pressSubmit(WidgetTester tester) async {
    await tester.tap(find.text('Submit Inspection'));
    await fixture.flush(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await fixture.flush(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Confirm & Submit'));
    await fixture.flush(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await fixture.flush(tester);
  }

  /// Scrolls the review ListView until [target] can actually receive a tap.
  /// scrollUntilVisible alone can stop while the widget is still off-screen.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 12 && target.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -220),
        warnIfMissed: false,
      );
      await tester.pump();
    }
    await tester.ensureVisible(target);
    await tester.pump();
  }

  fixture.widgetTest(
    'Submit validates an unselected assessment instead of assuming Compliant',
    (tester) async {
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await pressSubmit(tester);
      expect(find.byType(SubmissionSuccessScreen), findsNothing);
      expect(find.textContaining('Choose an assessment'), findsWidgets);
      expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
    },
  );

  for (final result in [
    'With Discrepancy',
    'For Review',
    'Requires Reinspection',
  ]) {
    for (final reason in ['', ' \n\t ']) {
      fixture.widgetTest(
        '$result blocks ${reason.isEmpty ? 'blank' : 'whitespace-only'} explanation at Submit',
        (tester) async {
          findings(reason);
          fixture.provider.updateResult(result);
          await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
          await pressSubmit(tester);
          expect(find.byType(SubmissionSuccessScreen), findsNothing);
          expect(
            find.textContaining('Explain what you observed'),
            findsWidgets,
          );
          expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
          expect(fixture.provider.inspectionResult, result);
        },
      );
    }
  }

  fixture.widgetTest(
    'Compliant with discrepancy evidence requires correction without overriding the choice',
    (tester) async {
      findings(explanation);
      fixture.provider.updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await pressSubmit(tester);
      expect(find.byType(SubmissionSuccessScreen), findsNothing);
      expect(
        find.textContaining('does not match the recorded discrepancy'),
        findsWidgets,
      );
      expect(fixture.provider.inspectionResult, 'Compliant');
      expect(fixture.provider.discrepancies, explanation);
      expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
    },
  );

  for (final result in [
    'Compliant',
    'With Discrepancy',
    'For Review',
    'Requires Reinspection',
  ]) {
    fixture.widgetTest(
      '$result confirmation preserves the exact assessment and explanation offline',
      (tester) async {
        findings(result == 'Compliant' ? '' : explanation);
        fixture.provider.updateResult(result);
        await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
        await pressSubmit(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(of: dialog, matching: find.text(result)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('0 of 5 checked'),
          ),
          findsOneWidget,
          reason: 'unchecked alone is never a failed-compliance judgment',
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('0 photos'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('Planning Officer'),
          ),
          findsOneWidget,
        );
        expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
        await confirm(tester);
        expect(find.byType(SubmissionSuccessScreen), findsOneWidget);
        expect(find.text('Saved Offline'), findsOneWidget);
        final queued = (await tester.runAsync(
          DBHelper.getActionableActions,
        ))!.single;
        final payload = jsonDecode(queued['payload'] as String) as Map;
        expect(payload['inspectionResult'], result);
        expect(payload['isCompliant'], result == 'Compliant');
        expect(
          payload['discrepancies'],
          result == 'Compliant' ? null : explanation,
        );
        expect(payload['checklistData'], hasLength(5));
        expect(fixture.remoteWrites, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.restartDatabase);
        final restored = InspectionProvider();
        await tester.runAsync(() => restored.startInspection(offlineTask));
        expect(restored.inspectionResult, result);
        expect(
          restored.discrepancies,
          result == 'Compliant' ? '' : explanation,
        );
        restored.dispose();
      },
    );
  }

  fixture.widgetTest(
    'enabled structured answers reach the final submission once',
    (tester) async {
      StructuredChecklist.remoteTransmissionEnabledForTesting = true;
      addTearDown(() {
        StructuredChecklist.remoteTransmissionEnabledForTesting = null;
      });
      fixture.provider
        ..setSiteCondition('Structure matches declared use', true)
        ..setStructuredAnswer(
          StructuredChecklist.existingDevelopment,
          StructuredChecklist.yes,
        )
        ..setStructuredAnswer(
          StructuredChecklist.existingUse,
          'Fictional clinic',
        )
        ..updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await pressSubmit(tester);
      await confirm(tester);

      final queued = (await tester.runAsync(
        DBHelper.getActionableActions,
      ))!.single;
      final payload = jsonDecode(queued['payload'] as String) as Map;
      expect(payload['checklistCompletedCount'], 1);
      expect(payload['checklistTotalCount'], 5);
      final data = payload['checklistData'] as List;
      expect(data, hasLength(7));
      final items = data.map((entry) => (entry as Map)['item']).toList();
      expect(items.toSet(), hasLength(items.length));
      expect(data.last, {
        'item':
            StructuredChecklist.questionLabels[StructuredChecklist.existingUse],
        'answer': 'Fictional clinic',
      });
    },
  );

  fixture.widgetTest('cancel confirmation sends no business submission', (
    tester,
  ) async {
    fixture.provider.updateResult('Compliant');
    await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
    await pressSubmit(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await fixture.flush(tester);
    expect(find.byType(ReviewSubmitScreen), findsOneWidget);
    expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
    expect(fixture.remoteWrites, 0);
  });

  for (final code in ['42501', '23514']) {
    fixture.widgetTest(
      'server $code rejection preserves the draft but never announces acceptance/offline success',
      (tester) async {
        fixture.provider.updateResult('Compliant');
        SyncOutboxService.hasConnectionOverride = () async => true;
        fixture.online = true;
        fixture.requestOverride = (request) async {
          if (!request.url.path.contains('field_jobs')) return null;
          final data = request.method == 'GET'
              ? [
                  {
                    'id': offlineJob,
                    'assigned_inspector_id': offlineInspector,
                    'status': 'in_progress',
                    'current_step': 5,
                  },
                ]
              : {
                  'code': code,
                  'message': 'Fictional known permanent rejection',
                };
          return http.Response(
            jsonEncode(data),
            request.method == 'GET' ? 200 : 400,
            headers: {'content-type': 'application/json'},
          );
        };
        await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
        await pressSubmit(tester);
        // Before the fix there is no confirmation and the rejection is already
        // misreported as Saved Offline. Let the failure catch that exact branch.
        if (find.text('Confirm & Submit').evaluate().isNotEmpty) {
          await confirm(tester);
        }
        expect(find.byType(SubmissionSuccessScreen), findsNothing);
        expect(find.byType(ReviewSubmitScreen), findsOneWidget);
        expect(find.textContaining('not accepted'), findsWidgets);
        expect(
          await tester.runAsync(() => DBHelper.getLocalInspection(offlineJob)),
          isNotNull,
        );
        final rows = (await tester.runAsync(
          DBHelper.getSyncCenterQueueActions,
        ))!;
        expect(rows.single['status'], 'paused');
        expect(
          await tester.runAsync(() => DBHelper.getRecentSyncedActions()),
          isEmpty,
        );
      },
    );
  }

  fixture.widgetTest(
    'selection and the shared Step 5 explanation survive interruption before Submit',
    (tester) async {
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      final choice = find.text('For Review');
      await reveal(tester, choice);
      await tester.tap(choice);
      final field = find.byKey(const ValueKey('assessment-explanation'));
      await reveal(tester, field);
      await tester.enterText(field, explanation);
      await fixture.flush(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.restartDatabase);
      final restored = InspectionProvider();
      await tester.runAsync(() => restored.startInspection(offlineTask));
      expect(restored.inspectionResult, 'For Review');
      expect(restored.discrepancies, explanation);
      expect(await tester.runAsync(DBHelper.getActionableActions), isEmpty);
      restored.dispose();
    },
  );
}
