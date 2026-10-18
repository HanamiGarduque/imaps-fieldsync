import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imaps_fieldsync/core/widgets/fieldsync_entrance_animation.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_logo_geometry.dart';

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

  testWidgets('camera snapshot at the 2.15s handoff seam matches the painter', (
    tester,
  ) async {
    expect(FieldSyncEntranceTimeline.handoffSeconds, 2.15);
    const t = 2.15;
    final camera = FieldSyncEntrancePainter.cameraAt(t);

    // Re-derived from the approved choreography constants and Flutter's own
    // curves — deliberately not read back from the painter, so a change on
    // either side breaks this pin.
    double win(double v, double a, double b) => ((v - a) / (b - a)).clamp(
      0.0,
      1.0,
    );
    final settleW = win(t, 4.90, 5.15);
    final expectedZoom =
        (8.0 + (1.0 - 8.0) * Curves.easeInOutQuart.transform(win(t, 2.02, 2.78))) *
        (1.008 + (1.0 - 1.008) * Curves.easeInOutSine.transform(settleW));
    final expectedAnchorT = Curves.easeInOutSine.transform(win(t, 2.10, 2.95));
    final metric = FieldSyncLogoGeometry.route.computeMetrics().first;
    final routeEnd = metric.getTangentForOffset(metric.length)!.position;
    final lockupCentre = Offset(
      FieldSyncLogoGeometry.viewBoxLeft +
          FieldSyncLogoGeometry.viewBoxWidth / 2,
      FieldSyncLogoGeometry.viewBoxTop +
          FieldSyncLogoGeometry.viewBoxHeight / 2,
    );
    final expectedCentre = Offset.lerp(routeEnd, lockupCentre, expectedAnchorT)!;

    expect(camera.zoom, closeTo(expectedZoom, 1e-9));
    expect(camera.anchorT, closeTo(expectedAnchorT, 1e-9));
    expect((camera.centre - expectedCentre).distance, lessThan(1e-9));
    // Seam sanity: still at the arrival zoom, framed on the route's end (the
    // site marker), only just beginning to recentre.
    expect(camera.zoom, inInclusiveRange(7.5, 8.2));
    expect(camera.anchorT, inInclusiveRange(0.0, 0.05));
    // The camera is valid outside the timeline too, held at the boundaries.
    expect(
      FieldSyncEntrancePainter.cameraAt(-5).zoom,
      closeTo(2.2 * 1.008, 1e-9),
    );
    expect(FieldSyncEntrancePainter.cameraAt(60).zoom, closeTo(1.0, 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('external driver supplies exact time, clamps ends, and never '
      'restarts the entrance', (tester) async {
    final driver = _TestSeconds(2.15);
    var calls = 0;
    await tester.pumpWidget(
      host(
        FieldSyncEntranceAnimation(
          width: 280,
          onCompleted: () => calls++,
          driver: driver,
        ),
      ),
    );
    await tester.pump();
    expect(
      _painter(tester).animation.value,
      closeTo(2.15 / FieldSyncEntranceTimeline.total, 1e-9),
      reason: 'mounting mid-timeline paints exactly the host second',
    );
    // Real time passes with the host clock frozen: nothing may advance.
    await tester.pump(const Duration(seconds: 5));
    expect(
      _painter(tester).animation.value,
      closeTo(2.15 / FieldSyncEntranceTimeline.total, 1e-9),
      reason: 'in driven mode the widget owns no clock',
    );
    expect(calls, 0);
    driver.value = 6.2;
    await tester.pump();
    expect(_painter(tester).animation.value, 1.0);
    expect(calls, 1, reason: 'completion fires when the host clock ends');
    driver.value = 99; // overrun clamps
    await tester.pump();
    expect(_painter(tester).animation.value, 1.0);
    driver.value = -3; // underrun clamps
    await tester.pump();
    expect(_painter(tester).animation.value, 0.0);
    expect(calls, 1, reason: 'the entrance reports completion once');
    expect(tester.takeException(), isNull);
  });

  testWidgets('startSeconds mounts at the seam and plays the rest 1:1', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        FieldSyncEntranceAnimation(
          width: 280,
          onCompleted: () => calls++,
          startSeconds: FieldSyncEntranceTimeline.handoffSeconds,
        ),
      ),
    );
    await tester.pump();
    expect(
      _painter(tester).animation.value,
      closeTo(2.15 / FieldSyncEntranceTimeline.total, 1e-9),
    );
    await tester.pump(const Duration(milliseconds: 4040)); // 4.05s span − 10ms
    expect(calls, 0, reason: 'the remaining span runs at the original pace');
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driven + reduced motion settles immediately and stays settled', (
    tester,
  ) async {
    final driver = _TestSeconds(0);
    var calls = 0;
    await tester.pumpWidget(
      host(
        FieldSyncEntranceAnimation(
          width: 280,
          onCompleted: () => calls++,
          driver: driver,
        ),
        reduced: true,
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(_painter(tester).animation.value, 1.0);
    driver.value = 3;
    await tester.pump();
    expect(
      _painter(tester).animation.value,
      1.0,
      reason: 'reduced motion shows the finished artwork, host clock or not',
    );
    expect(tester.takeException(), isNull);
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

/// The entrance's own painter, wherever it sits in the host tree.
FieldSyncEntrancePainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(FieldSyncEntranceAnimation),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((customPaint) => customPaint.painter)
    .whereType<FieldSyncEntrancePainter>()
    .single;

/// A minimal host clock for driven-mode tests: an [Animation<double>] in
/// entrance-local seconds whose value the test sets directly.
class _TestSeconds extends Animation<double> {
  _TestSeconds(this._value);

  double _value;
  final List<VoidCallback> _listeners = <VoidCallback>[];

  @override
  double get value => _value;

  set value(double next) {
    if (next == _value) return;
    _value = next;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}

  @override
  AnimationStatus get status => value >= FieldSyncEntranceTimeline.total
      ? AnimationStatus.completed
      : value <= 0.0
      ? AnimationStatus.dismissed
      : AnimationStatus.forward;
}
