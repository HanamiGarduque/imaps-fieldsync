import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import 'geotag_service.dart';

/// Deterministic, offline Site Location Reference card.
///
/// It draws only labelled points: the verified Step 2 inspector position and
/// the recorded parcel reference point. No basemap, road, tile, accuracy ring
/// or parcel boundary is invented, and the card says so.
const int kSiteLocationReferenceWidth = 1080;
const int kSiteLocationReferenceHeight = 1350;

const String kSiteLocationReferenceTitle = 'SITE LOCATION REFERENCE';
const String kSiteLocationReferenceDisclaimer =
    'Location reference only — Not a surveyed parcel boundary.';
const String kSiteLocationReferenceNotes =
    'SITE LOCATION REFERENCE — System-generated location reference showing the '
    'verified inspector GPS point relative to the recorded parcel point. '
    'Not a surveyed cadastral boundary.';

const String _referenceFilePrefix = 'inspection_site_location_reference';

bool isLocationReferencePhoto(Map<String, dynamic> photo) {
  if (photo['isLocationReference'] == true) return true;
  final notes = (photo['notes'] as String?)?.trim() ?? '';
  return notes.startsWith(kSiteLocationReferenceTitle);
}

class SiteLocationReferenceService {
  static final Uuid _uuid = const Uuid();

  /// Stable per job/round file name. A retry, reopen or app restart writes the
  /// same file, so the deterministic uploader reuses one storage object + row.
  static String fileName(String jobId, int? round) {
    final safeJob = jobId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${_referenceFilePrefix}_${safeJob}_r${round ?? 0}.jpg';
  }

