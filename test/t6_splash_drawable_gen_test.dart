// T6 SPLASH DRAWABLE GENERATOR — throwaway tooling for the approved Android
// 12+ splash fix. Reads the official kit's white symbol PNG (with the red
// site dot), measures its content, rescales it so the content fits inside the
// system splash icon's safe zone (the central 2/3 circle — 160dp of the 240dp
// icon area when an icon background is set; 192dp of 288dp without), and
// writes the padded transparent drawable into the app's res tree. Prints the
// before/after numbers as evidence.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const String kSrcPng =
    r'C:\Users\Ralph Lauren\imaps_fieldsync_main\assets\icon\FieldSync-Logo-Kit\png\transparent\symbol\fieldsync-symbol-white-1024.png';
const String kOutPng =
    r'C:\Users\Ralph Lauren\AppData\Local\Temp\opencode\fs-splash-cinematic-20261017\android\app\src\main\res\drawable-xxxhdpi\ic_splash_fieldsync.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('padded splash drawable', () async {
    await _generate();
  });
}

Future<void> _generate() async {
  final bytes = File(kSrcPng).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final src = frame.image;
  final w = src.width;
  final h = src.height;
  final bd = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
  final px = bd!.buffer.asUint8List();

  // Content stats (alpha above the visibility floor Android will show).
  var minX = w, maxX = -1, minY = h, maxY = -1;
  var rMax = 0.0;
  var redCount = 0;
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final a = px[i + 3];
      if (a <= 8) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      final r = px[i], g = px[i + 1], b = px[i + 2];
      if (r > 170 && g < 110 && b < 110) redCount++;
      final d = math.sqrt(
          math.pow(x - cx, 2).toDouble() + math.pow(y - cy, 2).toDouble());
      if (d > rMax) rMax = d;
    }
  }
  // ignore: avoid_print
  print('src ${w}x$h: content bbox $minX..$maxX x $minY..$maxY, '
      'max radius from centre ${rMax.toStringAsFixed(1)}px '
      '(${(2 * rMax / w * 100).toStringAsFixed(1)}% of width), '
      'red-dot-ish pixels $redCount');

  // Safe zone: the central 2/3 circle of the icon square (r = canvas/3),
  // with 3% slack so a mask can never bite the artwork.
  const canvas = 1024;
  final rTarget = canvas / 3 * 0.97;
  final scale = rTarget / rMax;

  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 1024, 1024));
  c.translate(canvas / 2, canvas / 2);
  c.scale(scale);
  c.translate(-w / 2.0, -h / 2.0);
  c.drawImage(src, ui.Offset.zero, ui.Paint());
  final img = await rec.endRecording().toImage(canvas, canvas);
  final outBd = await img.toByteData(format: ui.ImageByteFormat.png);
  final outBytes = outBd!.buffer.asUint8List();

  // Verify the written result, from the encoded bytes themselves.
  final codec2 = await ui.instantiateImageCodec(outBytes);
  final frame2 = await codec2.getNextFrame();
  final out = frame2.image;
  final obd = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  final opx = obd!.buffer.asUint8List();
  var oRMax = 0.0;
  var oCorners = 0;
  var oRed = 0;
  final ocx = (out.width - 1) / 2;
  final ocy = (out.height - 1) / 2;
  for (final p in [
    0, out.width - 1, (out.height - 1) * out.width,
    out.width * out.height - 1,
  ]) {
    expect(opx[p * 4 + 3], 0, reason: 'all four corners must be transparent');
    if (opx[p * 4 + 3] > 8) oCorners++;
  }
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final i = (y * out.width + x) * 4;
      if (opx[i + 3] <= 8) continue;
      final r = opx[i], g = opx[i + 1], b = opx[i + 2];
      if (r > 170 && g < 110 && b < 110) oRed++;
      final d = math.sqrt(math.pow(x - ocx, 2).toDouble() +
          math.pow(y - ocy, 2).toDouble());
      if (d > oRMax) oRMax = d;
    }
  }
  expect(out.width, 1024);
  expect(out.height, 1024);
  expect(oRMax, lessThan(out.width / 3),
      reason: 'visible content must fit inside the Android safe circle');
  expect(oRed, greaterThan(0), reason: 'preserve the official red site dot');
  // ignore: avoid_print
  print('out ${out.width}x${out.height}: scale ${scale.toStringAsFixed(4)}, '
      'max radius ${oRMax.toStringAsFixed(1)}px '
      '(${(oRMax / (out.width / 3) * 100).toStringAsFixed(1)}% of the safe '
      'radius), corner pixels visible $oCorners, red-dot-ish pixels $oRed');

  Directory(File(kOutPng).parent.path).createSync(recursive: true);
  File(kOutPng).writeAsBytesSync(outBytes);
  // ignore: avoid_print
  print('wrote $kOutPng (${outBytes.length} bytes)');
}
