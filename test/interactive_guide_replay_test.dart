import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/screens/interactive_guide_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/faq_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(() async {
    await fixture.initialize();
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.inter(fontWeight: weight);
      GoogleFonts.urbanist(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await fixture.reset();
    fixture.mode = 'success';
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> startReferenceReplay(WidgetTester tester) async {
    await GuidePreferences().write(
      offlineInspector,
      const GuideRecord(1, GuideLanguage.english, GuideStatus.completed),
    );
    await fixture.mount(
      tester,
      MainShellScreen(
        profile: UserProfile.fromMap(offlineProfile),
        initialIndex: 3,
      ),
    );
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Help & FAQ'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Help & FAQ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & FAQ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interactive-guide-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interactive-guide-start')));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  fixture.widgetTest(
    'reference acceptance: populated replay uses the real Home',
    (tester) async {
      await startReferenceReplay(tester);
      final home = find.byType(HomeDashboardScreen);
      expect(home, findsOneWidget);
      expect(
        find.descendant(of: home, matching: find.text('Fixture Inspector')),
        findsOneWidget,
      );
      expect(find.text('Sample Inspector — Fictional'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'reference acceptance: compact coach retains a visible target',
    (tester) async {
      await startReferenceReplay(tester);
      final coach = tester.getRect(find.byKey(const ValueKey('guide-coach')));
      expect(coach.height, lessThanOrEqualTo(280));
      final scrim =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      expect(scrim.target, isNotNull);
      expect(coach.overlaps(scrim.target!), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  fixture.widgetTest(
    'dedicated page translates all sections and returns only a chosen start request',
    (tester) async {
      GuideReplayRequest? result;
      await fixture.mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<GuideReplayRequest>(
                  MaterialPageRoute(
                    builder: (_) => const InteractiveGuideScreen(
                      initialLanguage: GuideLanguage.english,
                      hasPreviousOffer: false,
                    ),
                  ),
                );
              },
              child: const Text('Open guide'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();
      expect(find.text('Start Tour'), findsOneWidget);
      final list = find.byKey(const ValueKey('interactive-guide-copy'));
      await tester.scrollUntilVisible(
        find.text('Safe learning examples'),
        180,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Safe learning examples'), findsOneWidget);
      await tester.ensureVisible(find.text('Filipino (Tagalog)'));
      await tester.tap(find.text('Filipino (Tagalog)'));
      await tester.pumpAndSettle();
      final labels = GuideLabels(GuideLanguage.tagalog);
      expect(find.text(labels.pageIntroduction), findsOneWidget);
      expect(find.text(labels.navigation), findsOneWidget);
      expect(find.text(labels.examplesBody), findsOneWidget);
      expect(find.text(labels.safety), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('interactive-guide-start')));
      await tester.pumpAndSettle();
      expect(result?.language, GuideLanguage.tagalog);
      expect(fixture.remoteWrites, 0);
    },
  );

  fixture.widgetTest(
    'Help entry precedes search and remains available after filtering',
    (tester) async {
      await fixture.mount(tester, const HelpFaqScreen());
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('interactive-guide-entry'));
      expect(
        tester.getTopLeft(find.byType(FaqLanguageSegmentControl)).dy,
        lessThan(tester.getTopLeft(entry).dy),
      );
      expect(
        tester.getBottomLeft(entry).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
      await tester.enterText(
        find.byType(TextField),
        'no matching question at all',
      );
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveGuideScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('no matching question at all'), findsOneWidget);
    },
  );

  fixture.widgetTest(
    'replay retains Profile and restores Help query, language and scroll origin',
    (tester) async {
      await GuidePreferences().write(
        offlineInspector,
        const GuideRecord(1, GuideLanguage.english, GuideStatus.completed),
      );
      await fixture.mount(
        tester,
        MainShellScreen(
          profile: UserProfile.fromMap(offlineProfile),
          initialIndex: 3,
        ),
      );
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      final profile = tester.state(find.byType(ProfileScreen));
      await tester.scrollUntilVisible(
        find.text('Help & FAQ'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Help & FAQ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & FAQ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'GPS');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.byType(FaqLanguageSegmentControl));
      await tester.tap(find.text('Tagalog'));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('help-faq-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      await tester.tap(find.byKey(const ValueKey('interactive-guide-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Replay Tour'), findsOneWidget);
      await tester.tap(find.text('Filipino (Tagalog)'));
      await tester.tap(find.byKey(const ValueKey('interactive-guide-start')));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      expect(guide.phase, GuidePhase.active);
      expect(guide.stopIndex, 0);
      expect(guide.language, GuideLanguage.tagalog);
      expect(tester.state(find.byType(ProfileScreen, skipOffstage: false)), same(profile));
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveGuideScreen), findsOneWidget);
      expect(find.text('Ulitin ang Gabay'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('GPS'), findsOneWidget);
      expect(
        tester
            .widget<FaqLanguageSegmentControl>(
              find.byType(FaqLanguageSegmentControl),
            )
            .isTagalog,
        isTrue,
      );
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('help-faq-list')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        scroll,
      );
      expect(
        (await GuidePreferences().read(offlineInspector))?.status,
        GuideStatus.completed,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
