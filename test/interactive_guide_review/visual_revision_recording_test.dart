import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/interactive_guide_test_support.dart';
import '../support/offline_reliability_fixture.dart';

// Explicit visual-evidence command, not an installed-device recording.
void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(() async {
    await fixture.initialize();
    await prepareGuideTestFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    fixture.mode = 'success';
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  for (final language in GuideLanguage.values) {
    fixture.widgetTest(
      'record real first Help launch, all stops, Done and replay Skip in ${language.name}',
      (tester) async {
        final destination = Platform.environment['FS04_EVIDENCE_DIR'];
        expect(
          destination,
          isNotNull,
          reason: 'Set a separate output directory for these runtime frames.',
        );
        expect(Platform.environment['IMAPS_GUIDE_FONT_DIR'], isNotNull);
        final frames = <Map<String, Object>>[];
        Future<void> frame(String scene, int durationMs) async {
          final name =
              'record-${language.name}-${frames.length.toString().padLeft(4, '0')}';
          await fixture.capture(tester, name);
          frames.add({
            'file': 'screenshots/$name.png',
            'scene': scene,
            'duration_ms': durationMs,
          });
          expect(tester.takeException(), isNull, reason: scene);
        }

        Future<void> transition(String scene) async {
          for (var index = 0; index < 8; index++) {
            await tester.pump(const Duration(milliseconds: 50));
            await frame(scene, 50);
          }
          await fixture.flush(tester);
          await tester.pumpAndSettle();
        }

        await fixture.mount(
          tester,
          MainShellScreen(
            profile: UserProfile.fromMap(offlineProfile),
            initialIndex: 3,
          ),
          showDebugBanner: false,
        );
        await fixture.flush(tester);
        await tester.pumpAndSettle();
        await frame('Profile / first manual launch', 1000);
        await tester.scrollUntilVisible(
          find.text('Help & FAQ'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Help & FAQ'));
        await tester.pumpAndSettle();
        await frame('Profile / Help & FAQ', 1000);
        await tester.tap(find.text('Help & FAQ'));
        await transition('Open Help & FAQ');
        await frame('Help & FAQ / Interactive Guide entry', 1200);
        await tester.tap(find.byKey(const ValueKey('interactive-guide-entry')));
        await transition('Open dedicated Guide page');
        if (language == GuideLanguage.tagalog) {
          await tester.tap(find.text('Filipino (Tagalog)'));
          await tester.pumpAndSettle();
        }
        await frame('Guide page / language and Start', 1800);
        await tester.tap(find.byKey(const ValueKey('interactive-guide-start')));
        await transition('First Start / fingerprint introduction');
        final guide = tester
            .widget<GuideHost>(find.byType(GuideHost))
            .coordinator;
        expect(guide.phase, GuidePhase.active);
        expect(guide.language, language);
        expect(guide.stopIndex, 0);
        final before = await tester.runAsync(fixture.guideSafetySnapshot);
        final visited = <String>[];
        for (final stop in guideStops) {
          expect(guideStops[guide.stopIndex].id, stop.id);
          visited.add(stop.id);
          await frame('${stop.id} / ${stop.copyFor(language).title}', 2200);
          if ({'G02', 'G39-support', 'G39-policies', 'G41'}.contains(stop.id)) {
            await tester.tap(find.byKey(const ValueKey('guide-details')));
            await tester.pumpAndSettle();
            await frame('${stop.id} / full explanation', 2500);
            final copyScroll = find.descendant(
              of: find.byKey(
                ValueKey('guide-copy-${stop.id}-${language.name}'),
              ),
              matching: find.byType(Scrollable),
            );
            final position = tester.state<ScrollableState>(copyScroll).position;
            if (position.maxScrollExtent > 0) {
              await tester.drag(
                copyScroll,
                Offset(0, -position.maxScrollExtent),
              );
              await tester.pumpAndSettle();
              await frame('${stop.id} / explanation continued', 2000);
            }
            await tester.tap(find.byKey(const ValueKey('guide-details')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          await transition('${stop.id} / Next');
        }
        expect(visited, hasLength(35));
        expect(guide.phase, GuidePhase.idle);
        expect(await tester.runAsync(fixture.guideSafetySnapshot), before);
        expect(
          (await GuidePreferences().read(offlineInspector))?.status,
          GuideStatus.completed,
        );
        await frame('Done / restored Guide page', 1800);
        final labels = GuideLabels(language);
        await Scrollable.ensureVisible(
          tester.element(find.text(labels.safety)),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        await frame('Guide page / final safety copy, no Replay overlap', 2200);
        await tester.ensureVisible(
          find.byKey(const ValueKey('interactive-guide-start')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('interactive-guide-start')));
        await transition('Replay / fingerprint introduction');
        expect(guide.phase, GuidePhase.active);
        expect(guide.stopIndex, 0);
        await frame('Replay / same language', 1600);
        await tester.tap(find.byKey(const ValueKey('guide-skip')));
        await transition('Skip / return without changing records');
        expect(guide.phase, GuidePhase.idle);
        expect(
          (await GuidePreferences().read(offlineInspector))?.status,
          GuideStatus.completed,
        );
        await frame('Skip / restored Guide page', 1600);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Quick actions',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(QuickActionsSheet), findsOneWidget);
        await frame('Normal return / all five Quick Actions', 2200);
        expect(fixture.remoteWrites, 0);
        await tester.runAsync(() async {
          Directory(destination!).createSync(recursive: true);
          File(
            '$destination/recording-${language.name}.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              'renderer':
                  'Actual Flutter widget-test raster frames; not an installed-device recording',
              'data':
                  'Isolated fictional test fixtures, not production inspector records',
              'language': language.name,
              'transition_fps': 20,
              'reading_holds_added': true,
              'all_stops': visited,
              'frames': frames,
            }),
          );
        });
      },
    );
  }
}
