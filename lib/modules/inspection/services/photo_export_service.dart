import 'dart:io';

import 'package:flutter/services.dart';
import '../../../core/services/db_helper.dart';
import 'site_location_reference_service.dart';

enum PhotoCopyOutcome {
  saved,
  cancelled,
  unavailable,
  failed,
  unauthorized,
  unsupported,
}

/// Read-only export of accepted local evidence. No network, row update or image
/// encoding. Recheck ownership AFTER the system picker, before releasing bytes.
class PhotoExportService {
  static const _channel = MethodChannel('imaps_fieldsync/photo_export');

  static Future<PhotoCopyOutcome> saveCopy({
    required String path,
    required String? jobId,
    required String? inspectorId,
  }) async {
    var selected = false;
    var saved = false;
    try {
      if (Uri.tryParse(path)?.hasScheme == true &&
          !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
        return PhotoCopyOutcome.unavailable;
      }
      if (!await File(path).exists() || await File(path).length() == 0) {
        return PhotoCopyOutcome.unavailable;
      }
      Future<Map<String, dynamic>> verify() async {
        if (jobId == null || inspectorId == null) {
          throw StateError('Missing context');
        }
        DBHelper.requireSameInspector(inspectorId);
        final db = await DBHelper.database;
        return db.transaction((txn) async {
          await DBHelper.requireOwnedJob(txn, jobId, inspectorId);
          final rows = await txn.query(
            'local_photos',
            where: 'job_id = ? AND inspector_id = ? AND photo_path = ?',
            whereArgs: [jobId, inspectorId, path],
          );
          DBHelper.requireSameInspector(inspectorId);
          if (rows.length != 1) throw StateError('Unverified evidence');
          return rows.single;
        });
      }

      final photo = await verify();
      final id = (photo['id'] as String).replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final prefix = isLocationReferencePhoto(photo)
          ? 'site-location-reference'
          : 'inspection-photo';
      selected =
          await _channel.invokeMethod<bool>('createDocument', {
            'name': '$prefix-${id.length > 96 ? id.substring(0, 96) : id}.jpg',
          }) ??
          false;
      if (!selected) return PhotoCopyOutcome.cancelled;
      final current = await verify();
      if (current['id'] != photo['id']) throw StateError('Evidence changed');
      await _channel.invokeMethod<void>('copyPhoto', {'path': path});
      saved = true;
      return PhotoCopyOutcome.saved;
    } on MissingPluginException {
      return PhotoCopyOutcome.unsupported;
    } on StateError {
      return PhotoCopyOutcome.unauthorized;
    } on FileSystemException {
      return PhotoCopyOutcome.unavailable;
    } catch (_) {
      return PhotoCopyOutcome.failed;
    } finally {
      if (selected && !saved) {
        try {
          await _channel.invokeMethod<void>('discardDocument');
        } catch (_) {
          // A provider may retain a partial destination; never touch evidence.
        }
      }
    }
  }
}
