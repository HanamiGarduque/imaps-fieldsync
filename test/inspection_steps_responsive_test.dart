import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/layout/responsive_layout.dart';

/// Inspection Steps 3–6 share the same shape: a fixed header above a
/// scrollable body. On a tablet that body stretched full-bleed, so this now
/// wraps it in the shared `ConstrainedContent`.
///
/// The step bodies are long forms/checklists that do not expose a spatial
/// visual worth splitting off, so the correct adaptive behaviour is a bounded,
/// centred, scrollable column — portrait keeps its accepted full-width card,
/// landscape and tablet stop the content row running edge to edge.

void setViewport(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(top: 42, bottom: 42);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

const matrix = <Size>[
  Size(390, 844),
  Size(844, 390),
  Size(430, 932),
  Size(932, 430),
  Size(800, 1280),
  Size(1280, 800),
];

/// Faithful composition for a long step body: the shared bounded wrapper
/// around a real scrolling list of the right row height.
Widget stepBody() => Expanded(
      child: ConstrainedContent(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 40,
          itemBuilder: (_, _) => Container(
            height: 56,
            margin: const EdgeInsets.only(bottom: 4),
            color: Colors.white,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

void main() {
  group('S1. every wrapped step body fits and stays bounded', () {
    for (final size in matrix) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        setViewport(tester, size);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 138), // the shared step header chrome
                  stepBody(),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the content column is capped on a tablet, not edge-to-edge',
        (tester) async {
      setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 138),
                stepBody(),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      final list = tester.getRect(find.byType(ListView));
      expect(list.width, lessThanOrEqualTo(InsightBreakpoints.contentMaxWidth),
          reason: 'a long checklist row must not span 1280px');
      expect(list.width, greaterThan(300),
          reason: 'the column keeps a usable width');
    });

    testWidgets('portrait is under the cap, so it renders full-width',
        (tester) async {
      setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 138),
                stepBody(),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.getRect(find.byType(ListView)).width, 390);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1.3x text scale does not overflow on any viewport',
        (tester) async {
      for (final size in matrix) {
        setViewport(tester, size, textScale: 1.3);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 138),
                  stepBody(),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('S2. production steps 3–6 use the shared wrapper', () {
    test('photo grid, checklist, findings and review are all bounded', () {
      for (final f in [
        'lib/modules/inspection/screens/capture_photo_screen.dart',
        'lib/modules/inspection/screens/inspection_checklist_screen.dart',
        'lib/modules/inspection/screens/field_findings_screen.dart',
        'lib/modules/inspection/screens/review_submit_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, contains('ConstrainedContent'), reason: f);
        expect(src, contains('responsive_layout.dart'), reason: f);
      }
    });

    test('no step screen reads orientation directly', () {
      for (final f in [
        'lib/modules/inspection/screens/capture_photo_screen.dart',
        'lib/modules/inspection/screens/inspection_checklist_screen.dart',
        'lib/modules/inspection/screens/field_findings_screen.dart',
        'lib/modules/inspection/screens/review_submit_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, isNot(contains('.orientation')), reason: f);
      }
    });

    test('steps 1 and 2 use the shared split primitive', () {
      expect(
        File('lib/modules/inspection/screens/gps_verification_screen.dart')
            .readAsStringSync(),
        contains('HeaderSplitBody'),
      );
      expect(
        File('lib/modules/inspection/screens/compass_preview_screen.dart')
            .readAsStringSync(),
        contains('HeaderSplitBody'),
      );
      // Step 1 is spatial-primary: the map fills the canvas and the detail card
      // is handed to the shared map panel.
      final map = File('lib/modules/inspection/screens/site_map_screen.dart')
          .readAsStringSync();
      expect(map, contains('MapDetailPanel'));
    });

    test('step semantics are untouched', () {
      // Step completion markers and copy survive verbatim — a layout pass must
      // not move a workflow rule.
      expect(
        File('lib/modules/inspection/screens/site_map_screen.dart')
            .readAsStringSync(),
        contains('markStepComplete(1)'),
      );
      expect(
        File('lib/modules/inspection/screens/capture_photo_screen.dart')
            .readAsStringSync(),
        contains('saveStepPhotos'),
      );
      expect(
        File('lib/modules/inspection/screens/inspection_checklist_screen.dart')
            .readAsStringSync(),
        contains('_doneCount of'),
      );
      expect(
        File('lib/modules/inspection/screens/field_findings_screen.dart')
            .readAsStringSync(),
        contains('OBSERVATIONS'),
      );
      expect(
        File('lib/modules/inspection/screens/review_submit_screen.dart')
            .readAsStringSync(),
        contains('_selectedStatus'),
      );
    });
  });
}
