import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/supabase_service.dart';
import '../services/db_helper.dart';
import '../screens/tasks_screen.dart'; // To access TaskItem class

class InspectionProvider extends ChangeNotifier {
  TaskItem? _activeTask;
  int _currentStep = 1;

  // Checklist State
  final Map<String, bool> _siteCondition = {
    'Structure matches declared use': true,
    'Setback distances compliant': true,
  };
  final Map<String, bool> _zoningObservations = {
    'Accessibility & road frontage': true,
    'Surrounding developments noted': false,
    'Signage / commercial activity present': false,
  };

  // Photo Evidence State
  final List<Map<String, dynamic>> _capturedPhotos = [];

  // Findings State
  String _actualLandUse = 'Single-detached residential';
  String _notes = '';
  String _discrepancies = '';
  String _recommendations = '';
  String _boundaryStatus = 'Compliant';
  String _inspectionResult = 'Compliant'; // Selected assessment result

  bool _isSyncing = false;

  // Getters
  TaskItem? get activeTask => _activeTask;
  int get currentStep => _currentStep;
  Map<String, bool> get siteCondition => _siteCondition;
  Map<String, bool> get zoningObservations => _zoningObservations;
  List<Map<String, dynamic>> get capturedPhotos => _capturedPhotos;
  String get actualLandUse => _actualLandUse;
  String get notes => _notes;
  String get discrepancies => _discrepancies;
  String get recommendations => _recommendations;
  String get boundaryStatus => _boundaryStatus;
  String get inspectionResult => _inspectionResult;
  bool get isSyncing => _isSyncing;

  // --- INITIALIZATION & NAVIGATION ---

  void startInspection(TaskItem task) {
    _activeTask = task;
    _currentStep = 1;
    
    // Reset Checklist
    _siteCondition.updateAll((key, value) => key == 'Surrounding developments noted' || key == 'Signage / commercial activity present' ? false : true);
    _zoningObservations.updateAll((key, value) => key == 'Accessibility & road frontage' ? true : false);

    // Reset Photos
    _capturedPhotos.clear();

    // Reset Findings
    _actualLandUse = 'Single-detached residential';
    _notes = '';
    _discrepancies = '';
    _recommendations = '';
    _boundaryStatus = 'Compliant';
    _inspectionResult = 'Compliant';
    
    _loadLocalDraftIfExists(task.id);
    notifyListeners();
  }

  void updateStep(int step) {
    _currentStep = step;
    notifyListeners();
  }

  // --- CHECKLIST UPDATE METHODS ---

  void setSiteCondition(String key, bool value) {
    _siteCondition[key] = value;
    notifyListeners();
  }

  void setZoningObservation(String key, bool value) {
    _zoningObservations[key] = value;
    notifyListeners();
  }

  // --- PHOTO METHODS ---

