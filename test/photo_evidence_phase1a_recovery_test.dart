import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_checklist_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  late File raw;
  Completer<String>? documents;
  var documentRequests = 0;
  var fixRequests = 0;
  var lateShutterFix = false;
  var gpsDisabled = false;
  var reportedAccuracy = 8.0;
  var fixAge = Duration.zero;
  String? clipboard;
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    documents = null;
    documentRequests = 0;
    fixRequests = 0;
    lateShutterFix = false;
    gpsDisabled = false;
    reportedAccuracy = 8;
    fixAge = Duration.zero;
    clipboard = null;
    raw = File('${fixture.directory.path}/raw.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 320, height: 480)));
    final messenger = fixture.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async {
        documentRequests++;
        return documents?.future ?? fixture.directory.path;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (call) async {
        switch (call.method) {
          case 'availableCameras':
            return [
              {'name': 'back', 'lensFacing': 'back', 'sensorOrientation': 90},
            ];
          case 'create':
            return {'cameraId': 1};
          case 'initialize':
            fixture.binding.channelBuffers.push(
              'flutter.io/cameraPlugin/camera1',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('initialized', {
                  'previewWidth': 320.0,
                  'previewHeight': 480.0,
                  'exposureMode': 'auto',
                  'focusMode': 'auto',
                  'exposurePointSupported': false,
                  'focusPointSupported': false,
                }),
              ),
              (_) {},
            );
            return null;
          case 'takePicture':
            return raw.path;
          case 'dispose':
            return null;
        }
        throw MissingPluginException(call.method);
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async {
        if (call.method == 'isLocationServiceEnabled') return !gpsDisabled;
        if (call.method == 'checkPermission') return 3;
        if (call.method != 'getCurrentPosition') {
          throw MissingPluginException(call.method);
        }
        fixRequests++;
        if (lateShutterFix && fixRequests > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 2300));
        }
        return {
          'latitude': 13.842512,
          'longitude': 121.123456,
          'accuracy': lateShutterFix && fixRequests == 1
              ? 100.0
              : reportedAccuracy,
          'timestamp': DateTime.now().subtract(fixAge).millisecondsSinceEpoch,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
        };
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  Future<void> flushUntil(WidgetTester tester, bool Function() ready) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 400 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(
      ready(),
      isTrue,
      reason: 'bounded wait for the real async evidence operation',
    );
  }

  Future<void> capture(WidgetTester tester) async {
    await tester.ensureVisible(find.bySemanticsLabel('Add site photo'));
    await tester.tap(find.bySemanticsLabel('Add site photo'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.bySemanticsLabel('Capture site photo')),
    );
    await flushUntil(
      tester,
      () => find.text('Save Photo').evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.text('Save Photo'));
  }

  Future<void> referenceInputs() async {
    await fixture.db.update(
      'local_jobs',
      {'parcel_lat': 13.8427, 'parcel_lng': 121.1236},
      where: 'id = ?',
      whereArgs: [offlineJob],
    );
    await fixture.provider.recordGpsVerification(
      distanceMeters: 24,
      latitude: 13.842512,
      longitude: 121.123456,
      accuracyMeters: 8,
      fixAt: DateTime.now(),
    );
  }

  fixture.widgetTest('unaccepted camera JPEG stays outside canonical evidence until Save', (tester) async {
    await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
    await tester.pumpAndSettle();
    await capture(tester);
    final files = fixture.directory.listSync(recursive: true).whereType<File>()
        .where((file) => file.path.endsWith('.jpg') && p.basename(file.path) != 'raw.jpg').toList();
    expect(files, hasLength(1));
    expect(files.single.path, contains('pending_captures_v1'));
    expect(await DBHelper.getLocalPhotos(offlineJob), isEmpty);
    await tester.tap(find.text('Save Photo'));
    await fixture.flush(tester);
    final row = (await DBHelper.getLocalPhotos(offlineJob)).single;
    expect(row['photo_path'], isNot(contains('pending_captures_v1')));
    expect(File(row['photo_path'] as String).existsSync(), isTrue);
  });

  Future<File> abandoned({String owner = offlineInspector, String job = offlineJob,
      String state = 'pending', bool malformed = false, bool extraFile = false}) async {
    String key(String value) => base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
    final dir = Directory(p.join(fixture.directory.path, 'pending_captures_v1',
      key(owner), key(job), 'round_${offlineTask.inspectionRoundNumber ?? 0}', id));
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'capture.json')).writeAsStringSync(malformed ? '{' : jsonEncode({
      'version': 1, 'owner': owner, 'job': job,
      'round': offlineTask.inspectionRoundNumber ?? 0, 'id': id, 'state': state,
    }));
    final photo = raw.copySync(p.join(dir.path, 'photo.jpg'));
    if (extraFile) File(p.join(dir.path, 'unknown.txt')).writeAsStringSync('retain');
    return photo;
  }

  fixture.widgetTest('reopening cleans only proved abandoned temporary capture, not legacy evidence', (tester) async {
    final pending = await abandoned();
    final legacy = raw.copySync(p.join(fixture.directory.path, 'legacy.jpg'));
    await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
    await flushUntil(tester, () => !pending.existsSync());
    expect(legacy.existsSync(), isTrue);
    expect(raw.existsSync(), isTrue);
    expect(await DBHelper.getLocalPhotos(offlineJob), isEmpty);
  });

  for (final protection in ['local row', 'queued upload', 'final submission', 'malformed receipt',
      'unknown file', 'accepting state', 'foreign owner', 'other round', 'malformed queue']) {
    fixture.widgetTest('temporary cleanup retains $protection evidence', (tester) async {
      final pending = await abandoned(
        owner: protection == 'foreign owner' ? 'foreign-owner' : offlineInspector,
        job: protection == 'other round' ? offlineRound2 : offlineJob,
        state: protection == 'accepting state' ? 'accepting' : 'pending',
        malformed: protection == 'malformed receipt', extraFile: protection == 'unknown file');
      if (protection == 'local row') {
        await DBHelper.savePhotoLocally(photoId: 'protected-photo', jobId: offlineJob,
          photoPath: pending.path, notes: 'accepted', latitude: null, longitude: null);
      }
      if (['queued upload', 'final submission', 'malformed queue'].contains(protection)) {
        await fixture.db.insert('pending_actions', {
          'id': 'protected-action', 'job_id': offlineJob, 'inspector_id': offlineInspector,
          'type': protection == 'final submission' ? 'submit_inspection' : 'photos_update',
          'payload': protection == 'malformed queue' ? '{' : jsonEncode({'photos': [{'photoPath': pending.path}]}),
          'created_at': '2026-10-22T00:00:00Z', 'updated_at': '2026-10-22T00:00:00Z',
        });
      }
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(pending.existsSync(), isTrue);
      expect(pending.readAsBytesSync(), raw.readAsBytesSync());
    });
  }

  for (final scenario in ['unavailable', 'inaccurate', 'stale']) {
    fixture.widgetTest(
      '$scenario camera GPS stays null despite a valid Step 2/parcel reference',
      (tester) async {
        await referenceInputs();
        gpsDisabled = scenario == 'unavailable';
        reportedAccuracy = scenario == 'inaccurate' ? 25.1 : 8;
        fixAge = scenario == 'stale'
            ? const Duration(seconds: 16)
            : Duration.zero;
        await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
        await flushUntil(tester, () => fixture.provider.hasLocationReference);
        await capture(tester);
        await tester.tap(find.text('Save Photo'));
        await fixture.flush(tester);
        await tester.pumpAndSettle();
        final camera = fixture.provider.capturedPhotos.singleWhere(
          (photo) => !isLocationReferencePhoto(photo),
        );
        expect(camera['latitude'], isNull);
        expect(camera['longitude'], isNull);
        expect(fixture.provider.realPhotoCount, 1);
        await tester.tap(find.bySemanticsLabel(RegExp('View photo 1')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Copy Google Maps Location'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }

  fixture.widgetTest(
    'a reference-only resumed Review cannot submit as camera evidence',
    (tester) async {
      fixture.provider.addPhoto(
        photoPath: raw.path,
        photoNotes: kSiteLocationReferenceNotes,
        latitude: 13.842512,
        longitude: 121.123456,
        isLocationReference: true,
      );
      fixture.provider.updateResult('Compliant');
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Confirm & Submit'), findsNothing);
      expect(find.textContaining('at least one camera photo'), findsWidgets);
      expect(
        await fixture.db.query(
          'pending_actions',
          where: 'type = ?',
          whereArgs: ['submit_inspection'],
        ),
        isEmpty,
      );
    },
  );

  fixture.widgetTest(
    'ten real photos plus one reference hide Add without raising the camera limit',
    (tester) async {
      for (var i = 0; i < 10; i++) {
        fixture.provider.addPhoto(
          photoPath: raw.path,
          photoNotes: 'camera $i',
          latitude: null,
          longitude: null,
        );
      }
      fixture.provider.addPhoto(
        photoPath: raw.path,
        photoNotes: kSiteLocationReferenceNotes,
        latitude: 13.842512,
        longitude: 121.123456,
        isLocationReference: true,
      );
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await tester.pumpAndSettle();
      expect(find.text('10 / 10 photos'), findsOneWidget);
      expect(find.bySemanticsLabel('Add site photo'), findsNothing);
      expect(fixture.provider.capturedPhotos, hasLength(11));
    },
  );

  fixture.widgetTest(
    'Continue cannot advance when a restored camera photo cannot be persisted',
    (tester) async {
      fixture.provider.addPhoto(
        photoPath: raw.path,
        photoNotes: 'restored unsaved session',
        latitude: null,
        longitude: null,
      );
      await fixture.db.execute(
        "CREATE TRIGGER fail_photo BEFORE INSERT ON local_photos BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
      );
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Checklist'));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(find.byType(InspectionChecklistScreen), findsNothing);
      expect(find.textContaining('Stay on Step 3'), findsOneWidget);
    },
  );

  test('a silent SQLite IGNORE cannot acknowledge an absent photo row', () async {
    await fixture.db.execute(
      'CREATE TRIGGER ignore_photo BEFORE INSERT ON local_photos BEGIN SELECT RAISE(IGNORE); END',
    );
    fixture.provider.addPhoto(
      photoPath: raw.path,
      photoNotes: 'must be durable',
      latitude: null,
      longitude: null,
    );
    expect(await fixture.provider.saveStepPhotos(), isFalse);
    expect(await DBHelper.getLocalPhotos(offlineJob), isEmpty);
  });

  fixture.widgetTest(
    'failed local camera save is not accepted and retains preview for retry',
    (tester) async {
      await fixture.db.execute(
        "CREATE TRIGGER fail_photo BEFORE INSERT ON local_photos BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
      );
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await tester.pumpAndSettle();
      await capture(tester);
      await tester.tap(find.text('Save Photo'));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(fixture.provider.capturedPhotos, isEmpty);
      expect(find.text('Capture Site Photo'), findsOneWidget);
      expect(find.byType(InspectionChecklistScreen), findsNothing);
      await fixture.db.execute('DROP TRIGGER fail_photo');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Photo'));
      await tester.tap(find.text('Save Photo'));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(await DBHelper.getLocalPhotos(offlineJob), hasLength(1));
      expect(fixture.provider.capturedPhotos, hasLength(1));
    },
  );

  fixture.widgetTest(
    'Retake and Close cannot delete the file during a pending local save',
    (tester) async {
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await tester.pumpAndSettle();
      await capture(tester);
      final release = Completer<void>();
      final held = fixture.db.transaction((_) => release.future);
      try {
        await tester.tap(find.text('Save Photo'));
        await tester.pump();
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Retake'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Close camera',
                ),
              )
              .onPressed,
          isNull,
        );
      } finally {
        release.complete();
        await tester.runAsync(() => held);
        await fixture.flush(tester);
      }
      expect(
        File(
          fixture.provider.capturedPhotos.single['photoPath'] as String,
        ).existsSync(),
        isTrue,
      );
    },
  );

  fixture.widgetTest(
    'a fix measured after the shutter skew window is not attributed to that camera photo',
    (tester) async {
      lateShutterFix = true;
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await tester.pumpAndSettle();
      await capture(tester);
      await tester.tap(find.text('Save Photo'));
      await fixture.flush(tester);
      final saved = fixture.provider.capturedPhotos.single;
      expect(saved['latitude'], isNull);
      expect(saved['longitude'], isNull);
    },
  );

  fixture.widgetTest(
    'late reference completion cannot attach evidence to another active job',
    (tester) async {
      await referenceInputs();
      documents = Completer<String>();
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await flushUntil(tester, () => documentRequests > 0);
      await tester.pumpWidget(const SizedBox.shrink());
      final other = TaskItem(
        id: offlineRound2,
        name: 'Other round',
        location: 'Other location',
        parcels: '1',
        status: 'in_progress',
        inspectionNo: 'SYNTHETIC-R2',
      );
      await fixture.provider.startInspection(other);
      documents!.complete(fixture.directory.path);
      await fixture.flush(tester);
      expect(fixture.provider.capturedPhotos, isEmpty);
      expect(await DBHelper.getLocalPhotos(offlineRound2), isEmpty);
    },
  );

  fixture.widgetTest(
    'reference write failure is retryable without a hidden provider entry or duplicate on reopen',
    (tester) async {
      await referenceInputs();
      await fixture.db.execute(
        "CREATE TRIGGER fail_reference BEFORE INSERT ON local_photos BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
      );
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await flushUntil(tester, () => find.text('Retry').evaluate().isNotEmpty);
      expect(fixture.provider.capturedPhotos, isEmpty);
      await fixture.db.execute('DROP TRIGGER fail_reference');
      await tester.tap(find.text('Retry'));
      await flushUntil(tester, () => fixture.provider.hasLocationReference);
      expect(await DBHelper.getLocalPhotos(offlineJob), hasLength(1));
      await tester.tap(find.text('Continue to Checklist'));
      await tester.pumpAndSettle();
      expect(
        find.byType(InspectionChecklistScreen),
        findsNothing,
        reason: 'a generated reference is not a camera photo',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.provider.dispose();
      fixture.provider = InspectionProvider();
      await fixture.provider.startInspection(offlineTask);
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await fixture.flush(tester);
      expect(fixture.provider.capturedPhotos, hasLength(1));
      expect(await DBHelper.getLocalPhotos(offlineJob), hasLength(1));
    },
  );

  fixture.widgetTest(
    'canonical private-storage reference is preserved on completed rework',
    (tester) async {
      await referenceInputs();
      final task = TaskItem(
        id: offlineJob,
        name: 'Synthetic completed',
        location: 'Synthetic address',
        parcels: '1',
        status: 'completed',
        inspectionNo: 'SYNTHETIC-R1',
        confirmedLatitude: 13.842512,
        confirmedLongitude: 121.123456,
        gpsAccuracyM: 8,
        gpsConfirmedAt: '2026-10-21T05:55:00Z',
        photoDetails: [
          {
            'id': 'remote-reference-row',
            'photo_url': 'inspections/$offlineJob/photo_reference.jpg',
            'notes': kSiteLocationReferenceNotes,
          },
        ],
      );
      fixture.provider.hydrateForRework(task);
      expect(fixture.provider.gpsVerification, isNotNull);
      await fixture.mount(tester, CapturePhotoScreen(task: task));
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(fixture.provider.capturedPhotos, hasLength(1));
      expect(
        fixture.provider.capturedPhotos.single['id'],
        'remote-reference-row',
      );
      final regenerated = File(
        p.join(fixture.directory.path, 'inspection_evidence',
            Uri.encodeComponent(offlineInspector), offlineJob,
            SiteLocationReferenceService.fileName(offlineJob, null)),
      );
      expect(
        regenerated.existsSync(),
        isFalse,
        reason: 'accepted remote evidence is not regenerated',
      );
    },
  );

  test(
    'an orphaned authored GPS snapshot prevents a replacement inspector from overwriting it',
    () async {
      await referenceInputs();
      await fixture.db.delete('local_jobs');
      await fixture.db.delete('inspection_job_retention');
      DBHelper.inspectorIdForTesting = otherOfflineInspector;
      try {
        expect(
          await DBHelper.classifyJobOwnership(
            fixture.db,
            offlineJob,
            otherOfflineInspector,
          ),
          LocalOwnershipResult.foreign,
        );
        await expectLater(
          DBHelper.saveGpsVerification(
            jobId: offlineJob,
            latitude: 1,
            longitude: 2,
            accuracyMeters: 8,
            fixAt: DateTime.now(),
            verifiedAt: DateTime.now(),
          ),
          throwsStateError,
        );
        expect(
          (await fixture.db.query(
            'local_gps_verifications',
          )).single['inspector_id'],
          offlineInspector,
        );
      } finally {
        DBHelper.inspectorIdForTesting = null;
      }
    },
  );

  fixture.widgetTest(
    'overview filters photo paths and GPS metadata as one record before Copy Maps',
    (tester) async {
      final task = TaskItem(
        id: offlineJob,
        name: 'Synthetic history',
        location: 'Synthetic address',
        parcels: '1',
        status: 'in_progress',
        inspectionNo: 'SYNTHETIC-HISTORY',
        photoDetails: [
          {
            'photo_url': '',
            'latitude': 50.0,
            'longitude': 50.0,
            'notes': 'invalid path',
          },
          {
            'photo_url': raw.path,
            'latitude': 13.842512,
            'longitude': 121.123456,
            'notes': 'valid camera photo',
          },
        ],
      );
      await fixture.mount(tester, ParcelDetailScreen(task: task));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(AdaptivePhotoImage),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(AdaptivePhotoImage).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AdaptivePhotoImage).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Google Maps Location'));
      await tester.pump();
      expect(clipboard, 'https://maps.google.com/?q=13.842512,121.123456');
    },
  );

  fixture.widgetTest(
    'photo Maps action remains usable on a 320px phone at 200 percent text',
    (tester) async {
      await fixture.mount(
        tester,
        FullscreenPhotoViewer(
          photoPaths: [raw.path],
          startIndex: 0,
          photoDetails: const [
            {'latitude': 13.842512, 'longitude': 121.123456},
          ],
        ),
        size: const Size(320, 640),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Copy Google Maps Location'));
      await tester.pump();
      expect(clipboard, 'https://maps.google.com/?q=13.842512,121.123456');
    },
  );
}
