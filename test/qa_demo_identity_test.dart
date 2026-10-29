// B1 verification for the isolated demo identity: the fail-closed identity
// matrix, the fixed fictional configuration values, and the deny-by-default
// demo transport. Capture stays OFF: grants here only prove the revocable
// permission contract, and every grant is revoked in teardown.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/main_qa.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const approvedPin =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  late ScreenProtectionService protection;
  setUp(() {
    protection = ScreenProtectionService(
      applyProtection: (_) async {},
      verifyIdentity: () async => true,
    );
  });
  tearDown(() {
    protection.revokeQaDocumentation();
    protection.dispose();
  });

  test('the demo identity matrix denies every unmet gate', () async {
    Future<bool> verified({
      bool debugMode = true,
      bool onAndroid = true,
      bool qaPreview = true,
      String flavor = 'demo',
      String signerPin = approvedPin,
      String packageName = ScreenProtectionService.demoPackageName,
      String buildSignature = approvedPin,
    }) => ScreenProtectionService.isVerifiedDemoContext(
          debugMode: debugMode,
          onAndroid: onAndroid,
          qaPreview: qaPreview,
          flavor: flavor,
          pin: signerPin,
          packageName: packageName,
          buildSignature: buildSignature,
        );

    expect(await verified(), isTrue);
    expect(await verified(debugMode: false), isFalse);
    expect(await verified(onAndroid: false), isFalse);
    expect(await verified(qaPreview: false), isFalse);
    expect(await verified(flavor: 'prod'), isFalse);
    expect(
      await verified(packageName: 'com.example.imaps_fieldsync'),
      isFalse,
    );
    expect(await verified(signerPin: approvedPin.substring(0, 63)), isFalse);
    expect(await verified(signerPin: 'z' * 64), isFalse);
    expect(await verified(signerPin: ''), isFalse);
    expect(await verified(buildSignature: 'a' * 64), isFalse);
    // The pin/signature match is case-insensitive on both sides.
    expect(await verified(signerPin: approvedPin.toUpperCase()), isTrue);
  });

  test('a regular context cannot grant and capture stays denied', () async {
    expect(protection.documentationEnabled, isFalse);
    expect(await protection.beginDocumentation(), isFalse);
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: approvedPin,
        packageName: 'com.example.imaps_fieldsync',
        buildSignature: approvedPin,
      ),
      isFalse,
    );
    expect(protection.documentationEnabled, isFalse);
    expect(await protection.beginDocumentation(), isFalse);
  });

  test('a verified demo identity grants, and revoke withdraws it', () async {
    expect(
      await protection.grantQaDocumentation(
        debugMode: true,
        onAndroid: true,
        qaPreview: true,
        flavor: 'demo',
        pin: approvedPin,
        packageName: ScreenProtectionService.demoPackageName,
        buildSignature: approvedPin,
      ),
      isTrue,
    );
    expect(protection.documentationEnabled, isTrue);
    // The granted state can open a session once a protected scope is visible.
    protection.register(Object(), null);
    // Two zero-delay turns: the reconcile chain runs in microtasks, and the
    // second turn guarantees _applied is observed before activation.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(await protection.beginDocumentation(), isTrue);
    // _phase flips to active only inside the next reconcile cycle, once the
    // OFF acknowledge lands; flush the microtask chain before asserting it.
    await Future<void>.delayed(Duration.zero);
    expect(protection.isDocumentationActive, isTrue);
    protection.revokeQaDocumentation();
    await Future<void>.delayed(Duration.zero);
    expect(protection.documentationEnabled, isFalse);
    expect(protection.isDocumentationActive, isFalse);
    expect(await protection.beginDocumentation(), isFalse);
  });

  test('demo environment values are fixed, fictional and loopback-only', () {
    expect(demoSupabaseUrl, 'http://127.0.0.1:54321');
    expect(Uri.parse(demoSupabaseUrl).host, '127.0.0.1');
    expect(demoPublishableKey, 'demo-fictional-local-only');
  });

  test('demo transport refuses every request without forwarding', () async {
    // MockClient answers every call from its handler; it never opens a
    // socket, so even this loopback URL is never contacted.
    final response = await demoTransport.post(
      Uri.parse('$demoSupabaseUrl/rest/v1/qa_table'),
      headers: {'apikey': demoPublishableKey},
      body: jsonEncode({'id': '11111111-1111-4111-8111-111111111111'}),
    );
    expect(response.statusCode, 403);
    expect(response.headers['content-type'], 'application/json');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['error'], 'demo_offline');
  });

  group('authorization races', () {
    Future<bool> grant(ScreenProtectionService service) => service.grantQaDocumentation(
      debugMode: true,
      onAndroid: true,
      qaPreview: true,
      flavor: 'demo',
      pin: approvedPin,
      packageName: ScreenProtectionService.demoPackageName,
      buildSignature: approvedPin,
    );

    for (final regrant in [false, true]) {
      testWidgets('cross-instance revoke${regrant ? '/regrant' : ''} fences activation', (
        tester,
      ) async {
        final identity = Completer<bool>();
        var first = true;
        final calls = <bool>[];
        final requester = ScreenProtectionService(
          applyProtection: (secure) async { calls.add(secure); },
          verifyIdentity: () {
            if (!first) return Future.value(true);
            first = false;
            return identity.future;
          },
        );
        addTearDown(requester.dispose);
        expect(await grant(protection), isTrue);
        requester.register(Object(), null);
        await tester.pump();
        final stale = requester.beginDocumentation();
        protection.revokeQaDocumentation();
        if (regrant) {
          expect(await grant(protection), isTrue);
          expect(await requester.beginDocumentation(), isTrue);
          await tester.pump();
        }
        final generation = requester.documentationGeneration;
        identity.complete(true);
        final accepted = await stale;
        await tester.pump();
        expect(accepted, isFalse);
        expect(requester.documentationGeneration, generation);
        expect(requester.isDocumentationActive, regrant);
        expect(requester.appliedProtection, !regrant);
        expect(calls, [true, if (regrant) false]);
      });
    }

    test('an already-false cross-instance revoke fences a pending grant', () async {
      final other = ScreenProtectionService(applyProtection: (_) async {});
      addTearDown(other.dispose);
      expect(protection.documentationEnabled, isFalse);
      final pending = grant(protection);
      other.revokeQaDocumentation();
      expect(await pending, isFalse);
      expect(protection.documentationEnabled, isFalse);
    });

    test('the first successful grant fences another pending grant', () async {
      final other = ScreenProtectionService(applyProtection: (_) async {});
      addTearDown(other.dispose);
      final first = grant(protection);
      final stale = grant(other);
      expect(await first, isTrue);
      expect(await stale, isFalse);
      expect(protection.documentationEnabled, isTrue);
    });

    test('a disposed instance cannot grant a verified identity', () async {
      protection.dispose();
      expect(await grant(protection), isFalse);
      expect(protection.documentationEnabled, isFalse);
    });

    testWidgets('held package attestation cannot revive cancelled grants', (
      tester,
    ) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final replies = <Completer<Map<String, dynamic>>>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'getAll');
        final reply = Completer<Map<String, dynamic>>();
        replies.add(reply);
        return reply.future;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final services = List.generate(5, (_) => ScreenProtectionService(
        applyProtection: (_) async {},
        verifyIdentity: () => throw StateError('Grant must use the full identity matrix'),
      ));
      addTearDown(() { for (final service in services) { service.dispose(); } });
      final settled = List.filled(services.length, false);
      // PackageInfo caches completed metadata, not in-flight requests. Start
      // every uncached call before supplying any platform reply.
      final pending = [for (var i = 0; i < services.length; i++)
        services[i].grantQaDocumentation(
          debugMode: true, onAndroid: true, qaPreview: true,
          flavor: 'demo', pin: approvedPin,
        ).then((value) { settled[i] = true; return value; }),
      ];
      await tester.pump();
      expect(replies, hasLength(5), reason: 'No package-info cache hit may bypass the hold');
      expect(replies.every((reply) => !reply.isCompleted), isTrue);
      expect(settled, everyElement(isFalse));
      const metadata = <String, dynamic>{
        'appName': 'FieldSync Demo',
        'packageName': ScreenProtectionService.demoPackageName,
        'version': '1.0.0', 'buildNumber': '1', 'buildSignature': approvedPin,
      };
      services[0].endDocumentation();
      services[1].invalidateDocumentation();
      services[2].dispose();
      final localResults = <bool>[];
      for (var i = 0; i < 3; i++) {
        replies[i].complete(metadata);
        localResults.add(await pending[i]);
      }
      final allowedBeforeRevoke = protection.documentationEnabled;
      services[3].revokeQaDocumentation();
      replies[3].complete(metadata);
      final revoked = await pending[3];
      expect(await grant(protection), isTrue);
      protection.register(Object(), null);
      await tester.pump();
      expect(await protection.beginDocumentation(), isTrue);
      await tester.pump();
      final generation = protection.documentationGeneration;
      replies[4].complete(metadata);
      final stale = await pending[4];
      await tester.pump();
      expect(localResults, [false, false, false]);
      expect(allowedBeforeRevoke, isFalse);
      expect(revoked, isFalse);
      expect(stale, isFalse);
      expect(protection.documentationEnabled, isTrue);
      expect(protection.isDocumentationActive, isTrue);
      expect(protection.documentationGeneration, generation);
    });
  });
}
