import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';

void main() {
  test(
    'same job and local path reuse one durable object and metadata identity',
    () {
      const localPath = '/data/user/0/com.app/files/inspection_123.jpg';
      final firstPath = SupabaseService.photoStoragePath('job-a', localPath);
      final secondPath = SupabaseService.photoStoragePath('job-a', localPath);

      expect(secondPath, firstPath);
      expect(
        SupabaseService.photoRowId(secondPath),
        SupabaseService.photoRowId(firstPath),
      );
    },
  );

  test('different jobs cannot share a durable object or metadata identity', () {
    const localPath = '/data/user/0/com.app/files/inspection_123.jpg';
    final jobAPath = SupabaseService.photoStoragePath('job-a', localPath);
    final jobBPath = SupabaseService.photoStoragePath('job-b', localPath);

    expect(jobBPath, isNot(jobAPath));
    expect(
      SupabaseService.photoRowId(jobBPath),
      isNot(SupabaseService.photoRowId(jobAPath)),
    );
  });

  test(
    'legacy local photo adapter preserves notes, coordinates, and capture time',
    () {
      final payload = SupabaseService.photoUploadPayloadFromLegacyLocalRow({
        'photo_path': '/data/user/0/com.app/files/inspection_123.jpg',
        'notes': 'photo note',
        'latitude': 13.8,
        'longitude': 121.2,
        'captured_at': '2026-01-01T00:00:00Z',
      });

      expect(payload, {
        'photoPath': '/data/user/0/com.app/files/inspection_123.jpg',
        'notes': 'photo note',
        'latitude': 13.8,
        'longitude': 121.2,
        'capturedAt': '2026-01-01T00:00:00Z',
      });
    },
  );

  test('legacy adapter preserves null optional metadata as null', () {
    final payload = SupabaseService.photoUploadPayloadFromLegacyLocalRow({
      'photo_path': '/data/user/0/com.app/files/inspection_123.jpg',
      'notes': null,
      'latitude': null,
      'longitude': null,
      'captured_at': null,
    });

    expect(payload['notes'], isNull);
    expect(payload['latitude'], isNull);
    expect(payload['longitude'], isNull);
    expect(payload['capturedAt'], isNull);
  });

  test(
    'reachable provider sync no longer contains the legacy remote writer',
    () {
      final source = File(
        'lib/modules/inspection/providers/inspection_provider.dart',
      ).readAsStringSync();

      expect(source, contains('SupabaseService.uploadInspectionPhotos('));
      expect(source, isNot(contains(r"photo_${photo['id']}.jpg")));
      expect(source, isNot(contains("from('field_job_photos')")));
    },
  );
}
