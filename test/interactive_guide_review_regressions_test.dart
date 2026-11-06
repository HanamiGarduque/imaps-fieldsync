import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/app_resume_lock_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_observer.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/profile_action_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late ScreenProtectionService protection;
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
    protection = ScreenProtectionService(
      documentationEnabled: false,
      applyProtection: (_) async {},
    );
  });
  tearDown(() async {
    protection.dispose();
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  Future<GuideCoordinator> mount(
    WidgetTester tester, {
    int index = 0,
    bool offered = false,
  }) async {
    if (!offered) {
      await GuidePreferences().write(
        offlineInspector,
        const GuideRecord(1, GuideLanguage.english, GuideStatus.completed),
      );
    }
    await fixture.mount(
      tester,
      ScreenProtectionHost(
        protection: protection,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [ScreenProtectionObserver(protection)],
          home: MainShellScreen(
            profile: UserProfile.fromMap(offlineProfile),
            initialIndex: index,
            offlineSession: !fixture.online,
          ),
        ),
      ),
    );
    await settle(tester);
    return tester.widget<GuideHost>(find.byType(GuideHost)).coordinator;
  }

  fixture.widgetTest(
    'rapid Home Tasks Home tab return never duplicates normal live guide targets',
    (tester) async {
      await mount(tester);
      var nav = tester.widget<InsightBottomNav>(find.byType(InsightBottomNav));
      nav.onTap(1);
      await tester.pump(const Duration(milliseconds: 100));
      nav = tester.widget<InsightBottomNav>(find.byType(InsightBottomNav));
      nav.onTap(0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await settle(tester);
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cover in ['App Lock', 'Login']) {
    fixture.widgetTest('Help awaiting metadata cannot navigate above $cover', (
      tester,
    ) async {
      await mount(tester, index: 3);
      final profile = tester.element(find.byType(ProfileScreen));
      // Invoke the real production callback without yielding, then interrupt
      // its awaited preferences read before that continuation can navigate.
      tester
          .widget<ProfileActionSections>(find.byType(ProfileActionSections))
          .onHelp!();
      Navigator.of(profile).push(
        MaterialPageRoute<void>(
          builder: (_) => cover == 'App Lock'
              ? const AppResumeLockScreen()
              : const LoginScreen(),
        ),
      );
      await settle(tester);
      expect(find.byType(HelpFaqScreen, skipOffstage: false), findsNothing);
      expect(
        cover == 'App Lock'
            ? find.byType(AppResumeLockScreen)
            : find.byType(LoginScreen),
        findsOneWidget,
      );
    });
  }

  fixture.widgetTest('overlapping Help launches produce exactly one route', (
    tester,
  ) async {
    await mount(tester, index: 3);
    final help = tester
        .widget<ProfileActionSections>(find.byType(ProfileActionSections))
        .onHelp!;
    help();
    help();
    await settle(tester);
    expect(find.byType(HelpFaqScreen, skipOffstage: false), findsOneWidget);
  });

  fixture.widgetTest(
    'live Home targets measure inset surfaces and ordinary identity/calendar spotlights fit',
    (tester) async {
      final guide = await mount(tester);
      final home = tester.element(find.byType(HomeDashboardScreen));
      final targets = home
          .getInheritedWidgetOfExactType<GuideTargetScope>()!
          .registry;
      final host = tester.renderObject<RenderBox>(find.byType(GuideOverlay));
      for (final id in [
        'inspector_section',
        'calendar_section',
        'assignments_section',
        'assignment_card',
      ]) {
        final rect = targets.rectFor(id, host);
        expect(rect, isNotNull, reason: id);
        expect(rect!.left, greaterThanOrEqualTo(18), reason: id);
        expect(rect.right, lessThanOrEqualTo(372), reason: id);
      }
      await guide.start(GuideLanguage.english, replay: true);
      for (var i = 0; i < 2; i++) {
        guide.next();
      }
      await tester.pumpAndSettle();
      GuideScrimPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('guide-scrim')),
                  )
                  .painter!
              as GuideScrimPainter;
      expect(
        painter().target,
        isNotNull,
        reason: 'Actual inset identity fits ordinary portrait',
      );
      guide.next();
      guide.next();
      await tester.pumpAndSettle();
      expect(
        painter().target,
        isNotNull,
        reason: 'Actual inset calendar fits ordinary portrait',
      );
    },
  );

  for (final online in [true, false]) {
    fixture.widgetTest(
      '${online ? 'empty' : 'unavailable'} Home supplies a labelled assignment example without changing real data',
      (tester) async {
        for (final table in [
          'local_jobs',
          'local_inspections',
          'local_photos',
          'pending_actions',
        ]) {
          await fixture.db.delete(table);
        }
        fixture.online = online;
        final guide = await mount(tester, offered: true);
        final home = tester.state(find.byType(HomeDashboardScreen));
        final secure = Map<String, String>.from(fixture.secure);
        fixture.requests.clear();
        await guide.start(GuideLanguage.english);
        for (var i = 0; i < 5; i++) {
          guide.next();
        }
        await tester.pumpAndSettle();
        await fixture.flush(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('guide-active-page')), findsOneWidget);
        expect(find.text('Sample Applicant — Fictional'), findsOneWidget);
        guide.next();
        await tester.pumpAndSettle();
        expect(find.text('Sample Applicant — Fictional'), findsOneWidget);
        await guide.skip();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(HomeDashboardScreen)), same(home));
        expect(await fixture.db.query('local_jobs'), isEmpty);
        expect(fixture.secure, secure);
        expect(fixture.requests, isEmpty);
        expect(protection.isDocumentationActive, isFalse);
      },
    );
  }
}
