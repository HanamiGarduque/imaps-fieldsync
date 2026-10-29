// ISOLATED DEMO PREVIEW ENTRY POINT - NOT THE PRODUCTION APP.
//
// This file is deliberately NOT `lib/main.dart`. It runs only when every
// gate below passes, so it cannot become the normal release entry point by
// accident:
//
//   1. the build is debug (`kReleaseMode` throws);
//   2. the build was started with `--dart-define=QA_PREVIEW=true`;
//   3. the build targets the `demo` flavor (`FLUTTER_APP_FLAVOR` is injected
//      by the flutter tool), installing the separate package
//      com.example.imaps_fieldsync.demo with its own private data sandbox,
//      its own launcher icon and no INTERNET permission
//      (android/app/build.gradle.kts + android/app/src/demoDebug);
//   4. the installed signing certificate matches the approved signer pin
//      supplied with --dart-define=FIELDSYNC_DEMO_SIGNER_SHA256 (64-hex
//      SHA-256), attested by ScreenProtectionService.isVerifiedDemoContext.
//
// Everything here is synthetic: a fictional inspector, fictional assignments,
// fixtures generated on the device, and a deny-by-default transport that
// never forwards anything. The environment is fictional constants loaded in
// memory through dotenv.testLoad — the prod-scoped `.env` asset is not
// readable by this build.
//
// Capture eligibility is granted only by the rendered demo root after live
// identity/fixture/watermark readiness. Protection stays ON until an explicit
// manual confirmation and native OFF acknowledgment. No automatic resume grant
// can resume a recording: every invalidated session needs fresh confirmation.
//
// Nothing in this file is imported by `lib/main.dart`.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart' show MockClient;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/models/user_profile.dart';
import 'core/navigation/main_shell_screen.dart';
import 'core/services/report_submission_service.dart';
import 'core/services/supabase_endpoint.dart';
import 'core/services/sync_outbox_service.dart';
import 'core/theme/insight_theme.dart';
import 'modules/inspection/providers/inspection_provider.dart';
import 'modules/auth_startup/services/screen_protection_service.dart';
import 'modules/auth_startup/services/screen_protection_observer.dart';
import 'core/widgets/sensitive_screen.dart';
import 'qa/demo_fixtures.dart';
import 'qa/demo_watermark.dart';

/// Fixed fictional environment values for the demo build, loaded through
/// dotenv.testLoad (in memory only). Never real values, and the prod-scoped
/// `.env` asset is not readable by this build.
@visibleForTesting
const String demoSupabaseUrl = 'http://127.0.0.1:54321';

@visibleForTesting
const String demoPublishableKey = 'demo-fictional-local-only';

/// Deny-by-default transport for the demo Supabase client: every request is
/// answered locally with an explicit refusal and nothing ever leaves the
/// process — not even to the loopback endpoint.
@visibleForTesting
final demoTransport = MockClient((request) async {
  return Response(
    jsonEncode({
      'error': 'demo_offline',
      'message': 'FieldSync demo build: network access is denied by design.',
    }),
    403,
    headers: {'content-type': 'application/json'},
  );
});

/// Fictional QA inspector. Not a real account, not a real UUID from any
/// environment.
const String qaInspectorId = DemoFixtures.owner;

Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('The demo preview entry point is debug-only.');
  }

  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  if (!await ScreenProtectionService.isVerifiedDemoContext()) {
    throw StateError(
      'The demo preview needs the verified demo identity: --flavor=demo '
      '(demo package), --dart-define=QA_PREVIEW=true and the approved '
      'signer pin --dart-define=FIELDSYNC_DEMO_SIGNER_SHA256=<64-hex>.',
    );
  }

  // Fixed fictional configuration, loaded into dotenv's in-memory map only.
  // The prod-scoped `.env` asset is not readable by this build.
  dotenv.testLoad(
    mergeWith: const {
      'SUPABASE_URL': demoSupabaseUrl,
      'SUPABASE_PUBLISHABLE_KEY': demoPublishableKey,
    },
  );

  // Structural isolation: even the configured endpoint must be loopback.
  final endpoint = validateSupabaseEndpoint(
    dotenv.env['SUPABASE_URL'],
    release: false,
  );
  final endpointHost = Uri.parse(endpoint).host;
  if (!const {'127.0.0.1', 'localhost', '::1'}.contains(endpointHost)) {
    throw StateError('The demo preview refuses a non-loopback endpoint.');
  }

  await Supabase.initialize(
    url: endpoint,
    publishableKey:
        dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? demoPublishableKey,
    // Deny-by-default transport: the client never opens a socket, so no
    // request — not even to the loopback endpoint — leaves the process.
    httpClient: DemoFixtures.instance.transport,
    authOptions: const FlutterAuthClientOptions(
      // No token refresh traffic and no web-redirect session sniffing: the
      // demo session is local-only and nothing is persisted.
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
  );
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode(DemoFixtures.session()),
  );

  // Deterministic offline transport for both queue seams: every sync attempt
  // sees "no network", so nothing is ever sent anywhere.
  // ignore: invalid_use_of_visible_for_testing_member
  SyncOutboxService.hasConnectionOverride = () async => false;
  // ignore: invalid_use_of_visible_for_testing_member
  ReportQueueService.connectivityOverride = () async => false;

  await DemoFixtures.instance.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: _QaApp(profile: DemoFixtures.profile),
    ),
  );
}

class _QaApp extends StatefulWidget {
  const _QaApp({required this.profile});

  final UserProfile profile;
  @override
  State<_QaApp> createState() => _QaAppState();
}

class _QaAppState extends State<_QaApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _observer = ScreenProtectionObserver(
    ScreenProtectionService.instance,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldSync DEMO (Synthetic)',
      debugShowCheckedModeBanner: true,
      navigatorKey: _navigator,
      navigatorObservers: [_observer],
      builder: (context, child) => DemoWatermark(
        fixtures: DemoFixtures.instance,
        protection: ScreenProtectionService.instance,
        navigatorKey: _navigator,
        child: ScreenProtectionHost(child: child!),
      ),
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: InsightTheme.blue1,
        colorScheme: ColorScheme.light(
          primary: InsightTheme.blue1,
          secondary: InsightTheme.blue2,
          surface: InsightTheme.surface,
          error: InsightTheme.red,
        ),
        scaffoldBackgroundColor: InsightTheme.bg,
      ),
      home: MainShellScreen(
        profile: widget.profile,
        initialIndex: 0,
        offlineSession: true,
      ),
    );
  }
}
