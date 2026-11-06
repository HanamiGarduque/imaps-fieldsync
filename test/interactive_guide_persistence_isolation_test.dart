import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  testWidgets(
    'a complete example walk preserves real jobs, evidence, outbox, progress and acknowledgements',
    (tester) async {
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      const tables = [
        'local_jobs',
        'local_inspections',
        'local_photos',
        'pending_actions',
      ];
      Future<String> snapshot() async => jsonEncode({
        for (final table in tables) table: await fixture.db.query(table),
      });
      final before = await tester.runAsync(snapshot);
      final secureBefore = Map<String, String>.from(fixture.secure);
      final store = await SharedPreferences.getInstance();
      await store.setString('existing-language', 'English');
      final prefsBefore = {
        for (final key in store.getKeys()) key: store.get(key),
      };
      final progress = InspectionProgress.instance;
      final progressBefore = [
        progress.currentStep,
        progress.highestCompleted,
        Map<int, String>.from(progress.stepCompletedAt),
      ];
      final activeTaskBefore = fixture.provider.activeTask;
      fixture.requestOverride = (request) async =>
          throw StateError('Guide attempted HTTP: ${request.method}');
      final hardware = <String>[];
      for (final channel in [
        'plugins.flutter.io/camera',
        'flutter.baseflow.com/geolocator',
        'flutter_compass',
      ]) {
        fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (call) async {
            hardware.add('$channel/${call.method}');
            throw StateError('Guide requested hardware');
          },
        );
      }
      var sampleTransitions = 0;
      await fixture.mount(
        tester,
        GuideHost(
          coordinator: guide,
          profile: UserProfile.fromMap(offlineProfile),
          child: const Scaffold(),
        ),
      );
      await guide.start(GuideLanguage.english);
      await fixture.flush(tester);
      for (final stop in guideStops) {
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('guide-active-page')), findsOneWidget);
        if (stop.id == 'G15') {
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          expect(guideStops[guide.stopIndex].id, 'G16');
          sampleTransitions++;
        } else {
          guide.next();
        }
        expect(tester.takeException(), isNull, reason: stop.id);
      }
      await tester.pumpWidget(const SizedBox());
      guide.dispose();
      expect(await tester.runAsync(snapshot), before);
      expect(fixture.secure, secureBefore);
      expect({
        for (final key in store.getKeys().where(
          (key) => !key.startsWith('fieldsync.guide.'),
        ))
          key: store.get(key),
      }, prefsBefore);
      expect([
        progress.currentStep,
        progress.highestCompleted,
        progress.stepCompletedAt,
      ], progressBefore);
      expect(fixture.provider.activeTask, same(activeTaskBefore));
      expect(fixture.requests, isEmpty);
      expect(hardware, isEmpty);
      expect(sampleTransitions, 1);
    },
  );
}
