import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class GuideAndroid200TextScaler extends TextScaler {
  const GuideAndroid200TextScaler();
  @override
  double get textScaleFactor => 2;
  @override
  double scale(double size) {
    const from = [8.0, 10.0, 12.0, 14.0, 18.0, 20.0, 24.0, 30.0, 100.0];
    const to = [16.0, 20.0, 24.0, 26.0, 30.0, 34.0, 36.0, 38.0, 100.0];
    if (size <= from.first) return size * 2;
    for (var i = 1; i < from.length; i++) {
      if (size <= from[i]) {
        return to[i - 1] +
            (to[i] - to[i - 1]) *
                (size - from[i - 1]) /
                (from[i] - from[i - 1]);
      }
    }
    return size;
  }
}

Future<void> prepareGuideTestFonts() async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final sdkFonts = Directory(
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  );
  final fallback = ByteData.sublistView(
    sdkFonts
        .listSync()
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.ttf'))
        .readAsBytesSync(),
  );
  final manifest = <String, Object>{};
  for (final family in ['Inter', 'Urbanist', 'OpenSans', 'JetBrainsMono']) {
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Light',
    ]) {
      final asset = '$family-$weight.ttf';
      manifest[asset] = [
        {'asset': asset},
      ];
    }
  }
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    final asset = const StringCodec().decodeMessage(message)!;
    if (asset == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(manifest);
    }
    if (asset.endsWith('.ttf')) {
      final folder = Platform.environment['IMAPS_GUIDE_FONT_DIR'];
      return folder == null
          ? fallback
          : ByteData.sublistView(File('$folder/$asset').readAsBytesSync());
    }
    return File(asset).existsSync()
        ? ByteData.sublistView(File(asset).readAsBytesSync())
        : null;
  });
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '${sdkFonts.path}/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      ))
      .load();
}
