import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

const offlineInspector = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const otherOfflineInspector = 'cccccccc-1111-4111-8111-cccccccccccc';
const offlineJob = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
const offlineRound2 = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const offlineProfile = {
  'id': offlineInspector,
  'full_name': 'Fixture Inspector',
  'role': 'inspector',
};

final offlineTask = TaskItem(
  id: offlineJob, parcelId: 'fictional-parcel', name: 'Fictional site',
  location: 'Isolated fixture only', parcels: '1', status: 'in_progress',
  inspectionNo: 'DEMO-FS04',
);

/// Real screens/services and SQLite; only platform/HTTP boundaries are fake.
/// No .env, real credentials, backend, GPS, provider HTTP or personal data.
class OfflineReliabilityFixture {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final secure = <String, String>{};
  final storageReplies = <String, Completer<String?>>{};
  final requests = <http.Request>[];
  final held = <({String stage, http.Request request,
    Completer<http.Response> response})>[];
  final captureKey = GlobalKey();
  late Directory directory;
  late Database db;
  late InspectionProvider provider;
  bool online = false;
  String mode = 'transport';
  Completer<List<String>>? connectivityReply;
  int remoteWrites = 0;
  /// Fictional remote rows a held or resolved `field_jobs` GET answers with.
  /// Used only by the `jobs-hold` mode; empty in every other mode.
  List<Map<String, dynamic>> jobsRows = [];

  /// Optional isolated HTTP boundary; null keeps every existing fixture mode.
  Future<http.Response?> Function(http.Request)? requestOverride;

  SupabaseClient get client => Supabase.instance.client;
  String get databasePath => '${directory.path}/fixture.db';

