import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/services/supabase_service.dart';

PhotoSourceResolver inspectionPhotoResolver() => PhotoSourceResolver(
  projectUrl: Uri.parse(dotenv.env['SUPABASE_URL']!),
  download: (path) => SupabaseService.client.storage
      .from('inspection-photos').download(path),
);

/// Presentation-only fallback; the provider's durable/upload payload is unchanged.
List<String> inspectionDisplayPaths(List<String> sources, String jobId,
    List<Map<String, dynamic>> details, List<String> persisted) {
  final candidates = PhotoSourceResolver.evidence(details, persisted)
      .map((p) => p['photoPath'] as String).toList();
  return sources.map((source) {
    try {
      if (PhotoSourceResolver.classify(source) == PhotoSourceKind.localFile &&
          !File(source).existsSync()) {
        return inspectionPhotoResolver().fallbackFor(source, jobId, candidates) ?? source;
      }
    } catch (_) {
      // A missing configuration/file is an explicit render failure, not evidence.
    }
    return source;
  }).toList();
}

enum PhotoSourceKind { localFile, remoteHttp, storageObject, invalid }

/// Read-only presentation boundary. Never writes URLs, metadata or photo bytes.
class PhotoSourceResolver {
  final Uri projectUrl;
  final Future<Uint8List> Function(String objectPath) download;
  final bool Function(String path) fileExists;

  PhotoSourceResolver({
    required this.projectUrl,
    required this.download,
    bool Function(String path)? fileExists,
  }) : fileExists = fileExists ?? ((path) => File(path).existsSync());

  static bool isObjectPath(String value) {
    final parts = value.split('/');
    return parts.length >= 3 &&
        parts.first == 'inspections' &&
        RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
            .hasMatch(parts[1]) &&
        parts.every((p) => p.isNotEmpty && p != '.' && p != '..' &&
            !p.contains('\\') && !p.contains('%') && !p.contains('?') &&
            !p.contains('#'));
  }

  static PhotoSourceKind classify(String value) {
    if (value.isEmpty) return PhotoSourceKind.invalid;
    if (isObjectPath(value)) return PhotoSourceKind.storageObject;
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return PhotoSourceKind.remoteHttp;
    }
    if (value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      return PhotoSourceKind.localFile;
    }
    return PhotoSourceKind.invalid;
  }

  /// Only the configured project's exact Storage route/bucket is accepted.
  /// Arbitrary HTTP URLs are not rewritten or fetched anonymously.
  String? objectPath(String value) {
    if (isObjectPath(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty || uri.origin != projectUrl.origin ||
        uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      return null;
    }
    final parts = uri.pathSegments;
    if (parts.length < 7 || parts[0] != 'storage' || parts[1] != 'v1' ||
        parts[2] != 'object' ||
        !{'public', 'sign', 'authenticated'}.contains(parts[3]) ||
        parts[4] != 'inspection-photos') {
      return null;
    }
    final path = parts.skip(5).join('/');
    return isObjectPath(path) ? path : null;
  }

  Future<ResolvedPhoto?> resolve(String value, {String? fallback}) async {
    for (final source in [value, ?fallback]) {
      try {
        if (classify(source) == PhotoSourceKind.localFile && fileExists(source)) {
          return ResolvedPhoto.local(source);
        }
        final path = objectPath(source);
        if (path != null) return ResolvedPhoto.remote(await download(path));
      } catch (_) {
        // Missing/inaccessible files, invalid URLs, denied or offline reads:
        // try only the supplied same-evidence fallback, otherwise fail visibly.
      }
    }
    return null;
  }

  /// Matches the actual deterministic uploader identity, never list position.
  String? fallbackFor(String localPath, String jobId, List<String> candidates) {
    final key = base64Url.encode(utf8.encode(localPath)).replaceAll('=', '');
    final expected = 'inspections/$jobId/photo_$key.jpg';
    for (final candidate in candidates) {
      try {
        if (objectPath(candidate) == expected) return candidate;
      } catch (_) { /* Invalid candidate is not evidence. */ }
    }
    return null;
  }

  static List<Map<String, dynamic>> evidence(
    List<Map<String, dynamic>> details, List<String> paths,
  ) {
    final validDetails = details.where((p) =>
        (p['photo_url'] as String?)?.isNotEmpty == true).toList();
    return validDetails.isNotEmpty
        ? validDetails.map((p) => {...p, 'photoPath': p['photo_url']}).toList()
        : paths.map((p) => <String, dynamic>{'photoPath': p}).toList();
  }
}

class ResolvedPhoto {
  final String? localPath;
  final Uint8List? bytes;
  const ResolvedPhoto.local(String path) : localPath = path, bytes = null;
  const ResolvedPhoto.remote(Uint8List data) : localPath = null, bytes = data;
}
