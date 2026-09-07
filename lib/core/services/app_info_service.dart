import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  static String _version = '';
  static String _buildNumber = '';

  static String get version => _version;
  static String get buildNumber => _buildNumber;

  static String get fullVersionString {
    if (_version.isEmpty) {
      return 'Version unavailable';
    }
    return 'Version $_version';
  }

  static Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _version = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    } catch (e) {
      debugPrint('[AppInfoService] Failed to initialize package info: $e');
      _version = '';
      _buildNumber = '';
    }
  }
}

