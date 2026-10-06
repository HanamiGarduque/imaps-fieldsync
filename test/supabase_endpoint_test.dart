import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/supabase_endpoint.dart';

void main() {
  for (final url in [
    'https://project.supabase.co',
    'https://valid-public-host.example',
    'https://custom.example.org',
    'https://172.32.0.1',
    'https://8.8.8.8',
    'https://[2606:4700:4700::1111]',
  ]) {
    test('release accepts $url', () {
      expect(validateSupabaseEndpoint(url, release: true), url);
    });
  }
  for (final url in <String?>[
    null,
    '',
    'malformed',
    'https://',
    'https://bad host.example',
    'http://project.supabase.co',
    'http://localhost',
    'http://127.0.0.1',
    'http://10.0.2.2',
    'https://localhost',
    'https://127.255.255.254',
    'https://0.0.0.0',
    'https://10.10.0.2',
    'https://172.16.0.1',
    'https://172.31.255.254',
    'https://192.168.1.10',
    'https://169.254.1.1',
    'https://[::1]',
    'https://[::]',
    'https://[fe80::1]',
    'https://[fd00::1]',
    'https://[::ffff:192.168.1.10]',
    'https://devbox',
    'https://devbox.local',
    'https://devbox.lan',
    'https://devbox.home.arpa',
    'https://app.localhost',
    'https://127.1',
    'https://2130706433',
    'https://0177.0.0.1',
    'https://user:isolated-secret@public.example',
  ]) {
    test('release rejects ${url ?? "missing URL"}', () {
      expect(
        () => validateSupabaseEndpoint(url, release: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('isolated-secret')),
          ),
        ),
      );
    });
  }
  test('debug still permits local HTTP development', () {
    expect(
      validateSupabaseEndpoint('http://10.0.2.2:54321', release: false),
      'http://10.0.2.2:54321',
    );
  });
}
