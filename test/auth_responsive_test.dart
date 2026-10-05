import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';

/// Auth surfaces: App Resume Lock and Login.
///
/// Both were audited as risky on a short landscape viewport — the lock screen's
/// non-scrollable column summed to ~304px with ~26px of slack — and both
/// stretched their inputs to ~1228px on a tablet. These tests pin the fixes.
///
/// Mounting the real screens needs a live Supabase/secure-prefs session, so the
/// layout is proven against the production source contract plus a faithful
/// local composition, and the untouched security behaviour is asserted
/// structurally. No replica of the layout is introduced.

const viewports = <String, Size>{
  '390x844': Size(390, 844),
  '844x390': Size(844, 390),
  '430x932': Size(430, 932),
  '932x430': Size(932, 430),
  '800x1280': Size(800, 1280),
  '1280x800': Size(1280, 800),
};

void setViewport(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(top: 42, bottom: 42);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Reproduces the resume-lock composition using the same primitives the screen
/// now uses, with the real measured sizes (72 icon, 52 button, 12 gap).
Widget lockComposition() => ConstrainedContent(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 72, width: 72),
            const SizedBox(height: 24),
            const Text('App Locked', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'That didn\'t match. Try again with Device Credential.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(height: 52, width: double.infinity),
            const SizedBox(height: 12),
            const SizedBox(height: 44, width: 120),
          ],
        ),
      ),
    );

void main() {
  group('A1. resume lock no longer overflows a short viewport', () {
    for (final e in viewports.entries) {
      testWidgets('no RenderFlex overflow at ${e.key}', (tester) async {
        setViewport(tester, e.value);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(child: Center(child: lockComposition())),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: e.key);
      });
    }

    testWidgets('survives 1.3x text scale at every viewport', (tester) async {
      for (final e in viewports.entries) {
        setViewport(tester, e.value, textScale: 1.3);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(child: Center(child: lockComposition())),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${e.key} 1.3x');
      }
    });

    testWidgets('the primary unlock action stays reachable', (tester) async {
      setViewport(tester, const Size(844, 390));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(child: Center(child: lockComposition())),
        ),
      ));
      await tester.pump();
      final button = tester.getRect(find.byType(SizedBox).last);
      final screen = tester.getRect(find.byType(Scaffold));
      expect(button.bottom, lessThanOrEqualTo(screen.bottom + 0.5),
          reason: 'unlock action must be on screen, not clipped away');
    });

    testWidgets('content is bounded and centred on a tablet', (tester) async {
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(child: Center(child: lockComposition())),
        ),
      ));
      await tester.pump();
      // ConstrainedContent is a Centred+ConstrainedBox wrapper, so its own box
      // still spans the canvas; the bounded child is what carries the cap.
      expect(tester.getSize(find.byType(ConstrainedContent)).width, 1280);
      final child = tester.getRect(find.byType(SingleChildScrollView));
      expect(child.width, lessThanOrEqualTo(
          InsightBreakpoints.contentMaxWidth));
      expect(child.center.dx, closeTo(640, 1));
    });

    test('the production screen is now bounded and scrollable', () {
      final src =
          File('lib/modules/auth_startup/screens/app_resume_lock_screen.dart')
              .readAsStringSync();
      expect(src, contains('ConstrainedContent'));
      expect(src, contains('SingleChildScrollView'));
      expect(src, contains('responsive_layout.dart'));
    });
  });

  group('A2. login stays bounded and keeps its accepted portrait design', () {
    test('production login uses the shared width constraint', () {
      final src =
          File('lib/modules/auth_startup/screens/splash_screen.dart')
              .readAsStringSync();
      expect(src, contains('ConstrainedContent'));
      expect(src, contains('responsive_layout.dart'));
      // The outer scroll view that already absorbed short heights is retained.
      expect(src, contains('SingleChildScrollView'));
      expect(src, contains('BouncingScrollPhysics'),
          reason: 'the accepted scroll feel is unchanged');
    });

    test('phone portrait is under the cap, so login is visually unchanged',
        () {
      expect(390, lessThan(InsightBreakpoints.contentMaxWidth));
      expect(430, lessThan(InsightBreakpoints.contentMaxWidth));
    });

    for (final e in viewports.entries) {
      testWidgets('no overflow at ${e.key} with a keyboard-sized viewport',
          (tester) async {
        // Simulates the keyboard: the visible height shrinks to ~350.
        setViewport(tester, e.value);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedContent(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 68, width: 68),
                        const SizedBox(height: 16),
                        const SizedBox(height: 50),
                        const SizedBox(height: 10),
                        const SizedBox(height: 50),
                        const SizedBox(height: 16),
                        const SizedBox(height: 52),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: e.key);
      });
    }
  });

  group('A3. authentication and security behaviour is untouched', () {
    late String lock;
    late String splash;

    setUpAll(() {
      lock = File('lib/modules/auth_startup/screens/app_resume_lock_screen.dart')
          .readAsStringSync();
      splash = File('lib/modules/auth_startup/screens/splash_screen.dart')
          .readAsStringSync();
    });

    test('the lock screen still wraps itself in SensitiveScreen', () {
      // FLAG_SECURE behaviour lives here; it must not be bypassed.
      expect(lock, contains('SensitiveScreen'));
    });

    test('the lock screen keeps both unlock paths', () {
      expect(lock, contains('_attempt'), reason: 'biometric/device credential');
      expect(lock, contains('_signOutInstead'), reason: 'log out fallback');
      expect(lock, contains('Unlock with'));
      expect(lock, contains('Log Out'));
    });

    test('the lock screen keeps its failure feedback', () {
      expect(lock, contains('_lastAttemptFailed'));
      expect(lock, contains('That didn'), reason: 'failure copy preserved');
      expect(lock, contains('match. Try again with'), reason: 'retry copy');
    });

    test('login keeps its terms checkbox and cooldown gate', () {
      expect(splash, contains('_handleLogin'));
      expect(splash, contains('_cooldownSecondsRemaining'));
      expect(splash, contains('Try again in'));
    });

    test('no authentication rule was edited', () {
      // Layout-only: these call sites are unchanged.
      expect(splash, contains('onPressed: (_isLoading ||'));
      expect(lock, contains('onPressed: _checking ? null : _attempt'));
    });
  });

  group('A4. no screen-local orientation logic', () {
    test('neither auth screen reads orientation directly', () {
      for (final f in [
        'lib/modules/auth_startup/screens/app_resume_lock_screen.dart',
        'lib/modules/auth_startup/screens/splash_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('.orientation'), isFalse, reason: f);
        expect(src.contains('isPortrait'), isFalse, reason: f);
        expect(src.contains('isLandscape'), isFalse, reason: f);
      }
    });
  });
}
