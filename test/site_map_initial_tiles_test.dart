import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/site_map_screen.dart';

final _image = MemoryImage(File('assets/icon/app_icon.png').readAsBytesSync());

class _Tiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _image;
}

void main() {
  testWidgets('initial fitted map loads visible tiles without a gesture', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final ready = Completer<void>();
      final stream = _image.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (_, _) => ready.complete(),
        onError: ready.completeError,
      );
      stream.addListener(listener);
      await ready.future;
      stream.removeListener(listener);
    });
    for (final device in [
      const LatLng(14.04, 121.12),
      const LatLng(13.84, 121.2),
      null,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final controller = MapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              mapController: controller,
              options: siteMapOptions(
                parcel: const LatLng(13.84, 121.2),
                device: device,
              ),
              children: [TileLayer(tileProvider: _Tiles())],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.camera.zoom.isFinite, isTrue);
      expect(controller.camera.zoom, lessThanOrEqualTo(17));
      expect(
        controller.camera.visibleBounds.contains(const LatLng(13.84, 121.2)),
        isTrue,
      );
      if (device != null) {
        expect(
          controller.camera.visibleBounds.contains(device),
          isTrue,
          reason: 'initial tiles must belong to a camera that shows both pins',
        );
      }
      final visibleImages = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((image) => image.image != null);
      expect(
        visibleImages,
        isNotEmpty,
        reason:
            'both distant and coincident pins must show tiles on initial open',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
