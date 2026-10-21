import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/services/site_location_reference_service.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  const channel = MethodChannel('imaps_fieldsync/photo_export');
  late File original;
  late File exported;
  var cancel = false;
  var failCopy = false;
  var copies = 0;
  var discarded = 0;
  Completer<bool>? picker;
  setUpAll(fixture.initialize);
  setUp(() async {
    await fixture.reset();
    original = File('${fixture.directory.path}/accepted.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 24, height: 24)));
    exported = File('${fixture.directory.path}/user-selected-copy.jpg');
    cancel = false;
    failCopy = false;
    copies = 0;
    discarded = 0;
    picker = null;
    await fixture.provider.persistPhoto(
      {
        'id': 'ce04b-photo',
        'photoPath': original.path,
        'notes': 'Original notes',
        'latitude': 12.0,
        'longitude': 120.0,
        'capturedAt': '2026-10-21T01:02:03.000Z',
      },
      task: offlineTask,
      inspectorId: offlineInspector,
    );
    fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'createDocument') return picker?.future ?? !cancel;
      if (call.method == 'discardDocument') {
        discarded++;
        return null;
      }
      if (call.method == 'copyPhoto') {
        copies++;
        if (failCopy) throw PlatformException(code: 'copy_failed');
        await File(
          (call.arguments as Map)['path'] as String,
        ).copy(exported.path);
        return null;
      }
      throw MissingPluginException(call.method);
    });
  });
  tearDown(() async {
    DBHelper.inspectorIdForTesting = null;
    fixture.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  Future<void> show(
    WidgetTester tester, {
    String? path,
    bool reference = false,
  }) async {
    await fixture.mount(
      tester,
      FullscreenPhotoViewer(
        photoPaths: [path ?? original.path],
        startIndex: 0,
        photoDetails: [
          {
            ...fixture.provider.capturedPhotos.single,
            'job_id': offlineJob,
            if (reference) 'notes': kSiteLocationReferenceNotes,
          },
        ],
      ),
    );
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save Copy'));
    await fixture.flush(tester);
    await tester.pumpAndSettle();
  }

  fixture.widgetTest(
    'offline Save Copy exports exact bytes without changing evidence or outbox',
    (tester) async {
      final before = await DBHelper.getLocalPhotos(offlineJob);
      final bytes = original.readAsBytesSync();
      await show(tester);
      await save(tester);
      expect(
        find.text('Copy saved. Original inspection evidence is unchanged.'),
        findsOneWidget,
      );
      expect(exported.readAsBytesSync(), bytes);
      expect(original.readAsBytesSync(), bytes);
      expect(await DBHelper.getLocalPhotos(offlineJob), before);
      expect(await fixture.db.query('pending_actions'), isEmpty);
      expect(fixture.remoteWrites, 0);
    },
  );

  fixture.widgetTest(
    'cancelling Save As leaves original and metadata untouched',
    (tester) async {
      cancel = true;
      final before = await DBHelper.getLocalPhotos(offlineJob);
      await show(tester);
      await save(tester);
      expect(copies, 0);
      expect(exported.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
      expect(await DBHelper.getLocalPhotos(offlineJob), before);
      expect(find.textContaining('Copy saved.'), findsNothing);
    },
  );

  fixture.widgetTest(
    'remote-only evidence is honestly unavailable instead of downloading offline',
    (tester) async {
      await show(tester, path: 'https://example.invalid/remote.jpg');
      await save(tester);
      expect(
        find.textContaining('not available on this device'),
        findsOneWidget,
      );
      expect(copies, 0);
      expect(fixture.remoteWrites, 0);
    },
  );

  fixture.widgetTest(
    'destination failure preserves original and permits a retry',
    (tester) async {
      failCopy = true;
      await show(tester);
      await save(tester);
      expect(
        find.textContaining('Check free space and destination access'),
        findsOneWidget,
      );
      expect(original.existsSync(), isTrue);
      expect(find.textContaining('Copy saved.'), findsNothing);
      failCopy = false;
      await save(tester);
      expect(exported.readAsBytesSync(), original.readAsBytesSync());
      expect(discarded, 1);
    },
  );

  fixture.widgetTest(
    'an inspector switch while Save As is open prevents copying',
    (tester) async {
      picker = Completer<bool>();
      await show(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save Copy'));
      await fixture.flush(tester);
      DBHelper.inspectorIdForTesting = 'other-inspector';
      picker!.complete(true);
      await fixture.flush(tester);
      await tester.pumpAndSettle();
      expect(copies, 0);
      expect(discarded, 1);
      expect(exported.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
    },
  );

  fixture.widgetTest(
    'generated reference export preserves bytes and its non-camera identity',
    (tester) async {
      await fixture.db.update(
        'local_photos',
        {'notes': kSiteLocationReferenceNotes},
        where: 'id = ?',
        whereArgs: ['ce04b-photo'],
      );
      await show(tester, reference: true);
      await save(tester);
      expect(exported.readAsBytesSync(), original.readAsBytesSync());
      final row = (await DBHelper.getLocalPhotos(offlineJob)).single;
      expect(row['notes'], kSiteLocationReferenceNotes);
      expect(row['captured_at'], '2026-10-21T01:02:03.000Z');
    },
  );
}
