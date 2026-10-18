import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/sensitive_screen.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_observer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  late ScreenProtectionService protection;
  setUp(() {
    calls.clear();
    // The service applies through this hook (real platforms additionally run
    // the screen_protector channel; desktop builds and tests carry none).
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure ? 'preventScreenshotOn' : 'preventScreenshotOff');
        return Future.value();
      },
    );
  });
  tearDown(() => protection.dispose());

  Future<GlobalKey<NavigatorState>> mount(
    WidgetTester tester,
    Widget page,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [ScreenProtectionObserver(protection)],
        builder: (_, child) => ScreenProtectionHost(
          protection: protection,
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
    return navigator;
  }

  Future<void> authorize(WidgetTester tester) async {
    // The settings UI/attestation is exercised end-to-end in
    // debug_screenshot_settings_test.dart; these tests isolate route policy.
    expect(protection.beginDocumentation(), isTrue);
    await tester.pumpAndSettle();
  }

  testWidgets('Generic page has no documentation screenshot control', (
    tester,
  ) async {
    await mount(tester, const Scaffold(body: Text('Generic help')));
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(calls, isNot(contains('preventScreenshotOn')));
  });

  testWidgets('Opaque generic route does not inherit hidden sensitive scope', (
    tester,
  ) async {
    final navigator = await mount(
      tester,
      const SensitiveScreen(child: Scaffold(body: Text('Demo record'))),
    );
    expect(calls.last, 'preventScreenshotOn');
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Generic help')),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last, 'preventScreenshotOff');
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls.last, 'preventScreenshotOn');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Protected push and pop never issue an unprotect command', (
    tester,
  ) async {
    final navigator = await mount(
      tester,
      const SensitiveScreen(child: Scaffold(body: Text('Demo A'))),
    );
    calls.clear();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const SensitiveScreen(child: Scaffold(body: Text('Demo B'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      calls,
      isNot(contains('preventScreenshotOff')),
      reason: 'during push',
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(protection.requiresProtection, isTrue);
    expect(protection.appliedProtection, isTrue);
    expect(calls, isNot(contains('preventScreenshotOff')));
  });

  testWidgets(
    'Transparent dialog retains privacy and hides documentation control',
    (tester) async {
      final navigator = await mount(
        tester,
        const SensitiveScreen(child: Scaffold(body: Text('Demo A'))),
      );
      showDialog<void>(
        context: navigator.currentState!.overlay!.context,
        builder: (_) => const AlertDialog(content: Text('Demo dialog')),
      );
      await tester.pumpAndSettle();
      expect(protection.requiresProtection, isTrue);
      expect(protection.appliedProtection, isTrue);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    },
  );

  testWidgets(
    'Native failure hides sensitive content and exposes a safe retry',
    (tester) async {
      var fail = true;
      protection.dispose();
      protection = ScreenProtectionService(
        applyProtection: (secure) async {
          if (fail) throw PlatformException(code: 'unavailable');
        },
      );
      await mount(
        tester,
        const SensitiveScreen(
          child: Scaffold(body: Text('Private demo record')),
        ),
      );
      expect(protection.nativeFailure, isTrue);
      // Content stays mounted underneath (live state no longer destroyed) while
      // the opaque curtain owns every pixel until protection is confirmed.
      final record = find.text('Private demo record');
      expect(record, findsOneWidget);
      final curtain = find.byKey(const ValueKey('privacy-curtain'));
      expect(curtain, findsOneWidget);
      expect(
        tester.getRect(curtain),
        tester.getRect(find.byType(ScreenProtectionHost)),
      );
      expect(find.text('Retry protection'), findsOneWidget);
      expect(find.byKey(const ValueKey('documentation-control')), findsNothing);
      fail = false;
      await tester.tap(find.text('Retry protection'));
      await tester.pumpAndSettle();
      expect(protection.appliedProtection, isTrue);
      expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
      expect(record, findsOneWidget);
    },
  );

  testWidgets('Resumed modal stays covered until native protection acknowledges',
      (tester) async {
    final ready = Completer<void>();
    var hold = false;
    protection.dispose();
    protection = ScreenProtectionService(applyProtection: (secure) =>
        secure && hold ? ready.future : Future.value());
    addTearDown(() async {
      if (!ready.isCompleted) ready.complete();
      await tester.pump();
    });
    final navigator = await mount(tester, const SensitiveScreen(
      child: Scaffold(body: Text('Fictional secured page')),
    ));
    await authorize(tester);
    var tapped = false;
    showModalBottomSheet<void>(
      context: navigator.currentState!.overlay!.context,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Fictional task location'),
        ElevatedButton(onPressed: () => tapped = true,
            child: const Text('Open task location')),
      ]),
    );
    await tester.pumpAndSettle();
    expect(protection.hasPopup, isTrue);
    final action = find.widgetWithText(ElevatedButton, 'Open task location');
    expect(action.hitTestable(), findsOneWidget);
    hold = true;
    protection.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isNull);
    expect(protection.mustObscure, isTrue);
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget,
        reason: 'a modal is above its sensitive page, so it needs the host cover');
    expect(action.hitTestable(), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(protection.appliedProtection, isTrue);
    expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
    await tester.tap(action);
    expect(tapped, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('No global debug control covers shutter or form actions', (
    tester,
  ) async {
    await mount(
      tester,
      SensitiveScreen(
        child: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['Shutter', 'Save', 'Next', 'Submit'])
                ElevatedButton(onPressed: () {}, child: Text(label)),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    for (final label in ['Shutter', 'Save', 'Next', 'Submit']) {
      expect(find.widgetWithText(ElevatedButton, label).hitTestable(), findsOneWidget);
    }
    expect(protection.appliedProtection, isTrue);
  });

  testWidgets(
    'Manual OFF restores protection without recreating live form state',
    (tester) async {
      await mount(
        tester,
        SensitiveScreen(child: Scaffold(body: TextFormField(
          initialValue: 'Fictional unsaved notes',
        ))),
      );
      final before = find.byType(TextField).evaluate().single;
      await authorize(tester);
      expect(protection.isDocumentationActive, isTrue);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      expect(protection.appliedProtection, isFalse);
      protection.endDocumentation();
      await tester.pumpAndSettle();
      expect(protection.appliedProtection, isTrue);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      expect(find.byType(TextField).evaluate().single, same(before));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Fictional unsaved notes');
    },
  );

  testWidgets('Retained hidden tabs cannot keep generic tab protected', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter changeTab;
    await mount(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          changeTab = setState;
          return Stack(
            children: [
              for (var index = 0; index < 2; index++)
                Offstage(
                  offstage: selected != index,
                  child: SensitiveScreenVisibility(
                    visible: selected == index,
                    child: SensitiveScreen(
                      child: Scaffold(body: Text('Fictional tab $index')),
                    ),
                  ),
                ),
              if (selected == 2) const Scaffold(body: Text('Generic tab')),
            ],
          );
        },
      ),
    );
    await authorize(tester);
    expect(protection.isDocumentationActive, isTrue);
    changeTab(() => selected = 1);
    await tester.pumpAndSettle();
    expect(protection.isDocumentationActive, isTrue);
    expect(protection.appliedProtection, isFalse);
    for (final tab in [0, 1, 0, 2]) {
      changeTab(() => selected = tab);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(protection.requiresProtection, isFalse);
    expect(protection.appliedProtection, isFalse);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
  });

  testWidgets('Privacy curtain preserves live form state across background', (
    tester,
  ) async {
    await mount(
      tester,
      SensitiveScreen(
        child: Scaffold(
          body: TextFormField(initialValue: 'Fictional initial notes'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Fictional unsaved notes');
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller;
    final before = find.byType(TextField).evaluate().single;
    protection.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    // Content is covered, not unmounted: the same element and controller keep
    // holding the unsaved draft while the privacy curtain owns the paint.
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    expect(find.byType(TextField).evaluate(), [before]);
    expect(controller!.text, 'Fictional unsaved notes');
    protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
    expect(find.text('Fictional unsaved notes'), findsOneWidget);
  });

  testWidgets('Route replacement and removal discard only hidden scopes', (
    tester,
  ) async {
    final navigator = await mount(
      tester,
      const SensitiveScreen(child: Scaffold(body: Text('Fictional A'))),
    );
    final second = MaterialPageRoute<void>(
      builder: (_) =>
          const SensitiveScreen(child: Scaffold(body: Text('Fictional B'))),
    );
    navigator.currentState!.push(second);
    await tester.pumpAndSettle();
    navigator.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Public help')),
      ),
    );
    await tester.pumpAndSettle();
    expect(protection.requiresProtection, isFalse);
    expect(protection.appliedProtection, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(protection.requiresProtection, isTrue);
  });

  testWidgets(
    'Nested navigator inherits parent visibility and handles inner push/pop',
    (tester) async {
      final nested = GlobalKey<NavigatorState>();
      final observer = ScreenProtectionObserver(protection);
      final navigator = await mount(
        tester,
        Navigator(
          key: nested,
          observers: [observer],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const SensitiveScreen(
              child: Scaffold(body: Text('Fictional nested record')),
            ),
          ),
        ),
      );
      expect(protection.requiresProtection, isTrue);
      nested.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Nested help')),
        ),
      );
      await tester.pumpAndSettle();
      expect(protection.requiresProtection, isFalse);
      nested.currentState!.pop();
      await tester.pumpAndSettle();
      expect(protection.requiresProtection, isTrue);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Outer public help')),
        ),
      );
      await tester.pumpAndSettle();
      expect(protection.requiresProtection, isFalse);
    },
  );
}
