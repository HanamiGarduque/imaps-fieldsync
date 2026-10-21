import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Burns the evidence caption into a band appended BELOW the camera image.
///
/// The camera scene is never covered: the output is the original pixels on
/// top plus a new footer band. Text is laid out with Flutter's paragraph
/// engine so accented Filipino names (ñ/Ñ/é) and long addresses keep their
/// glyphs and wrap instead of being dropped by `image`'s ASCII-only fonts.
class GeotagService {
  static const String photoTitle = 'SITE PHOTO — FIELD EVIDENCE';

  /// UTC, offset-aware storage value for `field_job_photos.captured_at`.
  static String storageTimestamp(DateTime capturedAt) =>
      capturedAt.toUtc().toIso8601String();

  /// Human local time with an explicit UTC offset, e.g.
  /// `Oct 21, 2026 14:05:09 +08:00`.
  static String localTimestamp(DateTime capturedAt) {
    final local = capturedAt.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${_monthName(local.month)} ${local.day.toString().padLeft(2, '0')}, '
        '${local.year} ${two(local.hour)}:${two(local.minute)}:'
        '${two(local.second)} $sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
  }

  /// The exact lines burned into a new camera photo. One capture timestamp is
  /// passed in; the absent-GPS state is explicit and never borrows the Step 2
  /// or parcel point.
  static List<String> captureFooterLines({
    required String applicant,
    required String? address,
    required DateTime capturedAt,
    required double? latitude,
    required double? longitude,
    required double? accuracyMeters,
  }) {
    final name = applicant.trim();
    final siteAddress = address?.trim() ?? '';
    final gps = latitude == null || longitude == null
        ? 'GPS unavailable — no reliable camera fix'
        : accuracyMeters == null
        ? 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
        : 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)} '
              '(±${accuracyMeters.round()} m)';
    return [
      photoTitle,
      'Applicant: ${name.isEmpty ? 'Not on file' : name}',
      'Address: ${siteAddress.isEmpty ? 'Address not on file' : siteAddress}',
      'Captured: ${localTimestamp(capturedAt)}',
      gps,
    ];
  }

  /// Appends [lines] as a dark footer band below [photoBytes].
  static Future<Uint8List> appendFooter({
    required Uint8List photoBytes,
    required List<String> lines,
  }) async {
    final image = img.decodeImage(photoBytes);
    if (image == null) {
      throw Exception('Unable to decode captured photo.');
    }
    final text = lines.where((line) => line.trim().isNotEmpty).join('\n');
    if (text.isEmpty) return photoBytes;

    final width = image.width;
    final fontSize = (width / 38).clamp(20.0, 40.0).toDouble();
    final padding = (fontSize * 0.9).round();
    final maxTextWidth = (width - padding * 2).clamp(1, width).toDouble();

    final paragraph = _paragraph(
      text,
      maxWidth: maxTextWidth,
      fontSize: fontSize,
      color: const ui.Color(0xFFFFFFFF),
      weight: ui.FontWeight.w500,
      height: 1.42,
    );
    final footerHeight = (paragraph.height + padding * 2 + 4).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), footerHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF0B1220),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), 4),
      ui.Paint()..color = const ui.Color(0xFF2563EB),
    );
    canvas.drawParagraph(
      paragraph,
      ui.Offset(padding.toDouble(), padding.toDouble() + 4),
    );
    paragraph.dispose();

    final picture = recorder.endRecording();
    final footerUi = await picture.toImage(width, footerHeight);
    final png = await footerUi.toByteData(format: ui.ImageByteFormat.png);
    footerUi.dispose();
    picture.dispose();
    if (png == null) {
      throw Exception('Unable to render the photo footer.');
    }

    final footer = img.decodePng(png.buffer.asUint8List());
    if (footer == null) {
      throw Exception('Unable to compose the photo footer.');
    }
    final output = img.Image(
      width: width,
      height: image.height + footer.height,
      numChannels: 3,
    );
    img.fill(output, color: img.ColorRgb8(11, 18, 32));
    img.compositeImage(output, image, dstX: 0, dstY: 0);
    img.compositeImage(output, footer, dstX: 0, dstY: image.height);
    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  static ui.Paragraph _paragraph(
    String text, {
    required double maxWidth,
    required double fontSize,
    required ui.Color color,
    required ui.FontWeight weight,
    required double height,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'Roboto',
              fontSize: fontSize,
              height: height,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
              height: height,
              fontWeight: weight,
            ),
          )
          ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  static String _monthName(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}
