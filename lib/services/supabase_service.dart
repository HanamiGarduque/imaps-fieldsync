import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

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
  static Future<void> logActivity({
    required String eventType,
    required String title,
    String? subtitle,
    String? fieldJobId,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client.from('activity_log').insert({
        'inspector_id': userId,
        'field_job_id': fieldJobId,
        'event_type': eventType,
        'title': title,
        'subtitle': subtitle,
      });
    } catch (e) {
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
  static Future<List<Map<String, dynamic>>> fetchMyJobs() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await client
        .from('field_jobs')
        .select('''
      id,
      local_inspection_id,
      status,
      scheduled_date,
      deadline_date,
      is_self_scheduled,
      current_step,
      rework_started_at,
      created_at,
      updated_at,
      started_at,
      submitted_at,
      supabase_parcel_id,
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
        longitude
      )
    ''')
        .eq('assigned_inspector_id', userId)
        .order('scheduled_date', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  static Future<String?> fetchJobUpdatedAt(String jobId) async {
    final response = await client
        .from('field_jobs')
        .select('updated_at')
        .eq('id', jobId)
        .single();
    final updatedAt = response['updated_at'];
    return updatedAt == null ? null : updatedAt.toString();
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
  // SCHEDULE A PENDING JOB  (Tasks screen → long-press a Pending card)
  //   Inspector picks a specific future date (never past deadline_date,
  //   enforced both here and by the date picker's lastDate on the UI side).
  //   TaskItem.category treats any future scheduled_date as "Scheduled",
  //   so this alone is enough to move the card into that tab.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> scheduleJob({
    required String jobId,
    required DateTime date,
    String? note,
  }) async {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client
        .from('field_jobs')
        .update({
          'scheduled_date': dateStr,
          'is_self_scheduled': true,
          if (note != null && note.trim().isNotEmpty) 'remarks': note.trim(),
        })
        .eq('id', jobId);
  }

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
  static Future<bool> markJobOngoing(String jobId) async {
    try {
      await client
          .from('field_jobs')
          .update({'status': 'in_progress'})
          .eq('id', jobId)
          .not('status', 'ilike', 'completed');
      await client
          .from('field_jobs')
          .update({'started_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', jobId)
          .filter(
            'started_at',
            'is',
            null,
          ); // huwag lang i-touch kung completed na
      return true;
    } catch (e) {
      debugPrint('Error marking job ongoing: $e');
      return false;
    }
  }

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
      await client
          .from('field_jobs')
          .update({
            'status': 'in_progress',
            'confirmed_latitude': latitude,
            'confirmed_longitude': longitude,
            'gps_accuracy_m': accuracyMeters,
            'gps_confirmed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', jobId);
      await client
          .from('field_jobs')
          .update({'started_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', jobId)
          .filter('started_at', 'is', null); // only sets it the first time
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
  //   and returns the public URLs to store in field_jobs.photo_paths.
  //   Local device paths (e.g. /data/user/0/.../inspection_xxx.jpg) only
  //   exist on the phone that took them — they must never be written to
  //   the DB as-is, since they're meaningless on any other device/session.
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // UPLOAD INSPECTION PHOTOS  (Review & submit screen, online path)
  //   Local device paths lang ang meron dito — i-upload sa Storage at
  //   ibalik ang public URLs para hindi mawala kapag na-clear ang cache
  //   ng device. Parehong bucket/path convention gaya ng
  //   InspectionProvider.syncToServer para compatible ang dalawang path.
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
  //   duplicate row. Kapareho ito ng pattern na ginagamit na sa
  //   InspectionProvider.syncToServer() (photo_${photo['id']}.jpg +
  //   upsert), para consistent ang dalawang code path.
  // ─────────────────────────────────────────────────────────────────────────
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
    final rowId = const Uuid().v5(Uuid.NAMESPACE_URL, storagePath);
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

  static Future<List<String>> uploadInspectionPhotos({
    required String jobId,
    required List<Map<String, dynamic>>
    photosData, // Changed from List<String> localPaths
    void Function(int photoIndex, int photoTotal)? onProgress,
  }) async {
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
    //   which ones already have a field_job_photos row (i.e. already fully
    //   uploaded), and skip the storage upload + row upsert entirely for
    //   those — just reuse the known public URL. Only photos not yet in
    //   that set actually transfer bytes this attempt.
    // ─────────────────────────────────────────────────────────────────
    final Map<String, String> pathToStoragePath = {};
    final Map<String, String> pathToRowId = {};
    for (final photo in photosData) {
      final path = photo['photoPath'] as String?;
      if (path == null) continue;
      final photoKey = _stablePhotoKey(path);
      final storagePath = 'inspections/$jobId/photo_$photoKey.jpg';
      final rowId = const Uuid().v5(Uuid.NAMESPACE_URL, storagePath);
      pathToStoragePath[path] = storagePath;
      pathToRowId[path] = rowId;
    }

    Set<String> alreadyUploadedRowIds = {};
    if (pathToRowId.isNotEmpty) {
      try {
        final existing = await client
            .from('field_job_photos')
            .select('id')
            .eq('field_job_id', jobId)
            .inFilter('id', pathToRowId.values.toList());
        alreadyUploadedRowIds = (existing as List)
            .map((row) => (row as Map)['id'] as String)
            .toSet();
      } catch (e) {
        // If the check itself fails (e.g. offline mid-retry), fall back to
        // the old safe-but-not-resumable behavior: treat nothing as
        // already uploaded, so every photo is attempted this pass. Still
        // correct (idempotent), just not optimized for this one attempt.
        debugPrint('Photo resume check failed, uploading all: $e');
        alreadyUploadedRowIds = {};
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
          onProgress?.call(i + 1, photoTotal);
          uploadedUrls.add(path);
          continue;
        }

        final storagePath = pathToStoragePath[path];
        final rowId = pathToRowId[path];
        if (storagePath == null || rowId == null) continue;

        if (alreadyUploadedRowIds.contains(rowId)) {
          // Already fully uploaded in a previous attempt — skip re-sending
          // the file bytes, just reuse the existing public URL. Still
          // reported to onProgress so "photo X of Y" reflects the whole
          // batch, not just the ones actually transferred this pass.
          onProgress?.call(i + 1, photoTotal);
          uploadedUrls.add(
            client.storage.from('inspection-photos').getPublicUrl(storagePath),
          );
          continue;
        }

        final file = File(path);
        if (!await file.exists()) continue;

        onProgress?.call(i + 1, photoTotal);

        // 1. Upload to Supabase Storage — upsert:true means a retry
        //    overwrites the SAME storage object instead of creating a new
        //    one under a new random name.
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

        final publicUrl = client.storage
            .from('inspection-photos')
            .getPublicUrl(storagePath);
        uploadedUrls.add(publicUrl);

        // 2. Upsert (not insert) metadata into field_job_photos, keyed by
        //    the same deterministic id derived from the photo's storage
        //    path. A retry updates this one row in place — it never adds
        //    a second row for a photo that already synced.
        await client.from('field_job_photos').upsert({
          'id': rowId,
          'field_job_id': jobId,
          'photo_url': publicUrl,
          'latitude': photo['latitude'],
          'longitude': photo['longitude'],
          'captured_at': photo['capturedAt'],
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('Error uploading photo $path: $e');
        failedPaths.add(path);
      }
    }

    if (failedPaths.isNotEmpty) {
      throw Exception(
        '${failedPaths.length} of ${photosData.length} photo(s) failed to upload. '
        'Check your connection and try submitting again.',
      );
    }
    return uploadedUrls;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMIT INSPECTION  (Review & submit screen → marks job completed)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> submitInspection({
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
  }) async {
    try {
      await client
          .from('field_jobs')
          .update({
            'status': 'completed',
            'findings': findings,
            'is_compliant': isCompliant,
            'inspection_result': inspectionResult,
            if (observations != null) 'observations': observations,
            if (discrepancies != null) 'discrepancies': discrepancies,
            if (recommendations != null) 'recommendations': recommendations,
            if (inspectorNotes != null) 'inspector_notes': inspectorNotes,
            if (checklistData != null) 'checklist_data': checklistData,
            'checklist_completed_count': checklistCompletedCount,
            'checklist_total_count': checklistTotalCount,
            if (photoPaths != null) 'photo_paths': photoPaths,
            'photo_count': photoCount,
            'submitted_at': DateTime.now().toUtc().toIso8601String(),
            // Rework redesign: Review & Submit is the one finalize point,
            // for both a normal submit (already null — harmless) and a
            // rework resubmit (clears the "Modified" signal). status was
            // already 'completed' the whole time it was being reworked,
            // so this update is really "confirm the new revision," not
            // "close out an in-progress task."
            'rework_started_at': null,
          })
          .eq('id', jobId);
      await logActivity(
        eventType: 'inspection_completed',
        title: 'Inspection completed',
        subtitle: locationLabel,
        fieldJobId: jobId,
      );
    } catch (e) {
      debugPrint('Error submitting inspection: $e');
      rethrow;
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
      final response = await client
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
              property_index_number
            ),
            field_job_photos (
              id,
              photo_url,
              latitude,
              longitude,
              captured_at
            )
          ''') // Added field_job_photos to the select query
          .eq('id', jobId)
          .single();
      return response;
    } catch (e) {
      debugPrint('Error fetching job detail: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REOPEN A COMPLETED JOB FOR REWORK  (Completed detail screen → "Rework")
  //   Moves the job back to in_progress (so it shows under Ongoing again)
  //   without touching the previously submitted answers — those stay in
  //   place until the inspector actually edits and resubmits that step.
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
      // allowing entry, and logging that a rework session was opened —
      // just no longer a data-changing action by itself.
      final rows = await client
          .from('field_jobs')
          .select('status')
          .eq('id', jobId)
          .limit(1);
      final status = (rows as List).isNotEmpty ? rows.first['status'] as String? : null;
      if (status?.toLowerCase() != 'completed') {
        throw Exception('Job is not completed — cannot reopen for rework.');
      }
      await logActivity(
        eventType: 'rework_started',
        title: 'Reopened for rework',
        subtitle: locationLabel,
        fieldJobId: jobId,
      );
    } catch (e) {
      debugPrint('Error reopening job for rework: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERIC PARTIAL UPDATE  (checklist progress, photo upload count, etc.)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> updateJobInspectionProgress({
    required String jobId,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      await client.from('field_jobs').update(updateData).eq('id', jobId);
    } catch (e) {
      debugPrint('Error updating field job: $e');
      rethrow;
    }
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
          status,
          scheduled_date,
          submitted_at,
          inspection_result,
          is_compliant,
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