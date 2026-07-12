import 'dart:typed_data';
import 'package:image/image.dart' as img;

class GeotagService {
  /// Nagla-lagay ng text (geotag lines) sa ilalim ng litrato,
  /// permanenteng naka-burn sa image mismo (hindi lang UI overlay).
  static Uint8List embedGeotag({
    required Uint8List photoBytes,
    required List<String> lines,
  }) {
    final image = img.decodeImage(photoBytes);
    if (image == null) {
      throw Exception('Unable to decode captured photo.');
    }

    final font = img.arial24;
    const padding = 16;
    final lineHeight = font.lineHeight;
    final boxHeight = (lines.length * lineHeight) + (padding * 2);

    img.fillRect(
      image,
      x1: 0,
      y1: image.height - boxHeight,
      x2: image.width,
      y2: image.height,
      color: img.ColorRgba8(0, 0, 0, 140),
    );

    var y = image.height - boxHeight + padding;
    for (final line in lines) {
      img.drawString(
        image,
        line,
        font: font,
        x: padding,
        y: y,
        color: img.ColorRgb8(255, 255, 255),
      );
      y += lineHeight;
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }
}