import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// Batch 3: Steps 3, 4 and 5 are independent. Once Step 2 is verified the
/// inspector may complete them in any order, and every step keeps its own
/// real completion.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  void hydrate({
    int initialStep = 0,
    Map<String, String> times = const <String, String>{},
  }) {
    InspectionProgress.instance.ensureActiveInspection(
      offlineJob,
      label: 'Flexible fixture',
      initialStep: initialStep,
      stepTimestamps: times,
    );
  }

  /// Lets the queued durable step write finish.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  /// Completes the sequential prefix exactly as the app does, so the stored
  /// per-step times carry steps 1 and 2.
  Future<void> completeStepsOneAndTwo() async {
    InspectionProgress.instance.markStepComplete(1);
    InspectionProgress.instance.markStepComplete(2);
    await settle();
  }

  test('steps 3, 4 and 5 complete in any order once step 2 is verified', () async {
    const orders = [
      [3, 4, 5],
      [4, 3, 5],
      [5, 4, 3],
      [3, 5, 4],
    ];
    for (final order in orders) {
      InspectionProgress.instance.reset();
      hydrate();
      await completeStepsOneAndTwo();
      for (final step in order) {
        InspectionProgress.instance.markStepComplete(step);
      }
      await settle();
      final progress = InspectionProgress.instance;
      expect(progress.isDone(3), isTrue, reason: 'order $order');
      expect(progress.isDone(4), isTrue, reason: 'order $order');
      expect(progress.isDone(5), isTrue, reason: 'order $order');
      expect(progress.completedStepCount, 5, reason: 'order $order');
      expect(progress.isLocked(6), isFalse, reason: 'order $order');
      expect(progress.currentStep, 6, reason: 'order $order');
      // The persisted current_step is the highest step reached and never
      // regresses, whatever order the steps were done in.
      final draft = await DBHelper.getLocalInspection(offlineJob);
      expect(draft?['current_step'], 5, reason: 'order $order');
      final times = jsonDecode(draft?['step_timestamps'] as String) as Map;
      expect(
        times.keys.map((key) => key.toString()).toSet(),
        containsAll(<String>{'1', '2', '3', '4', '5'}),
        reason: 'order $order',
      );
    }
  });

  test('an independent step is not complete just because a later one is', () async {
    InspectionProgress.instance.reset();
    hydrate();
    await completeStepsOneAndTwo();
    InspectionProgress.instance.markStepComplete(5);
    await settle();
    final progress = InspectionProgress.instance;
    expect(progress.isDone(5), isTrue);
    expect(progress.isDone(3), isFalse);
    expect(progress.isDone(4), isFalse);
    expect(progress.completedStepCount, 3);
    expect(progress.currentStep, 3);
    expect(progress.isLocked(6), isTrue);
  });

  test('steps 3 to 5 stay locked until step 2 is verified', () async {
    InspectionProgress.instance.reset();
    hydrate(initialStep: 1);
    expect(InspectionProgress.instance.isLocked(3), isTrue);
    expect(InspectionProgress.instance.isLocked(4), isTrue);
    expect(InspectionProgress.instance.isLocked(5), isTrue);
    InspectionProgress.instance.markStepComplete(4);
    await settle();
    expect(InspectionProgress.instance.isDone(4), isFalse);
  });

  test('opening a step never completes it', () async {
    InspectionProgress.instance.reset();
    hydrate();
    await completeStepsOneAndTwo();
    expect(InspectionProgress.instance.isDone(3), isFalse);
    expect(InspectionProgress.instance.isDone(4), isFalse);
    expect(InspectionProgress.instance.isDone(5), isFalse);
    expect(InspectionProgress.instance.completedStepCount, 2);
  });

  test('independent completion survives an offline restart', () async {
    InspectionProgress.instance.reset();
    hydrate();
    await completeStepsOneAndTwo();
    InspectionProgress.instance.markStepComplete(4);
    await settle();

    // Restart the app's storage and re-open the same inspection.
    await fixture.restartDatabase();
    final draft = await DBHelper.getLocalInspection(offlineJob);
    final times = jsonDecode(draft?['step_timestamps'] as String) as Map;
    InspectionProgress.instance.reset();
    hydrate(
      initialStep: draft?['current_step'] as int? ?? 0,
      times: times.map((k, v) => MapEntry(k.toString(), v as String)),
    );
    expect(InspectionProgress.instance.isDone(4), isTrue);
    expect(InspectionProgress.instance.isDone(3), isFalse);
    expect(InspectionProgress.instance.isDone(5), isFalse);
    expect(InspectionProgress.instance.completedStepCount, 3);
  });

  test('a sequential draft saved before the steps became independent still reads as complete', () async {
    InspectionProgress.instance.reset();
    hydrate(initialStep: 5);
    expect(InspectionProgress.instance.isDone(3), isTrue);
    expect(InspectionProgress.instance.isDone(4), isTrue);
    expect(InspectionProgress.instance.isDone(5), isTrue);

    InspectionProgress.instance.reset();
    hydrate(
      initialStep: 5,
      times: {
        '1': '2026-10-22T01:00:00.000Z',
        '2': '2026-10-22T02:00:00.000Z',
        '3': '2026-10-22T03:00:00.000Z',
        '4': '2026-10-22T04:00:00.000Z',
        '5': '2026-10-22T05:00:00.000Z',
      },
    );
    expect(InspectionProgress.instance.isDone(3), isTrue);
    expect(InspectionProgress.instance.isDone(4), isTrue);
    expect(InspectionProgress.instance.isDone(5), isTrue);
  });

  test('a later step never regresses the stored progress', () async {
    InspectionProgress.instance.reset();
    hydrate();
    await completeStepsOneAndTwo();
    InspectionProgress.instance.markStepComplete(5);
    await settle();
    InspectionProgress.instance.markStepComplete(3);
    await settle();
    final draft = await DBHelper.getLocalInspection(offlineJob);
    expect(draft?['current_step'], 5);
    final times = jsonDecode(draft?['step_timestamps'] as String) as Map;
    expect(times.containsKey('3'), isTrue);
    expect(times.containsKey('5'), isTrue);
  });

  test('one inspection never inherits another inspection progress', () async {
    InspectionProgress.instance.reset();
    hydrate();
    await completeStepsOneAndTwo();
    InspectionProgress.instance.markStepComplete(4);
    await settle();

    InspectionProgress.instance.reset();
    hydrate();
    expect(InspectionProgress.instance.isDone(4), isFalse);
    expect(InspectionProgress.instance.completedStepCount, 0);
  });

  fixture.widgetTest(
    'review refuses to submit while an independent step is unfinished',
    (tester) async {
      final raw = File('${fixture.directory.path}/camera.png')
        ..writeAsBytesSync([1, 2, 3]);
      fixture.provider.addPhoto(
        photoPath: raw.path,
        photoNotes: 'real camera photo',
        latitude: null,
        longitude: null,
      );
      InspectionProgress.instance.markStepComplete(1);
      InspectionProgress.instance.markStepComplete(2);
      InspectionProgress.instance.markStepComplete(4);
      await fixture.flush(tester);

      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await fixture.flush(tester);
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.textContaining('Complete the remaining inspection step'),
        findsWidgets,
      );
      expect(
        await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['submit_inspection'],
        ),
        isEmpty,
      );
    },
  );

  fixture.widgetTest(
    'review refuses to submit with only the generated reference as evidence',
    (tester) async {
      fixture.provider.addPhoto(
        photoPath: File('${fixture.directory.path}/camera.png').path,
        photoNotes: kReferenceNotes,
        latitude: 13.842512,
        longitude: 121.123456,
        isLocationReference: true,
      );
      InspectionProgress.instance.markStepComplete(1);
      InspectionProgress.instance.markStepComplete(2);
      InspectionProgress.instance.markStepComplete(3);
      InspectionProgress.instance.markStepComplete(4);
      InspectionProgress.instance.markStepComplete(5);
      await fixture.flush(tester);

      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await fixture.flush(tester);
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('at least one camera photo'), findsWidgets);
    },
  );
}

const kReferenceNotes = 'Site Location Reference';
