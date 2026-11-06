import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const currentGuideVersion = 1;

enum GuideLanguage { english, tagalog }

enum GuideStatus { offered, skipped, completed }

class GuideRecord {
  final int version;
  final GuideLanguage language;
  final GuideStatus status;

  const GuideRecord(this.version, this.language, this.status);
}

/// Non-sensitive, device-local metadata, never authentication or task state.
class GuidePreferences {
  String _key(String inspectorId) {
    final id = inspectorId.trim().toLowerCase();
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(id)) {
      throw ArgumentError(
        'Guide preferences require an authenticated account UUID',
      );
    }
    return 'fieldsync.guide.${sha256.convert(utf8.encode(id))}';
  }

  Future<GuideRecord?> read(String inspectorId) async {
    final key = _key(inspectorId);
    final store = await SharedPreferences.getInstance();
    final raw = store.get(key);
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('Invalid guide record');
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['version'] is! int ||
        (value['version'] as int) < 1 ||
        !GuideLanguage.values.any((v) => v.name == value['language']) ||
        !GuideStatus.values.any((v) => v.name == value['status'])) {
      throw const FormatException('Invalid guide record');
    }
    return GuideRecord(
      value['version'] as int,
      GuideLanguage.values.byName(value['language'] as String),
      GuideStatus.values.byName(value['status'] as String),
    );
  }

  Future<void> write(String inspectorId, GuideRecord record) async {
    final key = _key(inspectorId);
    if (record.version < 1) throw ArgumentError('Invalid guide version');
    final store = await SharedPreferences.getInstance();
    final saved = await store.setString(
      key,
      jsonEncode({
        'version': record.version,
        'language': record.language.name,
        'status': record.status.name,
      }),
    );
    if (!saved) throw StateError('Guide metadata could not be saved');
  }
}
