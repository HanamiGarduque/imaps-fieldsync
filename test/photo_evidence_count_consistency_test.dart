import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imaps_fieldsync/core/models/task_submission.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/field_findings_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/inspection/services/photo_evidence_presentation.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => fixture.directory.path,
    );
  });
  tearDown(() async {
    completedDetailFetcherOverride = null;
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  // Reference first deliberately: raw attachment indices must not number
  // either the reference or the camera photos that follow it.
  void seed(int siteCount, int referenceCount, {bool blankNotes = false}) {
    final bytes = img.encodePng(img.Image(width: 2, height: 2));
    if (referenceCount == 1) {
      final path = File('${fixture.directory.path}/reference.png')
        ..writeAsBytesSync(bytes);
      fixture.provider.addPhoto(
        photoPath: path.path,
        photoNotes: kSiteLocationReferenceNotes,
        latitude: 0.0001,
        longitude: 0.0002,
        capturedAt: DateTime.utc(2026, 10, 22, 2, 3),
        photoId: SiteLocationReferenceService.photoId(offlineJob, 1),
        isLocationReference: true,
      );
    }
    for (var i = 0; i < siteCount; i++) {
      final path = File('${fixture.directory.path}/camera-$i.png')
        ..writeAsBytesSync(bytes);
      fixture.provider.addPhoto(
        photoPath: path.path,
        photoNotes: blankNotes ? '' : 'Camera observation ${i + 1}',
        latitude: 0.0003,
        longitude: 0.0004,
        capturedAt: DateTime.utc(2026, 10, 22, 2, 4),
        photoId: 'camera-$i',
      );
    }
  }

  List<Map<String, dynamic>> remoteDetails() => [
    for (final photo in fixture.provider.capturedPhotos)
      {
        'id': photo['id'],
        'photo_url': photo['photoPath'],
        'notes': photo['notes'],
        'latitude': photo['latitude'],
        'longitude': photo['longitude'],
        'captured_at': photo['capturedAt'],
      },
  ];

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    // Keep the finder unfiltered while the ListView builds off-screen rows.
    await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
    await fixture.flush(tester);
  }

  Future<void> completeSteps(WidgetTester tester) async {
    InspectionProgress.instance.ensureActiveInspection(
      offlineJob,
      initialStep: 5,
    );
    await fixture.flush(tester);
    fixture.provider.updateResult('Compliant');
  }

  Future<void> enqueue({List<Map<String, dynamic>>? photos}) =>
      SyncOutboxService.enqueueSubmitInspection(
        jobId: offlineJob,
        findings: 'Fictional observation',
        isCompliant: true,
        inspectionResult: 'Compliant',
        observations: 'Fictional site',
        inspectorNotes: 'Fictional observation',
        checklistData: const [],
        checklistCompletedCount: 0,
        checklistTotalCount: 0,
        photosData: photos ?? fixture.provider.capturedPhotos,
      );

  for (final (a, b, c) in const [
    (0, 0, 0),
    (0, 1, 1),
    (1, 1, 2),
    (10, 1, 11),
    (12, 1, 13),
    (100, 1, 101),
  ]) {
    fixture.widgetTest('Review distinguishes A=$a B=$b C=$c', (tester) async {
      seed(a, b);
      final before = jsonEncode(fixture.provider.capturedPhotos);
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await fixture.flush(tester);
      expect(find.text('Site photos'), findsOneWidget);
      expect(find.text('Total evidence attachments'), findsOneWidget);
      expect(
        find.text('Site Location Reference'),
        b == 1 ? findsWidgets : findsNothing,
      );
      expect(find.text('$a'), findsWidgets);
      expect(find.text('$c'), findsWidgets);
      if (c > 0) {
        await reveal(tester, find.text('Evidence attachments'));
        expect(find.text('$c total attachments'), findsOneWidget);
        expect(find.text('Photo ${a + 1}'), findsNothing);
        for (var number = 1; number <= a; number++) {
          expect(find.text('Photo $number'), findsOneWidget);
        }
        if (b == 1) {
          final reference = find.bySemanticsLabel(
            RegExp('^View site location reference'),
          );
          expect(reference, findsOneWidget);
          expect(
            find.descendant(
              of: reference,
              matching: find.byIcon(Icons.map_outlined),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: reference,
              matching: find.byIcon(Icons.camera_alt_outlined),
            ),
            findsNothing,
          );
          await tester.tap(reference);
          await fixture.flush(tester);
          final viewer = tester.widget<FullscreenPhotoViewer>(
            find.byType(FullscreenPhotoViewer),
          );
          expect(
            viewer.photoDetails!.first,
            fixture.provider.capturedPhotos.first,
          );
          expect(viewer.startIndex, 0);
          expect(find.text('Save Copy'), findsOneWidget);
        }
      }
      expect(jsonEncode(fixture.provider.capturedPhotos), before);
    });

    fixture.widgetTest('Findings distinguishes A=$a B=$b C=$c', (tester) async {
      seed(a, b);
      await fixture.mount(
        tester,
        FieldFindingsScreen(
          task: offlineTask,
          capturedPhotos: fixture.provider.capturedPhotos,
        ),
      );
      await fixture.flush(tester);
      if (c > 0) {
        final siteLabel =
            '$a ${a == 1 ? 'site photo' : 'site photos'} attached';
        expect(find.text(siteLabel), findsOneWidget);
        await reveal(tester, find.text(siteLabel));
      }
      expect(
        find.text('Site Location Reference attached'),
        b == 1 ? findsOneWidget : findsNothing,
      );
    });

    test(
      'A=$a B=$b C=$c payload, metadata and restart stay compatible',
      () async {
        seed(a, b);
        final before = jsonDecode(jsonEncode(fixture.provider.capturedPhotos));
        final display = PhotoEvidencePresentation(
          fixture.provider.capturedPhotos,
        );
        expect(display.sitePhotoCount, a);
        expect(display.referenceCount, b);
        expect(display.totalCount, c);
        final remoteDisplay = PhotoEvidencePresentation(
          remoteDetails(),
          requireMetadata: true,
        );
        expect(remoteDisplay.sitePhotoCount, a);
        expect(remoteDisplay.referenceCount, b);
        expect(remoteDisplay.totalCount, c);
        expect(fixture.provider.realPhotoCount, a);
        expect(
          fixture.provider.capturedPhotos.where(isLocationReferencePhoto),
          hasLength(b),
        );
        expect(fixture.provider.capturedPhotos, hasLength(c));
        await fixture.provider.persistCapturedPhotos();
        await fixture.provider.persistCapturedPhotos();
        await enqueue();
        final row = (await DBHelper.getSyncCenterQueueActions()).singleWhere(
          (r) => r['type'] == 'submit_inspection',
        );
        final submission = TaskSubmission.fromRow(row);
        expect(submission.payload['photosData'], before);
        expect(submission.evidenceFields['photo_count'], c);
        expect(submission.evidenceFields['field_job_photos'], hasLength(c));
        await fixture.restartDatabase();
        final restored = InspectionProvider();
        await restored.startInspection(offlineTask);
        expect(restored.realPhotoCount, a);
        expect(
          restored.capturedPhotos.where(isLocationReferencePhoto),
          hasLength(b),
        );
        expect(restored.capturedPhotos, hasLength(c));
        for (final photo in restored.capturedPhotos) {
          final original = (before as List).singleWhere(
            (p) => p['id'] == photo['id'],
          );
          for (final key in ['notes', 'latitude', 'longitude', 'capturedAt']) {
            expect(photo[key], original[key], reason: '$key survives restart');
          }
        }
        final rows = await DBHelper.getLocalPhotos(offlineJob);
        expect(rows.map((r) => r['id']).toSet(), hasLength(c));
        expect(await DBHelper.getLocalPhotos(offlineRound2), isEmpty);
        DBHelper.inspectorIdForTesting = otherOfflineInspector;
        expect(restored.capturedPhotos, isEmpty);
        expect(await DBHelper.getLocalPhotos(offlineJob), isEmpty);
        DBHelper.inspectorIdForTesting = null;
        restored.dispose();
      },
    );

    fixture.widgetTest('Completed distinguishes A=$a B=$b C=$c', (
      tester,
    ) async {
      seed(a, b);
      final details = remoteDetails();
      final job = <String, dynamic>{
        'id': offlineJob,
        'status': 'completed',
        'current_step': 6,
        'photo_count': c,
        'field_job_photos': details,
      };
      completedDetailFetcherOverride = (_) async => job;
      await fixture.mount(
        tester,
        CompletedInspectionDetailScreen(task: TaskItem.fromJob(job)),
      );
      await fixture.flush(tester);
      await reveal(tester, find.text('Photographic Evidence'));
      await tester.tap(find.text('Photographic Evidence').first);
      await fixture.flush(tester);
      for (var number = 1; number <= a; number++) {
        expect(find.text('Photo $number of $a'), findsOneWidget);
      }
      expect(find.text('Photo ${a + 1} of $c'), findsNothing);
      expect(
        find.text('Site Location Reference'),
        b == 1 ? findsOneWidget : findsNothing,
      );
      if (b == 1) {
        final reference = find.bySemanticsLabel(
          RegExp('^View site location reference'),
        );
        expect(
          find.descendant(
            of: reference,
            matching: find.byIcon(Icons.map_outlined),
          ),
          findsOneWidget,
        );
        await reveal(tester, reference);
        await tester.tap(
          find
              .descendant(of: reference, matching: find.byType(GestureDetector))
              .first,
        );
        await fixture.flush(tester);
        final viewer = tester.widget<FullscreenPhotoViewer>(
          find.byType(FullscreenPhotoViewer),
        );
        expect(viewer.photoDetails, details);
        expect(viewer.startIndex, 0);
      }
      expect(job['photo_count'], c);
    });
  }

  for (final b in [0, 1]) {
    fixture.widgetTest('zero camera photos block submission with B=$b', (
      tester,
    ) async {
      seed(0, b);
      await completeSteps(tester);
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      expect(
        find.textContaining('Capture at least one camera photo'),
        findsWidgets,
      );
      expect(find.text('Confirm & Submit'), findsNothing);
      expect(
        (await DBHelper.getSyncCenterQueueActions()).where(
          (r) => r['type'] == 'submit_inspection',
        ),
        isEmpty,
      );
      expect(fixture.provider.inspectionResult, 'Compliant');
    });
  }

  fixture.widgetTest(
    'confirmation and final offline intent preserve A=1 B=1 C=2',
    (tester) async {
      seed(1, 1);
      await completeSteps(tester);
      final before = jsonDecode(jsonEncode(fixture.provider.capturedPhotos));
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Site photos: 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Site Location Reference: 1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Total evidence attachments: 2'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm & Submit'));
      await fixture.flush(tester);
      final row = (await DBHelper.getSyncCenterQueueActions()).singleWhere(
        (r) => r['type'] == 'submit_inspection',
      );
      expect(TaskSubmission.fromRow(row).payload['photosData'], before);
      expect(TaskSubmission.fromRow(row).evidenceFields['photo_count'], 2);
      expect(fixture.remoteWrites, 0);
    },
  );

  for (final legacy in [false, true]) {
    fixture.widgetTest(
      'Overview ${legacy ? 'path-only legacy' : 'remote metadata'} uses honest evidence labels',
      (tester) async {
        seed(1, 1);
        final details = remoteDetails();
        // Use another round so the active local provider cannot substitute data.
        final task = TaskItem.fromJob({
          'id': offlineRound2,
          'status': 'in_progress',
          'field_job_photos': legacy ? [] : details,
          'photo_paths': details.map((p) => p['photo_url']).toList(),
        });
        await fixture.mount(tester, ParcelDetailScreen(task: task));
        await fixture.flush(tester);
        await reveal(
          tester,
          find.text(
            legacy ? 'Evidence attachments (type unavailable)' : 'Site photos',
          ),
        );
        expect(
          find.text('Site Location Reference'),
          legacy ? findsNothing : findsWidgets,
        );
        if (legacy) expect(find.text('Site photos'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  fixture.widgetTest(
    'Completed unknown rows never become camera photos or references',
    (tester) async {
      final job = <String, dynamic>{
        'id': offlineJob,
        'status': 'completed',
        'field_job_photos': [
          {
            'photo_url':
                '/missing/inspection_site_location_reference_legacy_r1.jpg',
          },
          {'photo_url': '/missing/null-note.jpg', 'notes': null},
          {'photo_url': '/missing/empty-note.jpg', 'notes': ''},
        ],
      };
      completedDetailFetcherOverride = (_) async => job;
      await fixture.mount(
        tester,
        CompletedInspectionDetailScreen(task: TaskItem.fromJob(job)),
      );
      await fixture.flush(tester);
      await reveal(tester, find.text('Photographic Evidence'));
      await tester.tap(find.text('Photographic Evidence').first);
      await fixture.flush(tester);
      expect(find.text('Evidence attachment 1 of 3'), findsOneWidget);
      expect(find.text('Evidence attachment 3 of 3'), findsOneWidget);
      expect(find.textContaining('Photo 1 of'), findsNothing);
      expect(find.text('Site Location Reference'), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    },
  );

  fixture.widgetTest(
    'blank-note camera identity survives saved submission and restart',
    (tester) async {
      seed(1, 1, blankNotes: true);
      await completeSteps(tester);
      await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask));
      await tester.tap(find.text('Submit Inspection'));
      await fixture.flush(tester);
      await tester.tap(find.text('Confirm & Submit'));
      await fixture.flush(tester);
      for (final restart in [false, true]) {
        await fixture.unmount(tester);
        if (restart) await tester.runAsync(fixture.restartDatabase);
        final row = (await DBHelper.getSyncCenterQueueActions()).singleWhere(
          (r) => r['type'] == 'submit_inspection',
        );
        final receipt = TaskSubmission.fromRow(row);
        expect((receipt.payload['photosData'] as List)[1]['notes'], '');
        await fixture.mount(
          tester,
          CompletedInspectionDetailScreen(
            task: offlineTask,
            submission: receipt,
          ),
        );
        for (
          var i = 0;
          i < 40 && find.byType(Scrollable).evaluate().isEmpty;
          i++
        ) {
          await fixture.flush(tester);
        }
        await reveal(tester, find.text('Photographic Evidence'));
        await tester.tap(find.text('Photographic Evidence').first);
        await fixture.flush(tester);
        expect(find.text('Photo 1 of 1'), findsOneWidget);
        expect(find.text('Site Location Reference'), findsOneWidget);
        expect(find.textContaining('Evidence attachment 2'), findsNothing);
        expect(receipt.evidenceFields['photo_count'], 2);
      }
    },
  );

  fixture.widgetTest(
    'saved mixed legacy evidence is not given capture provenance',
    (tester) async {
      seed(1, 1, blankNotes: true);
      await enqueue(
        photos: [
          ...fixture.provider.capturedPhotos,
          {'photoPath': '/legacy/no-metadata.jpg'},
          {
            'id': 'legacy-remote',
            'photoPath': 'inspections/$offlineJob/remote.jpg',
            'notes': '',
            'capturedAt': '2026-10-22T02:04:00Z',
            'isRemoteUrl': true,
          },
        ],
      );
      final row = (await DBHelper.getSyncCenterQueueActions()).singleWhere(
        (r) => r['type'] == 'submit_inspection',
      );
      final receipt = TaskSubmission.fromRow(row);
      await fixture.mount(
        tester,
        CompletedInspectionDetailScreen(task: offlineTask, submission: receipt),
      );
      for (
        var i = 0;
        i < 40 && find.byType(Scrollable).evaluate().isEmpty;
        i++
      ) {
        await fixture.flush(tester);
      }
      await reveal(tester, find.text('Photographic Evidence'));
      await tester.tap(find.text('Photographic Evidence').first);
      await fixture.flush(tester);
      expect(find.text('Photo 1 of 1'), findsOneWidget);
      expect(find.text('Site Location Reference'), findsOneWidget);
      expect(find.text('Evidence attachment 3 of 4'), findsOneWidget);
      expect(find.text('Evidence attachment 4 of 4'), findsOneWidget);
      expect(receipt.evidenceFields['photo_count'], 4);
    },
  );

  fixture.widgetTest(
    'local and rework Overview preserve reference identity and viewer metadata',
    (tester) async {
      seed(1, 1);
      final details = remoteDetails();
      for (final rework in [false, true]) {
        if (rework) {
          fixture.provider.hydrateForRework(
            TaskItem.fromJob({
              'id': offlineJob,
              'status': 'completed',
              'field_job_photos': details,
            }),
          );
        }
        await fixture.mount(tester, ParcelDetailScreen(task: offlineTask));
        await fixture.flush(tester);
        await reveal(tester, find.text('Site Location Reference'));
        expect(find.text('Site photos'), findsOneWidget);
        final reference = find.bySemanticsLabel(
          RegExp('^View site location reference'),
        );
        expect(reference, findsOneWidget);
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
        await tester.tap(reference);
        await fixture.flush(tester);
        final viewer = tester.widget<FullscreenPhotoViewer>(
          find.byType(FullscreenPhotoViewer),
        );
        expect(
          viewer.photoDetails!.first['notes'],
          kSiteLocationReferenceNotes,
        );
        expect(viewer.photoDetails!.first['latitude'], 0.0001);
        expect(viewer.startIndex, 0);
        await fixture.unmount(tester);
      }
    },
  );

  fixture.widgetTest('reference caption keeps whole words at enlarged text', (tester) async {
    seed(1, 1);
    await fixture.mount(tester, ReviewSubmitScreen(task: offlineTask), size: const Size(800, 1280), textScale: 2);
    await fixture.flush(tester);
    await reveal(tester, find.text('Evidence attachments'));
    final caption = find.descendant(
      of: find.bySemanticsLabel(RegExp('^View site location reference')),
      matching: find.text('Site Location Reference'),
    );
    final text = tester.widget<Text>(caption);
    final painter = TextPainter(
      text: TextSpan(text: 'Reference', style: text.style),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2),
    )..layout();
    expect(tester.getSize(caption).width, greaterThanOrEqualTo(painter.width));
    painter.dispose();
  });

  for (final size in [
    const Size(320, 640),
    const Size(640, 360),
    const Size(800, 1280),
  ]) {
    fixture.widgetTest(
      'reference labels remain responsive at $size with 2x text',
      (tester) async {
        seed(12, 1);
        await fixture.mount(
          tester,
          ReviewSubmitScreen(task: offlineTask),
          size: size,
          textScale: 2,
        );
        await fixture.flush(tester);
        await reveal(tester, find.text('Evidence attachments'));
        await fixture.capture(tester, 'review-reference-${size.width.toInt()}');
        expect(find.text('Photo 13'), findsNothing);
        expect(tester.takeException(), isNull);
        await fixture.mount(
          tester,
          FieldFindingsScreen(task: offlineTask),
          size: size,
          textScale: 2,
        );
        await fixture.flush(tester);
        await reveal(tester, find.text('Site Location Reference attached'));
        await fixture.capture(
          tester,
          'findings-reference-${size.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        final job = <String, dynamic>{
          'id': offlineJob,
          'status': 'completed',
          'field_job_photos': remoteDetails(),
        };
        completedDetailFetcherOverride = (_) async => job;
        await fixture.mount(
          tester,
          CompletedInspectionDetailScreen(task: TaskItem.fromJob(job)),
          size: size,
          textScale: 2,
        );
        await fixture.flush(tester);
        await reveal(tester, find.text('Photographic Evidence'));
        await tester.tap(find.text('Photographic Evidence').first);
        await fixture.flush(tester);
        await reveal(tester, find.text('Site Location Reference'));
        await fixture.capture(
          tester,
          'completed-reference-${size.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  fixture.widgetTest(
    'Sync Center calls C=13 evidence attachments, not site photos',
    (tester) async {
      seed(12, 1);
      await enqueue();
      await fixture.mount(
        tester,
        UpdatesScreen(
          profile: UserProfile(
            id: offlineInspector,
            fullName: 'Fixture Inspector',
            role: 'inspector',
          ),
        ),
      );
      for (
        var i = 0;
        i < 50 && find.text('Sync Center').evaluate().isEmpty;
        i++
      ) {
        await fixture.flush(tester);
      }
      expect(find.text('Sync Center'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('13 evidence attachments'), findsWidgets);
      expect(find.textContaining('13 photos'), findsNothing);
      expect(find.text('Evidence files 13'), findsOneWidget);
    },
  );
}
