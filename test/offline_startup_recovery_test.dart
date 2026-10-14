import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/navigation/main_shell_screen.dart';
import 'package:imaps_fieldsync/core/services/auth_failure.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final measurements = <Map<String, Object>>[];
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(() async {
    final evidence = Platform.environment['FS04_EVIDENCE_DIR'];
    if (evidence != null) {
      File('$evidence/startup-measurements.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(measurements));
    }
    await fixture.dispose();
  });

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    await tester.pump(elapsed); await fixture.flush(tester);
  }

  for (final expired in [false, true]) {
    fixture.widgetTest('${expired ? "expired" : "valid"} retained owner starts offline within splash delay', (tester) async {
      await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: expired)));
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));
      await advance(tester, const Duration(milliseconds: 400));
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(fixture.requests.where((r) => r.url.path.contains('/profiles')), isEmpty);
      final shell = tester.widget<MainShellScreen>(find.byType(MainShellScreen));
      expect(shell.profile.id, offlineInspector);
      measurements.add({'scenario': '${expired ? "expired" : "valid"}-no-transport',
        'clock': 'simulated', 'awaited_stage': 'connectivity/local cached profile',
        'splash_seconds': 3, 'network_recovery_seconds': 0,
        'observed_shell_by_seconds': 3.4, 'destination': 'Home'});
    });
  }

  fixture.widgetTest('profile hang releases Splash at eight seconds of recovery', (tester) async {
    fixture.online = true; fixture.mode = 'profile-hang';
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    expect(fixture.held.single.stage, 'profile');
    await advance(tester, const Duration(milliseconds: 7999));
    expect(find.byType(MainShellScreen), findsNothing);
    await advance(tester, const Duration(milliseconds: 1));
    expect(find.byType(MainShellScreen), findsOneWidget);
    measurements.add({'scenario': 'valid-online-profile-hang', 'clock': 'simulated',
      'awaited_stage': 'profile', 'splash_seconds': 3, 'network_recovery_seconds': 8,
      'observed_shell_by_seconds': 11, 'destination': 'Home using cached profile'});
    expect(tester.takeException(), isNull);
  });

  fixture.widgetTest('slow refresh plus profile hang share ONE eight-second budget', (tester) async {
    fixture.online = true; fixture.mode = 'refresh-hang';
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: true)));
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    expect(fixture.held.single.stage, 'refresh');
    await advance(tester, const Duration(seconds: 5));
    fixture.mode = 'profile-hang'; fixture.resolveHeld(); await fixture.flush(tester);
    expect(fixture.held.last.stage, 'profile');
    await advance(tester, const Duration(milliseconds: 2999));
    expect(find.byType(MainShellScreen), findsNothing);
    await advance(tester, const Duration(milliseconds: 1));
    expect(find.byType(MainShellScreen), findsOneWidget);
    measurements.add({'scenario': 'expired-slow-refresh-profile-hang', 'clock': 'simulated',
      'awaited_stage': 'refresh 5s then profile 3s', 'splash_seconds': 3,
      'network_recovery_seconds': 8, 'observed_shell_by_seconds': 11,
      'destination': 'Home using cached profile'});
  });

  fixture.widgetTest('connectivity probe latency is inside startup budget', (tester) async {
    fixture.connectivityReply = Completer<List<String>>();
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 8400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(fixture.requests.where((r) => r.url.path.contains('/profiles') ||
        r.url.path.contains('/token')), isEmpty);
    measurements.add({'scenario': 'connectivity-probe-hang', 'clock': 'simulated',
      'awaited_stage': 'connectivity', 'splash_seconds': 3,
      'network_recovery_seconds': 8, 'observed_shell_by_seconds': 11.4,
      'destination': 'Home using cached profile'});
  });

  fixture.widgetTest('late connectivity cannot start a refresh after startup budget expired', (tester) async {
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: true)));
    fixture.connectivityReply = Completer<List<String>>();
    await fixture.mount(tester, const SizedBox.shrink());
    final recovering = AuthService.getCurrentProfileOfflineAware(restoreSession: true);
    await advance(tester, const Duration(seconds: 8));
    expect((await recovering)?.id, offlineInspector);
    fixture.connectivityReply!.complete(['wifi']); await fixture.flush(tester);
    expect(fixture.requests.where((r) => r.url.path.contains('/token')), isEmpty);
  });

  for (final expired in [false, true]) {
    fixture.widgetTest('online transport failure with ${expired ? "expired" : "valid"} prior session stays bounded', (tester) async {
      fixture.online = true; fixture.mode = 'transport';
      await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: expired)));
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));
      for (var i = 0; i < 8; i++) { await advance(tester, const Duration(seconds: 1)); }
      expect(find.byType(MainShellScreen), findsOneWidget);
      measurements.add({'scenario': '${expired ? "expired" : "valid"}-online-backend-unreachable',
        'clock': 'simulated', 'awaited_stage': expired ? 'refresh SDK retry' : 'profile SDK retry',
        'splash_seconds': 3, 'network_recovery_bound_seconds': 8,
        'observed_shell_by_seconds': 11, 'destination': 'Home using cached profile'});
    });
  }

  for (final scenario in ['missing-profile', 'different-owner', 'soft-logout',
    'no-session', 'refresh-refusal', 'profile-refusal', 'non-inspector-cache', 'empty-name-cache']) {
    fixture.widgetTest('$scenario never receives cached offline shell access', (tester) async {
      if (scenario == 'missing-profile') fixture.secure.remove('sp_cached_profile');
      if (scenario == 'different-owner') {
        fixture.secure['sp_cached_profile'] = jsonEncode({...offlineProfile, 'id': otherOfflineInspector});
      }
      if (scenario == 'soft-logout') {
        await SecurePrefsService.setSoftLoggedOut(true); await AuthService.loadSoftLogoutState();
      }
      if (scenario == 'no-session') {
        await tester.runAsync(() => fixture.client.auth.signOut(scope: SignOutScope.local));
      }
      if (scenario == 'refresh-refusal') {
        fixture.online = true; fixture.mode = 'refresh-reject';
        await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: true)));
      }
      if (scenario == 'profile-refusal') {
        fixture.online = true; fixture.mode = 'profile-reject';
      }
      if (scenario == 'non-inspector-cache') {
        fixture.secure['sp_cached_profile'] = jsonEncode({...offlineProfile, 'role': 'unknown'});
      }
      if (scenario == 'empty-name-cache') {
        fixture.secure['sp_cached_profile'] = jsonEncode({...offlineProfile, 'full_name': ''});
      }
      await fixture.mount(tester, const SplashScreen());
      await advance(tester, const Duration(seconds: 3));
      await advance(tester, const Duration(seconds: 9));
      expect(find.byType(MainShellScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      measurements.add({'scenario': scenario, 'clock': 'simulated',
        'awaited_stage': scenario == 'refresh-refusal' ? 'refresh' :
          scenario == 'profile-refusal' ? 'profile' : 'local authorization/cache',
        'observed_login_by_seconds': 12, 'destination': 'Login, no offline shell'});
    });
  }

  test('server refusal with network-looking text is not transport fallback', () async {
    fixture.online = true; fixture.mode = 'profile-reject-network-text';
    await expectLater(AuthService.getCurrentProfileOfflineAware(),
      throwsA(AuthFailure.profileUnavailable));
  });

  test('known missing profile cannot use its old cache on the next offline start', () async {
    fixture.online = true; fixture.mode = 'profile-reject';
    await expectLater(AuthService.getCurrentProfileOfflineAware(),
      throwsA(AuthFailure.profileUnavailable));
    fixture.online = false; fixture.mode = 'transport';
    await expectLater(AuthService.getCurrentProfileOfflineAware(),
      throwsA(AuthFailure.networkUnavailable));
  });

  test('in-flight profile response cannot cross inspector ownership', () async {
    fixture.online = true; fixture.mode = 'profile-hang';
    final assertion = expectLater(AuthService.getCurrentProfileOfflineAware(),
      throwsA(AuthFailure.sessionRestoreFailed));
    while (fixture.held.isEmpty) { await Future<void>.delayed(Duration.zero); }
    await fixture.client.auth.setInitialSession(jsonEncode(
      fixture.session(owner: otherOfflineInspector)));
    fixture.resolveHeld(); await assertion;
    expect((await SecurePrefsService.getCachedProfile())?.id, offlineInspector);
  });

  test('a cache read in flight cannot bypass an observed profile refusal', () async {
    final storage = Completer<String?>();
    fixture.storageReplies['sp_cached_profile'] = storage;
    final cached = AuthService.getCachedProfileForCurrentInspector();
    fixture.online = true; fixture.mode = 'profile-reject';
    final refusal = expectLater(AuthService.getCurrentProfileOfflineAware(),
      throwsA(AuthFailure.profileUnavailable));
    while (AuthService.profileRefusedOwner.value != offlineInspector) {
      await Future<void>.delayed(Duration.zero);
    }
    storage.complete(jsonEncode(offlineProfile));
    expect(await cached, isNull); await refusal;
  });

  fixture.widgetTest('owner change during startup local lock preferences cannot open stale profile', (tester) async {
    final preference = Completer<String?>();
    fixture.storageReplies['sp_bio_require_on_open'] = preference;
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(owner: otherOfflineInspector)));
    preference.complete('false'); await fixture.flush(tester);
    await advance(tester, const Duration(seconds: 1));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  fixture.widgetTest('offline cold restart preserves the owner and Home destination', (tester) async {
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, const Duration(milliseconds: 100));
    await tester.runAsync(fixture.restartDatabase);
    await tester.pumpWidget(MaterialApp(home: const SplashScreen()));
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 400));
    expect(tester.widget<MainShellScreen>(find.byType(MainShellScreen)).profile.id,
      offlineInspector);
  });

  fixture.widgetTest('late authoritative refresh refusal closes cached shell access', (tester) async {
    fixture.online = true; fixture.mode = 'refresh-hang';
    await fixture.client.auth.setInitialSession(jsonEncode(fixture.session(expired: true)));
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 8400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    fixture.resolveHeld(rejectRefresh: true); await fixture.flush(tester);
    await advance(tester, const Duration(seconds: 1));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  fixture.widgetTest('late authoritative profile refusal closes cached shell and invalidates stale profile', (tester) async {
    fixture.online = true; fixture.mode = 'profile-hang';
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 8400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    final item = fixture.held.single;
    item.response.complete(http.Response(jsonEncode({'code': '42501',
      'message': 'Isolated authoritative refusal'}), 403, request: item.request));
    await fixture.flush(tester); await advance(tester, const Duration(seconds: 1));
    expect(find.byType(MainShellScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await SecurePrefsService.getCachedProfile(), isNull);
  });

  fixture.widgetTest('offline background resume keeps owner without reentering startup loading', (tester) async {
    await fixture.mount(tester, const SplashScreen());
    await advance(tester, const Duration(seconds: 3));
    await advance(tester, const Duration(milliseconds: 400));
    expect(find.byType(MainShellScreen), findsOneWidget);
    final profilesBefore = fixture.requests.where((r) => r.url.path.contains('/profiles')).length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await advance(tester, const Duration(seconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await fixture.flush(tester);
    expect(find.byType(MainShellScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(fixture.requests.where((r) => r.url.path.contains('/profiles')).length, profilesBefore);
    measurements.add({'scenario': 'offline-background-resume', 'clock': 'simulated',
      'awaited_stage': 'existing lifecycle/local lock preference',
      'simulated_background_seconds': 60, 'network_startup_wait_seconds': 0,
      'destination': 'Same owner Home'});
  });
}
