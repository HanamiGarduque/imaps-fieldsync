import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/widgets/fieldsync_entrance_animation.dart';

/// The approved splash entrance (`FieldSync_Inspector_Entrance_v2.mp4`,
/// implemented natively) must:
///  - complete exactly once, only after its full duration,
///  - land immediately on the final artwork under reduced motion,
///  - and settle on the official kit artwork, verified against the shipped
///    `fieldsync-logo-white.svg` itself rather than any redraw.
///
/// Set `IMAPS_ENTRANCE_CAPTURE_DIR` to also export phone-frame PNGs of the
/// entrance for preview/evidence (same env-gated harness pattern as the other
/// approved capture suites).
void main() {
  Widget host(Widget child, {bool reduced = false, Key? captureKey}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: Scaffold(
            backgroundColor: const Color(0xFF1D4ED8),
            body: Align(
              alignment: Alignment.topLeft,
              child: captureKey == null
                  ? child
                  : RepaintBoundary(key: captureKey, child: child),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> snapshot(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late ByteData data;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return data.buffer.asUint8List();
  }

  testWidgets('calls onCompleted exactly once, after the full entrance', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(FieldSyncEntranceAnimation(width: 280, onCompleted: () => calls++)),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 5000));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(calls, 0, reason: '6.0s is still mid-entrance');
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1, reason: 'the entrance reports completion once');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion lands on the final artwork immediately', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        FieldSyncEntranceAnimation(width: 280, onCompleted: () => calls++),
        reduced: true,
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settled frame is the official artwork, pixel for pixel', (
    tester,
  ) async {
    const width = 280.0;
    final settledKey = GlobalKey();
    await tester.pumpWidget(
      host(
        FieldSyncEntranceAnimation(width: width, onCompleted: () {}),
        captureKey: settledKey,
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    final settled = await snapshot(tester, settledKey);

    final assetKey = GlobalKey();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: width,
          height: width * 1115 / 887,
          child: SvgPicture.asset(
            'assets/branding/fieldsync-logo-white.svg',
            fit: BoxFit.fill,
          ),
        ),
        captureKey: assetKey,
      ),
    );
    await tester.pump();
    await tester.pump();
    final asset = await snapshot(tester, assetKey);

    expect(
      asset.length,
      settled.length,
      reason: 'both captures render the same box at the same ratio',
    );
    var bad = 0;
    var total = 0;
    var sum = 0;
    for (var i = 0; i < settled.length; i += 4) {
      final d = math.max(
        math.max(
          (settled[i] - asset[i]).abs(),
          (settled[i + 1] - asset[i + 1]).abs(),
        ),
        math.max(
          (settled[i + 2] - asset[i + 2]).abs(),
          (settled[i + 3] - asset[i + 3]).abs(),
        ),
      );
      if (d > 48) bad++;
      sum += d;
      total++;
    }
    final badFraction = bad / total;
    final mean = sum / total;
    // ignore: avoid_print
    print(
      'entrance-vs-asset: mean=$mean badFraction=$badFraction '
      '($bad/$total pixels)',
    );
    expect(
      badFraction,
      lessThan(0.005),
      reason: 'the settled frame must be the official artwork, not a redraw',
    );
    expect(
      mean,
      lessThan(0.5),
      reason: 'only anti-aliasing noise may differ from the artwork',
    );
  });

  testWidgets('paints mid-flight and settled at phone and landscape sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          FieldSyncEntranceAnimation(
            width: math.min(280.8, size.width * 0.72),
            onCompleted: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 3300));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('captures entrance frames for preview', (tester) async {
    final folder = Platform.environment['IMAPS_ENTRANCE_CAPTURE_DIR'];
    if (folder == null) return;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1D4ED8),
          body: RepaintBoundary(
            key: key,
            child: const Padding(
              padding: EdgeInsets.all(32),
              child: Align(
                alignment: Alignment.topLeft,
                child: FieldSyncEntranceAnimation(
                  width: 280.8, // matches the splash: 0.72 * 390, capped at 360
                  onCompleted: _noop,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Directory(folder).createSync(recursive: true);
    const times = <double>[
      0,
      0.25,
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      1.65,
      1.8,
      2.0,
      2.15,
      2.3,
      2.45,
      2.6,
      2.8,
      3.0,
      3.2,
      3.4,
      3.6,
      3.9,
      4.2,
      4.5,
      4.8,
      5.1,
      5.4,
      6.2,
    ];
    var now = 0.0;
    for (final ts in times) {
      await tester.pump(Duration(microseconds: ((ts - now) * 1000000).round()));
      now = ts;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$folder/splash_${ts.toStringAsFixed(2).padLeft(5, '0')}s.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
