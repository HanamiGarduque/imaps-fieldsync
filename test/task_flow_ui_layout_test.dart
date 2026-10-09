import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_edit_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/security_settings_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/secure_prefs_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database profileDb;
  Completer<void>? analyticsGate;
  final task = TaskItem(
    id: 'ui-preview-job',
    name: 'Field inspection applicant',
    parcels: '1 parcel',
    location: 'San Carlos, Rosario — a long site address with an access road',
    status: 'completed',
    inspectionNo: 'FIELD-2026-0123456789',
    inspectorNotes:
        'The existing structure and road frontage were inspected. ' * 8,
    discrepancies:
        'A long recorded discrepancy describing the location and condition. ' *
        5,
    recommendations:
        'Confirm the supporting documents before the next review. ' * 5,
    inspectionResult: 'With Discrepancy',
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    profileDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await profileDb.execute(
      'CREATE TABLE local_jobs (id TEXT, status TEXT, inspector_id TEXT)',
    );
    await profileDb.execute(
      'CREATE TABLE pending_actions (job_id TEXT, type TEXT, status TEXT)',
    );
    DBHelper.useDatabaseForTesting(profileDb);
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final fallback = ByteData.sublistView(
      fonts
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset},
        ];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset == 'assets/icon/app_icon.png') {
        return ByteData.sublistView(File(asset).readAsBytesSync());
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null
          ? fallback
          : ByteData.sublistView(
              File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
            );
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('screen_protector'),
      (_) async => null,
    );
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
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async =>
          call.method == 'getAvailableBiometrics' ? <String>[] : true,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    await Supabase.initialize(
      url: 'https://ui-layout.test',
      publishableKey: 'fixture-key',
      httpClient: MockClient((request) async {
        final gate = analyticsGate;
        if (request.url.path.endsWith('/field_jobs') && gate != null) {
          await gate.future;
        }
        return http.Response(
          request.url.path.endsWith('/profiles')
              ? jsonEncode({
                  'id': 'ui-layout-inspector',
                  'full_name':
                      'Gemini Norawit Alexandria Maria Dela Cruz Example',
                  'role': 'inspector',
                  'avatar_url': null,
                })
              : '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fixture-token',
        'refresh_token': 'fixture-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'ui-layout-inspector',
          'email': 'gemini.norawit@example.com',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    await Supabase.instance.dispose();
    DBHelper.useDatabaseForTesting(null);
    await profileDb.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double scale = 2,
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    final provider = InspectionProvider()..hydrateForRework(task);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    if (screen is ProfileScreen) {
      await tester.runAsync(SupabaseService.fetchMyJobs);
    }
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'overview keeps numbered steps and independent assignment fields',
    (tester) async {
      for (final fields in [
        (true, true),
        (true, false),
        (false, true),
        (false, false),
      ]) {
        final assignedTask = TaskItem(
          id: task.id,
          name: task.name,
          parcels: task.parcels,
          location: task.location,
          status: 'in_progress',
          inspectionNo: task.inspectionNo,
          assignmentInstructions: fields.$1
              ? 'Verify the recorded residential use.'
              : null,
          assignedByName: fields.$2 ? 'Maria Santos' : null,
        );
        await mount(
          tester,
          ParcelDetailScreen(task: assignedTask),
          const Size(375, 900),
          scale: 1,
        );
        expect(find.text('01'), findsOneWidget);
        expect(find.text('06'), findsOneWidget);
        await tester.drag(find.byType(ListView).first, const Offset(0, -360));
        await tester.pumpAndSettle();
        expect(
          find.text('Verify the recorded residential use.'),
          fields.$1 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Maria Santos'),
          fields.$2 ? findsOneWidget : findsNothing,
        );
        if (fields.$1 && fields.$2) {
          final assignmentGroup = find
              .ancestor(
                of: find.text('Verify the recorded residential use.'),
                matching: find.byType(Column),
              )
              .first;
          expect(
            find.descendant(
              of: assignmentGroup,
              matching: find.text('Maria Santos'),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'long enlarged pinned identity leaves Log Out reachable above shell navigation',
    (tester) async {
      const name = 'Gemini Norawit Alexandria Maria Dela Cruz Example';
      final email =
          '${'inspector' * 7}@${'barangay' * 7}.${'municipal' * 6}.example.com';
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession!.toJson();
      final originalSession = jsonEncode(session);
      await auth.setInitialSession(
        jsonEncode({
          ...session,
          'user': {...auth.currentUser!.toJson(), 'email': email},
        }),
      );
      final gate = analyticsGate = Completer<void>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        analyticsGate = null;
        await tester.runAsync(SupabaseService.fetchMyJobs);
        await auth.setInitialSession(originalSession);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            extendBody: true,
            body: ProfileScreen(
              profile: UserProfile(
                id: 'ui-layout-inspector',
                fullName: name,
                role: 'inspector',
              ),
            ),
            bottomNavigationBar: const SizedBox(
              height: kInsightBottomNavReserve,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump(const Duration(seconds: 1));
      final identity = find.byType(ProfileIdentityCard);
      expect(tester.widget<ProfileIdentityCard>(identity).compact, isTrue);
      expect(
        tester.getBottomLeft(identity).dy,
        lessThan(640 - kInsightBottomNavReserve - 48),
        reason: 'Identity must leave a usable menu viewport above navigation.',
      );
      await tester.scrollUntilVisible(
        find.text('Log Out'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Log Out').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('profile-edit-button')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(name), findsOneWidget);
      expect(find.text('Zoning Officer I'), findsOneWidget);
      expect(find.text(email), findsOneWidget);
      final details = find.descendant(
        of: identity,
        matching: find.byType(Scrollable),
      );
      expect(details, findsOneWidget);
      await tester.drag(details, const Offset(0, -1000));
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.state<ScrollableState>(details).position.pixels,
        greaterThan(0),
      );
      expect(
        tester.getBottomLeft(find.text(email)).dy,
        lessThanOrEqualTo(tester.getBottomLeft(identity).dy),
      );
      await tester.drag(details, const Offset(0, 80));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<ProfileIdentityCard>(identity).compact,
        isTrue,
        reason:
            'Scrolling identity details must not change the page scroll state.',
      );
      await tester.tap(find.text('Log Out'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(800, 360),
    const Size(768, 1024),
  ]) {
    // The accepted Analytics chart has an existing 320px / 2x overflow;
    // narrow 2x identity wrapping is covered in profile_header_name_layout_test.
    final profileScale = size.width == 320 ? 1.0 : 2.0;
    testWidgets(
      'pinned identity and Log Out remain reachable at $size / $profileScale',
      (tester) async {
        const name = 'Gemini Norawit Alexandria Maria Dela Cruz Example';
        await mount(
          tester,
          ProfileScreen(
            profile: UserProfile(
              id: 'ui-layout-inspector',
              fullName: name,
              role: 'inspector',
            ),
          ),
          size,
          scale: profileScale,
        );
        expect(tester.takeException(), isNull);
        final identity = find.byType(ProfileIdentityCard);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(tester.widget<ProfileIdentityCard>(identity).compact, isTrue);
        await tester.scrollUntilVisible(
          find.text('Log Out'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        for (final field in [
          name,
          'Zoning Officer I',
          'gemini.norawit@example.com',
          'Edit',
          'Log Out',
        ]) {
          expect(find.text(field).hitTestable(), findsOneWidget);
        }
        final card = tester.getRect(identity);
        expect(card.top, greaterThanOrEqualTo(0));
        expect(card.bottom, lessThan(tester.getRect(find.text('Log Out')).top));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
        await tester.pumpAndSettle();
        expect(tester.widget<ProfileIdentityCard>(identity).compact, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'confirmed completion remains readable and action reachable at $size / 2x',
      (tester) async {
        await mount(
          tester,
          SubmissionSuccessScreen(
            referenceNo: task.inspectionNo,
            finalStatus: 'Requires Reinspection',
          ),
          size,
        );
        expect(tester.takeException(), isNull);
        final action = find.byType(ElevatedButton);
        await tester.scrollUntilVisible(
          action,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(size.height));
        expect(find.textContaining('Requires Reinspection'), findsOneWidget);
        expect(find.text('Inspection Submitted'), findsOneWidget);
      },
    );
    testWidgets('later-step context and existing actions survive $size / 2x', (
      tester,
    ) async {
      await mount(tester, InspectionChecklistScreen(task: task), size);
      expect(tester.takeException(), isNull);
      expect(find.text('Zoning Checklist'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(ElevatedButton, 'Save'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Save')).bottom,
        lessThanOrEqualTo(size.height),
      );
    });
  }

  testWidgets(
    'long findings remain identified and Save reachable above a keyboard',
    (tester) async {
      await mount(
        tester,
        FieldFindingsScreen(task: task),
        const Size(360, 800),
        keyboard: 320,
      );
      final notes = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller!.text == task.inspectorNotes,
      );
      await tester.scrollUntilVisible(
        notes,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(notes).controller!.text,
        task.inspectorNotes,
      );
      final details = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller!.text == task.discrepancies,
      );
      await tester.scrollUntilVisible(
        details,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(details).decoration!.labelText,
        isNotNull,
        reason: 'filled narrative fields must retain their identity',
      );
      expect(tester.widget<TextField>(details).maxLines, isNot(1));
      await tester.scrollUntilVisible(
        find.widgetWithText(ElevatedButton, 'Save'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Save')).bottom,
        lessThanOrEqualTo(480),
      );
    },
  );

  testWidgets('queued presentation never claims server-confirmed completion', (
    tester,
  ) async {
    await mount(
      tester,
      SubmissionSuccessScreen(
        referenceNo: task.inspectionNo,
        finalStatus: 'For Review',
        queuedOffline: true,
      ),
      const Size(360, 800),
      scale: 1,
    );
    expect(find.text('Saved Offline'), findsOneWidget);
    expect(find.text('Inspection Submitted'), findsNothing);
    expect(find.textContaining('For Review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty photo evidence explains the requirement and exposes a named capture action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, CapturePhotoScreen(task: task), const Size(320, 640));
      final capture = find.bySemanticsLabel('Add site photo');
      await tester.scrollUntilVisible(
        capture,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(capture).shortestSide, greaterThanOrEqualTo(48));
      expect(find.textContaining('at least one photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('camera capture gates notes and saving, retakes, and returns saved evidence to the grid', (tester) async {
    final semantics = tester.ensureSemantics();
    final root = Platform.isWindows
        ? Directory('${Platform.environment['LOCALAPPDATA']}/Temp/opencode')
        : Directory.systemTemp;
    final directory = root.createTempSync('fieldsync-camera-');
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final raw = File('${directory.path}/raw.jpg')
      ..writeAsBytesSync(image.encodeJpg(image.Image(width: 320, height: 480)));
    const cameraChannel = MethodChannel('plugins.flutter.io/camera');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(cameraChannel, (call) async {
      switch (call.method) {
        case 'availableCameras':
          return [{'name': 'back', 'lensFacing': 'back', 'sensorOrientation': 90}];
        case 'create':
          return {'cameraId': 1};
        case 'initialize':
          binding.channelBuffers.push('flutter.io/cameraPlugin/camera1',
            const StandardMethodCodec().encodeMethodCall(const MethodCall('initialized', {
              'previewWidth': 320.0, 'previewHeight': 480.0,
              'exposureMode': 'auto', 'focusMode': 'auto',
              'exposurePointSupported': false, 'focusPointSupported': false,
            })), (_) {});
          return null;
        case 'takePicture':
          return raw.path;
        case 'dispose':
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel,
        (call) async => call.method == 'getApplicationDocumentsDirectory' ? directory.path : null);
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(cameraChannel, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
    });
    await mount(tester, CapturePhotoScreen(task: task), const Size(360, 800), scale: 1);
    await tester.tap(find.bySemanticsLabel('Add site photo'));
    await tester.pumpAndSettle();
    final shutter = find.bySemanticsLabel('Capture site photo');
    expect(shutter, findsOneWidget);
    expect(tester.getSize(shutter).shortestSide, greaterThanOrEqualTo(48));
    expect(find.text('Photo notes'), findsNothing);
    expect(find.text('Save Photo'), findsNothing);
    expect(find.text('Retake'), findsNothing);
    final preview = find.byType(Texture);
    expect(tester.getRect(shutter).top, greaterThan(tester.getRect(preview).bottom),
        reason: 'The shutter must not be obstructed by the preview/geotag overlay.');
    Future<void> capture() async {
      await tester.ensureVisible(shutter);
      await tester.runAsync(() async {
        await tester.tap(shutter);
        for (var frame = 0; frame < 250 && find.text('Photo notes').evaluate().isEmpty; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Photo notes'), findsOneWidget);
      expect(find.text('Save Photo'), findsOneWidget);
      expect(shutter, findsNothing);
    }
    await capture();
    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();
    expect(find.text('Photo notes'), findsNothing);
    expect(shutter, findsOneWidget);
    await capture();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Local fixture photo notes');
    await tester.ensureVisible(find.text('Save Photo'));
    await tester.tap(find.text('Save Photo'));
    await tester.pumpAndSettle();
    final provider = tester.element(find.byType(CapturePhotoScreen)).read<InspectionProvider>();
    expect(provider.capturedPhotos, hasLength(1));
    expect(provider.capturedPhotos.single['notes'], 'Local fixture photo notes');
    expect(File(provider.capturedPhotos.single['photoPath'] as String).existsSync(), isTrue);
    expect(find.text('Capture Site Photo'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('View photo 1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('security status distinguishes enrollment from activated login and reports actual opening protection', (tester) async {
    final storage = <String, String>{};
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    const localAuth = MethodChannel('plugins.flutter.io/local_auth');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(localAuth,
        (call) async => call.method == 'getAvailableBiometrics' ? ['fingerprint'] : true);
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(localAuth,
        (call) async => call.method == 'getAvailableBiometrics' ? <String>[] : true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'read': return storage[args['key']];
        case 'write': storage[args['key'] as String] = args['value'] as String; return null;
        case 'delete': storage.remove(args['key']); return null;
        default: return null;
      }
    });
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, (_) async => null));
    final profile = UserProfile(id: 'ui-layout-inspector', fullName: 'Inspector', role: 'inspector');
    await mount(tester, SecuritySettingsScreen(profile: profile), const Size(360, 800), scale: 1);
    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch).first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Pending Activation'), findsOneWidget);
    expect(find.textContaining('Fingerprint Active'), findsNothing);
    await SecurePrefsService.setBioConfirmed(true);
    await SecurePrefsService.setBioRequireOnOpen(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, SecuritySettingsScreen(profile: profile), const Size(320, 640));
    expect(find.text('Fingerprint Active'), findsOneWidget);
    expect(find.textContaining('App opening protection off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review groups each section in its own surface', (tester) async {
    await mount(
      tester,
      ReviewSubmitScreen(task: task),
      const Size(360, 800),
      scale: 1,
    );
    for (final row in [
      'Applicant',
      'Coordinates',
      'Structure matches declared use',
      task.inspectorNotes!,
    ]) {
      final target = find.text(row);
      if (target.evaluate().isEmpty) continue;
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.ancestor(of: target, matching: find.byType(FieldReadOnlyCard)),
        findsWidgets,
        reason: '$row must read inside a grouped surface, not as a bare row',
      );
    }
    // The always-present record card keeps its own labels grouped.
    for (final row in ['Site Location', 'Checklist', 'Photos', 'Assessment']) {
      expect(
        find.ancestor(
          of: find.text(row),
          matching: find.byType(FieldReadOnlyCard),
        ),
        findsWidgets,
        reason: '$row must not read as a bare label on the canvas',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('findings hints keep full guidance but render below the title', (
    tester,
  ) async {
    await mount(
      tester,
      FieldFindingsScreen(task: task),
      const Size(360, 800),
      scale: 1,
    );
    final titleSize = tester
        .widget<Text>(find.text('Observations'))
        .style!
        .fontSize!;
    for (final hint in [
      'Record the site condition, land use and notable features.',
      'Optional. Leave these fields blank if no issues were found.',
      'Describe any permits, follow-up or other recommended action.',
    ]) {
      final target = find.text(hint);
      expect(
        target,
        findsOneWidget,
        reason: 'the guidance must stay readable in full, word for word',
      );
      expect(
        tester.widget<Text>(target).style!.fontSize!,
        lessThan(titleSize),
        reason: 'a hint must not compete with its own section title',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review exposes restored evidence without truncating narratives',
    (tester) async {
      await mount(
        tester,
        ReviewSubmitScreen(task: task),
        const Size(360, 800),
        scale: 1,
      );
      expect(
        tester.getTopLeft(find.text('Applicant')).dx,
        closeTo(tester.getTopLeft(find.text('Site Location')).dx, 0.5),
        reason: 'read-only labels must share a consistent reading edge',
      );
      await mount(tester, ReviewSubmitScreen(task: task), const Size(360, 800));
      final notes = find.text(task.inspectorNotes!);
      await tester.scrollUntilVisible(
        notes,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<Text>(notes).maxLines, isNull);
      expect(find.text(task.discrepancies!), findsOneWidget);
      final submit = find.widgetWithText(ElevatedButton, 'Submit Inspection');
      await tester.scrollUntilVisible(
        submit,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(800));
    },
  );

  testWidgets(
    'profile photo is named and form/save remain accessible with enlarged text and keyboard',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final profile = UserProfile(
        id: 'ui-layout-inspector',
        fullName: 'Gemini Norawit Example',
        role: 'inspector',
        phoneNumber: '09171234567',
      );
      await mount(
        tester,
        ProfileEditScreen(profile: profile),
        const Size(320, 640),
        keyboard: 240,
      );
      final photo = find.bySemanticsLabel(RegExp('Change profile photo'));
      await tester.scrollUntilVisible(
        photo,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(photo).shortestSide, greaterThanOrEqualTo(48));
      final name = find.byWidgetPredicate(
        (w) => w is TextField && w.controller!.text == profile.fullName,
      );
      await tester.scrollUntilVisible(
        name,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextField>(name).decoration!.labelText, isNotNull);
      final save = find.widgetWithText(ElevatedButton, 'Save changes');
      await tester.scrollUntilVisible(
        save,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'both login legal links remain keyboard reachable and open the correct notice',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, const LoginScreen(), const Size(360, 800), scale: 1);
      SemanticsNode? namedNode(SemanticsNode node, String label) {
        if (node.getSemanticsData().label == label) return node;
        SemanticsNode? result;
        node.visitChildren((child) {
          result ??= namedNode(child, label);
          return result == null;
        });
        return result;
      }

      for (final (label, heading) in [
        ('Terms of Use', '1. Authorized Use & Municipal Purpose'),
        ('Privacy Policy', '1. Information We Collect & Process'),
      ]) {
        // ignore: deprecated_member_use
        final root = binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        SemanticsNode? link() => namedNode(root, label);
        expect(link(), isNotNull);
        // These are inline links inside one sentence, so they stay at the
        // baseline 48x24 text-link box (keyboard-focusable) rather than the
        // 48px-square floor reserved for standalone tap targets; a taller box
        // would push the two notice sentences apart again.
        expect(tester.getSize(find.widgetWithText(TextButton, label)).width,
            greaterThanOrEqualTo(48), reason: 'Legal links keep a 48px minimum width.');
        expect(tester.getSize(find.widgetWithText(TextButton, label)).height,
            lessThanOrEqualTo(20), reason: 'Inline links must not inflate the sentence line.');
        // ignore: deprecated_member_use
        final flags = link()!.getSemanticsData().flagsCollection;
        expect(
          flags.isFocused != Tristate.none,
          isTrue,
          reason: '$label must be keyboard-focusable',
        );
        var tabsLeft = 12;
        while (link()!.getSemanticsData().flagsCollection.isFocused !=
                Tristate.isTrue &&
            --tabsLeft >= 0) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(
          link()!.getSemanticsData().flagsCollection.isFocused,
          Tristate.isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text(heading), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login legal notice reads as one compact sentence below the brand, '
    'without a sign-in heading competing with the app title',
    (tester) async {
      await mount(tester, const LoginScreen(), const Size(360, 800), scale: 1);
      await tester.ensureVisible(find.byTooltip('Show passcode'));
      await tester.pumpAndSettle();
      final notice = tester.getRect(
        find.ancestor(
          of: find.text('Authorized MPDO personnel only.'),
          matching: find.byType(Column),
        ).first,
      );
      final links = find.text('Terms of Use');
      final lastLine = tester.getRect(find.text('Authorized MPDO personnel only.'));
      // Two 12px lines at 1.4 line-height need ~17px each; the notice should read
      // as one tight block. Anything past ~24px means a gap crept back in.
      expect(
        lastLine.top - tester.getRect(links).bottom,
        lessThanOrEqualTo(24),
        reason: 'The two notice sentences must not drift apart.',
      );
      expect(
        notice.height,
        lessThanOrEqualTo(64),
        reason: 'A two-sentence notice must not occupy a tall empty block.',
      );
      // The notice supports the brand block; it must not read as a second title.
      expect(find.text('Inspector sign-in'), findsNothing);
      expect(find.text('Use your authorized inspector account.'), findsNothing);
      final brand = tester.getRect(find.text('FieldSync'));
      expect(brand.top, lessThan(notice.top),
          reason: 'The app title must stay above the legal notice.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login retains a named passcode toggle and reachable sign-in with large text and keyboard',
    (tester) async {
      await mount(
        tester,
        const LoginScreen(),
        const Size(320, 640),
        keyboard: 240,
      );
      final reveal = find.byTooltip('Show passcode');
      await tester.scrollUntilVisible(
        reveal,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(TextFormField).last,
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      final signIn = find.widgetWithText(ElevatedButton, 'Sign in');
      await tester.scrollUntilVisible(
        signIn,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(signIn).bottom, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    },
  );
}
