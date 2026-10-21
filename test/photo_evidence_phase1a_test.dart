// Phase 1A — photographic evidence contract.
//
// Covers: appended Unicode geotag footer, honest unavailable states, one
// capture timestamp, deterministic Site Location Reference identity, real
// photo counting (10 real + 1 generated reference), removal protection,
// Step 3 local durability across a provider restart, and the unchanged
// iMAPS photo metadata shape.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/services/geotag_service.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'inspection_owner_fixture.dart';

TaskItem _task({int? round = 1}) => TaskItem(
  id: 'job-1',
  inspectionRoundNumber: round,
  parcelId: 'parcel-1',
  name: 'Peña, Juana',
  location: 'Brgy. Rosario',
  locationAddress: '123 Purok 4, Brgy. Rosario, Rosario, Batangas',
  parcels: '2026-10-22',
  status: 'in_progress',
  inspectionNo: 'FI-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('geotag footer', () {
    test('keeps Unicode, the real address and one capture timestamp', () {
      final capturedAt = DateTime(2026, 10, 21, 14, 5, 9);
      final lines = GeotagService.captureFooterLines(
        applicant: 'Peña, Juana',
        address: '123 Purok 4, Brgy. Rosario, Rosario, Batangas',
        capturedAt: capturedAt,
        latitude: 13.842512,
        longitude: 121.123456,
        accuracyMeters: 12.4,
      );

      expect(lines.join('\n'), contains('Peña, Juana'));
      expect(lines.join('\n'), contains('123 Purok 4'));
      expect(lines.join('\n'), contains('13.842512, 121.123456'));
      expect(lines.join('\n'), contains('±12 m'));
      expect(
        lines.where((l) => l.startsWith('Captured:')).length,
        1,
        reason: 'a photo carries exactly one capture timestamp',
      );
    });

    test('says GPS unavailable instead of Locating... or a parcel point', () {
      final lines = GeotagService.captureFooterLines(
        applicant: 'Applicant',
        address: null,
        capturedAt: DateTime(2026, 10, 21, 14, 5, 9),
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      );

      expect(lines.join('\n'), contains('Address not on file'));
      expect(lines.join('\n'), contains('GPS unavailable'));
      expect(lines.join('\n'), isNot(contains('Locating')));
      expect(lines.join('\n'), isNot(contains('13.84')));
    });

    testWidgets('appends the footer below the photo, never over it', (
      tester,
    ) async {
      final original = img.Image(width: 48, height: 32);
      img.fill(original, color: img.ColorRgb8(180, 30, 30));
      final bytes = img.encodeJpg(original, quality: 90);

      final output = await tester.runAsync(() async {
        return GeotagService.appendFooter(
          photoBytes: bytes,
          lines: GeotagService.captureFooterLines(
            applicant: 'Peña, Juana',
            address: '123 Purok 4',
            capturedAt: DateTime(2026, 10, 21, 14, 5, 9),
            latitude: 13.842512,
            longitude: 121.123456,
            accuracyMeters: 12,
          ),
        );
      });
      expect(output, isNotNull);

      final decoded = img.decodeJpg(output!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 48);
      expect(
        decoded.height,
        greaterThan(32),
        reason: 'footer is appended, not burned over the scene',
      );
      // The top band is the untouched scene: still predominantly red.
      final top = decoded.getPixel(24, 4);
      expect(top.r, greaterThan(top.g + 40));
      expect(top.r, greaterThan(top.b + 40));
      // The appended band is dark.
      final footerPixel = decoded.getPixel(24, decoded.height - 4);
      expect(footerPixel.r, lessThan(80));
      expect(footerPixel.g, lessThan(80));
      expect(footerPixel.b, lessThan(80));
    });
  });

  group('Site Location Reference', () {
    testWidgets('renders an offline labelled JPEG with the disclaimer', (
      tester,
    ) async {
      final bytes = await tester.runAsync(() async {
        return SiteLocationReferenceService.render(
          jobId: 'job-1',
          round: 1,
          applicant: 'Peña, Juana',
          address: '123 Purok 4, Brgy. Rosario',
          verifiedLatitude: 13.842512,
          verifiedLongitude: 121.123456,
          verifiedAt: DateTime(2026, 10, 21, 13, 55),
          verifiedAccuracyMeters: 8,
          parcelLatitude: 13.8427,
          parcelLongitude: 121.1236,
          generatedAt: DateTime(2026, 10, 21, 14, 5, 9),
        );
      });
      expect(bytes, isNotNull);

      final decoded = img.decodeJpg(bytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, kSiteLocationReferenceWidth);
      expect(decoded.height, kSiteLocationReferenceHeight);
      var markerPixelsInLegend = 0;
      for (var y = 920; y < 1040; y++) {
        for (var x = 48; x < 1032; x++) {
          final pixel = decoded.getPixel(x, y);
          if ((pixel.r - 37).abs() < 8 &&
              (pixel.g - 99).abs() < 8 &&
              (pixel.b - 235).abs() < 8) {
            markerPixelsInLegend++;
          }
        }
      }
      expect(
        markerPixelsInLegend,
        0,
        reason: 'the GPS marker must not cover the diagram legend',
      );
      expect(
        kSiteLocationReferenceDisclaimer,
        'Location reference only — Not a surveyed parcel boundary.',
      );
    });

    test('uses a deterministic identity per job and round', () {
      final first = SiteLocationReferenceService.fileName('job-1', 1);
      final again = SiteLocationReferenceService.fileName('job-1', 1);
      final nextRound = SiteLocationReferenceService.fileName('job-1', 2);

      expect(first, again);
      expect(first, isNot(nextRound));
      expect(first, isNot(contains('/')));
      expect(first, isNot(contains('\\')));
      expect(
        SiteLocationReferenceService.photoId('job-1', 1),
        SiteLocationReferenceService.photoId('job-1', 1),
      );
      expect(
        SiteLocationReferenceService.photoId('job-1', 1),
        isNot(SiteLocationReferenceService.photoId('job-1', 2)),
      );
    });

    test('recognises the generated reference from its notes only', () {
      expect(
        isLocationReferencePhoto({
          'notes': kSiteLocationReferenceNotes,
          'photoPath': '/tmp/reference.jpg',
        }),
        isTrue,
      );
      expect(
        isLocationReferencePhoto({
          'notes': 'Crushed rock stockpile at the rear lot',
          'photoPath': '/tmp/camera.jpg',
        }),
        isFalse,
      );
    });
  });

  group('provider photo accounting', () {
    setUp(useOwnerFixture);
    tearDown(clearOwnerFixture);

    test('a generated reference is not a real camera photo', () {
      final provider = InspectionProvider()..hydrateForRework(_task());
      provider.addPhoto(
        photoPath: '/tmp/reference.jpg',
        photoNotes: kSiteLocationReferenceNotes,
        latitude: 13.842512,
        longitude: 121.123456,
        isLocationReference: true,
      );
      for (var i = 0; i < 10; i++) {
        provider.addPhoto(
          photoPath: '/tmp/real-$i.jpg',
          photoNotes: 'site photo $i',
          latitude: 13.842512,
          longitude: 121.123456,
        );
      }

      expect(provider.capturedPhotos, hasLength(11));
      expect(provider.realPhotoCount, 10);
      expect(provider.hasLocationReference, isTrue);
      provider.dispose();
    });

    test('the generated reference cannot be removed as evidence', () async {
      final provider = InspectionProvider()..hydrateForRework(_task());
      provider.addPhoto(
        photoPath: '/tmp/reference.jpg',
        photoNotes: kSiteLocationReferenceNotes,
        latitude: 13.842512,
        longitude: 121.123456,
        isLocationReference: true,
      );

      expect(await provider.removePhoto(0), isFalse);
      expect(provider.capturedPhotos, hasLength(1));
      provider.dispose();
    });
  });

  group('Step 3 durability', () {
    late Directory temp;
    late Database db;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('phase1a-durability-');
      db = await databaseFactoryFfi.openDatabase('${temp.path}/fixture.db');
      final source = await File(
        'lib/core/services/db_helper.dart',
      ).readAsString();
      for (final match in RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
      ).allMatches(source)) {
        await db.execute(match.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      useOwnerFixture();
      await DBHelper.cacheJobs([
        {'id': 'job-1', 'status': 'assigned'},
      ]);
    });

    tearDown(() async {
      clearOwnerFixture();
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await temp.delete(recursive: true);
    });

    test('a saved Step 3 photo survives a provider restart', () async {
      final file = File('${temp.path}/accepted.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final first = InspectionProvider();
      await first.startInspection(_task());
      first.addPhoto(
        photoPath: file.path,
        photoNotes: 'accepted before a crash',
        latitude: 13.842512,
        longitude: 121.123456,
        capturedAt: DateTime.utc(2026, 10, 21, 6, 5, 9),
      );
      await first.persistPhoto(
        first.capturedPhotos.single,
        task: _task(),
        inspectorId: ownerFixture,
      );
      first.dispose();

      final restarted = InspectionProvider();
      await restarted.startInspection(_task());
      expect(restarted.capturedPhotos, hasLength(1));
      final restored = restarted.capturedPhotos.single;
      expect(restored['photoPath'], file.path);
      expect(restored['notes'], 'accepted before a crash');
      expect(restored['latitude'], 13.842512);
      expect(restored['capturedAt'], '2026-10-21T06:05:09.000Z');
      restarted.dispose();
    });

    test(
      'the accepted Step 2 fix survives a restart for offline rendering',
      () async {
        await DBHelper.saveGpsVerification(
          jobId: 'job-1',
          latitude: 13.842512,
          longitude: 121.123456,
          accuracyMeters: 8,
          fixAt: DateTime.utc(2026, 10, 21, 5, 55),
          verifiedAt: DateTime.utc(2026, 10, 21, 5, 55, 4),
        );

        final restarted = InspectionProvider();
        await restarted.startInspection(_task());
        final snapshot = restarted.gpsVerification;
        expect(snapshot, isNotNull);
        expect(snapshot!.latitude, 13.842512);
        expect(snapshot.longitude, 121.123456);
        expect(snapshot.accuracyMeters, 8);
        expect(snapshot.fixAt.toUtc(), DateTime.utc(2026, 10, 21, 5, 55));
        restarted.dispose();
      },
    );
  });

  group('unchanged iMAPS reader contract', () {
    test('photo metadata keeps the exact fields the PO reader selects', () {
      final row = SupabaseService.inspectionPhotoMetadataRow(
        rowId: 'row-1',
        jobId: 'job-1',
        photoUrl: 'inspections/job-1/photo_key.jpg',
        photo: {
          'latitude': 13.842512,
          'longitude': 121.123456,
          'capturedAt': '2026-10-21T06:05:09.000Z',
          'notes': kSiteLocationReferenceNotes,
        },
      );

      expect(row.keys.toSet(), {
        'id',
        'field_job_id',
        'photo_url',
        'latitude',
        'longitude',
        'captured_at',
        'notes',
      });
      expect(row['field_job_id'], 'job-1');
      expect(row['captured_at'], '2026-10-21T06:05:09.000Z');
      expect(row['notes'], kSiteLocationReferenceNotes);
    });

    test('the generated reference keeps one stable storage identity', () {
      final name = SiteLocationReferenceService.fileName('job-1', 1);
      final path = '/documents/$name';
      expect(
        SupabaseService.photoStoragePath('job-1', path),
        SupabaseService.photoStoragePath('job-1', path),
      );
    });

    test(
      'fake PostgREST round-trip keeps every field the PO reader selects',
      () async {
        final row = SupabaseService.inspectionPhotoMetadataRow(
          rowId: 'row-1',
          jobId: 'job-1',
          photoUrl: 'inspections/job-1/photo_key.jpg',
          photo: {
            'latitude': 13.842512,
            'longitude': 121.123456,
            'capturedAt': '2026-10-21T06:05:09.000Z',
            'notes': kSiteLocationReferenceNotes,
          },
        );

        Map<String, dynamic>? stored;
        final transport = MockClient((request) async {
          if (request.method == 'POST') {
            stored = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('', 201);
          }
          // The unchanged iMAPS reader asks only for these columns.
          const selected = {
            'photo_url',
            'latitude',
            'longitude',
            'captured_at',
            'notes',
          };
          return http.Response(
            jsonEncode([
              {for (final key in selected) key: stored![key]},
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        await transport.post(
          Uri.parse('https://fake.supabase.co/rest/v1/field_job_photos'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(row),
        );
        final response = await transport.get(
          Uri.parse(
            'https://fake.supabase.co/rest/v1/field_job_photos'
            '?select=photo_url,latitude,longitude,captured_at,notes',
          ),
        );
        final read =
            (jsonDecode(response.body) as List).single as Map<String, dynamic>;

        expect(read['photo_url'], row['photo_url']);
        expect(read['latitude'], 13.842512);
        expect(read['longitude'], 121.123456);
        expect(read['captured_at'], '2026-10-21T06:05:09.000Z');
        expect(read['notes'], kSiteLocationReferenceNotes);
      },
    );
  });
}
