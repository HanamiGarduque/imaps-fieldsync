import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  fixture.widgetTest(
    'guide-only Navigator is discarded on Back without recreating the real subtree',
    (tester) async {
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      final scroll = ScrollController();
      await fixture.mount(
        tester,
        MaterialApp(
          home: GuideHost(
            coordinator: guide,
            profile: UserProfile.fromMap(offlineProfile),
            child: Scaffold(
              body: SingleChildScrollView(
                controller: scroll,
                child: const Column(
                  children: [
                    TextField(),
                    SizedBox(height: 1600),
                    Text('Real retained page'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'unsaved filter');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      scroll.jumpTo(100);
      final field = tester.state(find.byType(TextField));
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G16')) {
        guide.next();
      }
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-active-page')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
      expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
      expect(tester.state(find.byType(TextField)), same(field));
      expect(find.text('unsaved filter'), findsOneWidget);
      expect(scroll.offset, 100);
      await tester.pumpWidget(const SizedBox());
      guide.dispose();
      scroll.dispose();
    },
  );

  fixture.widgetTest(
    'invalidation during a sample transition or font change cannot resurrect it',
    (tester) async {
      final guide = GuideCoordinator(
        inspectorId: offlineInspector,
        preferences: GuidePreferences(),
        canPresent: () => true,
      );
      await guide.start(GuideLanguage.tagalog);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G15')) {
        guide.next();
      }
      await fixture.mount(
        tester,
        MaterialApp(
          home: GuideHost(
            coordinator: guide,
            profile: UserProfile.fromMap(offlineProfile),
            child: const Scaffold(body: Text('Real retained page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      guide.next();
      guide.invalidate();
      await tester.pumpAndSettle();
      await guide.start(GuideLanguage.english, replay: true);
      await tester.pumpAndSettle();
      expect(guide.phase, GuidePhase.idle);
      expect(find.byKey(const ValueKey('guide-active-page')), findsNothing);
      expect(find.byKey(const ValueKey('guide-coach')), findsNothing);
      expect(find.text('Real retained page'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      guide.dispose();
    },
  );
}
