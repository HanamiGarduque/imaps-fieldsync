import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imaps_fieldsync/core/widgets/field_form_widgets.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_edit_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/screens/splash_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
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
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(800, 360),
    const Size(768, 1024),
  ]) {
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
