import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/inspection/services/photo_source_resolver.dart';

void main() {
  const job = '11111111-1111-4111-8111-111111111111';
  const path = 'inspections/$job/photo_test.jpg';
  final calls = <String>[];
  late PhotoSourceResolver resolver;
  setUp(() {
    calls.clear();
    resolver = PhotoSourceResolver(
      projectUrl: Uri.parse('https://fixture.supabase.co'),
      download: (p) async { calls.add(p); return Uint8List.fromList([1, 2]); },
    );
  });
  test('existing local file stays local', () async {
    final dir = Directory.systemTemp.createTempSync('photo-source-');
    try {
      final file = File('${dir.path}/photo.jpg')..writeAsBytesSync([1]);
      expect((await resolver.resolve(file.path))!.localPath, file.path);
      expect(calls, isEmpty);
    } finally { dir.deleteSync(recursive: true); }
  });
  test('missing local file falls back to authenticated storage read', () async {
    expect((await resolver.resolve('/missing/photo.jpg', fallback: path))!.bytes,
        [1, 2]);
    expect(calls, [path]);
  });
  for (final route in ['public', 'sign', 'authenticated']) {
    test('historical $route URL resolves through authenticated download', () async {
      final url = 'https://fixture.supabase.co/storage/v1/object/$route/inspection-photos/$path?token=expired';
      expect((await resolver.resolve(url))!.bytes, [1, 2]);
      expect(calls, [path]);
    });
  }
  test('object path downloads without a permanent public URL', () async {
    expect((await resolver.resolve(path))!.bytes, [1, 2]);
    expect(calls, [path]);
  });
  test('invalid and foreign sources fail explicitly', () async {
    for (final value in ['', 'relative.jpg', 'https://foreign.test/$path',
      'https://fixture.supabase.co/storage/v1/object/public/avatars/$path',
      'inspections/$job/../other.jpg']) {
      expect(await resolver.resolve(value), isNull);
    }
    expect(calls, isEmpty);
  });
  test('fallback matches photo identity, never list index', () {
    const local = '/missing/evidence.jpg';
    final key = base64Url.encode(utf8.encode(local)).replaceAll('=', '');
    final matching = 'inspections/$job/photo_$key.jpg';
    expect(resolver.fallbackFor(local, job, [path, matching]), matching);
    expect(resolver.fallbackFor('/other.jpg', job, [matching]), isNull);
  });
  test('metadata preferred during persisted evidence reconstruction', () {
    expect(PhotoSourceResolver.evidence([{'photo_url': path, 'notes': 'original'}], [])
        .single, containsPair('photoPath', path));
    expect(PhotoSourceResolver.evidence([], [path]).single['photoPath'], path);
  });
}
