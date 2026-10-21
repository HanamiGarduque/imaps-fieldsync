import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/db_helper.dart';

/// Owner/job/round-scoped staging for camera captures that are not yet
/// accepted evidence. A receipt beside the JPEG records who owns the capture
/// and whether the app ever started accepting it, so a later launch can prove
/// a directory abandoned instead of guessing. Accepted evidence never lives
/// here, and cleanup never touches canonical evidence, other owners, other
/// rounds, queued photos or anything it cannot prove unused.
///
/// File operations are deliberately synchronous: they are a few small,
/// already-serialized steps on the Save/launch path, and keeping them out of
/// the microtask queue makes the accept-or-retain decision deterministic.
class PendingCaptureStore {
  static const rootName = 'pending_captures_v1';
  static const receiptName = 'capture.json';
  static const photoName = 'photo.jpg';

  static String _key(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static Future<Directory> _roundRoot({
    required String owner,
    required String jobId,
    required int round,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      p.join(
        documents.path,
        rootName,
        _key(owner),
        _key(jobId),
        'round_$round',
      ),
    );
  }

  static Map<String, dynamic> _receipt(Directory dir) {
    try {
      final decoded = jsonDecode(
        File(p.join(dir.path, receiptName)).readAsStringSync(),
      );
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Writes a receipt first, then the JPEG. A crash between the two leaves a
  /// `staging` receipt with no accepted evidence, which cleanup may remove.
  static Future<String> stage({
    required String owner,
    required String jobId,
    required int round,
    required String id,
    required List<int> bytes,
  }) async {
    final dir = Directory(
      p.join(
        (await _roundRoot(owner: owner, jobId: jobId, round: round)).path,
        id,
      ),
    );
    dir.createSync(recursive: true);
    final photo = File(p.join(dir.path, photoName));
    final receipt = File(p.join(dir.path, receiptName));
    void writeReceipt(String state) => receipt.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'owner': owner,
        'job': jobId,
        'round': round,
        'id': id,
        'state': state,
      }),
      flush: true,
    );
    writeReceipt('staging');
    final partial = File('${photo.path}.part');
    partial.writeAsBytesSync(bytes, flush: true);
    partial.renameSync(photo.path);
    writeReceipt('pending');
    return photo.path;
  }

  /// Durably records that acceptance started. From here the capture is no
  /// longer cleanup-eligible, even if the process dies mid-acceptance.
  static Future<void> markAccepting(String photoPath) async {
    final receipt = File(p.join(File(photoPath).parent.path, receiptName));
    if (!receipt.existsSync()) return;
    try {
      final decoded = jsonDecode(receipt.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return;
      receipt.writeAsStringSync(
        jsonEncode({...decoded, 'state': 'accepting'}),
        flush: true,
      );
    } catch (_) {
      // An unreadable receipt stays unreadable: cleanup will retain it.
    }
  }

  /// Removes staged bytes for a capture this session discarded or accepted.
  /// Never removes a path a local row or pending queue entry references.
  static Future<void> discard(String photoPath) async {
    try {
      final photo = File(photoPath);
      final dir = photo.parent;
      if (p.basename(photo.path) != photoName) {
        if (photo.existsSync()) photo.deleteSync();
        return;
      }
      final receipt = _receipt(dir);
      final job = receipt['job'];
      if (job is String) {
        final db = await DBHelper.database;
        final rows = await db.query(
          'local_photos',
          columns: ['id'],
          where: 'photo_path = ?',
          whereArgs: [photo.path],
        );
        if (rows.isNotEmpty) return;
        final queued = await db.query(
          'pending_actions',
          columns: ['payload'],
          where: 'job_id = ?',
          whereArgs: [job],
        );
        for (final row in queued) {
          if ((row['payload'] as String?)?.contains(photo.path) ?? false) {
            return;
          }
        }
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Cleanup is best-effort; evidence is never deleted on uncertainty.
    }
  }

  static Set<String> _strings(Object? value, Set<String> into) {
    if (value is String) into.add(value);
    if (value is List) {
      for (final item in value) {
        _strings(item, into);
      }
    }
    if (value is Map) {
      for (final item in value.values) {
        _strings(item, into);
      }
    }
    return into;
  }

  /// Deletes only directories under this owner/job/round whose receipt proves
  /// an unaccepted capture and whose JPEG is referenced nowhere. Any read or
  /// parse failure retains everything: cleanup must never become data loss.
  static Future<void> cleanupAbandoned({
    required String owner,
    required String jobId,
    required int round,
    Set<String> protectedPaths = const <String>{},
  }) async {
    final root = await _roundRoot(owner: owner, jobId: jobId, round: round);
    if (!root.existsSync()) return;
    final Set<String> referenced;
    try {
      final db = await DBHelper.database;
      final photos = await db.query(
        'local_photos',
        columns: ['photo_path'],
        where: 'inspector_id = ? AND job_id = ?',
        whereArgs: [owner, jobId],
      );
      referenced = photos
          .map((row) => row['photo_path'])
          .whereType<String>()
          .toSet();
      final queued = await db.query(
        'pending_actions',
        columns: ['payload'],
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      for (final row in queued) {
        final payload = row['payload'] as String?;
        if (payload == null) continue;
        // Malformed or unexpected payloads throw and retain everything.
        referenced.addAll(_strings(jsonDecode(payload), <String>{}));
      }
    } catch (_) {
      return;
    }
    final List<FileSystemEntity> entries;
    try {
      entries = root.listSync();
    } catch (_) {
      return;
    }
    for (final entry in entries.whereType<Directory>()) {
      final receipt = _receipt(entry);
      if (receipt.length < 6 || receipt['version'] != 1) continue;
      if (receipt['owner'] != owner ||
          receipt['job'] != jobId ||
          receipt['round'] != round) {
        continue;
      }
      final state = receipt['state'];
      if (state != 'staging' && state != 'pending') continue;
      final names = <String>{};
      try {
        for (final child in entry.listSync()) {
          names.add(p.basename(child.path));
        }
      } catch (_) {
        continue;
      }
      if (names.length != 2 ||
          !names.containsAll(<String>{receiptName, photoName})) {
        continue;
      }
      final photoPath = p.join(entry.path, photoName);
      if (protectedPaths.contains(photoPath) ||
          referenced.contains(photoPath)) {
        continue;
      }
      try {
        entry.deleteSync(recursive: true);
      } catch (_) {
        // Retained; a later launch may retry once permissions allow.
      }
    }
  }
}
