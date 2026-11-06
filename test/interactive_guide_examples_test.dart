import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_protocol_view.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_examples.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_read_only_data.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  fixture.widgetTest(
    'each fictional record, diagram, evidence and statistic carries its own sample label',
    (tester) async {
      await fixture.db.delete('local_jobs');
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: UserProfile.fromMap(offlineProfile),
          child: const Scaffold(),
        ),
      );
      await guide.start(GuideLanguage.tagalog);
      await fixture.flush(tester);
      var examples = 0;
      for (final stop in guideStops) {
        await tester.pumpAndSettle();
        for (final element in find.byType(GuideSample).evaluate()) {
          examples++;
          expect(
            find.descendant(
              of: find.byWidget(element.widget),
              matching: find.text(guideSampleLabel),
            ),
            findsAtLeastNWidgets(1),
            reason: stop.id,
          );
        }
        expect(tester.takeException(), isNull, reason: stop.id);
        guide.next();
      }
      expect(examples, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      guide.dispose();
    },
  );

  fixture.widgetTest(
    'actual overview retains six protocol titles and refuses their business callbacks',
    (tester) async {
      const titles = [
        'Site Verification',
        'GPS Verification',
        'Photographic Evidence',
        'Zoning Checklist',
        'Field Findings',
        'Review & Submit',
      ];
      final data = GuideReadOnlyData(
        ownerId: offlineInspector,
        language: GuideLanguage.english,
      );
      final before = await tester.runAsync(fixture.guideSafetySnapshot);
      await fixture.mount(
        tester,
        ParcelDetailScreen(
          task: TaskItem(
            id: '',
            name: guideExample.applicant,
            location: guideExample.location,
            parcels: '',
            status: 'assigned',
            inspectionNo: guideExample.reference,
          ),
          walkthrough: data,
        ),
      );
      await tester.pumpAndSettle();
      final protocol = tester.widget<InspectionProtocolView>(
        find.byType(InspectionProtocolView),
      );
      expect(protocol.steps.map((s) => s.title), titles);
      for (final step in protocol.steps) {
        step.onTap?.call();
      }
      await fixture.flush(tester);
      expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Submit'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  fixture.widgetTest(
    'the one sample target invokes only the guide-owned transition',
    (tester) async {
      await fixture.db.delete('local_jobs');
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final before = await tester.runAsync(fixture.guideSafetySnapshot);
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: UserProfile.fromMap(offlineProfile),
          child: const Scaffold(),
        ),
      );
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pumpAndSettle();
      expect(guideStops[guide.stopIndex].id, 'G16');
      expect(find.byType(ParcelDetailScreen), findsOneWidget);
      expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
      await tester.pumpWidget(const SizedBox());
      guide.dispose();
    },
  );

  testWidgets(
    'normal protocol dispatch stays with the supplied callback, not display status',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InspectionProtocolView(
                completedCount: 2,
                steps: [
                  InspectionProtocolStep(
                    index: 4,
                    title: 'Zoning Checklist',
                    description: 'Independent after Step 2',
                    icon: Icons.checklist_rounded,
                    onTap: () => opened++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Zoning Checklist'));
      expect(opened, 1);
    },
  );
}
