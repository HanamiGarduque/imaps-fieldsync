import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/insight_theme.dart';

/// Local reference geometry only; never an input to GPS, routing, or progress.
class RosarioBoundaryLoader {
  RosarioBoundaryLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/maps/rosario_boundary.geojson';
  static final shared = RosarioBoundaryLoader();
  final AssetBundle _bundle;
  List<Polygon>? _polygons;
  Future<List<Polygon>>? _pending;

  Future<List<Polygon>> load() {
    if (_polygons != null) return Future.value(_polygons);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<List<Polygon>> _load() async {
    try {
      final polygons = parse(await _bundle.loadString(assetPath));
      // Failed loads are retryable on the next screen open, not cached forever.
      if (polygons.isNotEmpty) _polygons = polygons;
      return polygons;
    } catch (_) {
      debugPrint('Rosario boundary unavailable: bundled asset could not load.');
      return const [];
    }
  }

  static List<Polygon> parse(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (json['type'] != 'FeatureCollection') {
        throw const FormatException('Expected FeatureCollection');
      }
      final features = json['features'] as List;
      if (features.isEmpty) {
        throw const FormatException('Empty boundary');
      }
      final polygons = <Polygon>[];
      for (final feature in features) {
        if (feature['type'] != 'Feature') {
          throw const FormatException('Expected Feature');
        }
        final geometry = feature['geometry'] as Map<String, dynamic>;
        if (geometry['type'] != 'MultiPolygon') {
          throw const FormatException('Expected MultiPolygon');
        }
        final parts = geometry['coordinates'] as List;
        if (parts.isEmpty) {
          throw const FormatException('Empty MultiPolygon');
        }
        for (final part in parts) {
          final rings = (part as List).map(_parseRing).toList();
          if (rings.isEmpty) {
            throw const FormatException('Empty polygon');
          }
          polygons.add(
            Polygon(
              points: rings.first,
              holePointsList: List.unmodifiable(rings.skip(1)),
              // Outline only: a null colour disables filling so the parcel and
              // device markers stay readable inside the municipal border.
              color: null,
              borderColor: InsightTheme.blueInk.withValues(alpha: 0.75),
              borderStrokeWidth: 2,
            ),
          );
        }
      }
      return List.unmodifiable(polygons);
    } catch (_) {
      debugPrint('Rosario boundary unavailable: invalid bundled geometry.');
      return const [];
    }
  }

  static List<LatLng> _parseRing(dynamic value) {
    final ring = value as List;
    if (ring.length < 4) {
      throw const FormatException('Invalid ring');
    }
    final points = ring.map((coordinate) {
      final pair = coordinate as List;
      if (pair.length != 2) {
        throw const FormatException('Expected XY coordinate');
      }
      final longitude = (pair[0] as num).toDouble();
      final latitude = (pair[1] as num).toDouble();
      if (!longitude.isFinite ||
          !latitude.isFinite ||
          longitude.abs() > 180 ||
          latitude.abs() > 90) {
        throw const FormatException('Invalid WGS84 coordinate');
      }
      return LatLng(latitude, longitude);
    }).toList();
    if (points.first != points.last) {
      throw const FormatException('Unclosed ring');
    }
    return List.unmodifiable(points);
  }
}

class RosarioBoundaryOverlay extends StatefulWidget {
  const RosarioBoundaryOverlay({super.key, this.loader});

  final RosarioBoundaryLoader? loader;

  @override
  State<RosarioBoundaryOverlay> createState() => _RosarioBoundaryOverlayState();
}

class _RosarioBoundaryOverlayState extends State<RosarioBoundaryOverlay> {
  late final Future<List<Polygon>> _boundary;

  @override
  void initState() {
    super.initState();
    _boundary = (widget.loader ?? RosarioBoundaryLoader.shared).load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Polygon>>(
      future: _boundary,
      builder: (context, snapshot) {
        final polygons = snapshot.data;
        if (polygons == null || polygons.isEmpty) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: PolygonLayer(
            polygons: polygons,
            // Preserve the raw export, including holes; no display simplification.
            simplificationTolerance: 0,
          ),
        );
      },
    );
  }
}
