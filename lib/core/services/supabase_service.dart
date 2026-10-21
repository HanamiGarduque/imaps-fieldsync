import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'db_helper.dart';
import 'inspection_authority.dart';
import 'supabase_endpoint.dart';
import '../utils/calendar_date.dart';
export 'inspection_authority.dart';

enum PhotoObjectState { exists, missing, unknown }

/// Remote lifecycle values an inspector may start a task from. `pending` is a
/// pre-start state too — self-reschedule writes it — so matching only
/// `assigned` left every rescheduled task unable to start, and its queued
/// `mark_ongoing` retrying forever. Already-started rows are deliberately NOT
/// here: they must reconcile through the existing satisfied-state read so the
/// original `started_at` is never rewritten.
const List<String> kStartableTaskStatuses = ['assigned', 'Pending', 'pending'];

/// Active states a committed visit may be written to.
///
/// `pending` belongs here because earlier scheduling writes used that state,
/// so excluding it made every repeat reschedule a
/// zero-row write that the authority check then refused. `completed` and the
/// unsupported lifecycle values stay excluded, so a finished round can never
/// be resurrected.
const List<String> kSchedulableTaskStatuses = [
  'assigned',
  'Pending',
  'pending',
  'in_progress',
  'in-progress',
  'ongoing',
];

class PhotoRecoveryUnknownException implements Exception {
  final String message;
  const PhotoRecoveryUnknownException(this.message);
  @override
  String toString() => message;
}

/// Result of a timestamp-only write.
enum StepTimestampWriteOutcome {
  /// The remote record now holds the requested times.
  written,

