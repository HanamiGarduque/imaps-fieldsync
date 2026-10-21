import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/capture_photo_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';

import 'support/offline_reliability_fixture.dart';

/// 1x1 PNG so the real image pipeline decodes without synthetic failures.
final Uint8List _png = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  45,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  /// Scrolls the page until the Add cell is built and visible.
  Future<void> revealAddCell(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Add site photo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  fixture.widgetTest(
    'site photo counter and Add cell keep working at 0, 1, 10, 11, 20, 50 and 100',
    (tester) async {
      final raw = File('${fixture.directory.path}/camera.png')
        ..writeAsBytesSync(_png);
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await fixture.flush(tester);
      expect(find.text('0 site photos'), findsOneWidget);
      await revealAddCell(tester);
      expect(find.bySemanticsLabel('Add site photo'), findsOneWidget);

      for (final target in [1, 10, 11, 20, 50, 100]) {
        while (fixture.provider.capturedPhotos.length < target) {
          fixture.provider.addPhoto(
            photoPath: raw.path,
            photoNotes: 'scale photo ${fixture.provider.capturedPhotos.length}',
            latitude: null,
            longitude: null,
          );
        }
        await fixture.flush(tester);
        expect(
          find.text(target == 1 ? '1 site photo' : '$target site photos'),
          findsOneWidget,
        );
        await revealAddCell(tester);
        expect(find.bySemanticsLabel('Add site photo'), findsOneWidget);
      }

      // Every accepted photo is in the grid, and no cell may ask for a
      // full-resolution decode.
      expect(find.bySemanticsLabel(RegExp('View photo ')), findsNWidgets(100));
      final thumbnails = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(GridView),
              matching: find.byType(Image),
            ),
          )
          .toList();
      expect(thumbnails, isNotEmpty);
      for (final image in thumbnails) {
        expect(image.image, isA<ResizeImage>());
        expect(
          (image.image as ResizeImage).width,
          lessThanOrEqualTo(CapturePhotoScreen.thumbnailCacheWidth),
        );
      }
    },
  );

  fixture.widgetTest(
    'opening a photo from a scaled grid still decodes the original resolution',
    (tester) async {
      final raw = File('${fixture.directory.path}/camera.png')
        ..writeAsBytesSync(_png);
      fixture.provider.addPhoto(
        photoPath: raw.path,
        photoNotes: 'full resolution',
        latitude: null,
        longitude: null,
      );
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await fixture.flush(tester);
      final cell = find.bySemanticsLabel(RegExp('View photo 1'));
      await tester.scrollUntilVisible(
        cell,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(cell);
      await fixture.flush(tester);

      final viewerImages = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(FullscreenPhotoViewer),
              matching: find.byType(Image),
            ),
          )
          .toList();
      expect(viewerImages, isNotEmpty);
      expect(viewerImages.first.image, isNot(isA<ResizeImage>()));
    },
  );

  test(
    'fifty accepted photos persist with stable ids, queue once and survive restart',
    () async {
      final raw = File('${fixture.directory.path}/camera.png')
        ..writeAsBytesSync(_png);
      final ids = <String>[];
      for (var i = 0; i < 50; i++) {
        final id = 'scale-photo-$i';
        ids.add(id);
        fixture.provider.addPhoto(
          photoPath: raw.path,
          photoNotes: 'camera $i',
          latitude: null,
          longitude: null,
          photoId: id,
        );
      }
      expect(await fixture.provider.saveStepPhotos(), isTrue);

      var rows = await DBHelper.getLocalPhotos(offlineJob);
      expect(rows, hasLength(50));
      expect(rows.map((row) => row['id']), containsAll(ids));
      expect(
        rows.every((row) => row['inspector_id'] == offlineInspector),
        isTrue,
      );
      final queued = await fixture.db.query(
        'pending_actions',
        where: 'type = ?',
        whereArgs: ['photos_update'],
      );
      expect(queued, hasLength(1));
      expect(
        (jsonDecode(queued.single['payload'] as String) as Map)['photos'],
        hasLength(50),
      );
      expect(await DBHelper.getPendingPhotos(), hasLength(50));

      await fixture.restartDatabase();
      rows = await DBHelper.getLocalPhotos(offlineJob);
      expect(rows, hasLength(50));
      expect(rows.map((row) => row['id']).toSet(), containsAll(ids));
      expect(await DBHelper.getPendingPhotos(), hasLength(50));
    },
  );

  fixture.widgetTest(
    'a missing photo file does not hide or corrupt the rest of a large set',
    (tester) async {
      final raw = File('${fixture.directory.path}/camera.png')
        ..writeAsBytesSync(_png);
      for (var i = 0; i < 20; i++) {
        fixture.provider.addPhoto(
          photoPath: i == 7
              ? '${fixture.directory.path}/already-deleted.png'
              : raw.path,
          photoNotes: 'camera $i',
          latitude: null,
          longitude: null,
        );
      }
      await fixture.mount(tester, CapturePhotoScreen(task: offlineTask));
      await fixture.flush(tester);
      expect(find.text('20 site photos'), findsOneWidget);
      expect(find.bySemanticsLabel('Add site photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