  static String photoId(String jobId, int? round) => _uuid.v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
    'site-location-reference:$jobId:${round ?? 0}',
  );

  /// Renders the reference from already-verified data. Pure local drawing:
  /// no network, tiles, geocoding, accuracy estimate or boundary inference.
  static Future<Uint8List> render({
    required String jobId,
    required int? round,
    required String applicant,
    required String? address,
    required double verifiedLatitude,
    required double verifiedLongitude,
    required DateTime verifiedAt,
    required double? verifiedAccuracyMeters,
    required double parcelLatitude,
    required double parcelLongitude,
    required DateTime generatedAt,
  }) async {
    const width = kSiteLocationReferenceWidth;
    const height = kSiteLocationReferenceHeight;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFF4F6FA),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), 200),
      ui.Paint()..color = const ui.Color(0xFF0B1220),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 200, width.toDouble(), 6),
      ui.Paint()..color = const ui.Color(0xFF2563EB),
    );

    _paintText(
      canvas,
      kSiteLocationReferenceTitle,
      x: 48,
      y: 58,
      maxWidth: 984,
      fontSize: 40,
      weight: ui.FontWeight.w800,
      color: const ui.Color(0xFFFFFFFF),
      letterSpacing: 0.6,
    );
    _paintText(
      canvas,
      'SYSTEM-GENERATED · NOT A CAMERA PHOTO',
      x: 48,
      y: 128,
      maxWidth: 984,
      fontSize: 22,
      weight: ui.FontWeight.w600,
      color: const ui.Color(0xFF93C5FD),
      letterSpacing: 1.2,
    );

    _paintText(
      canvas,
      'Applicant: ${applicant.trim().isEmpty ? 'Not on file' : applicant.trim()}',
      x: 48,
      y: 232,
      maxWidth: 984,
      fontSize: 26,
      weight: ui.FontWeight.w600,
    );
    _paintText(
      canvas,
      'Address: ${(address ?? '').trim().isEmpty ? 'Address not on file' : address!.trim()}',
      x: 48,
      y: 272,
      maxWidth: 984,
      fontSize: 22,
      color: const ui.Color(0xFF475569),
      maxLines: 2,
    );

    const diagramLeft = 48.0;
    const diagramTop = 340.0;
    const diagramWidth = 984.0;
    const diagramHeight = 700.0;
    final diagram = ui.Rect.fromLTWH(
      diagramLeft,
      diagramTop,
      diagramWidth,
      diagramHeight,
    );
    final diagramFill = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(diagram, const ui.Radius.circular(24)),
      diagramFill,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(diagram, const ui.Radius.circular(24)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const ui.Color(0xFFCBD5E1),
    );

    // Neutral reference grid — explicitly not a road/parcel/street map.
    final gridPaint = ui.Paint()
      ..color = const ui.Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var x = diagramLeft + 56; x < diagram.right - 20; x += 64) {
      canvas.drawLine(
        ui.Offset(x, diagramTop + 20),
        ui.Offset(x, diagram.bottom - 20),
        gridPaint,
      );
    }
    for (var y = diagramTop + 56; y < diagram.bottom - 20; y += 64) {
      canvas.drawLine(
        ui.Offset(diagramLeft + 20, y),
        ui.Offset(diagram.right - 20, y),
        gridPaint,
      );
    }

    _paintNorthArrow(canvas, diagram.right - 64, diagramTop + 40);

    // Reserve the legend separately; both markers stay inset in the plot.
    final plot = ui.Rect.fromLTRB(
      diagram.left + 64,
      diagram.top + 64,
      diagram.right - 64,
      diagram.bottom - 168,
    );
    final center = plot.center;
    final dxMeters = _eastMeters(
      verifiedLongitude,
      parcelLongitude,
      (verifiedLatitude + parcelLatitude) / 2,
    );
    final dyMeters = _northMeters(verifiedLatitude, parcelLatitude);
    final distanceMeters = math.sqrt(dxMeters * dxMeters + dyMeters * dyMeters);
    final spanMeters = math.max(
      30.0,
      math.max(dxMeters.abs(), dyMeters.abs()) * 1.4,
    );
    final pixelsPerMeter = math.min(plot.width, plot.height) / spanMeters;
    var deviceOffset = ui.Offset(
      dxMeters * pixelsPerMeter / 2,
      -dyMeters * pixelsPerMeter / 2,
    );
    final coincident = distanceMeters < 1;
    if (coincident) {
      deviceOffset = const ui.Offset(-16, -16);
    }

    final devicePoint = center + deviceOffset;
    final parcelPoint = center - deviceOffset;
    _paintDashedLine(canvas, devicePoint, parcelPoint);

    if (!coincident && distanceMeters >= 1) {
      final midpoint = ui.Offset(
        (devicePoint.dx + parcelPoint.dx) / 2,
        (devicePoint.dy + parcelPoint.dy) / 2,
      );
      _paintChip(
        canvas,
        '≈ ${distanceMeters.round()} m apart (straight line)',
        midpoint + const ui.Offset(-150, -58),
        fontSize: 20,
      );
    } else {
      _paintChip(
        canvas,
        'Recorded points <1 m apart (markers separated)',
        center + const ui.Offset(-125, -150),
        fontSize: 20,
      );
    }

    _paintParcelMarker(canvas, parcelPoint);
    _paintDeviceMarker(canvas, devicePoint);

    _paintText(
      canvas,
      'Verified inspector GPS (Step 2)',
      x: diagramLeft + 40,
      y: diagram.bottom - 104,
      maxWidth: 520,
      fontSize: 20,
      weight: ui.FontWeight.w600,
      color: const ui.Color(0xFF1D4ED8),
    );
    _paintText(
      canvas,
      'Recorded parcel reference point',
      x: diagramLeft + 40,
      y: diagram.bottom - 70,
      maxWidth: 520,
      fontSize: 20,
      weight: ui.FontWeight.w600,
      color: const ui.Color(0xFFB45309),
    );
    _paintText(
      canvas,
      'Straight-line distance only; no boundary is implied.',
      x: diagramLeft + 40,
      y: diagram.bottom - 38,
      maxWidth: 640,
      fontSize: 17,
      color: const ui.Color(0xFF64748B),
    );

    var infoY = 1062.0;
    _paintText(
      canvas,
      'Verified GPS: ${verifiedLatitude.toStringAsFixed(6)}, '
      '${verifiedLongitude.toStringAsFixed(6)}'
      '${verifiedAccuracyMeters == null ? '' : '  (±${verifiedAccuracyMeters.round()} m)'}',
      x: 48,
      y: infoY,
      maxWidth: 984,
      fontSize: 22,
      weight: ui.FontWeight.w600,
    );
    infoY += 34;
    _paintText(
      canvas,
      'Verified at: ${GeotagService.localTimestamp(verifiedAt)}',
      x: 48,
      y: infoY,
      maxWidth: 984,
      fontSize: 20,
      color: const ui.Color(0xFF475569),
    );
    infoY += 32;
    _paintText(
      canvas,
      'Parcel point: ${parcelLatitude.toStringAsFixed(6)}, '
      '${parcelLongitude.toStringAsFixed(6)}',
      x: 48,
      y: infoY,
      maxWidth: 984,
      fontSize: 20,
      color: const ui.Color(0xFF475569),
    );

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 1196, width.toDouble(), 118),
      ui.Paint()..color = const ui.Color(0xFFFFF7ED),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 1196, 10, 118),
      ui.Paint()..color = const ui.Color(0xFFB45309),
    );
    _paintText(
      canvas,
      kSiteLocationReferenceDisclaimer,
      x: 40,
      y: 1216,
      maxWidth: 996,
      fontSize: 28,
      weight: ui.FontWeight.w800,
      color: const ui.Color(0xFF7C2D12),
    );
    _paintText(
      canvas,
      'Labeled points only — no basemap, roads, or parcel boundaries are shown.',
      x: 40,
      y: 1260,
      maxWidth: 996,
      fontSize: 19,
      color: const ui.Color(0xFF7C2D12),
    );
    _paintText(
      canvas,
      'Generated: ${GeotagService.localTimestamp(generatedAt)} · '
      'Job $jobId · Round ${round ?? 0}',
      x: 40,
      y: 1292,
      maxWidth: 996,
      fontSize: 17,
      color: const ui.Color(0xFF9A3412),
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    if (data == null) {
      throw Exception('Unable to render the site location reference.');
    }
    final png = img.decodePng(data.buffer.asUint8List());
    if (png == null) {
      throw Exception('Unable to decode the site location reference.');
    }
    return Uint8List.fromList(img.encodeJpg(png, quality: 90));
  }

  static double _eastMeters(double lng, double originLng, double midLat) =>
      (lng - originLng) * 111320.0 * math.cos(midLat * math.pi / 180.0);

  static double _northMeters(double lat, double originLat) =>
      (lat - originLat) * 110540.0;

  static void _paintDeviceMarker(ui.Canvas canvas, ui.Offset point) {
    canvas.drawCircle(
      point,
      22,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      point,
      17,
      ui.Paint()..color = const ui.Color(0xFF2563EB),
    );
    canvas.drawCircle(point, 6, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  }

  static void _paintParcelMarker(ui.Canvas canvas, ui.Offset point) {
    final path = ui.Path()
      ..moveTo(point.dx, point.dy - 24)
      ..lineTo(point.dx + 19, point.dy)
      ..lineTo(point.dx, point.dy + 24)
      ..lineTo(point.dx - 19, point.dy)
      ..close();
    canvas.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeJoin = ui.StrokeJoin.round
        ..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawPath(path, ui.Paint()..color = const ui.Color(0xFFB45309));
  }

  static void _paintDashedLine(ui.Canvas canvas, ui.Offset a, ui.Offset b) {
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final unit = delta / length;
    final paint = ui.Paint()
      ..color = const ui.Color(0xFF64748B)
      ..strokeWidth = 2.5;
    for (var travelled = 0.0; travelled < length; travelled += 18) {
      final end = math.min(travelled + 10, length);
      canvas.drawLine(a + unit * travelled, a + unit * end, paint);
    }
  }

  static void _paintNorthArrow(ui.Canvas canvas, double x, double y) {
    canvas.drawCircle(
      ui.Offset(x, y),
      30,
      ui.Paint()..color = const ui.Color(0xFFF1F5F9),
    );
    final arrow = ui.Path()
      ..moveTo(x, y - 18)
      ..lineTo(x + 8, y + 10)
      ..lineTo(x, y + 4)
      ..lineTo(x - 8, y + 10)
      ..close();
    canvas.drawPath(arrow, ui.Paint()..color = const ui.Color(0xFF0F172A));
    _paintText(
      canvas,
      'N',
      x: x - 8,
      y: y + 12,
      maxWidth: 40,
      fontSize: 14,
      weight: ui.FontWeight.w700,
      align: ui.TextAlign.center,
    );
  }

  static void _paintChip(
    ui.Canvas canvas,
    String text,
    ui.Offset topLeft, {
    required double fontSize,
  }) {
    final paragraph = _buildParagraph(
      text,
      maxWidth: 300,
      fontSize: fontSize,
      weight: ui.FontWeight.w600,
      color: const ui.Color(0xFF0F172A),
      align: ui.TextAlign.center,
    );
    final rect = ui.Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      300,
      paragraph.height + 16,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(10)),
      ui.Paint()..color = const ui.Color(0xF2FFFFFF),
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(10)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const ui.Color(0xFFCBD5E1),
    );
    canvas.drawParagraph(paragraph, topLeft + const ui.Offset(0, 8));
    paragraph.dispose();
  }

  static void _paintText(
    ui.Canvas canvas,
    String text, {
    required double x,
    required double y,
    required double maxWidth,
    required double fontSize,
    ui.FontWeight weight = ui.FontWeight.w400,
    ui.Color color = const ui.Color(0xFF0F172A),
    double? letterSpacing,
    int? maxLines,
    ui.TextAlign align = ui.TextAlign.left,
  }) {
    final paragraph = _buildParagraph(
      text,
      maxWidth: maxWidth,
      fontSize: fontSize,
      weight: weight,
      color: color,
      letterSpacing: letterSpacing,
      maxLines: maxLines,
      align: align,
    );
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
    paragraph.dispose();
  }

  static ui.Paragraph _buildParagraph(
    String text, {
    required double maxWidth,
    required double fontSize,
    required ui.FontWeight weight,
    required ui.Color color,
    double? letterSpacing,
    int? maxLines,
    ui.TextAlign align = ui.TextAlign.left,
  }) {
    final style = ui.ParagraphStyle(
      fontFamily: 'Roboto',
      fontSize: fontSize,
      height: 1.25,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.25,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        ),
      )
      ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }
}