  void addPhoto({
    required String photoPath,
    required String photoNotes,
    required double? latitude,
    required double? longitude,
  }) {
    _capturedPhotos.add({
      'photoPath': photoPath,
      'notes': photoNotes,
      'latitude': latitude,
      'longitude': longitude,
      'capturedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  void removePhoto(int index) {
    _capturedPhotos.removeAt(index);
    notifyListeners();
  }

  // --- FINDINGS METHODS ---

  void updateFindings({
    required String actualLandUse,
    required String notes,
    required String discrepancies,
    required String recommendations,
    required String boundaryStatus,
  }) {
    _actualLandUse = actualLandUse;
    _notes = notes;
    _discrepancies = discrepancies;
    _recommendations = recommendations;
    _boundaryStatus = boundaryStatus;
    notifyListeners();
  }

  void updateResult(String result) {
    _inspectionResult = result;
    notifyListeners();
  }

  // --- LOCAL SQLite DRAFT RECOVERY ---

  Future<void> _loadLocalDraftIfExists(String jobId) async {
    final draft = await DBHelper.getLocalInspection(jobId);
    if (draft != null) {
      _actualLandUse = draft['actual_land_use'] ?? _actualLandUse;
      _notes = draft['notes'] ?? _notes;
      _boundaryStatus = draft['boundary_status'] ?? _boundaryStatus;
      _inspectionResult = draft['is_compliant'] == 1 ? 'Compliant' : 'With discrepancy';
      
      if (draft['checklist_json'] != null) {
        try {
          final Map<String, dynamic> checklist = jsonDecode(draft['checklist_json']);
          checklist.forEach((key, value) {
            if (_siteCondition.containsKey(key)) _siteCondition[key] = value == true;
            if (_zoningObservations.containsKey(key)) _zoningObservations[key] = value == true;
          });
        } catch (e) {
          debugPrint('Error decoding local checklist: $e');
        }
      }
    }

    final localPhotos = await DBHelper.getLocalPhotos(jobId);
    if (localPhotos.isNotEmpty) {
      _capturedPhotos.clear();
      for (final p in localPhotos) {
        _capturedPhotos.add({
          'photoPath': p['photo_path'],
          'notes': p['notes'],
          'latitude': p['latitude'],
          'longitude': p['longitude'],
          'capturedAt': p['captured_at'],
        });
      }
    }
    notifyListeners();
  }

  // --- LOCAL SAVE & ONLINE SYNC ---

  Future<bool> saveInspectionProgress() async {
    if (_activeTask == null) return false;

    // Save Checklist observations
    final Map<String, bool> combinedChecklist = {..._siteCondition, ..._zoningObservations};

    // 1. Save main inspection details to local sqlite
    await DBHelper.saveInspectionLocally(
      jobId: _activeTask!.id,
      actualLandUse: _actualLandUse,
      notes: _notes,
      isCompliant: _inspectionResult == 'Compliant',
      checklist: combinedChecklist,
      boundaryStatus: _boundaryStatus,
    );

    // 2. Save photos to local sqlite
    for (final photo in _capturedPhotos) {
      final photoId = const Uuid().v4();
      await DBHelper.savePhotoLocally(
        photoId: photoId,
        jobId: _activeTask!.id,
        photoPath: photo.containsKey('photoPath') ? photo['photoPath'] : '',
        notes: photo.containsKey('notes') ? photo['notes'] : '',
        latitude: photo['latitude'],
        longitude: photo['longitude'],
      );
    }

    notifyListeners();

    // 3. Attempt to Sync automatically if online
    final isConnected = await _checkConnectivity();
    if (isConnected) {
      await syncToServer();
      return true;
    }
    return false; // Stored offline
  }

  Future<bool> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> syncToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final supabase = SupabaseService.client;

      // 1. Sync Pending Photos first (needed for database metadata joins)
      final pendingPhotos = await DBHelper.getPendingPhotos();
      for (final photo in pendingPhotos) {
        final file = File(photo['photo_path']);
        if (!await file.exists()) {
          // File was deleted/missing locally, skip it
          await DBHelper.markPhotoSynced(photo['id']);
          continue;
        }

        final fileName = 'photo_${photo['id']}.jpg';
        final storagePath = 'inspections/${photo['job_id']}/$fileName';

        // Upload physical file to Supabase Storage Bucket 'inspection-photos'
        await supabase.storage.from('inspection-photos').upload(
          storagePath,
          file,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

        final publicUrl = supabase.storage.from('inspection-photos').getPublicUrl(storagePath);

        // Save metadata to field_job_photos table (or similar DB mapping)
        await supabase.from('field_job_photos').upsert({
          'id': photo['id'],
          'job_id': photo['job_id'],
          'photo_url': publicUrl,
          'notes': photo['notes'],
          'latitude': photo['latitude'],
          'longitude': photo['longitude'],
          'created_at': photo['captured_at'],
        });

        await DBHelper.markPhotoSynced(photo['id']);
      }

      // 2. Sync Pending Inspections
      final pendingInspections = await DBHelper.getPendingInspections();
      for (final insp in pendingInspections) {
        // Update field_jobs table in cloud Supabase
        await supabase.from('field_jobs').update({
          'status': 'completed',
          'actual_land_use': insp['actual_land_use'],
          'findings': insp['notes'],
          'is_compliant': insp['is_compliant'] == 1,
          'checklist_json': jsonDecode(insp['checklist_json']),
          'boundary_status': insp['boundary_status'],
          'updated_at': insp['updated_at'],
        }).eq('id', insp['id']);

        await DBHelper.markInspectionSynced(insp['id']);
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
