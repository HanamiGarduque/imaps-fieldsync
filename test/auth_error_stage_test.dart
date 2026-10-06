import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/services/auth_failure.dart';
import 'package:imaps_fieldsync/core/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const inspector = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var authStatus = 200;
  var authCode = 'invalid_credentials';
  var profileFails = false;
  var networkFails = false;
  var refreshFails = false;
  var profileNetworkFails = false;
  var storageFails = false;
  final secureValues = <String, String>{};
  final session = {
    'access_token': 'isolated-access',
    'refresh_token': 'isolated-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': inspector,
      'email': 'inspector@example.test',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (storageFails) throw PlatformException(code: 'isolated-storage');
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secureValues[key];
          case 'write':
            secureValues[key!] = args['value'] as String;
            return null;
          case 'delete':
            secureValues.remove(key);
            return null;
          case 'deleteAll':
            secureValues.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(secureValues);
        }
        throw StateError('Unexpected secure-storage operation');
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    await Supabase.initialize(
      url: 'https://auth-stage.test',
      publishableKey: 'isolated-test-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.host, 'auth-stage.test');
        if (request.url.path == '/auth/v1/token') {
          if (networkFails) throw const SocketException('isolated transport');
          if (refreshFails || authStatus != 200) {
            return http.Response(
              jsonEncode({
                'code': refreshFails ? 'refresh_token_not_found' : authCode,
                'msg': 'isolated rejection',
              }),
              refreshFails ? 400 : authStatus,
              request: request,
              headers: {'x-supabase-api-version': '2024-01-01'},
            );
          }
          return http.Response(jsonEncode(session), 200, request: request);
        }
        expect(request.url.path, '/rest/v1/profiles');
        expect(request.url.queryParameters['id'], 'eq.$inspector');
        if (profileNetworkFails) {
          throw const SocketException('isolated profile transport');
        }
        if (profileFails) {
          return http.Response(
            jsonEncode({
              'code': 'PGRST116',
              'message': 'isolated absent profile',
            }),
            406,
            request: request,
          );
        }
        return http.Response(
          jsonEncode({
            'id': inspector,
            'full_name': 'Test Inspector',
            'role': 'inspector',
          }),
          200,
          request: request,
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    secureValues.clear();
    authStatus = 200;
    authCode = 'invalid_credentials';
    profileFails = networkFails = refreshFails = profileNetworkFails =
        storageFails = false;
  });

  Future<void> signIn() => AuthService.signIn(
    email: 'inspector@example.test',
    password: 'isolated-passcode',
  ).then((_) {});

  test('password rejection alone produces the credential state', () async {
    authStatus = 400;
    await expectLater(signIn(), throwsA(AuthFailure.authRejected));
    expect(
      AuthFailure.authRejected.message,
      contains('Invalid ID or passcode'),
    );
  });

  test(
    'successful Auth followed by missing profile is a profile failure',
    () async {
      await signIn();
      profileFails = true;
      await expectLater(
        AuthService.getCurrentProfileOfflineAware(),
        throwsA(AuthFailure.profileUnavailable),
      );
      expect(AuthService.isLoggedIn, isTrue);
      expect(
        AuthFailure.profileUnavailable.message,
        contains('inspector profile'),
      );
      expect(
        AuthFailure.profileUnavailable.message,
        isNot(contains('Invalid ID')),
      );
    },
  );

  test('sign-in transport failure produces connectivity feedback', () async {
    networkFails = true;
    await expectLater(signIn(), throwsA(AuthFailure.networkUnavailable));
    expect(AuthFailure.networkUnavailable.message, contains('connection'));
  });

  test('refresh rejection is session restoration, never credentials', () async {
    await signIn();
    refreshFails = true;
    await expectLater(
      AuthService.restoreSessionOfflineAware(),
      throwsA(AuthFailure.sessionRestoreFailed),
    );
    expect(AuthFailure.sessionRestoreFailed.message, contains('session'));
    expect(
      AuthFailure.sessionRestoreFailed.message,
      isNot(contains('Invalid ID')),
    );
  });

  test(
    'successful Auth and profile retain the normal authenticated result',
    () async {
      await signIn();
      final profile = await AuthService.getCurrentProfileOfflineAware();
      expect(AuthService.isLoggedIn, isTrue);
      expect(profile?.id, inspector);
      expect(profile?.fullName, 'Test Inspector');
      expect(profile?.isInspector, isTrue);
    },
  );

  test('other Auth API refusals are not labeled wrong credentials', () async {
    authStatus = 429;
    authCode = 'over_request_rate_limit';
    await expectLater(signIn(), throwsA(AuthFailure.unknownPostAuth));
  });

  test(
    'transport failure during restore preserves the owner-matched cache',
    () async {
      await signIn();
      await AuthService.getCurrentProfileOfflineAware();
      networkFails = profileNetworkFails = true;
      await AuthService.restoreSessionOfflineAware();
      expect(AuthService.hasLiveUnderlyingSession, isTrue);
      expect(
        (await AuthService.getCurrentProfileOfflineAware())?.id,
        inspector,
      );
    },
  );

  test('post-auth local storage failure is not credential rejection', () async {
    storageFails = true;
    await expectLater(signIn(), throwsA(AuthFailure.unknownPostAuth));
  });
}