  Map<String, dynamic> session({bool expired = false,
    String owner = offlineInspector}) => {
    // Locally decoded JWT expiry is necessary: this SDK ignores expires_at.
    // This unsigned fictional token is never sent outside the mock client.
    'access_token': 'eyJhbGciOiJub25lIn0.'
        '${base64Url.encode(utf8.encode(jsonEncode({
          'sub': owner, 'exp': expired ? 946684800 : 2208988800,
        })))}.fixture-signature',
    'refresh_token': 'fixture-refresh', 'token_type': 'bearer',
    'expires_in': expired ? -3600 : 3600,
    'user': {'id': owner, 'email': 'fixture@example.test',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{}, 'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z'},
  };

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts');
    final fallback = fonts.listSync().whereType<File>()
        .firstWhere((f) => f.path.endsWith('.ttf')).readAsBytesSync();
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist', 'OpenSans']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [{'asset': asset}];
      }
    }
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (bytes) async {
      final asset = const StringCodec().decodeMessage(bytes)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset.startsWith('assets/')) {
        return ByteData.sublistView(File(asset).readAsBytesSync());
      }
      if (asset.endsWith('.ttf')) {
        final realFonts = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
        return ByteData.sublistView(realFonts == null
            ? fallback
            : File('$realFonts/${asset.split('-').first}.ttf').readAsBytesSync());
      }
      return null;
    });
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(
      File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
    // Material controls use Roboto; load the SDK font for readable status
    // explanations rather than the widget-test Ahem placeholder.
    await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(
      File('${fonts.path}/Roboto-Regular.ttf').readAsBytesSync())))).load();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read': return storageReplies[key]?.future ?? secure[key];
          case 'write': secure[key!] = args['value'] as String; return null;
          case 'delete': secure.remove(key); return null;
          case 'readAll': return Map<String, String>.of(secure);
          case 'deleteAll': secure.clear(); return null;
        }
        throw StateError('Unexpected isolated storage operation');
      });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async {
        final reply = connectivityReply;
        return reply == null ? [online ? 'wifi' : 'none'] : reply.future;
      });
    for (final channel in ['dev.fluttercommunity.plus/connectivity_status',
      'screen_protector', 'plugins.flutter.io/firebase_messaging']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'), (_) async => {
        'appName': 'Fixture', 'packageName': 'fixture', 'version': '0', 'buildNumber': '0',
      });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'), (call) async =>
        call.method == 'getAvailableBiometrics' ? <String>[] : false);
    await Supabase.initialize(url: 'https://fs04.test',
      publishableKey: 'fixture-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        if (request.url.host != 'fs04.test') {
          throw StateError('External requests are forbidden by this fixture');
        }
        requests.add(request);
        final overridden = await requestOverride?.call(request);
        if (overridden != null) return overridden;
        final path = request.url.path;
        final stage = path.contains('/token') ? 'refresh'
            : path.contains('/profiles') ? 'profile' : 'other';
        http.Response reply(Object data, int status) => http.Response(
          jsonEncode(data), status, request: request,
          headers: {'content-type': 'application/json',
            'x-supabase-api-version': '2024-01-01'},
        );
        if (path.contains('/logout')) return reply({}, 200);
        if ((mode == 'profile-hang' && stage == 'profile') ||
            (mode == 'refresh-hang' && stage == 'refresh')) {
          final response = Completer<http.Response>();
          held.add((stage: stage, request: request, response: response));
          return response.future;
        }
        // Holds the inspector-scoped assignment read so a test can decide when
        // (or whether) the refresh answers, without any real transport.
        if (mode == 'jobs-hold' && stage == 'other' &&
            (request.method == 'GET' || request.method == 'HEAD')) {
          final response = Completer<http.Response>();
          held.add((stage: 'jobs', request: request, response: response));
          return response.future;
        }
        if (mode == 'refresh-reject' && stage == 'refresh') {
          return reply({'code': 'refresh_token_not_found',
            'msg': 'Isolated server refusal'}, 400);
        }
        if (mode == 'profile-reject' && stage == 'profile') {
          return reply({'code': 'PGRST116',
            'message': 'Isolated missing profile'}, 406);
        }
        if (mode == 'profile-reject-network-text' && stage == 'profile') {
          return reply({'code': '42501',
            'message': 'Permission denied: clientexception is not transport'}, 403);
        }
        if (mode == 'transport') {
          throw const SocketException('Isolated unavailable transport');
        }
        if (stage == 'refresh') return reply(session(), 200);
        if (stage == 'profile') return reply(offlineProfile, 200);
        if (request.method == 'GET' || request.method == 'HEAD') return reply([], 200);
        if (path.startsWith('/rest/v1/rpc/')) return reply({}, 200);
        if (request.method != 'GET' && request.method != 'HEAD') remoteWrites++;
        return reply({}, 201);
      }));
  }

  Future<void> reset({bool expired = false}) async {
    secure.clear(); storageReplies.clear(); requests.clear(); held.clear();
    online = false; mode = 'transport'; connectivityReply = null; remoteWrites = 0;
    jobsRows = [];
    requestOverride = null;
    secure['sp_cached_profile'] = jsonEncode(offlineProfile);
    secure['sp_bio_require_on_open'] = 'false';
    await client.auth.setInitialSession(jsonEncode(session(expired: expired)));
    await AuthService.loadSoftLogoutState();
    // Each case starts with an actually validated inspector profile. This also
    // resolves the previous case's refusal state through production auth code.
    online = true; mode = 'success';
    await AuthService.getCurrentProfileOfflineAware();
    online = false; mode = 'transport'; requests.clear();
    directory = await Directory.systemTemp.createTemp('fieldsync-fs04-isolated-');
    // No-isolate SQLite avoids bridging real isolate IO into FakeAsync clocks.
    // It still executes actual file-backed SQLite transactions and triggers.
    db = await databaseFactoryFfiNoIsolate.openDatabase(databasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    await ReportQueueSchema.createTable(db);
    DBHelper.useDatabaseForTesting(db);
    await DBHelper.cacheJobs([
      {'id': offlineJob, 'assigned_inspector_id': offlineInspector,
        'status': 'in_progress', 'inspection_round': 1},
      {'id': offlineRound2, 'assigned_inspector_id': offlineInspector,
        'status': 'assigned', 'inspection_round': 2},
    ]);
    await DBHelper.retainInspectionJob(offlineJob);
    provider = InspectionProvider();
    await provider.startInspection(offlineTask);
    InspectionProgress.instance.reset();
    SyncOutboxService.hasConnectionOverride = () async => false;
  }

  void resolveHeld({bool rejectRefresh = false}) {
    for (final item in held.where((item) => !item.response.isCompleted)) {
      final rejection = rejectRefresh && item.stage == 'refresh';
      // `jobs` answers the held assignment read; every other stage keeps its
      // original auth payload.
      final Object body = rejection
          ? {'code': 'refresh_token_not_found', 'msg': 'Isolated server refusal'}
          : item.stage == 'profile'
              ? offlineProfile
              : item.stage == 'jobs' ? jobsRows : session();
      item.response.complete(http.Response(jsonEncode(body),
        rejection ? 400 : 200, request: item.request,
        headers: {'x-supabase-api-version': '2024-01-01'}));
    }
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
      await tester.pump();
    }
  }

  Future<void> mount(WidgetTester tester, Widget screen,
      {Size size = const Size(390, 844), double textScale = 1}) async {
    tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(() {
      tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
      tester.view.resetPadding(); tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(RepaintBoundary(key: captureKey,
      child: ChangeNotifierProvider.value(value: provider,
        child: MaterialApp(home: screen))));
  }

  void widgetTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try { await body(tester); }
      finally { await unmount(tester); }
    });
  }

  Future<void> unmount(WidgetTester tester) async {
    mode = 'success';
    for (final reply in storageReplies.entries) {
      if (!reply.value.isCompleted) reply.value.complete(secure[reply.key]);
    }
    if (connectivityReply?.isCompleted == false) connectivityReply!.complete(['none']);
    connectivityReply = null; resolveHeld();
    await tester.pumpWidget(const SizedBox.shrink());
    // Invariants run before addTearDown. Drain finite SDK/UI timers inside the
    // test body, preserving the real screens and their network side effects.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 10)); await flush(tester);
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final destination = Platform.environment['FS04_EVIDENCE_DIR'];
    if (destination == null) return;
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('$destination/screenshots'); folder.createSync(recursive: true);
      File('${folder.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> restartDatabase() async {
    DBHelper.useDatabaseForTesting(null); await db.close();
    db = await databaseFactoryFfiNoIsolate.openDatabase(databasePath);
    DBHelper.useDatabaseForTesting(db);
  }

  Future<void> closeCase() async {
    for (final reply in storageReplies.entries) {
      if (!reply.value.isCompleted) reply.value.complete(secure[reply.key]);
    }
    mode = 'success'; resolveHeld();
    SyncOutboxService.resetRecoverySessionForTesting();
    SyncOutboxService.hasConnectionOverride = null;
    provider.dispose(); DBHelper.useDatabaseForTesting(null); await db.close();
    await directory.delete(recursive: true);
  }

  Future<void> dispose() => Supabase.instance.dispose();
}
