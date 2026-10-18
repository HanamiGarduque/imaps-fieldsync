import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);

  fixture.widgetTest('Task Overview has a neutral header background, not a blue glow',
      (tester) async {
    await fixture.mount(tester, ParcelDetailScreen(task: offlineTask));
    await fixture.flush(tester);
    expect(find.text('Task Overview'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('06'), findsOneWidget);
    await fixture.capture(tester, 'overview-neutral');
    final pixel = (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(fixture.captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      const i = 4 * (70 * 390 + 340); // Empty header, clear of controls/debug banner.
      return [for (var channel = 0; channel < 3; channel++) data.getUint8(i + channel)];
    }))!;
    final expected = [InsightTheme.bg.r, InsightTheme.bg.g, InsightTheme.bg.b];
    for (var channel = 0; channel < 3; channel++) {
      expect(pixel[channel], closeTo(expected[channel] * 255, 2), reason: '$pixel');
    }
    expect(tester.takeException(), isNull);
  });
}
