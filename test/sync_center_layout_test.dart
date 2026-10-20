import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  var online = true;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final sdkFonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final sdkBytes = ByteData.sublistView(
      sdkFonts
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset},
        ];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (!asset.endsWith('.ttf')) return null;
      final folder = Platform.environment['IMAPS_LAYOUT_FONT_DIR'];
      return folder == null
          ? sdkBytes
          : ByteData.sublistView(
              File('$folder/${asset.split('-').first}.ttf').readAsBytesSync(),
            );
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => [online ? 'wifi' : 'none'],
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final statement in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(statement.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = 'sync-inspector';
  });

  setUp(() async {
    online = true;
    SharedPreferences.setMockInitialValues({});
    SyncOutboxService.progress.value = null;
    await db.delete('pending_actions');
  });

  tearDownAll(() async {
    DBHelper.inspectorIdForTesting = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  Future<void> openScreen(WidgetTester tester, Size size, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      SyncOutboxService.progress.value = null;
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: UpdatesScreen(
          profile: UserProfile(
            id: 'sync-inspector',
            fullName: 'Maria Dela Cruz',
            role: 'inspector',
          ),
        ),
      ),
    );
    // The screen's periodic poll is left real; stop before its next tick and
    // unmount at the end so timers/listeners are verified to clean up normally.
    for (
      var frame = 0;
      frame < 50 && find.text('Sync Center').evaluate().isEmpty;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.text('Sync Center'),
      findsOneWidget,
      reason: 'The real SQLite-backed screen finished loading.',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(640, 360),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Sync header and cards stay readable at $size with $scale text',
        (tester) async {
          await tester.runAsync(() async {
            for (var index = 0; index < 12; index++) {
              await db.insert('pending_actions', {
                'id': 'queued-$index',
                'inspector_id': 'sync-inspector',
                'job_id': 'job-1',
                'type': 'checklist_update',
                'status': 'pending',
                'payload': '{}',
                'created_at': '2026-10-08T00:00:00Z',
                'updated_at': '2026-10-08T00:00:00Z',
              });
            }
          });
          await openScreen(tester, size, scale);
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason:
                'Queued work should show a waiting cue, not an active upload spinner.',
          );
          expect(tester.takeException(), isNull);
          final header = find.byKey(const ValueKey('sync_header'));
          expect(header, findsOneWidget);
          final bounds = tester.getRect(header);
          expect(find.text('Sync Center'), findsOneWidget);
          expect(find.text('Online'), findsOneWidget);
          expect(find.text('Last sync: Never'), findsOneWidget);
          final help = find.ancestor(
            of: find.byTooltip('About Sync Center'),
            matching: find.byType(IconButton),
          );
          expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
          final action = find.ancestor(
            of: find.text('Sync 12 Queued'),
            matching: find.byType(FilledButton),
          );
          expect(action, findsOneWidget);
          expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text('Sync 12 Queued'),
          );
          final glyphs = paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 14),
          );
          expect(
            glyphs.last.right,
            lessThanOrEqualTo(paragraph.size.width + 0.1),
            reason:
                'The queue count/action must fit without shrinking or clipping.',
          );
          await tester.drag(
            find.byKey(const ValueKey('sync_body')),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(header),
            bounds,
            reason: 'The complete header panel stays pinned.',
          );
          final bodyScroll = find.descendant(
            of: find.byKey(const ValueKey('sync_body')),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.text('Offline Storage Cache'),
            250,
            scrollable: bodyScroll,
            maxScrolls: 30,
          );
          await tester.pumpAndSettle();
          expect(find.text('Cached Jobs'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'Offline all-synced status is readable and exposes a disabled action',
    (tester) async {
      online = false;
      final semantics = tester.ensureSemantics();
      try {
        await openScreen(tester, const Size(360, 800), 1);
        expect(find.text('Offline'), findsOneWidget);
        final action = find.ancestor(
          of: find.text('No queued updates'),
          matching: find.byType(FilledButton),
        );
        expect(action, findsOneWidget);
        expect(tester.widget<FilledButton>(action).onPressed, isNull);
        expect(
          tester.getSemantics(action),
          matchesSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            label: 'No queued updates',
          ),
        );
        await tester.tap(find.byTooltip('About Sync Center'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'offline queued update is truthfully described as waiting for connection',
    (tester) async {
      online = false;
      await tester.runAsync(() async {
        await db.insert('pending_actions', {
          'id': 'offline-queued',
          'inspector_id': 'sync-inspector',
          'job_id': 'job-1',
          'type': 'current_step_update',
          'status': 'pending',
          'payload': '{"currentStep":2}',
          'created_at': '2026-10-08T00:00:00Z',
          'updated_at': '2026-10-08T00:00:00Z',
        });
      });
      await openScreen(tester, const Size(360, 800), 1);
      final bodyScroll = find.descendant(
        of: find.byKey(const ValueKey('sync_body')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Saved on device — waiting for connection'),
        250,
        scrollable: bodyScroll,
        maxScrolls: 30,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Queued'), findsOneWidget);
      expect(
        find.text('Saved on device — waiting for connection'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Live upload progress wraps and disables sync immediately in short landscape',
    (tester) async {
      await openScreen(tester, const Size(640, 360), 2);
      SyncOutboxService.progress.value = const SyncProgress(
        actionIndex: 2,
        actionTotal: 12,
        actionType: 'submit_inspection',
        photoIndex: 3,
        photoTotal: 120,
      );
      await tester.pump(const Duration(milliseconds: 80));
      final progress = find.text(
        'Submitting inspection (2 of 12) — Uploading photo 3 of 120',
      );
      expect(progress, findsOneWidget);
      expect(tester.widget<Text>(progress).maxLines, isNull);
      final action = find.ancestor(
        of: find.text('Syncing...'),
        matching: find.byType(FilledButton),
      );
      expect(action, findsOneWidget);
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      SyncOutboxService.progress.value = null;
    },
  );

  testWidgets('Selective sync keeps queued sibling updates waiting', (
    tester,
  ) async {
    final upload = Completer<Map<String, dynamic>?>();
    var readStarted = false;
    SyncOutboxService.recoveryReadForTesting = (_) {
      readStarted = true;
      return upload.future;
    };
    addTearDown(() async {
      if (!upload.isCompleted) {
        upload.complete({'status': 'completed', 'current_step': 6});
      }
      // The drain continuation lives in this test's fake zone: it only
      // resumes when the zone's microtasks are flushed, so alternate fake
      // and real advances until the service reports itself settled.
      for (
        var frame = 0;
        frame < 100 && SyncOutboxService.isDraining;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      SyncOutboxService.recoveryReadForTesting = null;
    });
    await tester.runAsync(() async {
      for (var step = 1; step <= 2; step++) {
        await db.insert('pending_actions', {
          'id': 'selective-$step',
          'inspector_id': 'sync-inspector',
          'job_id': 'job-1',
          'type': 'current_step_update',
          'status': 'pending',
          'payload': '{"currentStep":$step}',
          'created_at': '2026-10-08T00:00:0${step}Z',
          'updated_at': '2026-10-08T00:00:0${step}Z',
        });
      }
    });
    await openScreen(tester, const Size(360, 800), 1);
    await tester.scrollUntilVisible(
      find.text('Sync Inspection (2)'),
      150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('sync_body')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Sync Inspection (2)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await tester.tap(find.text('Sync Inspection (2)'));
      for (var frame = 0; frame < 100 && !readStarted; frame++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(
      readStarted,
      isTrue,
      reason:
          'The real drain claimed the first update before inspecting its waiting sibling.',
    );
    await tester.runAsync(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 400));
    // This harness reports connectivity, so the queued sibling says it is
    // waiting to send — never an uploaded/synced claim, and never a spinner.
    expect(
      find.text('Saved on device — waiting to send'),
      findsOneWidget,
      reason:
          'Only the claimed action uploads; the next update remains queued.',
    );
    expect(
      find.text('Syncing — sending to FieldSync-Supabase'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a queued final submission is presented as waiting, never accepted',
    (tester) async {
      await tester.runAsync(() async {
        await db.insert('pending_actions', {
          'id': 'submit-queued',
          'inspector_id': 'sync-inspector',
          'job_id': 'job-1',
          'type': 'submit_inspection',
          'status': 'pending',
          'payload': jsonEncode({
            'findings': 'Fixture findings',
            'photosData': [
              {'photoPath': 'C:/isolated/fixture-photo.png'},
            ],
          }),
          'created_at': '2026-10-08T00:00:00Z',
          'updated_at': '2026-10-08T00:00:00Z',
        });
      });
      await openScreen(tester, const Size(360, 800), 1);
      // The screen refresh is async: wait until this case's queue renders
      // before asserting so the labels below are the settled ones.
      for (
        var frame = 0;
        frame < 60 && find.text('Sync 1 Queued').evaluate().isEmpty;
        frame++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The queue counts it and offers one job-scoped sync action.
      final action = find.ancestor(
        of: find.text('Sync 1 Queued'),
        matching: find.byType(FilledButton),
      );
      expect(action, findsOneWidget);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      expect(find.text('No queued updates'), findsNothing);
      expect(find.text('Completed Audit Log'), findsNothing);
      final bodyScroll = find.descendant(
        of: find.byKey(const ValueKey('sync_body')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Full Submission — 1 photo(s) + Findings'),
        250,
        scrollable: bodyScroll,
        maxScrolls: 30,
      );
      await tester.pump(const Duration(milliseconds: 400));
      // Saved on device, waiting to send — never an upload spinner or a
      // synced/uploaded claim. The offline wording is pinned by the dedicated
      // offline test above.
      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Saved on device — waiting to send'), findsOneWidget);
      expect(find.text('Final submission'), findsOneWidget);
      expect(find.text('Sync Inspection (1)'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a failed final submission reports truthful failure without acceptance',
    (tester) async {
      await tester.runAsync(() async {
        await db.insert('pending_actions', {
          'id': 'submit-failed',
          'inspector_id': 'sync-inspector',
          'job_id': 'job-1',
          'type': 'submit_inspection',
          'status': 'failed',
          'retry_count': 2,
          'payload': jsonEncode({
            'findings': 'Fixture findings',
            'photosData': [],
          }),
          'last_error': 'Isolated transport failure',
          'created_at': '2026-10-08T00:00:00Z',
          'updated_at': '2026-10-08T00:00:00Z',
        });
      });
      await openScreen(tester, const Size(360, 800), 1);
      expect(find.text('No queued updates'), findsNothing);
      final bodyScroll = find.descendant(
        of: find.byKey(const ValueKey('sync_body')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Retry waiting — saved on device'),
        250,
        scrollable: bodyScroll,
        maxScrolls: 30,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Retry waiting — saved on device'), findsOneWidget);
      expect(find.byIcon(Icons.error_rounded), findsWidgets);
      expect(
        find.text('Full Submission — 0 photo(s) + Findings'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
