import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/rosario_boundary_overlay.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.source);
  String? source;
  int reads = 0;

  @override
  Future<ByteData> load(String key) async {
    reads++;
    if (source == null) throw const FormatException('Missing asset');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source!)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final file = File(RosarioBoundaryLoader.assetPath);
  final raw = utf8.decode(file.readAsBytesSync());

  test('bundled asset is byte-identical to authoritative export', () async {
    const hash =
        '0d5e5454de6a8e0f1e6fd8965c74fb8ebbc6ad84db33da01f910644130089baf';
    expect(sha256.convert(file.readAsBytesSync()).toString(), hash);
    final bundled = await rootBundle.load(RosarioBoundaryLoader.assetPath);
    expect(
      sha256
          .convert(
            bundled.buffer.asUint8List(
              bundled.offsetInBytes,
              bundled.lengthInBytes,
            ),
          )
          .toString(),
      hash,
    );
    final metadata = jsonDecode(
      await rootBundle.loadString('assets/maps/rosario_boundary.metadata.json'),
    );
    expect(metadata['authority'], 'MPDO Rosario');
    expect(metadata['source_table'], 'public.rosario_boundary');
    expect(metadata['geometry_policy'], 'raw_unsimplified');
    expect(metadata['dataset_version'], isNull);
    expect(metadata['dataset_issue_date'], isNull);
  });

  test('actual MultiPolygon preserves every coordinate and hole in order', () {
    final json = jsonDecode(raw);
    expect(json['features'], hasLength(1));
    final parts = json['features'][0]['geometry']['coordinates'] as List;
    final polygons = RosarioBoundaryLoader.parse(raw);
    expect(polygons, hasLength(parts.length));
    var vertices = 0;
    for (var p = 0; p < parts.length; p++) {
      final actualRings = [polygons[p].points, ...polygons[p].holePointsList!];
      expect(actualRings, hasLength(parts[p].length));
      // Outline only, so the border never hides the parcel/device markers.
      expect(polygons[p].color, isNull);
      for (var r = 0; r < actualRings.length; r++) {
        final expected = parts[p][r] as List;
        expect(actualRings[r], hasLength(expected.length));
        for (var v = 0; v < expected.length; v++) {
          expect(actualRings[r][v].longitude, expected[v][0]);
          expect(actualRings[r][v].latitude, expected[v][1]);
          vertices++;
        }
      }
    }
    expect(vertices, 1512);
  });

  test(
    'malformed JSON and unsupported geometry fail closed without throwing',
    () {
      for (final source in [
        '{',
        'null',
        '{}',
        raw.replaceFirst('MultiPolygon', 'Point'),
      ]) {
        expect(RosarioBoundaryLoader.parse(source), isEmpty);
      }
    },
  );

  test(
    'invalid coordinates, empty geometry and unclosed rings fail gracefully',
    () {
      for (final coords in [
        [],
        [
          [[]],
        ],
        [
          [
            [
              [181, 0],
              [1, 0],
              [1, 1],
              [181, 0],
            ],
          ],
        ],
        [
          [
            [
              [1, 0],
              [1, 1],
              [2, 1],
              [2, 0],
            ],
          ],
        ],
      ]) {
        final source = jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {'type': 'MultiPolygon', 'coordinates': coords},
            },
          ],
        });
        expect(RosarioBoundaryLoader.parse(source), isEmpty);
      }
    },
  );

  test(
    'successful parse is shared across concurrent and subsequent loads',
    () async {
      final bundle = _Bundle(raw);
      final loader = RosarioBoundaryLoader(bundle: bundle);
      final results = await Future.wait([loader.load(), loader.load()]);
      expect(results.first, isNotEmpty);
      expect(identical(results.first, results.last), isTrue);
      expect(identical(results.first, await loader.load()), isTrue);
      expect(bundle.reads, 1);
    },
  );

  test('missing asset fails gracefully and next open can retry', () async {
    final bundle = _Bundle(null);
    final loader = RosarioBoundaryLoader(bundle: bundle);
    expect(await loader.load(), isEmpty);
    bundle.source = raw;
    bundle.evict(RosarioBoundaryLoader.assetPath);
    expect(await loader.load(), isNotEmpty);
    expect(bundle.reads, 2);
  });

  for (final source in [
    raw,
    null,
    '{',
    raw.replaceFirst('MultiPolygon', 'Point'),
  ]) {
    testWidgets(
      'local outline/route/markers remain independent: ${source == raw
          ? 'valid'
          : source == null
          ? 'missing'
          : source == '{'
          ? 'malformed'
          : 'unsupported'}',
      (tester) async {
        const route = [
          LatLng(13.6, 121.1),
          LatLng(13.8, 121.3),
          LatLng(14, 121.5),
        ];
        final loader = RosarioBoundaryLoader(bundle: _Bundle(source));
        // Asset reads are real async I/O, so they must complete outside the
        // fake-async pump zone; the loader is primed before it is mounted.
        await tester.runAsync(() => loader.load());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(13.8, 121.3),
                  initialZoom: 10,
                ),
                children: [
                  RosarioBoundaryOverlay(loader: loader),
                  PolylineLayer(
                    polylines: [Polyline(points: route, strokeWidth: 4)],
                  ),
                  const MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(13.8, 121.3),
                        child: Icon(Icons.place),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        // The boundary load is asynchronous, so pump until the FutureBuilder
        // resolves instead of relying on pumpAndSettle, which can settle
        // before the asset future completes.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        // PolygonLayer<R extends Object> cannot be matched with a bare `is
        // PolygonLayer` (that resolves to the invalid PolygonLayer<dynamic>),
        // so match the concrete type argument flutter_map constructs.
        final polygons = find.byWidgetPredicate(
          (w) => w is PolygonLayer<Object>,
        );
        expect(polygons, source == raw ? findsOneWidget : findsNothing);
        if (source == raw) {
          expect(
            tester
                .widget<PolygonLayer<Object>>(polygons)
                .simplificationTolerance,
            0,
          );
        }
        expect(
          tester
              .widget<PolylineLayer>(find.byType(PolylineLayer))
              .polylines
              .single
              .points,
          route,
        );
        expect(find.byIcon(Icons.place), findsOneWidget);
      },
    );
  }
}
