import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/app_bootstrap.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/services/auth_failure.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_host.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppBootstrap.resetForTests();
    await fixture.reset();
    fixture.mode = 'success';
  });
  tearDown(() async {
    AppBootstrap.resetForTests();
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  Widget shell() => MainShellScreen(
    profile: UserProfile.fromMap(offlineProfile),
    offlineSession: true,
  );
  Future<void> settle(WidgetTester tester) async {
    await fixture.flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  fixture.widgetTest(
    'pending bootstrap cannot offer; a settled successful bootstrap can',
    (tester) async {
      final ready = Completer<void>();
      AppBootstrap.initialize(
        steps: [(name: 'isolated startup gate', run: () => ready.future)],
      );
      await fixture.mount(tester, shell());
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      expect(guide.phase, GuidePhase.idle);
      expect(await GuidePreferences().read(offlineInspector), isNull);
      ready.complete();
      await settle(tester);
      expect(guide.phase, GuidePhase.invitation);
    },
  );

  fixture.widgetTest(
    'native protection must acknowledge before offering and failure suspends examples',
    (tester) async {
      final acknowledged = Completer<void>();
      var fail = false;
      final protection = ScreenProtectionService(
        applyProtection: (secure) async {
          if (!secure) return;
          await acknowledged.future;
          if (fail) throw StateError('isolated protection unavailable');
        },
      );
      addTearDown(protection.dispose);
      await fixture.mount(
        tester,
        ScreenProtectionHost(protection: protection, child: shell()),
      );
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      expect(guide.phase, GuidePhase.idle);
      expect(await GuidePreferences().read(offlineInspector), isNull);
      acknowledged.complete();
      await settle(tester);
      expect(guide.phase, GuidePhase.invitation);
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G16')) {
        guide.next();
      }
      await tester.pumpAndSettle();
      fail = true;
      protection.retryProtection();
      await settle(tester);
      expect(protection.nativeFailure, isTrue);
      expect(guide.phase, GuidePhase.suspended);
      expect(
        find.byKey(const ValueKey('guide-active-page'), skipOffstage: false),
        findsNothing,
      );
      fail = false;
      protection.retryProtection();
      await settle(tester);
      expect(guide.phase, GuidePhase.active);
      expect(guideStops[guide.stopIndex].id, 'G16');
    },
  );

  fixture.widgetTest(
    'profile refusal invalidates an active sample before redirecting to Login',
    (tester) async {
      await fixture.mount(tester, shell());
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      await guide.start(GuideLanguage.english);
      while (guide.stopIndex <
          guideStops.indexWhere((stop) => stop.id == 'G16')) {
        guide.next();
      }
      await tester.pumpAndSettle();
      fixture.online = true;
      fixture.mode = 'profile-reject';
      await tester.runAsync(() async {
        await expectLater(
          AuthService.getCurrentProfileOfflineAware(),
          throwsA(AuthFailure.profileUnavailable),
        );
      });
      await settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guide-active-page'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('guide-coach'), skipOffstage: false),
        findsNothing,
      );
      expect(
        (await GuidePreferences().read(offlineInspector))?.status,
        isNot(GuideStatus.completed),
      );
    },
  );

  fixture.widgetTest(
    'owner change while suspended never restores the old guide or Help origin',
    (tester) async {
      await fixture.mount(tester, shell());
      await settle(tester);
      final guide = tester
          .widget<GuideHost>(find.byType(GuideHost))
          .coordinator;
      await guide.start(GuideLanguage.english);
      guide.suspend();
      await fixture.client.auth.setInitialSession(
        jsonEncode(fixture.session(owner: otherOfflineInspector)),
      );
      await settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(GuideHost, skipOffstage: false), findsNothing);
      expect(await GuidePreferences().read(otherOfflineInspector), isNull);
    },
  );
}
