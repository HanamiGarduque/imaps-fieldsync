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
      await client.from('inspector_device_subscriptions').upsert(
        {
          'inspector_id': user.id,
          'device_token': deviceToken,
          'platform': platform,
        },
        onConflict: 'inspector_id,device_token',
      );
    } catch (e) {
      debugPrint('Failed to save notification subscription: $e');
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
          priority,
          supabase_parcel_id,
          supabase_zoning_applications!supabase_application_id (
            reference_number,
            applicant_name,
            barangay,
            application_type,
            declared_land_use
          ),
          supabase_parcels!supabase_parcel_id (
            id,
            latitude,
            longitude,
            land_area_sqm,
            lot_number,
            land_classification
          )
        ''')
        .eq('assigned_inspector_id', userId)
        .inFilter('status', ['assigned', 'in_progress'])
        .order('scheduled_date', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH PARCEL DETAILS  (Parcel detail screen)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> fetchParcelDetails(String parcelId) async {
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
  // CONFIRM GPS ON-SITE  (GPS verification screen → marks job in_progress)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> confirmGpsOnSite({
    required String jobId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    try {
      await client.from('field_jobs').update({
        'status': 'in_progress',
        'confirmed_latitude': latitude,
        'confirmed_longitude': longitude,
        'gps_accuracy_m': accuracyMeters,
        'gps_confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', jobId);
    } catch (e) {
      debugPrint('Error confirming GPS on site: $e');
      rethrow;
    }
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
  }) async {
    try {
      await client.from('field_jobs').update({
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
      }).eq('id', jobId);
    } catch (e) {
      debugPrint('Error submitting inspection: $e');
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
      await client
          .from('field_jobs')
          .update(updateData)
          .eq('id', jobId);
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
        .eq('status', 'completed')
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
}