  /// The remote record already held every requested time; nothing to write.
  alreadyPresent,
}
class SupabaseService {
  /// Live session identity, or null when no client session exists. Reading it
  /// never throws, so a caller can demand a session only at the point it
  /// actually performs a remote write.
  static String? get _sessionUid {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Refuse any remote write once the session is gone or has changed.
  static void _requireSession(String? uid) {
    if (uid == null || _sessionUid != uid) {
      throw const InspectionAuthorityException(
        InspectionAuthorityResult.authRequired,
      );
    }
  }

  /// Classify only known rejections. Unknown/transport outcomes still require
  /// verification; never expose SQL, response details or exception text to UI.
  static InspectionAuthorityResult _authorityFailure(Object error) {
    if (error is InspectionAuthorityException) return error.result;
    if (error is AuthException) return InspectionAuthorityResult.authRequired;
    final code = error is PostgrestException
        ? error.code
        : error is StorageException
        ? error.statusCode
        : null;
    if (const {
      '401',
      'PGRST301',
      'PGRST302',
      'PGRST303',
      '28000',
      '28P01',
    }.contains(code)) {
      return InspectionAuthorityResult.authRequired;
    }
    if (code != null &&
        (code.startsWith('22') ||
            code.startsWith('23') ||
            const {
              '400',
              '403',
              '405',
              '409',
              '413',
              '415',
              '422',
              '42501',
              'PGRST100',
              'PGRST102',
              'PGRST105',
              'PGRST106',
              'PGRST107',
              'PGRST108',
              'PGRST200',
              'PGRST201',
              'PGRST202',
              'PGRST204',
            }.contains(code))) {
      return InspectionAuthorityResult.serverRejected;
    }
    return InspectionAuthorityResult.offlineOrUnverifiable;
  }

  /// One authority-checked write. Zero returned rows are never success: only a
  /// current authoritative read can tell an idempotent no-op from lost or
  /// unverifiable authority.
  static Future<InspectionAuthorityResult> _writeWithAuthority(
    String jobId,
    Future<List<Map<String, dynamic>>> Function(String uid) write, {
    bool Function(Map<String, dynamic>)? satisfied,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return InspectionAuthorityResult.authRequired;
    try {
      final rows = await write(uid).timeout(const Duration(seconds: 10));
      if (client.auth.currentUser?.id != uid) {
        return InspectionAuthorityResult.authRequired;
      }
      if (rows.length == 1 &&
          rows.single['id'] == jobId &&
          rows.single['assigned_inspector_id'] == uid) {
        return satisfied == null || satisfied(rows.single)
            ? InspectionAuthorityResult.authorized
            : InspectionAuthorityResult.offlineOrUnverifiable;
      }
      if (rows.isNotEmpty) {
        return InspectionAuthorityResult.offlineOrUnverifiable;
      }
      final row = await client
          .from('field_jobs')
          .select()
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .maybeSingle()
          .retry(enabled: false)
          .timeout(const Duration(seconds: 10));
      if (client.auth.currentUser?.id != uid) {
        return InspectionAuthorityResult.authRequired;
      }
      if (row == null) {
        return InspectionAuthorityResult.notAssignedOrUnavailable;
      }
      if (row['id'] != jobId || row['assigned_inspector_id'] != uid) {
        return InspectionAuthorityResult.offlineOrUnverifiable;
      }
      return satisfied != null && satisfied(row)
          ? InspectionAuthorityResult.authorized
          : InspectionAuthorityResult.offlineOrUnverifiable;
    } catch (e) {
      return _authorityFailure(e);
    }
  }

  static Future<void> initialize() async {
    // Release builds fail before any network call when the bundled endpoint is
    // not a public HTTPS host; the message never echoes the configured value.
    final url = validateSupabaseEndpoint(
      dotenv.env['SUPABASE_URL'],
      release: kReleaseMode,
    );
    await Supabase.initialize(
      url: url,
      publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Test hook: pins [hasClient] so the client-unavailable startup shapes stay
  /// exercisable from `flutter test` (where a fixture Supabase instance may
  /// already exist in the same process). Never set by app code.
  @visibleForTesting
  static bool? debugClientAvailableOverride;

  /// Whether a usable Supabase client exists right now. Never throws: before
  /// [Supabase.initialize] has run, debug builds trip [Supabase.instance]'s
  /// assert and release builds hit the unassigned `client` field — both mean
  /// exactly "no client". Startup gates and build methods read this, so it
  /// must stay exception-free.
  static bool get hasClient {
    final override = debugClientAvailableOverride;
    if (override != null) return override;
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// R4 read: absence/reassignment is not a successful delivery. Transport
  /// failures propagate, unlike the UI's best-effort detail reader.
  static Future<Map<String, dynamic>?> readOutboxRecoveryJob(
    String jobId,
  ) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Recovery requires authenticated session');
    }
    return await client
        .from('field_jobs')
        .select()
        .eq('id', jobId)
        .eq('assigned_inspector_id', user.id)
        .maybeSingle();
  }

  /// Compare-and-set: WHERE tests the old tuple before BEFORE UPDATE stamps
  /// NEW.updated_at. RETURNING yields the actual post-trigger revision. Never
  /// send an updated_at assignment or interpret zero returned rows as success.
  static Future<Map<String, dynamic>?> conditionalOutboxUpdate(
    String jobId,
    String version,
    String status,
    Map<String, dynamic> values,
  ) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Recovery requires authenticated session');
    }
    return await client
        .from('field_jobs')
        .update(values)
        .eq('id', jobId)
        .eq('assigned_inspector_id', user.id)
        .eq('updated_at', version)
        .eq('status', status)
        .select()
        .maybeSingle();
  }

  @visibleForTesting
  static String stablePhotoKey(String localPath) => _stablePhotoKey(localPath);

  @visibleForTesting
  static String photoStoragePath(String jobId, String localPath) =>
      'inspections/$jobId/photo_${_stablePhotoKey(localPath)}.jpg';

  @visibleForTesting
  static String photoRowId(String storagePath) =>
      const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', storagePath);

  static String? extractStorageObjectPath(String value) {
    if (value.isEmpty) return null;
    final parts = value.split('/');
    if (parts.length >= 3 &&
        parts.first == 'inspections' &&
        parts[1].isNotEmpty &&
        parts.every(
          (p) =>
              p.isNotEmpty &&
              p != '.' &&
              p != '..' &&
              !p.contains('\\') &&
              !p.contains('%') &&
              !p.contains('?') &&
              !p.contains('#'),
        )) {
      return value;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final segs = uri.pathSegments;
    if (segs.length < 7 ||
        segs[0] != 'storage' ||
        segs[1] != 'v1' ||
        segs[2] != 'object' ||
        !{'public', 'sign', 'authenticated'}.contains(segs[3]) ||
        segs[4] != 'inspection-photos') {
      return null;
    }
    final extracted = segs.skip(5).join('/');
    final extractedParts = extracted.split('/');
    if (extractedParts.length >= 3 &&
        extractedParts.first == 'inspections' &&
        extractedParts[1].isNotEmpty &&
        extractedParts.every(
          (p) =>
              p.isNotEmpty &&
              p != '.' &&
              p != '..' &&
              !p.contains('\\') &&
              !p.contains('%') &&
              !p.contains('?') &&
              !p.contains('#'),
        )) {
      return extracted;
    }
    return null;
  }

  /// Narrow HEAD check for the exact canonical object. A transport failure is
  /// UNKNOWN, never evidence that the object is absent.
  static Future<PhotoObjectState> photoObjectState(String storagePath) async {
    try {
      final exists = await client.storage
          .from('inspection-photos')
          .exists(storagePath);
      return exists ? PhotoObjectState.exists : PhotoObjectState.missing;
    } catch (e) {
      final result = _authorityFailure(e);
      if (result != InspectionAuthorityResult.offlineOrUnverifiable) {
        throw InspectionAuthorityException(result);
      }
      debugPrint('Photo object existence check unknown for $storagePath: $e');
      return PhotoObjectState.unknown;
    }
  }

  static bool _isSamePhotoUrl(String? a, String? b, String expectedObjectPath) {
    if (a == null || b == null) return a == b;
    if (a == b) return true;
    final pathA = extractStorageObjectPath(a);
    final pathB = extractStorageObjectPath(b);
    if (pathA != null && pathB != null && pathA == pathB) return true;
    if (pathA != null && pathA == expectedObjectPath) return true;
    if (pathB != null && pathB == expectedObjectPath) return true;
    return false;
  }

  /// Recovery checks every queued photo, not just metadata ID existence.
  /// Missing evidence is returned as a conflict by the caller; no existing
  /// object or metadata is overwritten on the basis of an ID alone.
  static Future<List<String>> verifyOutboxRecoveryPhotos(
    String jobId,
    List<Map<String, dynamic>> photos, {
    bool allowMissingResume = false,
  }) async {
    final uid = _sessionUid;
    final paths = <String>[];
    for (final photo in photos) {
      final localPath = photo['photoPath'];
      if (localPath is! String || photo['isRemoteUrl'] == true) {
        throw StateError(
          'Recovery requires original deterministic photo identity',
        );
      }
      final path = photoStoragePath(jobId, localPath);
      final id = photoRowId(path);
      final row = await client
          .from('field_job_photos')
          .select()
          .eq('id', id)
          .eq('field_job_id', jobId)
          .maybeSingle();
      // Metadata is verified below after the object state is known. Do not
      // reject a missing row here: a definite canonical object can repair the
      // same deterministic metadata identity.
      final expected = <String, dynamic>{
        'photo_url': path,
        'latitude': photo['latitude'],
        'longitude': photo['longitude'],
        'captured_at': photo['capturedAt'],
        'notes': photo['notes'],
      };
      if (row != null) {
        for (final entry in expected.entries) {
          var equal = row[entry.key] == entry.value;
          if (entry.key == 'photo_url' && row[entry.key] is String) {
            equal = _isSamePhotoUrl(
              row[entry.key] as String,
              entry.value as String,
              path,
            );
          } else if (entry.key == 'captured_at' &&
              row[entry.key] is String &&
              entry.value is String) {
            final a = DateTime.tryParse(row[entry.key] as String);
            final b = DateTime.tryParse(entry.value as String);
            equal = a != null && b != null && a.isAtSameMomentAs(b);
          }
          if (!equal) {
            throw StateError('Differing photo metadata: ${entry.key}');
          }
        }
      }

      final file = File(localPath);
      final fileExists = await file.exists();
      final objectState = await photoObjectState(path);

      if (objectState == PhotoObjectState.unknown) {
        throw PhotoRecoveryUnknownException(
          'Photo object existence is unknown for $path',
        );
      }

      if (objectState == PhotoObjectState.missing) {
        if (!fileExists) {
          throw StateError('Missing photo object and local source');
        }
        if (!allowMissingResume) {
          throw StateError('Missing photo object without valid durable base');
        }
        _requireSession(uid);
        await client.storage
            .from('inspection-photos')
            .upload(
              path,
              file,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );
      } else if (fileExists) {
        // Existence is only the completeness gate. When both sides are
        // present, retain the existing byte proof for recovery decisions.
        Uint8List? bytes;
        try {
          final downloaded = await client.storage
              .from('inspection-photos')
              .download(path);
          if (downloaded.isNotEmpty) bytes = downloaded;
        } catch (e) {
          throw PhotoRecoveryUnknownException(
            'Photo object bytes could not be verified for $path',
          );
        }
        if (bytes == null) {
          throw PhotoRecoveryUnknownException(
            'Photo object returned no bytes for $path',
          );
        }
        final local = await file.readAsBytes();
        if (!listEquals(local, bytes)) {
          throw StateError('Differing photo bytes');
        }
      }

      if (row == null) {
        // INSERT, not upsert: a concurrent metadata row must not be overwritten.
        _requireSession(uid);
        await client.from('field_job_photos').insert({
          'id': id,
          'field_job_id': jobId,
          ...expected,
        });
      }
      paths.add(
        row != null && row['photo_url'] is String
            ? row['photo_url'] as String
            : path,
      );
    }
    return paths;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEVICE REGISTRATION
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> registerDeviceForPush({
    required String deviceToken,
    String platform = 'android',
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      debugPrint('No logged-in user found, unable to save device token.');
      return;
    }
    try {
      await client.from('inspector_device_subscriptions').upsert({
        'inspector_id': user.id,
        'device_token': deviceToken,
        'platform': platform,
      }, onConflict: 'inspector_id,device_token');
    } catch (e) {
      debugPrint('Failed to save notification subscription: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BIOMETRIC & SECURITY DEVICE SYNC
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> syncInspectorDevice({
    required String deviceId,
    required bool biometricEnabled,
    String? biometricType,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client.from('inspector_devices').upsert({
        'inspector_id': user.id,
        'device_id': deviceId,
        'platform': Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'desktop'),
        'biometric_enabled': biometricEnabled,
        'biometric_type': biometricType,
        'last_login_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'inspector_id,device_id');
    } catch (e) {
      debugPrint('[SUPABASE] syncInspectorDevice error: $e');
    }
  }

  static Future<void> logSecurityEvent({
    required String eventType,
    String? deviceId,
    String severity = 'info',
    Map<String, dynamic>? metadata,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client.rpc(
        'log_security_event',
        params: {
          'p_event_type': eventType,
          'p_device_id': deviceId,
          'p_severity': severity,
          'p_metadata': metadata ?? {},
        },
      );
    } catch (e) {
      debugPrint('[SUPABASE] logSecurityEvent error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVITY LOG  (Dashboard → Recent Activity)
  //   Fire-and-forget: a logging failure should never block the action
  //   that triggered it (GPS confirm, submit, rework, sync).
  // ─────────────────────────────────────────────────────────────────────────
  /// A durable outbox event supplies [activityId]: duplicate delivery is a
  /// no-op on the existing primary key, and other failures must stay
  /// retryable so the drain can hold the action open.
  static Future<void> logActivity({
    required String eventType,
    required String title,
    String? subtitle,
    String? fieldJobId,
    String? activityId,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = {
        'id': ?activityId,
        'inspector_id': userId,
        'field_job_id': fieldJobId,
        'event_type': eventType,
        'title': title,
        'subtitle': subtitle,
      };
      if (activityId == null) {
        await client.from('activity_log').insert(row);
      } else {
        // A durable action's event: repeat delivery is a no-op, any other
        // failure must propagate so the caller can retry it.
        await client
            .from('activity_log')
            .upsert(row, onConflict: 'id', ignoreDuplicates: true);
      }
    } catch (e) {
      if (activityId != null) rethrow;
      debugPrint('Error logging activity ($eventType): $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchRecentActivity({
    int limit = 10,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final response = await client
          .from('activity_log')
          .select()
          .eq('inspector_id', userId)
          .order('occurred_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching recent activity: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVITY READ TRACKING  (Notification bell)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<int> fetchUnreadActivityCount() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      final response = await client
          .from('activity_log')
          .select('id')
          .eq('inspector_id', userId)
          .eq('is_read', false);
      return (response as List).length;
    } catch (e) {
      debugPrint('Error fetching unread activity count: $e');
      return 0;
    }
  }

  static Future<void> markActivityRead(String activityId) async {
    try {
      await client
          .from('activity_log')
          .update({'is_read': true})
          .eq('id', activityId);
    } catch (e) {
      debugPrint('Error marking activity read: $e');
    }
  }

  static Future<void> markAllActivityRead() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client
          .from('activity_log')
          .update({'is_read': true})
          .eq('inspector_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Error marking all activity read: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DELETE ACTIVITY  (Notifications screen → swipe to delete)
  // Uses security-definer RPC to bypass RLS so the delete actually works.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> deleteActivity(String activityId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');
    // Direct delete scoped to this inspector — safe even with RLS
    try {
      await client
          .from('activity_log')
          .delete()
          .eq('id', activityId)
          .eq('inspector_id', userId);
    } catch (e) {
      // Fallback: try RPC if direct delete failed
      debugPrint('Direct delete failed, trying RPC fallback: $e');
      await client.rpc('delete_own_activity', params: {'p_id': activityId});
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLEAR ALL ACTIVITY  (Notifications screen → Clear All button)
  // Uses security-definer RPC to bypass RLS so the delete actually works.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> clearAllActivity() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');
    // Direct delete scoped to this inspector — safe even with RLS
    try {
      await client.from('activity_log').delete().eq('inspector_id', userId);
    } catch (e) {
      // Fallback: try RPC if direct delete failed
      debugPrint('Direct clear failed, trying RPC fallback: $e');
      await client.rpc('clear_own_activity');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH JOBS  (Tasks screen)
  //   FK hint: field_jobs.supabase_application_id → supabase_zoning_applications
  // ─────────────────────────────────────────────────────────────────────────
  // The address is optional presentation data, not a prerequisite for jobs.
  // Retry only a confirmed missing parcel-address column, never auth/network
  // failures or another field's schema error. Both reads retain owner filters.
  static Future<T> _withOptionalParcelAddress<T>(
    Future<T> Function(bool includeAddress) read,
  ) async {
    try {
      return await read(true);
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (!const ['42703', 'PGRST204'].contains(error.code) ||
          !message.contains('supabase_parcels') ||
          !message.contains('location_address')) {
        rethrow;
      }
      debugPrint(
        'Parcel address column unavailable; retrying without address.',
      );
      return read(false);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyJobs() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _withOptionalParcelAddress(
      (includeAddress) => client
          .from('field_jobs')
          .select('''
      id,
      local_inspection_id,
      inspection_round_number,
      previous_site_inspection_id,
      reinspection_reason,
      reinspection_reviewed_at,
      status,
      scheduled_date,
      deadline_date,
      is_self_scheduled,
      current_step,
      step_timestamps,
      rework_started_at,
      created_at,
      updated_at,
      started_at,
      submitted_at,
      supabase_parcel_id,
      supabase_application_id,
      bridge_source_id,
      assignment_instructions,
      assigned_by_imaps_user_id,
      assigned_by_name,
      supabase_zoning_applications!field_jobs_supabase_application_id_fkey (
        reference_number,
        applicant_name,
        barangay,
        application_type,
        purpose,
        contact_number,
        email
      ),
      supabase_parcels!field_jobs_supabase_parcel_id_fkey (
        lot_area_sqm,
        land_use_class,
        property_index_number,
        latitude,
        longitude${includeAddress ? ',location_address' : ''}
      ),
      field_job_reviews (
        id,
        technical_review_id,
        reviewed_site_inspection_id,
        decision,
        decision_reason,
        reviewed_by,
        reviewed_by_name,
        reviewed_at
      )
    ''')
          .eq('assigned_inspector_id', userId)
          .order('scheduled_date', ascending: true),
    );

    // Effective local presentation only: the remote row is not rewritten.
    // Both Tasks and Home Dashboard consume this same protected result.
    return DBHelper.projectPendingCompletions(
      List<Map<String, dynamic>>.from(response),
    );
  }

  static Future<String?> fetchJobUpdatedAt(String jobId) async {
    final response = await client
        .from('field_jobs')
        .select('updated_at')
        .eq('id', jobId)
        .single();
    final updatedAt = response['updated_at'];
    return updatedAt?.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH PARCEL DETAILS  (Parcel detail screen)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> fetchParcelDetails(
    String parcelId,
  ) async {
    try {
      final response = await client
          .from('supabase_parcels')
          .select()
          .eq('id', parcelId)
          .single();
      return response;
    } catch (e) {
      debugPrint('Error fetching parcel details: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCHEDULE / RESCHEDULE A JOB  (Tasks screen → a Pending, Scheduled or
  //   Ongoing card)
  //   Hard PO-deadline policy (MY_TASKS_FINAL_FLOW_SPEC_20261020 §3):
  //     today < Visit <= current verified PO deadline, all date-only.
  //     The earliest new Visit is tomorrow; the latest is the PO deadline.
  //     When the deadline is today or past, scheduling is closed.
  //   `pending` is schedulable: earlier scheduling writes set that state,
  //   so excluding it made every REPEAT reschedule a
  //   zero-row write that the authority check then refused. `completed` stays
  //   excluded, so a finished round can never be resurrected.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<InspectionAuthorityResult> scheduleJob({
    required String jobId,
    required DateTime date,
    DateTime? now,
    DateTime Function()? clock,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return InspectionAuthorityResult.authRequired;

    final visit = _localDay(date);
    final dateStr = _formatLocalDay(visit);

    // The PO deadline is the Planning Officer's to change, so it is read from
    // the server row — never from the card the inspector is looking at.
    final Map<String, dynamic>? current;
    try {
      current = await _readOwnedJob(jobId, uid);
    } catch (_) {
      if (_sessionUid != uid) return InspectionAuthorityResult.authRequired;
      return InspectionAuthorityResult.offlineOrUnverifiable;
    }
    if (_sessionUid != uid) return InspectionAuthorityResult.authRequired;
    if (current == null) return InspectionAuthorityResult.notAssignedOrUnavailable;

    final status = current['status'];
    if (!kSchedulableTaskStatuses.contains(status)) {
      return InspectionAuthorityResult.notAssignedOrUnavailable;
    }
    final deadline = parseLocalCalendarDate(current['deadline_date']);
    if (deadline == null) return InspectionAuthorityResult.deadlineUnavailable;
    // A slow read may cross midnight. Validate the dispatch day's window, not
    // the day on which the inspector opened or confirmed the picker.
    final today = _localDay(clock?.call() ?? now ?? DateTime.now());
    if (!deadline.isAfter(today)) return InspectionAuthorityResult.deadlinePassed;
    if (!visit.isAfter(today)) return InspectionAuthorityResult.visitDateNotAllowed;
    if (visit.isAfter(deadline)) return InspectionAuthorityResult.visitDateNotAllowed;

    final payload = <String, dynamic>{
      // Do not downgrade started rows or race a concurrent start/completion.
      // The committed Visit determines Scheduled presentation, not raw status.
      'scheduled_date': dateStr,
      'is_self_scheduled': true,
    };

    final result = await _writeWithAuthority(
      jobId,
      (uid) => client
          .from('field_jobs')
          .update(payload)
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .inFilter('status', kSchedulableTaskStatuses)
          // Re-checked against the server row at write time: the visit may
          // never be later than the PO deadline, so a deadline the PO
          // shortened since the card was drawn cannot be crossed.
          .gte('deadline_date', dateStr)
          .select()
          .retry(enabled: false),
      satisfied: (row) {
        final actualDeadline = parseLocalCalendarDate(row['deadline_date']);
        return row['scheduled_date'] == dateStr &&
            row['is_self_scheduled'] == true &&
            kSchedulableTaskStatuses.contains(row['status']) &&
            actualDeadline != null && actualDeadline.isAfter(today) &&
            !visit.isAfter(actualDeadline);
      },
    );
    if (_sessionUid != uid) return InspectionAuthorityResult.authRequired;
    if (result != InspectionAuthorityResult.offlineOrUnverifiable) return result;

    // A zero-row write is never success: name the real reason instead of
    // blaming the network.
    return _explainScheduleRefusal(jobId, uid, today, visit);
  }

  /// The current owner-scoped row, or null when this inspector cannot see it.
  static Future<Map<String, dynamic>?> _readOwnedJob(
    String jobId,
    String uid,
  ) async {
    final row = await client
        .from('field_jobs')
          .select(
            'id,status,deadline_date,scheduled_date,is_self_scheduled,assigned_inspector_id')
        .eq('id', jobId)
        .eq('assigned_inspector_id', uid)
        .maybeSingle()
        .retry(enabled: false)
        .timeout(const Duration(seconds: 10));
    if (row == null) return null;
    if (row['id'] != jobId || row['assigned_inspector_id'] != uid) return null;
    return row;
  }

  /// Explains a refused schedule write with the reason that actually applies.
  static Future<InspectionAuthorityResult> _explainScheduleRefusal(
    String jobId,
    String uid,
    DateTime today,
    DateTime visit,
  ) async {
    Map<String, dynamic>? row;
    try {
      row = await _readOwnedJob(jobId, uid);
    } catch (_) {
      if (_sessionUid != uid) return InspectionAuthorityResult.authRequired;
      return InspectionAuthorityResult.offlineOrUnverifiable;
    }
    if (_sessionUid != uid) return InspectionAuthorityResult.authRequired;
    if (row == null) return InspectionAuthorityResult.notAssignedOrUnavailable;
    final status = row['status'];
    if (!kSchedulableTaskStatuses.contains(status)) {
      return InspectionAuthorityResult.notAssignedOrUnavailable;
    }
    final deadline = parseLocalCalendarDate(row['deadline_date']);
    if (deadline == null) return InspectionAuthorityResult.deadlineUnavailable;
    if (!deadline.isAfter(today)) return InspectionAuthorityResult.deadlinePassed;
    if (!visit.isAfter(today) || visit.isAfter(deadline)) {
      return InspectionAuthorityResult.visitDateNotAllowed;
    }
    return InspectionAuthorityResult.offlineOrUnverifiable;
  }

  /// A calendar day in the device's local time, with the time of day dropped.
  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// `YYYY-MM-DD` for a local calendar day.
  static String _formatLocalDay(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────────────────
  // GPS DISTANCE CHECK  (GPS verification screen)
  //   Calls the distance_to_parcel_boundary() RPC — supabase_parcels.geom is
  //   a Point (confirmed via ST_GeometryType), so this returns straight-line
  //   distance in meters to the parcel's declared pin, and 0 only when the
  //   device is at that exact point.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<double> getDistanceToParcelBoundary({
    required String parcelId,
    required double latitude,
    required double longitude,
  }) async {
    final result = await client.rpc(
      'distance_to_parcel_boundary',
      params: {'parcel_id': parcelId, 'lat': latitude, 'lng': longitude},
    );
    return (result as num).toDouble();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MARK JOB ONGOING  (Exit-confirm gate → Step 1/2, before anything else
  //   would naturally flip status). Only moves 'assigned' -> 'in_progress'
  //   so the task shows under "Ongoing" once the inspector has opened it
  //   and stepped away, without clobbering a status a later step already set.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<InspectionAuthorityResult> markJobOngoing(String jobId) =>
      _writeWithAuthority(
        jobId,
        (uid) => client
            .from('field_jobs')
            .update({
              'status': 'in_progress',
              'started_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', jobId)
            .eq('assigned_inspector_id', uid)
            .inFilter('status', kStartableTaskStatuses)
            .select()
            .retry(enabled: false),
        satisfied: (row) =>
            (row['status'] == 'in_progress' && row['started_at'] != null) ||
            (row['status'] == 'completed' &&
                row['current_step'] == 6 &&
                row['submitted_at'] != null),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRM GPS ON-SITE  (GPS verification screen → marks job in_progress)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> confirmGpsOnSite({
    required String jobId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? locationLabel,
  }) async {
    try {
      final confirmedAt = DateTime.now().toUtc().toIso8601String();
      // GPS is evidence. It may be corrected during completed-task rework,
      // but must never carry a lifecycle assignment that reopens the job.
      final evidence = await _writeWithAuthority(
        jobId,
        (uid) => client
            .from('field_jobs')
            .update({
              'confirmed_latitude': latitude,
              'confirmed_longitude': longitude,
              'gps_accuracy_m': accuracyMeters,
              'gps_confirmed_at': confirmedAt,
            })
            .eq('id', jobId)
            .eq('assigned_inspector_id', uid)
            .select()
            .retry(enabled: false),
      );
      evidence.requireAuthorized();
      (await markJobOngoing(jobId)).requireAuthorized();
      await logActivity(
        eventType: 'gps_confirmed',
        title: 'GPS verified on-site',
        subtitle: locationLabel,
        fieldJobId: jobId,
      );
    } catch (e) {
      debugPrint('Error confirming GPS on site: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UPLOAD INSPECTION PHOTOS  (Review & submit screen → runs before submit)
  //   Uploads each locally-captured photo to the inspection-photos bucket
  //   and returns the raw durable Storage object paths to store in
  //   field_jobs.photo_paths for new writes.
  //   Local device paths (e.g. /data/user/0/.../inspection_xxx.jpg) only
  //   exist on the phone that took them — they must never be written to
  //   the DB as-is, since they're meaningless on any other device/session.
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // UPLOAD INSPECTION PHOTOS  (Review & submit screen, online path)
  //   Local device paths lang ang meron dito — i-upload sa Storage at
  //   ibalik ang raw durable paths para hindi mawala kapag na-clear ang cache
  //   ng device. Existing historical URLs are preserved on resume.
  //   Existing historical URLs are preserved on resume.
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // UPLOAD INSPECTION PHOTOS & STORE METADATA
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // IDEMPOTENCY FIX (Phase 1, Bahagi A — Sync Center audit)
  //   Dating bug: bagong random UUID filename bawat tawag → kapag na-retry
  //   ang isang na-fail na submit_inspection action, muling na-a-upload ang
  //   mga photo na successful na dati (duplicate sa Storage bucket AT sa
  //   field_job_photos table).
  //
  //   Fix: kunin ang storage path/photo-id mula sa LOCAL FILE PATH mismo
  //   (deterministic — parehong path, parehong id, sa bawat retry) sa
  //   halip na bagong Uuid().v4() bawat call. Storage upload gamit ang
  //   upsert:true (overwrite, hindi duplicate object), at field_job_photos
  //   row gamit ang .upsert() sa deterministic id (hindi .insert()) kaya
  //   parehong row lang ang ma-a-apektuhan sa bawat retry — walang bagong
  //   duplicate row. The legacy local_photos adapter is routed through this
  //   same canonical writer; it no longer creates a competing identity.
  // ─────────────────────────────────────────────────────────────────────────
  static Map<String, dynamic> photoUploadPayloadFromLegacyLocalRow(
    Map<String, dynamic> row,
  ) {
    return {
      'photoPath': row['photo_path'],
      'notes': row['notes'],
      'latitude': row['latitude'],
      'longitude': row['longitude'],
      'capturedAt': row['captured_at'],
    };
  }

  static String _stablePhotoKey(String localPath) {
    // Deterministic, filesystem/URL-safe key derived from the photo's own
    // local path — same file will always produce the same key, kahit
    // ilang beses pang ma-retry ang parehong submit_inspection action.
    final bytes = utf8.encode(localPath);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Best-effort cleanup of one photo that was already synced to Supabase —
  /// added alongside the new "remove photo" feature on the Photos step.
  /// Derives the exact same storage path / row id that
  /// `uploadInspectionPhotos()` would have used for this local file (same
  /// `_stablePhotoKey()` + Uuid v5 scheme), so it targets precisely the
  /// object this photo would have created, nothing else. Safe to call even
  /// if the photo was never actually uploaded (e.g. removed before ever
  /// going online) — storage/table deletes on a non-existent object are
  /// no-ops, not errors, so this doesn't need to know sync status upfront.
  static Future<void> deleteInspectionPhoto({
    required String jobId,
    required String localPath,
  }) async {
    final photoKey = _stablePhotoKey(localPath);
    final storagePath = 'inspections/$jobId/photo_$photoKey.jpg';
    const namespaceUrl = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';
    final rowId = const Uuid().v5(namespaceUrl, storagePath);
    try {
      await client.storage.from('inspection-photos').remove([storagePath]);
    } catch (e) {
      debugPrint('deleteInspectionPhoto: storage remove skipped — $e');
    }
    try {
      await client.from('field_job_photos').delete().eq('id', rowId);
    } catch (e) {
      debugPrint('deleteInspectionPhoto: row delete skipped — $e');
    }
  }

  /// Exact metadata contract consumed by the unchanged iMAPS PO reader
  /// (`field_job_photos`: photo_url + latitude/longitude/captured_at/notes).
  @visibleForTesting
  static Map<String, dynamic> inspectionPhotoMetadataRow({
    required String rowId,
    required String jobId,
    required String photoUrl,
    required Map<String, dynamic> photo,
  }) => {
    'id': rowId,
    'field_job_id': jobId,
    'photo_url': photoUrl,
    'latitude': photo['latitude'],
    'longitude': photo['longitude'],
    'captured_at': photo['capturedAt'],
    'notes': photo['notes'],
  };

  static Future<List<String>> uploadInspectionPhotos({
    required String jobId,
    required List<Map<String, dynamic>>
    photosData, // Changed from List<String> localPaths
    void Function(int photoIndex, int photoTotal)? onProgress,
  }) async {
    // Session identity is captured here and demanded at each write point, so
    // a queued action with nothing to upload still replays under a session that
    // was proven current when the drain began.
    final uid = _sessionUid;
    final List<String> uploadedUrls = [];
    final List<String> failedPaths = [];

    // ─────────────────────────────────────────────────────────────────
    // PHOTO UPLOAD RESUME (Phase 4)
    //   Idempotency (Phase 1) already made retries *safe* — a retry never
    //   creates a duplicate row/object. But it still re-uploaded every
    //   photo's bytes from scratch on every retry, even ones that fully
    //   succeeded on a prior attempt. On a flaky field connection where a
    //   10-photo submit dies at photo #7, that means re-transferring 6
    //   already-good photos every time, instead of resuming from #7.
    //
    //   Fix: compute each photo's deterministic rowId up front, batch-check
    //   which ones already have a field_job_photos row, then verify the exact
    //   canonical object before reusing that identity. A missing object is
    //   repaired with the same path; an UNKNOWN check remains retryable.
    //   New writes use the raw durable object path; existing historical values
    //   are preserved.
    // ─────────────────────────────────────────────────────────────────
    final Map<String, String> pathToStoragePath = {};
    final Map<String, String> pathToRowId = {};
    for (final photo in photosData) {
      final path = photo['photoPath'] as String?;
      if (path == null) continue;
      final photoKey = _stablePhotoKey(path);
      final storagePath = 'inspections/$jobId/photo_$photoKey.jpg';
      final rowId = const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        storagePath,
      );
      pathToStoragePath[path] = storagePath;
      pathToRowId[path] = rowId;
    }

    final Map<String, String> existingPhotoValues = {};
    if (pathToRowId.isNotEmpty) {
      try {
        // PostgREST encodes an `in.(...)` list into the request URL, so one
        // filter with every photo id overflows URL limits at large sets.
        // Chunk it; an unknown chunk still fails the whole pre-check and
        // remains retryable rather than being treated as absent.
        const metadataChunkSize = 50;
        final rowIds = pathToRowId.values.toList();
        for (var start = 0; start < rowIds.length; start += metadataChunkSize) {
          final chunk = rowIds.skip(start).take(metadataChunkSize).toList();
          final existing = await client
              .from('field_job_photos')
              .select('id,photo_url')
              .eq('field_job_id', jobId)
              .inFilter('id', chunk);
          for (final row in existing as List) {
            final map = row as Map;
            final id = map['id'];
            final value = map['photo_url'];
            if (id is String && value is String && value.isNotEmpty) {
              existingPhotoValues[id] = value;
            }
          }
        }
      } catch (e) {
        final result = _authorityFailure(e);
        if (result != InspectionAuthorityResult.offlineOrUnverifiable) {
          throw InspectionAuthorityException(result);
        }
        // An unknown metadata lookup is retryable. Never treat it as an
        // absent row: doing so could rewrite a historical stored value.
        throw PhotoRecoveryUnknownException(
          'Photo metadata could not be verified. Your local work is preserved.',
        );
      }
    }

    final int photoTotal = photosData.length;
    for (var i = 0; i < photosData.length; i++) {
      final photo = photosData[i];
      final path = photo['photoPath'] as String; // Extract path from the map
      try {
        // FIX (Completed/Rework audit, Finding 1): a photo rehydrated by
        // InspectionProvider.hydrateForRework() has `photoPath` set to its
        // already-uploaded remote URL, not a local device path — reusing
        // it directly here instead of falling through to the local-file
        // logic below, which would derive a resume-check key from the URL
        // string (never matching the row created from the *original*
        // local path), then fail File(path).exists() and silently drop
        // the photo from the resubmission with no error surfaced at all.
        if (photo['isRemoteUrl'] == true) {
          final objectPath = extractStorageObjectPath(path);
          if (objectPath == null || objectPath.split('/')[1] != jobId) {
            throw StateError('Remote photo identity is not a canonical object');
          }
          final objectState = await photoObjectState(objectPath);
          if (objectState == PhotoObjectState.unknown) {
            throw PhotoRecoveryUnknownException(
              'Remote photo object existence is unknown for $objectPath',
            );
          }
          if (objectState == PhotoObjectState.missing) {
            throw StateError('Remote photo object is missing for $objectPath');
          }
          final rowId = photoRowId(objectPath);
          final existing = await client
              .from('field_job_photos')
              .select('id,photo_url')
              .eq('id', rowId)
              .eq('field_job_id', jobId)
              .maybeSingle();
          if (existing == null || existing['photo_url'] is! String) {
            _requireSession(uid);
            await client.from('field_job_photos').upsert(
              inspectionPhotoMetadataRow(
                rowId: rowId,
                jobId: jobId,
                photoUrl: objectPath,
                photo: photo,
              ),
              onConflict: 'id',
            );
            uploadedUrls.add(objectPath);
          } else {
            uploadedUrls.add(existing['photo_url'] as String);
          }
          onProgress?.call(i + 1, photoTotal);
          continue;
        }

        final storagePath = pathToStoragePath[path];
        final rowId = pathToRowId[path];
        if (storagePath == null || rowId == null) continue;

        final objectState = await photoObjectState(storagePath);
        if (objectState == PhotoObjectState.unknown) {
          throw PhotoRecoveryUnknownException(
            'Photo object existence is unknown for $storagePath',
          );
        }

        final file = File(path);
        final fileExists = await file.exists();
        final metadataExists = existingPhotoValues.containsKey(rowId);
        if (objectState == PhotoObjectState.missing && !fileExists) {
          throw StateError('Missing photo object and local source');
        }
        if (objectState == PhotoObjectState.missing) {
          // Repair the same canonical object; never create a second identity.
          _requireSession(uid);
          await client.storage
              .from('inspection-photos')
              .upload(
                storagePath,
                file,
                fileOptions: const FileOptions(
                  cacheControl: '3600',
                  upsert: true,
                ),
              );
        }

        onProgress?.call(i + 1, photoTotal);
        uploadedUrls.add(existingPhotoValues[rowId] ?? storagePath);

        // Only repair metadata when the deterministic metadata identity is
        // absent. Existing historical rows keep their stored URL/values.
        if (!metadataExists) {
          _requireSession(uid);
          // 2. Upsert (not insert) metadata into field_job_photos, keyed by
          //    the same deterministic id derived from the photo's storage
          //    path. A retry updates this one row in place — it never adds
          //    a second row for a photo that already synced.
          await client.from('field_job_photos').upsert(
            inspectionPhotoMetadataRow(
              rowId: rowId,
              jobId: jobId,
              photoUrl: storagePath,
              photo: photo,
            ),
            onConflict: 'id',
          );
        }
      } catch (e) {
        debugPrint('Error uploading photo $path: $e');
        final result = _authorityFailure(e);
        if (result != InspectionAuthorityResult.offlineOrUnverifiable) {
          throw InspectionAuthorityException(result);
        }
        failedPaths.add(path);
      }
    }

    if (failedPaths.isNotEmpty) {
      throw Exception(
        '${failedPaths.length} of ${photosData.length} photo(s) failed to upload. '
        'Your local evidence is preserved. Review the photo evidence and retry.',
      );
    }
    _requireSession(uid);
    return uploadedUrls;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMIT INSPECTION  (Review & submit screen → marks job completed)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<InspectionAuthorityResult> submitInspection({
    required String jobId,
    required String findings,
    required bool isCompliant,
    required String inspectionResult,
    String? observations,
    String? discrepancies,
    String? recommendations,
    String? inspectorNotes,
    List<Map<String, dynamic>>? checklistData,
    int checklistCompletedCount = 0,
    int checklistTotalCount = 0,
    List<String>? photoPaths,
    int photoCount = 0,
    String? locationLabel,
    String? submittedAt,
    String? activityId,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return InspectionAuthorityResult.authRequired;
    try {
      // Preserve the first successful submission time. A final-submit retry or
      // completed-task evidence correction must not replace that lifecycle
      // boundary with a newer timestamp.
      final existing = await client
          .from('field_jobs')
          .select()
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .maybeSingle()
          .retry(enabled: false)
          .timeout(const Duration(seconds: 10));
      if (client.auth.currentUser?.id != uid) {
        return InspectionAuthorityResult.authRequired;
      }
      if (existing == null) {
        return InspectionAuthorityResult.notAssignedOrUnavailable;
      }
      if (existing['id'] != jobId || existing['assigned_inspector_id'] != uid) {
        return InspectionAuthorityResult.offlineOrUnverifiable;
      }
      final existingSubmittedAt = existing['submitted_at']?.toString();
      final effectiveSubmittedAt =
          existingSubmittedAt ??
          submittedAt ??
          DateTime.now().toUtc().toIso8601String();
      final evidence = <String, dynamic>{
        'findings': findings,
        'is_compliant': isCompliant,
        'inspection_result': inspectionResult,
        'observations': observations,
        'discrepancies': discrepancies,
        'recommendations': recommendations,
        'inspector_notes': inspectorNotes,
        'checklist_data': checklistData,
        'checklist_completed_count': checklistCompletedCount,
        'checklist_total_count': checklistTotalCount,
        'photo_paths': photoPaths,
        'photo_count': photoCount,
      };
      bool satisfied(Map<String, dynamic> row) =>
          row['status'] == 'completed' &&
          row['current_step'] == 6 &&
          row['submitted_at'] != null &&
          row['rework_started_at'] == null &&
          evidence.entries.every(
            (entry) =>
                row.containsKey(entry.key) &&
                sameInspectionEvidence(row[entry.key], entry.value),
          );
      // An authoritative receipt of this complete evidence is already enough.
      // Do not repeat the business mutation or invent another completion event.
      if (satisfied(existing)) return InspectionAuthorityResult.authorized;
      final result = await _writeWithAuthority(
        jobId,
        (owner) => client
            .from('field_jobs')
            .update({
              'status': 'completed',
              'current_step': 6,
              ...evidence,
              'submitted_at': effectiveSubmittedAt,
              // Rework redesign: Review & Submit is the one finalize point,
              // for both a normal submit (already null — harmless) and a
              // rework resubmit (clears the "Modified" signal). status was
              // already 'completed' the whole time it was being reworked,
              // so this update is really "confirm the new revision," not
              // "close out an in-progress task."
              'rework_started_at': null,
            })
            .eq('id', jobId)
            .eq('assigned_inspector_id', owner)
            .select()
            .retry(enabled: false),
        satisfied: satisfied,
      );
      if (result != InspectionAuthorityResult.authorized) return result;
      try {
        await logActivity(
          eventType: 'inspection_completed',
          title: 'Inspection completed',
          subtitle: locationLabel,
          fieldJobId: jobId,
          activityId: activityId,
        );
      } catch (_) {
        debugPrint('Completion accepted; activity delivery unverified.');
      }
      return result;
    } catch (e) {
      return _authorityFailure(e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH FULL JOB DETAIL  (Completed inspection detail / rework screen)
  //   fetchMyJobs() only selects the columns the Tasks list needs — this
  //   pulls everything else (findings, observations, discrepancies,
  //   recommendations, checklist_data, photo_paths, GPS confirmation, etc.)
  //   for the one job the inspector is actually opening.
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // FETCH FULL JOB DETAIL
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> fetchJobDetail(String jobId) async {
    try {
      // Security hardening (RLS audit, 2026-07): this used to fetch by
      // `id` alone, relying entirely on the "Inspectors can view their
      // own assigned jobs" RLS policy to prevent one inspector from
      // opening another inspector's job. That policy was being silently
      // overridden by a separate, overly broad "Enable read access for
      // all users" policy (USING (true), no role restriction) — Postgres
      // ORs permissive RLS policies together, so the open one won, and
      // ANY caller (even unauthenticated, via just the anon key) could
      // read any job by id. The open policy has been dropped in
      // migration_fix_field_jobs_rls.sql; this explicit filter is
      // defense-in-depth so this query is correctly scoped even if RLS
      // is ever misconfigured again — matching the same pattern already
      // used in fetchMyJobs() and fetchCompletedJobs() above.
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;
      final response = await _withOptionalParcelAddress(
        (includeAddress) => client
            .from('field_jobs')
            .select('''
            *,
            supabase_zoning_applications!field_jobs_supabase_application_id_fkey (
              reference_number,
              applicant_name,
              barangay,
              contact_number,
              email
            ),
            supabase_parcels!field_jobs_supabase_parcel_id_fkey (
              lot_area_sqm,
              land_use_class,
              property_index_number,
              latitude,
              longitude${includeAddress ? ',location_address' : ''}
            ),
            field_job_photos (
              id,
              photo_url,
              latitude,
              longitude,
              captured_at,
              notes
            ),
            field_job_reviews (
              id,
              technical_review_id,
              reviewed_site_inspection_id,
              decision,
              decision_reason,
              reviewed_by,
              reviewed_by_name,
              reviewed_at
            )
          ''') // Added field_job_photos to the select query
            .eq('id', jobId)
            .eq('assigned_inspector_id', userId)
            .single(),
      );
      return response;
    } catch (e) {
      debugPrint('Error fetching job detail: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OPEN A COMPLETED JOB FOR REWORK  (Completed detail screen → "Rework")
  //   This is an evidence-editing session only. Lifecycle, Step 6 and the
  //   original submission timestamp remain terminal and unchanged.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> reopenForRework({
    required String jobId,
    String? locationLabel,
  }) async {
    try {
      // Issue 2 fix (device-test finding): this used to write
      // rework_started_at right here, immediately on entry — meaning
      // opening a step for rework and backing out without changing
      // anything still showed a "Modified" badge. The write now happens
      // lazily, on the first actual edit (see
      // InspectionProvider._markReworkModifiedIfNeeded), not on entry.
      // Still worth confirming the job is actually completed before
      // allowing entry. Opening a step is read-only: the marker transition
      // owns the meaningful rework event, so revisits cannot spam it.
      final uid = _sessionUid;
      _requireSession(uid);
      final row = await client
          .from('field_jobs')
          .select('status')
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid!)
          .maybeSingle();
      _requireSession(uid);
      final status = row?['status'] as String?;
      if (status?.toLowerCase() != 'completed') {
        throw Exception('Job is not completed — cannot reopen for rework.');
      }
    } catch (e) {
      debugPrint('Error reopening job for rework: $e');
      rethrow;
    }
  }

  /// Preserve the first modification marker. Only its NULL → timestamp
  /// transition emits rework activity, never opening or refreshing a summary.
  /// Never touches `status`, `current_step` or `submitted_at`.
  /// Returns this mutation's accepted revision, or null when the marker is
  /// authoritatively already satisfied. Every unsuccessful mutation throws.
  static Future<String?> markReworkModified({
    required String jobId,
    String? locationLabel,
    String? expectedUpdatedAt,
  }) async {
    final uid = _sessionUid;
    _requireSession(uid);
    final marker = DateTime.now().toUtc().toIso8601String();
    var transitioned = false;
    Map<String, dynamic>? accepted;
    final result = await _writeWithAuthority(
      jobId,
      (uid) async {
        var update = client
            .from('field_jobs')
            .update({'rework_started_at': marker})
            .eq('id', jobId)
            .eq('assigned_inspector_id', uid)
            .eq('status', 'completed')
            .isFilter('rework_started_at', null);
        if (expectedUpdatedAt != null) {
          update = update.eq('updated_at', expectedUpdatedAt);
        }
        final rows = await update
            .select()
            .retry(enabled: false)
            .timeout(const Duration(seconds: 10));
        transitioned = rows.length == 1;
        return rows;
      },
      satisfied: (row) {
        final satisfied =
            row['status'] == 'completed' && row['rework_started_at'] != null;
        if (satisfied) accepted = row;
        return satisfied;
      },
    );
    if (result != InspectionAuthorityResult.authorized) {
      // A lost response is not success by itself. A fresh owned-job read can
      // prove the marker landed; otherwise preserve the explicit failure.
      final row = await readOutboxRecoveryJob(jobId);
      _requireSession(uid);
      if (row == null ||
          row['assigned_inspector_id'] != uid ||
          row['status'] != 'completed' ||
          row['rework_started_at'] == null) {
        result.requireAuthorized();
      }
      accepted = row;
      final landedMarker = row!['rework_started_at'];
      transitioned =
          landedMarker is String &&
          DateTime.tryParse(
                landedMarker,
              )?.isAtSameMomentAs(DateTime.parse(marker)) ==
              true;
    }
    if (!transitioned) return null;
    final revision = accepted?['updated_at'];
    if (revision is! String || DateTime.tryParse(revision) == null) {
      throw const InspectionAuthorityException(
        InspectionAuthorityResult.offlineOrUnverifiable,
      );
    }
    try {
      await logActivity(
        eventType: 'rework_started',
        title: 'Reopened for rework',
        subtitle: locationLabel,
        fieldJobId: jobId,
        activityId: const Uuid().v5(
          '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
          'rework_started:$jobId:$marker',
        ),
      );
    } catch (e) {
      debugPrint('Error logging rework activity: $e');
    }
    return revision;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERIC PARTIAL UPDATE  (checklist progress, photo upload count, etc.)
  // ─────────────────────────────────────────────────────────────────────────
  static const Set<String> _forbiddenProgressFields = {
    'status',
    'current_step',
    'submitted_at',
  };

  static Future<void> updateJobInspectionProgress({
    required String jobId,
    required Map<String, dynamic> updateData,
  }) async {
    final forbidden = updateData.keys.toSet().intersection(
      _forbiddenProgressFields,
    );
    if (forbidden.isNotEmpty) {
      throw ArgumentError(
        'Lifecycle/progress fields require a monotonic domain method: $forbidden',
      );
    }
    try {
      final result = await _writeWithAuthority(
        jobId,
        (uid) => client
            .from('field_jobs')
            .update(updateData)
            .eq('id', jobId)
            .eq('assigned_inspector_id', uid)
            .select()
            .retry(enabled: false),
      );
      result.requireAuthorized();
    } catch (e) {
      debugPrint('Error updating field job: $e');
      rethrow;
    }
  }

  /// Result of a timestamp-only write.
  /// Records the real completion time of an inspection step without touching
  /// `current_step`, the task status or any submitted evidence.
  ///
  /// [advanceJobInspectionProgress] can only update a row whose
  /// `current_step` is still below the requested step, so a step that is
  /// completed after a later one (the independent steps 3, 4 and 5) can
  /// never carry its own time to the server: the write matches no row and
  /// the "already at this step" condition is accepted as success. This
  /// writes that one column through the existing authority-checked partial
  /// update, which explicitly forbids the lifecycle fields, so
  /// `current_step` can never move backward.
  ///
  /// The stored map is merged, never replaced: times another writer already
  /// stored are kept, and only the steps this device recorded are added. A
  /// failed write throws, so the caller never reports a false receipt.
  static Future<StepTimestampWriteOutcome> recordStepTimestamps({
    required String jobId,
    required Map<String, String> stepTimestamps,
  }) async {
    if (stepTimestamps.isEmpty) {
      return StepTimestampWriteOutcome.alreadyPresent;
    }
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Authenticated inspector required');
    }
    final row = await client
        .from('field_jobs')
        .select('id,assigned_inspector_id,status,current_step,step_timestamps')
        .eq('id', jobId)
        .eq('assigned_inspector_id', uid)
        .maybeSingle()
        .retry(enabled: false)
        .timeout(const Duration(seconds: 10));
    if (client.auth.currentUser?.id != uid) {
      throw StateError('Session changed while recording step times');
    }
    if (row == null ||
        row['id'] != jobId ||
        row['assigned_inspector_id'] != uid) {
      throw StateError('Inspection is not available to this inspector');
    }
    final stored = <String, String>{};
    final raw = row['step_timestamps'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is String && value.isNotEmpty) {
          stored[key.toString()] = value;
        }
      });
    }
    final merged = <String, String>{...stored, ...stepTimestamps};
    if (merged.length == stored.length &&
        stored.keys.every((key) => merged[key] == stored[key])) {
      return StepTimestampWriteOutcome.alreadyPresent;
    }
    await updateJobInspectionProgress(
      jobId: jobId,
      updateData: {'step_timestamps': merged},
    );
    return StepTimestampWriteOutcome.written;
  }

  /// Advances ordinary inspection progress without ever lowering it or
  /// changing the terminal Step 6 of a completed job.
  static Future<InspectionAuthorityResult> advanceJobInspectionProgress({
    required String jobId,
    required int currentStep,
    Map<String, String>? stepTimestamps,
  }) async {
    if (currentStep < 0 || currentStep > 6) {
      throw RangeError.range(currentStep, 0, 6, 'currentStep');
    }
    return _writeWithAuthority(
      jobId,
      (uid) => client
          .from('field_jobs')
          .update({
            'current_step': currentStep,
            'step_timestamps': ?stepTimestamps,
          })
          .eq('id', jobId)
          .eq('assigned_inspector_id', uid)
          .neq('status', 'completed')
          .lt('current_step', currentStep)
          .select()
          .retry(enabled: false),
      satisfied: (row) =>
          row['current_step'] is num &&
          row['current_step'] >= currentStep &&
          (row['status'] != 'completed' || row['current_step'] == 6),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET JOBS AS GEOJSON  (Site map screen)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getJobsAsGeoJson() async {
    try {
      final response = await client.rpc('get_jobs_as_geojson');
      if (response is Map<String, dynamic>) return response;
      // rpc may return a String on some client versions
      return {'type': 'FeatureCollection', 'features': []};
    } catch (e) {
      debugPrint('Error fetching GeoJSON: $e');
      return {'type': 'FeatureCollection', 'features': []};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH INSPECTION HISTORY  (completed jobs)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchCompletedJobs() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await client
        .from('field_jobs')
        .select('''
          id,
          local_inspection_id,
          inspection_round_number,
          previous_site_inspection_id,
          reinspection_reason,
          reinspection_reviewed_at,
          status,
          scheduled_date,
          submitted_at,
          inspection_result,
          is_compliant,
          supabase_application_id,
          bridge_source_id,
          supabase_zoning_applications!supabase_application_id (
            reference_number,
            applicant_name,
            barangay
          )
        ''')
        .eq('assigned_inspector_id', userId)
        .ilike('status', 'completed')
        .order('submitted_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH USER PROFILE
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> fetchMyProfile() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AVATAR UPLOAD  (Profile edit screen)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> uploadAvatar({
    required String userId,
    required File file,
  }) async {
    try {
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = '$userId/$fileName';

      await client.storage
          .from('avatars')
          .upload(
            storagePath,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      return client.storage.from('avatars').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint('Error uploading avatar: $e');
      return null;
    }
  }
}
