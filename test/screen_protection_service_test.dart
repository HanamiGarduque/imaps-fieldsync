import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/native_screen_protection_ack.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const validPin =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  late ScreenProtectionService protection;
  late List<bool> calls;
  setUp(() async {
    calls = [];
    protection = ScreenProtectionService(
      applyProtection: (secure) async {
        calls.add(secure);
      },
      verifyIdentity: () async => true,
    );
    // Every suite here runs as a verified demo identity; the default-deny
    // contract is asserted explicitly further below.
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: validPin,
        packageName: ScreenProtectionService.demoPackageName,
        buildSignature: validPin,
      ),
      isTrue,
    );
  });
  tearDown(() {
    protection.revokeQaDocumentation();
    protection.dispose();
  });

  Future<void> enter(WidgetTester tester) async {
    protection.register(Object(), null);
    await tester.pump();
    expect(protection.appliedProtection, isTrue);
  }

  Future<bool> beginDocumentation() => protection.beginDocumentation();

  testWidgets('Documentation stays enabled until manually switched off', (
    tester,
  ) async {
    await enter(tester);
    expect(await beginDocumentation(), isTrue);
    await tester.pump();
    expect(protection.isDocumentationActive, isTrue);
    expect(calls.last, isFalse);
    await tester.pump(const Duration(seconds: 60));
    expect(protection.isDocumentationActive, isTrue);
    expect(protection.appliedProtection, isFalse);
    protection.endDocumentation();
    await tester.pump();
    expect(protection.documentationPhase, DocumentationPhase.off);
    expect(protection.appliedProtection, isTrue);
  });

  testWidgets('Pending native OFF does not grant a capture session', (
    tester,
  ) async {
    protection.dispose();
    final off = Completer<void>();
    protection = ScreenProtectionService(
      applyProtection: (secure) => secure ? Future.value() : off.future,
      verifyIdentity: () async => true,
    );
    await enter(tester);
    expect(await protection.beginDocumentation(), isTrue);
    await tester.pump();
    expect(protection.appliedProtection, isNull);
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.mustObscure, isTrue);
    off.complete();
    await tester.pump();
    expect(protection.isDocumentationActive, isTrue);
    expect(protection.appliedProtection, isFalse);
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
        expect(await beginDocumentation(), isTrue);
        await tester.pump();
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

  testWidgets('Ordinary visible-scope changes retain the manual debug setting', (
    tester,
  ) async {
    final token = Object();
    protection.register(token, null);
    await tester.pump();
    expect(await beginDocumentation(), isTrue);
    await tester.pump();
    protection.register(token, null, visible: false);
    protection.register(Object(), null);
    await tester.pump();
    expect(protection.documentationPhase, DocumentationPhase.active);
    expect(protection.appliedProtection, isFalse);
    expect(protection.requiresProtection, isTrue);
  });

  testWidgets('Account or lock invalidation restores immediately', (
    tester,
  ) async {
    await enter(tester);
    await beginDocumentation();
    await tester.pump();
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
      verifyIdentity: () async => true,
    );
    await enter(tester);
    await beginDocumentation();
    await tester.pump();
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
        verifyIdentity: () async => true,
      );
      await enter(tester);
      await beginDocumentation();
      await tester.pump();
      await tester.pump(ScreenProtectionService.nativeTimeout);
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      off.complete();
      await tester.pump();
      expect(calls, [true, false, true, true]);
      expect(protection.appliedProtection, isTrue);
    },
  );

  testWidgets('Stale ON cannot uncover a newer security epoch', (tester) async {
    protection.dispose();
    final stale = Completer<void>();
    final current = Completer<void>();
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure);
        return calls.length == 1 ? stale.future : current.future;
      },
      verifyIdentity: () async => true,
    );
    protection.register(Object(), null);
    await tester.pump();
    protection.invalidateDocumentation();
    await tester.pump();
    stale.complete();
    await tester.pump();
    expect(protection.mustObscure, isTrue);
    expect(protection.appliedProtection, isNull);
    expect(calls, [true, true]);
    current.complete();
    await tester.pump();
    expect(protection.appliedProtection, isTrue);
    expect(protection.mustObscure, isFalse);
  });

  testWidgets('Stale OFF cannot activate capture after a scope change', (
    tester,
  ) async {
    protection.dispose();
    final off = Completer<void>();
    final restored = Completer<void>();
    var offStarted = false;
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure);
        if (!secure) {
          offStarted = true;
          return off.future;
        }
        return offStarted ? restored.future : Future.value();
      },
      verifyIdentity: () async => true,
    );
    await enter(tester);
    await protection.beginDocumentation();
    await tester.pump();
    protection.register(Object(), null);
    await tester.pump();
    off.complete();
    await tester.pump();
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.mustObscure, isTrue);
    expect(protection.appliedProtection, isNull);
    expect(calls, [true, false, true]);
    restored.complete();
    await tester.pump();
    expect(protection.appliedProtection, isTrue);
    expect(protection.isDocumentationActive, isFalse);
  });

  testWidgets('Revocation serializes native ON requests', (tester) async {
    protection.dispose();
    final first = Completer<void>();
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure);
        return calls.length == 1 ? first.future : Future.value();
      },
    );
    protection.register(Object(), null);
    await tester.pump();
    protection.revokeQaDocumentation();
    await tester.pump();
    expect(calls, [true]);
    expect(protection.mustObscure, isTrue);
    first.completeError(StateError('superseded ON'));
    await tester.pump();
    expect(calls, [true, true]);
    expect(protection.appliedProtection, isTrue);
    expect(protection.nativeFailure, isFalse);
  });

  testWidgets('Stale ON failure cannot poison the current security epoch', (
    tester,
  ) async {
    protection.dispose();
    final first = Completer<void>();
    protection = ScreenProtectionService(
      applyProtection: (secure) {
        calls.add(secure);
        return calls.length == 1 ? first.future : Future.value();
      },
    );
    protection.register(Object(), null);
    await tester.pump();
    protection.invalidateDocumentation();
    first.completeError(StateError('old window failed'));
    await tester.pump();
    expect(calls, [true, true]);
    expect(protection.appliedProtection, isTrue);
    expect(protection.nativeFailure, isFalse);
    expect(protection.mustObscure, isFalse);
  });

  testWidgets(
    'Documentation can be restricted but never enabled outside debug',
    (tester) async {
      protection.dispose();
      protection = ScreenProtectionService(
        documentationEnabled: false,
        applyProtection: (_) async {},
      );
      await enter(tester);
      expect(await protection.beginDocumentation(), isFalse);
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
    await beginDocumentation();
    await tester.pump();
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
      verifyIdentity: () async => true,
    );
    await enter(tester);
    await beginDocumentation();
    await tester.pump();
    protection.dispose();
    await tester.pump();
    expect(calls, [true, false, true]);
    // A late native reply after disposal must not issue another write.
    off.complete();
    await tester.pump();
    expect(calls, [true, false, true]);
  });

  testWidgets('Documentation is denied until the demo identity grants it', (
    tester,
  ) async {
    // Start from the regular-app posture: no verified demo identity.
    protection.revokeQaDocumentation();
    await enter(tester);
    expect(protection.documentationEnabled, isFalse);
    expect(await beginDocumentation(), isFalse);
    expect(protection.isDocumentationActive, isFalse);
    // A wrong package cannot grant either.
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: validPin,
        packageName: 'com.example.imaps_fieldsync',
        buildSignature: validPin,
      ),
      isFalse,
    );
    expect(protection.documentationEnabled, isFalse);
    // The verified matrix grants, and the session can then begin.
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: validPin,
        packageName: ScreenProtectionService.demoPackageName,
        buildSignature: validPin,
      ),
      isTrue,
    );
    expect(protection.documentationEnabled, isTrue);
    expect(await beginDocumentation(), isTrue);
    await tester.pump();
    expect(protection.isDocumentationActive, isTrue);
    expect(calls.last, isFalse);
  });

  testWidgets('Revoking the grant closes the session and restores protection', (
    tester,
  ) async {
    await enter(tester);
    expect(await beginDocumentation(), isTrue);
    await tester.pump();
    expect(protection.isDocumentationActive, isTrue);
    protection.revokeQaDocumentation();
    await tester.pump();
    expect(protection.documentationEnabled, isFalse);
    expect(protection.isDocumentationActive, isFalse);
    expect(protection.appliedProtection, isTrue);
    expect(await beginDocumentation(), isFalse);
  });

  group('authorization races', () {
    late List<Completer<bool>> identities;
    Completer<void>? nativeOff;
    setUp(() {
      protection.dispose();
      identities = [];
      nativeOff = null;
      protection = ScreenProtectionService(
        applyProtection: (secure) {
          calls.add(secure);
          return !secure && nativeOff != null ? nativeOff!.future : Future.value();
        },
        verifyIdentity: () {
          final result = Completer<bool>();
          identities.add(result);
          return result.future;
        },
      );
    });

    Future<bool> grant() => protection.grantQaDocumentation(
      debugMode: true,
      onAndroid: true,
      qaPreview: true,
      flavor: 'demo',
      pin: validPin,
      packageName: ScreenProtectionService.demoPackageName,
      buildSignature: validPin,
    );

    for (final boundary in [
      'end', 'invalidate', 'revoke', 'inactive', 'hidden', 'paused',
      'detach/attach', 'scope change', 'dispose',
    ]) {
      testWidgets('$boundary cancels pending activation', (tester) async {
        if (boundary == 'detach/attach') protection.attach();
        await enter(tester);
        final pending = protection.beginDocumentation();
        expect(identities, hasLength(1));
        switch (boundary) {
          case 'end':
            protection.endDocumentation();
            break;
          case 'invalidate':
            protection.invalidateDocumentation();
            break;
          case 'revoke':
            protection.revokeQaDocumentation();
            break;
          case 'inactive':
          case 'hidden':
          case 'paused':
            protection.didChangeAppLifecycleState(
              AppLifecycleState.values.byName(boundary),
            );
            protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
            break;
          case 'detach/attach':
            protection.detach();
            protection.attach();
            break;
          case 'scope change':
            protection.register(Object(), null);
            break;
          case 'dispose':
            protection.dispose();
            break;
        }
        final generation = protection.documentationGeneration;
        identities.single.complete(true);
        final accepted = await pending;
        await tester.pump();
        expect(accepted, isFalse,
          reason: 'A late identity result must not revive $boundary authorization.');
        expect(protection.documentationGeneration, generation);
        expect(protection.documentationPhase, DocumentationPhase.off);
        expect(protection.appliedProtection, isTrue);
        expect(calls, [true]);
      });
    }

    for (final popup in [false, true]) {
      testWidgets('${popup ? 'popup' : 'transition'} denies pending activation', (
        tester,
      ) async {
        final observer = NavigatorObserver();
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            observers: [observer],
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => const SizedBox(),
            ),
          ),
        ));
        await enter(tester);
        final pending = protection.beginDocumentation();
        protection.updateNavigation(observer, known: {}, visible: {},
          parent: null, transitioning: !popup, popup: popup);
        identities.single.complete(true);
        final accepted = await pending;
        await tester.pump();
        expect(accepted, isFalse);
        expect(protection.documentationPhase, DocumentationPhase.off);
        expect(protection.appliedProtection, isTrue);
        expect(calls, [true]);
      });
    }

    for (final revoke in [false, true]) {
      testWidgets('a new grant${revoke ? ' after revoke' : ''} fences stale activation', (
        tester,
      ) async {
        await enter(tester);
        final stale = protection.beginDocumentation();
        if (revoke) protection.revokeQaDocumentation();
        expect(await grant(), isTrue);
        final fresh = protection.beginDocumentation();
        identities[1].complete(true);
        expect(await fresh, isTrue);
        await tester.pump();
        final generation = protection.documentationGeneration;
        identities[0].complete(true);
        final accepted = await stale;
        await tester.pump();
        expect(accepted, isFalse);
        expect(protection.documentationGeneration, generation);
        expect(protection.isDocumentationActive, isTrue);
        expect(protection.appliedProtection, isFalse);
        expect(calls, [true, false]);
      });
    }

    for (final first in [0, 1]) {
      testWidgets('duplicate pending activation accepts only completion $first', (
        tester,
      ) async {
        nativeOff = Completer<void>();
        await enter(tester);
        final generation = protection.documentationGeneration;
        final requests = [
          protection.beginDocumentation(), protection.beginDocumentation(),
        ];
        expect(identities, hasLength(2));
        identities[first].complete(true);
        final accepted = await requests[first];
        await tester.pump();
        final phaseWhilePending = protection.documentationPhase;
        identities[1 - first].complete(true);
        final duplicate = await requests[1 - first];
        nativeOff!.complete();
        await tester.pump();
        expect(accepted, isTrue);
        expect(duplicate, isFalse);
        expect(phaseWhilePending, DocumentationPhase.off);
        expect(protection.documentationGeneration, generation + 1);
        expect(protection.isDocumentationActive, isTrue);
        expect(calls, [true, false]);
      });
    }

    testWidgets('a disposed instance cannot start verification', (tester) async {
      await enter(tester);
      protection.dispose();
      final pending = protection.beginDocumentation();
      if (identities.isNotEmpty) identities.single.complete(true);
      expect(await pending, isFalse);
      expect(identities, isEmpty);
      expect(calls, [true]);
    });
  });

  group('Android native acknowledgment', () {
    const channel = MethodChannel('imaps_fieldsync/screen_protection_ack');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late NativeScreenProtectionAck adapter;
    late List<MethodCall> nativeCalls;
    late int session;

    Map<String, Object> acknowledgment(MethodCall call) {
      final args = call.arguments as Map;
      if (call.method == 'beginSession') session++;
      return {
        'success': true,
        'sessionId': call.method == 'beginSession' ? session : args['sessionId'],
        'requestId': args['requestId'],
        'secure': call.method == 'beginSession' ? true : args['secure'],
      };
    }

    void bridge(Future<Object?> Function(MethodCall) handler) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        return handler(call);
      });
    }

    setUp(() {
      protection.dispose();
      adapter = NativeScreenProtectionAck(
        onWindowChanged: () => protection.retryProtection(),
      );
      nativeCalls = [];
      session = 0;
      bridge((call) async => acknowledgment(call));
      protection = ScreenProtectionService(
        applyProtection: adapter.setSecure,
        verifyIdentity: () async => true,
      );
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      channel.setMethodCallHandler(null);
    });

    testWidgets('Window replacement invalidates the previous native acknowledgment', (
      tester,
    ) async {
      // Incoming platform messages execute in their listener's registration
      // zone. Register this listener inside the widget test's FakeAsync zone.
      protection.dispose();
      adapter = NativeScreenProtectionAck(
        onWindowChanged: () => protection.retryProtection(),
      );
      protection = ScreenProtectionService(
        applyProtection: adapter.setSecure,
        verifyIdentity: () async => true,
      );
      await enter(tester);
      final attached = Completer<Object?>();
      Object? reply;
      bridge((call) async {
        final acknowledgmentForCall = acknowledgment(call);
        if (call.method == 'beginSession') {
          reply = acknowledgmentForCall;
          return attached.future;
        }
        return acknowledgmentForCall;
      });
      tester.binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('windowChanged'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(protection.appliedProtection, isNull);
      expect(protection.mustObscure, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      await tester.pump();
      expect(session, 2, reason: 'Native calls: $nativeCalls');
      attached.complete(reply);
      await tester.pump();
      expect(protection.appliedProtection, isTrue);
      expect((nativeCalls.last.arguments as Map)['sessionId'], 2);
      expect(protection.isDocumentationActive, isFalse);
    });

    testWidgets('ON and OFF require correlated observed window state', (
      tester,
    ) async {
      await enter(tester);
      await protection.beginDocumentation();
      await tester.pump();
      expect(protection.appliedProtection, isFalse);
      expect(protection.isDocumentationActive, isTrue);
      expect(nativeCalls.map((call) => call.method), [
        'beginSession', 'setSecure', 'setSecure',
      ]);
      expect(nativeCalls[1].arguments, {
        'sessionId': 1, 'requestId': 1, 'secure': true,
      });
      expect(nativeCalls[2].arguments, {
        'sessionId': 1, 'requestId': 2, 'secure': false,
      });
      protection.endDocumentation();
      await tester.pump();
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
    });

    for (final invalid in [
      'false', 'null', 'empty', 'failure', 'wrong request', 'wrong session',
      'wrong state', 'nonboolean state', 'noninteger request', 'begin failure',
    ]) {
      testWidgets('$invalid acknowledgment keeps sensitive content covered', (
        tester,
      ) async {
        bridge((call) async {
          if (call.method == 'beginSession') {
            return invalid == 'begin failure' ? false : acknowledgment(call);
          }
          final reply = acknowledgment(call);
          return switch (invalid) {
            'false' => false,
            'null' => null,
            'empty' => <String, Object>{},
            'failure' => {...reply, 'success': false},
            'wrong request' => {...reply, 'requestId': 999},
            'wrong session' => {...reply, 'sessionId': 999},
            'wrong state' => {...reply, 'secure': false},
            'nonboolean state' => {...reply, 'secure': 'true'},
            'noninteger request' => {...reply, 'requestId': 1.0},
            _ => reply,
          };
        });
        protection.register(Object(), null);
        await tester.pump();
        expect(protection.appliedProtection, isNull);
        expect(protection.nativeFailure, isTrue);
        expect(protection.mustObscure, isTrue);
        expect(await protection.beginDocumentation(), isFalse);
        protection.dispose();
        await tester.pump();
      });
    }

    for (final failure in ['missing channel', 'activity_unavailable',
      'window_unavailable', 'native_failure']) {
      testWidgets('$failure is not a protection acknowledgment', (tester) async {
        if (failure == 'missing channel') {
          // An unregistered native channel replies with no codec envelope.
          messenger.setMockMessageHandler(channel.name, (_) async => null);
        } else {
          bridge((_) async => throw PlatformException(code: failure));
        }
        protection.register(Object(), null);
        await tester.pump();
        expect(protection.nativeFailure, isTrue);
        expect(protection.appliedProtection, isNull);
        expect(protection.mustObscure, isTrue);
        protection.dispose();
        await tester.pump();
      });
    }

    testWidgets('Timed-out initial ON stays covered and permits a fresh retry', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      Object? lateReply;
      bridge((call) async {
        final reply = acknowledgment(call);
        if (call.method == 'beginSession' && session == 1) {
          lateReply = reply;
          return pending.future;
        }
        return reply;
      });
      protection.register(Object(), null);
      await tester.pump();
      expect(protection.mustObscure, isTrue);
      expect(protection.appliedProtection, isNull);
      await tester.pump(ScreenProtectionService.nativeTimeout);
      expect(protection.nativeFailure, isTrue);
      expect(protection.mustObscure, isTrue);
      expect(await protection.beginDocumentation(), isFalse);
      protection.retryProtection();
      await tester.pump();
      expect(protection.appliedProtection, isTrue);
      expect(session, 2);
      pending.complete(lateReply);
      await tester.pump();
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      expect(nativeCalls.where((call) => call.method == 'setSecure'), hasLength(1));
    });

    testWidgets('Timed-out OFF is fenced by a new protective native session', (
      tester,
    ) async {
      final off = Completer<Object?>();
      MethodCall? pending;
      bridge((call) async {
        if (call.method == 'setSecure' &&
            (call.arguments as Map)['secure'] == false) {
          pending = call;
          return off.future;
        }
        return acknowledgment(call);
      });
      await enter(tester);
      await protection.beginDocumentation();
      await tester.pump();
      expect(protection.mustObscure, isTrue);
      await tester.pump(ScreenProtectionService.nativeTimeout);
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
      expect(session, 2);
      expect((nativeCalls.last.arguments as Map)['sessionId'], 2);
      off.complete(acknowledgment(pending!));
      await tester.pump();
      expect(protection.appliedProtection, isTrue);
      expect(protection.isDocumentationActive, isFalse);
    });

    testWidgets('Disposal ON supersedes an outstanding native OFF', (
      tester,
    ) async {
      final off = Completer<Object?>();
      MethodCall? pending;
      bridge((call) async {
        if (call.method == 'setSecure' &&
            (call.arguments as Map)['secure'] == false) {
          pending = call;
          return off.future;
        }
        return acknowledgment(call);
      });
      await enter(tester);
      await protection.beginDocumentation();
      await tester.pump();
      protection.dispose();
      await tester.pump();
      expect(nativeCalls.last.arguments, {
        'sessionId': 1, 'requestId': 3, 'secure': true,
      });
      off.complete(acknowledgment(pending!));
      await tester.pump();
      expect(protection.isDocumentationActive, isFalse);
      expect(protection.appliedProtection, isNot(false));
    });
  });
}
