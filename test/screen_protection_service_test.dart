import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScreenProtectionService protection;
  late List<bool> calls;
  setUp(() {
    calls = [];
    protection = ScreenProtectionService(
      applyProtection: (secure) async {
        calls.add(secure);
      },
    );
  });
  tearDown(() => protection.dispose());

  Future<void> enter(WidgetTester tester) async {
    protection.register(Object(), null);
    await tester.pump();
    expect(protection.appliedProtection, isTrue);
  }

  bool beginWithHiddenFrame() {
    final allowed = protection.beginDocumentation();
    if (allowed) {
      protection.confirmControlHidden(protection.documentationGeneration);
    }
    return allowed;
  }

  testWidgets('Documentation hides for 200ms then expires within 20 seconds', (
    tester,
  ) async {
    await enter(tester);
    expect(beginWithHiddenFrame(), isTrue);
    await tester.pump(const Duration(milliseconds: 199));
    expect(protection.appliedProtection, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(protection.isDocumentationActive, isTrue);
    expect(calls.last, isFalse);
    await tester.pump(const Duration(milliseconds: 19800));
    expect(protection.documentationPhase, DocumentationPhase.off);
    expect(protection.appliedProtection, isTrue);
  });

  testWidgets('A missing hidden-frame acknowledgment never disables privacy', (
    tester,
  ) async {
    await enter(tester);
    expect(protection.beginDocumentation(), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(protection.appliedProtection, isTrue);
    expect(protection.isDocumentationActive, isFalse);
    await tester.pump(const Duration(seconds: 19));
    expect(protection.documentationPhase, DocumentationPhase.off);
  });

  testWidgets(
    'Inactive and background states revoke permission, resume does not reauthorize',
    (tester) async {
      await enter(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        expect(beginWithHiddenFrame(), isTrue);
        await tester.pump(ScreenProtectionService.controlFadeDuration);
        protection.didChangeAppLifecycleState(state);
        await tester.pump();
        expect(protection.isDocumentationActive, isFalse);
        expect(protection.appliedProtection, isTrue);
        expect(protection.mustObscure, isTrue);
        protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(protection.appliedProtection, isTrue);
        expect(protection.mustObscure, isFalse);
      }
    },
  );

  testWidgets('Removing or changing visible scope revokes documentation', (
    tester,
  ) async {
    final token = Object();
    protection.register(token, null);
    await tester.pump();
    expect(beginWithHiddenFrame(), isTrue);
    await tester.pump(ScreenProtectionService.controlFadeDuration);
    protection.register(token, null, visible: false);
    protection.register(Object(), null);
    await tester.pump();
    expect(protection.documentationPhase, DocumentationPhase.off);
    expect(protection.appliedProtection, isTrue);
    expect(protection.requiresProtection, isTrue);
  });

  testWidgets('Account or lock invalidation restores immediately', (
    tester,
  ) async {
    await enter(tester);
    beginWithHiddenFrame();
    await tester.pump(ScreenProtectionService.controlFadeDuration);
    final epoch = protection.securityEpoch;
    protection.invalidateDocumentation();
    await tester.pump();
    expect(protection.securityEpoch, greaterThan(epoch));
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isTrue);
  });

  testWidgets('Failed native OFF never grants a capture session', (
    tester,
  ) async {
    protection.dispose();
    protection = ScreenProtectionService(
      applyProtection: (secure) async {
        calls.add(secure);
        if (!secure) throw StateError('plugin failure');
      },
    );
    await enter(tester);
    beginWithHiddenFrame();
    await tester.pump(ScreenProtectionService.controlFadeDuration);
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isTrue);
    expect(calls, [true, false, true]);
  });

  testWidgets(
    'Late OFF after timeout is followed by another protective write',
    (tester) async {
      protection.dispose();
      final off = Completer<void>();
      protection = ScreenProtectionService(
        applyProtection: (secure) {
          calls.add(secure);
          return secure ? Future.value() : off.future;
        },
      );
      await enter(tester);
      beginWithHiddenFrame();
      await tester.pump(ScreenProtectionService.controlFadeDuration);
      await tester.pump(ScreenProtectionService.nativeTimeout);
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      off.complete();
      await tester.pump();
      expect(calls, [true, false, true, true]);
      expect(protection.appliedProtection, isTrue);
    },
  );

  testWidgets(
    'Documentation can be restricted but never enabled outside debug',
    (tester) async {
      protection.dispose();
      protection = ScreenProtectionService(
        documentationEnabled: false,
        applyProtection: (_) async {},
      );
      await enter(tester);
      expect(protection.beginDocumentation(), isFalse);
      expect(protection.documentationEnabled, isFalse);
      expect(
        kDebugMode,
        isTrue,
      ); // release/profile proof is a separate Dart AOT check.
    },
  );

  testWidgets('Disposal cancels authorization and restores native protection', (
    tester,
  ) async {
    await enter(tester);
    beginWithHiddenFrame();
    await tester.pump(ScreenProtectionService.controlFadeDuration);
    protection.dispose();
    await tester.pump();
    expect(calls.last, isTrue);
    await tester.pump(const Duration(seconds: 21));
  });

  testWidgets('Disposal during a pending OFF restores protection immediately', (
    tester,
  ) async {
    protection.dispose();
    final off = Completer<void>();
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure);
        return secure ? Future.value() : off.future;
      },
    );
    await enter(tester);
    beginWithHiddenFrame();
    await tester.pump(ScreenProtectionService.controlFadeDuration);
    protection.dispose();
    await tester.pump();
    expect(calls, [true, false, true]);
    // A late native reply after disposal must not issue another write.
    off.complete();
    await tester.pump();
    expect(calls, [true, false, true]);
  });
}
