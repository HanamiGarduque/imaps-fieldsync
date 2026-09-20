import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:imaps_fieldsync/modules/inspection/services/photo_source_resolver.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  const job = '11111111-1111-4111-8111-111111111111';
  const path = 'inspections/$job/photo_fixture.jpg';
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9WQAAAAASUVORK5CYII=');
  setUp(() => dotenv.testLoad(fileInput: 'SUPABASE_URL=https://fixture.supabase.co'));
  testWidgets('private evidence renders bytes, never a NetworkImage', (tester) async {
    final calls = <String>[];
    final resolver = PhotoSourceResolver(projectUrl: Uri.parse('https://fixture.supabase.co'),
      download: (p) async { calls.add(p); return png; });
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 80, height: 80,
      child: AdaptivePhotoImage(path: path, resolver: resolver))));
    await tester.pumpAndSettle();
    expect(calls, [path]);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing evidence is an explicit error', (tester) async {
    final resolver = PhotoSourceResolver(projectUrl: Uri.parse('https://fixture.supabase.co'),
      download: (_) async => throw StateError('denied'));
    await tester.pumpWidget(MaterialApp(home: AdaptivePhotoImage(path: path, resolver: resolver)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
  test('rework prefers metadata and preserves notes; local values are not remote', () {
    final provider = InspectionProvider();
    final task = TaskItem.fromJob({'id': job, 'status': 'completed',
      'photo_paths': ['/missing/local.jpg'],
      'field_job_photos': [{'photo_url': path, 'notes': 'evidence note'}]});
    provider.hydrateForRework(task);
    expect(provider.capturedPhotos.single['photoPath'], path);
    expect(provider.capturedPhotos.single['notes'], 'evidence note');
    expect(provider.capturedPhotos.single['isRemoteUrl'], true);
    provider.hydrateForRework(TaskItem.fromJob({'id': job, 'status': 'completed',
      'photo_paths': ['/missing/local.jpg']}));
    expect(provider.capturedPhotos.single['isRemoteUrl'], false);
    provider.dispose();
  });
  test('overview and review fallback cannot mask matching remote evidence', () {
    const local = '/missing/photo.jpg';
    final key = base64Url.encode(utf8.encode(local)).replaceAll('=', '');
    final remote = 'inspections/$job/photo_$key.jpg';
    expect(inspectionDisplayPaths([local], job, [{'photo_url': remote}], []), [remote]);
    expect(inspectionDisplayPaths(['/different.jpg'], job, [{'photo_url': remote}], []), ['/different.jpg']);
  });
  test('completed, capture, review and fullscreen wire shared photo widget', () {
    // Source wiring guard; runtime byte decoding is tested above.
    for (final screen in ['completed_inspection_detail_screen', 'capture_photo_screen', 'review_submit_screen']) {
      final source = File('lib/modules/inspection/screens/$screen.dart').readAsStringSync();
      expect(source, contains('AdaptivePhotoImage('));
      expect(source, isNot(contains('Image.network(')));
    }
    expect(File('lib/core/navigation/parcel_detail_screen.dart').readAsStringSync(),
      contains('inspectionDisplayPaths('));
  });
}
