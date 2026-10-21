import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  test(
    'a delayed photo upload never updates or queues the newly active round',
    () async {
      final photo = File('${fixture.directory.path}/camera.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      fixture.provider.addPhoto(
        photoPath: photo.path,
        photoNotes: 'round one',
        latitude: null,
        longitude: null,
      );
      final reached = Completer<void>();
      final release = Completer<http.Response>();
      final patchedJobs = <String?>[];
      fixture.requestOverride = (request) async {
        http.Response reply(Object data, [int status = 200]) => http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        if (request.url.path == '/rest/v1/field_jobs') {
          final id = request.url.queryParameters['id']?.replaceFirst('eq.', '');
          if (request.method == 'PATCH') patchedJobs.add(id);
          final job = {
            'id': id,
            'assigned_inspector_id': offlineInspector,
            'status': 'in_progress',
          };
          return reply(
            request.headers['accept']?.contains(
                      'application/vnd.pgrst.object+json',
                    ) ==
                    true
                ? job
                : [job],
          );
        }
        if (request.url.path == '/rest/v1/field_job_photos') {
          if (request.method == 'GET') {
            if (!reached.isCompleted) reached.complete();
            return release.future;
          }
          return reply(jsonDecode(request.body), 201);
        }
        if (request.url.path.startsWith('/storage/')) {
          return reply({
            'Key': request.url.path,
          }, request.method == 'HEAD' ? 404 : 200);
        }
        if (request.url.path == '/rest/v1/activity_log') return reply([], 201);
        throw StateError('Unexpected synthetic request');
      };
      fixture.mode = 'success';
      fixture.online = true;
      final saving = fixture.provider.saveStepPhotos();
      await reached.future.timeout(const Duration(seconds: 5));
      await fixture.provider.startInspection(
        TaskItem(
          id: offlineRound2,
          name: 'Round two',
          location: 'Synthetic second round',
          parcels: '1',
          status: 'in_progress',
          inspectionNo: 'SYNTHETIC-R2',
        ),
      );
      release.complete(
        http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await saving;
      expect(patchedJobs, isNot(contains(offlineRound2)));
      expect(
        await fixture.db.query(
          'pending_actions',
          where: 'job_id = ?',
          whereArgs: [offlineRound2],
        ),
        isEmpty,
      );
    },
  );

  test(
    'ten camera photos and the generated JPEG survive offline queue, retry and double drain',
    () async {
      // Breaks if the real provider/outbox/uploader drops row 11, notes, time,
      // coordinates, local receipts, or reuploads an already stored reference.
      final generatedAt = DateTime.utc(2026, 10, 21, 6, 5, 9);
      final referenceBytes = await SiteLocationReferenceService.render(
        jobId: offlineJob,
        round: 1,
        applicant: 'Synthetic applicant',
        address: 'Synthetic address',
        verifiedLatitude: 13.842512,
        verifiedLongitude: 121.123456,
        verifiedAt: DateTime.utc(2026, 10, 21, 5, 55),
        verifiedAccuracyMeters: 8,
        parcelLatitude: 13.8427,
        parcelLongitude: 121.1236,
        generatedAt: generatedAt,
      );
      for (var i = 0; i <= 10; i++) {
        final reference = i == 10;
        final file = File(
          '${fixture.directory.path}/${reference ? SiteLocationReferenceService.fileName(offlineJob, 1) : 'camera-$i.jpg'}',
        );
        await file.writeAsBytes(referenceBytes, flush: true);
        fixture.provider.addPhoto(
          photoPath: file.path,
          photoNotes: reference
              ? kSiteLocationReferenceNotes
              : 'Synthetic camera photo $i',
          latitude: 13.842512,
          longitude: 121.123456,
          capturedAt: generatedAt,
          photoId: reference
              ? SiteLocationReferenceService.photoId(offlineJob, 1)
              : null,
          isLocationReference: reference,
        );
      }
      expect(await fixture.provider.saveStepPhotos(), isTrue);
      expect(await DBHelper.getLocalPhotos(offlineJob), hasLength(11));
      final queued = await fixture.db.query(
        'pending_actions',
        where: 'type = ?',
        whereArgs: ['photos_update'],
      );
      expect(queued, hasLength(1));
      expect(
        (jsonDecode(queued.single['payload'] as String) as Map)['photos'],
        hasLength(11),
      );

      final metadata = <String, Map<String, dynamic>>{};
      final objects = <String>{};
      var uploads = 0;
      var failMetadataOnce = true;
      var job = <String, dynamic>{
        'id': offlineJob,
        'assigned_inspector_id': offlineInspector,
        'status': 'in_progress',
        'updated_at': '2026-01-01T00:00:00Z',
        'photo_paths': <String>[],
        'photo_count': 0,
      };
      fixture.requestOverride = (request) async {
        http.Response reply(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        final path = request.url.path;
        if (path == '/rest/v1/field_jobs') {
          if (request.method == 'PATCH') {
            job = {...job, ...jsonDecode(request.body) as Map<String, dynamic>};
          }
          final single =
              request.headers['accept']?.contains(
                'application/vnd.pgrst.object+json',
              ) ??
              false;
          return reply(single ? job : [job]);
        }
        if (path == '/rest/v1/field_job_photos') {
          if (request.method == 'GET') {
            final id = request.url.queryParameters['id']?.replaceFirst(
              'eq.',
              '',
            );
            return reply(
              metadata.values
                  .where((row) => id == null || row['id'] == id)
                  .toList(),
            );
          }
          if (failMetadataOnce) {
            failMetadataOnce = false;
            return reply({
              'code': 'fixture',
              'message': 'Synthetic metadata interruption',
            }, 503);
          }
          final row = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          metadata[row['id'] as String] = row;
          return reply(row, 201);
        }
        if (path.startsWith('/storage/v1/object/inspection-photos/')) {
          if (request.method == 'HEAD') {
            return reply({}, objects.contains(path) ? 200 : 404);
          }
          if (request.method == 'POST') {
            expect(
              latin1.decode(request.bodyBytes),
              contains(latin1.decode(referenceBytes)),
            );
            uploads++;
            objects.add(path);
            return reply({'Key': path});
          }
        }
        if (path == '/rest/v1/activity_log') return reply([], 201);
        throw StateError(
          'Unexpected synthetic request ${request.method} $path',
        );
      };
      fixture.online = true;
      fixture.mode = 'success';
      SyncOutboxService.hasConnectionOverride = () async => true;
      await SyncOutboxService.drain(trigger: 'manual');
      expect(
        (await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['photos_update'],
        )).single['status'],
        'failed',
      );
      await SyncOutboxService.drain(trigger: 'manual');
      expect(
        (await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['photos_update'],
        )).single['status'],
        'synced',
      );
      expect(metadata, hasLength(11));
      expect(objects, hasLength(11));
      expect(
        uploads,
        11,
        reason:
            'retry must repair metadata without uploading the same JPEG twice',
      );
      expect(job['photo_count'], 11);
      final reference = metadata.values.singleWhere(
        (row) => row['notes'] == kSiteLocationReferenceNotes,
      );
      expect(reference['latitude'], 13.842512);
      expect(reference['longitude'], 121.123456);
      expect(reference['captured_at'], '2026-10-21T06:05:09.000Z');
      expect(
        reference['photo_url'],
        SupabaseService.photoStoragePath(
          offlineJob,
          fixture.provider.capturedPhotos.last['photoPath'] as String,
        ),
      );
      expect(
        (await DBHelper.getLocalPhotos(
          offlineJob,
        )).every((row) => row['is_synced'] == 1),
        isTrue,
      );
      await SyncOutboxService.drain(trigger: 'manual');
      expect(uploads, 11);
      expect(metadata, hasLength(11));
      final export = Platform.environment['PHASE1A_SYNTHETIC_EXPORT'];
      if (export != null) {
        await File(export).writeAsString(jsonEncode(metadata.values.toList()));
      }
    },
  );
}
