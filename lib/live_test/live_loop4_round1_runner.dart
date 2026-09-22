// LIVE / MUTATING / LOOP 4 ROUND-1 ONLY.
// Explicit alternate --target only. Never import this file from lib/main.dart.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/services/app_info_service.dart';
import '../core/services/supabase_service.dart';
import '../modules/inspection/inspection_constants.dart';
import '../modules/tasks/screens/tasks_screen.dart';

const _enabled = bool.fromEnvironment('RUN_LIVE_LOOP4_ROUND1');
const _reference = String.fromEnvironment('LOOP4_REFERENCE');
const _localId = int.fromEnvironment('LOOP4_LOCAL_INSPECTION_ID');
const _jobId = String.fromEnvironment('LOOP4_FIELD_JOB_ID');
const _userId = 'ddcebeac-2217-41c5-a6e2-d7f873db9af2';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Runner());
}

class _Runner extends StatefulWidget {
  const _Runner();
  @override
  State<_Runner> createState() => _RunnerState();
}

class _RunnerState extends State<_Runner> {
  final messages = <String>[];
  bool done = false;
  bool passed = false;

  @override
  void initState() {
    super.initState();
    unawaited(runLive());
  }

  void log(String value) {
    debugPrint('LOOP4_LIVE: $value');
    if (mounted) setState(() => messages.add(value));
  }

  Never stop(String reason) => throw StateError(reason);

  Future<void> runLive() async {
    try {
      if (!_enabled) stop('RUN_LIVE_LOOP4_ROUND1 flag is required');
      if (_reference != 'APP-2026-00026' ||
          _localId != 36 ||
          _jobId != '76d79ab8-e38e-4682-ada2-a67ac84dde00') {
        stop('Dart-define fixture identifiers do not match Loop 4 Round 1');
      }
      await dotenv.load(fileName: '.env');
      await AppInfoService.initialize();
      await SupabaseService.initialize();
      log('Same FieldSync/Supabase stack initialized');

      final user = SupabaseService.client.auth.currentUser;
      if (user == null || user.id != _userId) {
        stop(
          'LIVE TEST AUTH SESSION REQUIRED — SESSION DID NOT SURVIVE SAME-PACKAGE REINSTALL',
        );
      }
      log('Session guard PASS');

      final initial = await SupabaseService.fetchJobDetail(_jobId);
      final app = initial?['supabase_zoning_applications'] as Map?;
      final assignerId = int.tryParse(
        initial?['assigned_by_imaps_user_id']?.toString() ?? '',
      );
      if (initial?['status'] == 'completed') {
        await verifyCompleted(initial!);
        log('SNAPSHOT ${jsonEncode(snapshotOf(initial))}');
        log(
          'Existing completed fixture verified read-only; no mutation performed',
        );
        passed = true;
        return;
      }
      if (initial == null ||
          initial['local_inspection_id'] != _localId ||
          app?['reference_number'] != _reference ||
          initial['status'] != 'in_progress' ||
          initial['current_step'] != 1 ||
          initial['submitted_at'] != null ||
          initial['assigned_inspector_id'] != _userId ||
          assignerId != 4 ||
          initial['assigned_by_name'] != 'Jyerine Desunia') {
        stop('Hard job guard mismatch; no mutation performed');
      }
      log('Hard job guards PASS');

      final parcelId = initial['supabase_parcel_id']?.toString();
      final parcel = parcelId == null
          ? null
          : await SupabaseService.fetchParcelDetails(parcelId);
      final parcelLocalId = int.tryParse(
        parcel?['local_parcel_id']?.toString() ?? '',
      );
      final latitude = (parcel?['latitude'] as num?)?.toDouble();
      final longitude = (parcel?['longitude'] as num?)?.toDouble();
      if (parcelId == null ||
          parcelLocalId != 64 ||
          latitude == null ||
          longitude == null) {
        stop('Authoritative parcel 64 coordinates unavailable');
      }
      final distance = await SupabaseService.getDistanceToParcelBoundary(
        parcelId: parcelId,
        latitude: latitude,
        longitude: longitude,
      );
      if (distance > siteVerificationDistanceThresholdMeters) {
        stop(
          'Production GPS validation failed: ${distance.toStringAsFixed(2)}m',
        );
      }
      await SupabaseService.confirmGpsOnSite(
        jobId: _jobId,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 5.0,
        locationLabel: _reference,
      );
      await advance(2);
      log('Step 2 GPS PASS (${distance.toStringAsFixed(2)}m, 5.0m accuracy)');

      final photos = await SupabaseService.uploadInspectionPhotos(
        jobId: _jobId,
        photosData: const [],
      );
      await SupabaseService.updateJobInspectionProgress(
        jobId: _jobId,
        updateData: {'photo_paths': photos, 'photo_count': photos.length},
      );
      await advance(3);
      log('Step 3 Photos PASS (0 photos through production upload path)');

      const checklist = <Map<String, dynamic>>[
        {'item': 'Structure matches declared use', 'checked': false},
        {'item': 'Setback distances compliant', 'checked': false},
        {'item': 'Accessibility & road frontage', 'checked': true},
        {'item': 'Surrounding developments noted', 'checked': true},
        {'item': 'Signage / commercial activity present', 'checked': true},
      ];
      final checked = checklist.where((item) => item['checked'] == true).length;
      await SupabaseService.updateJobInspectionProgress(
        jobId: _jobId,
        updateData: {
          'checklist_data': checklist,
          'checklist_completed_count': checked,
          'checklist_total_count': checklist.length,
        },
      );
      await advance(4);
      log('Step 4 Checklist PASS ($checked/${checklist.length})');

      await finishFindingsAndSubmit(checklist, checked, photos);
    } catch (error, stack) {
      log('BLOCKER: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (mounted) setState(() => done = true);
    }
  }

  Future<void> finishFindingsAndSubmit(
    List<Map<String, dynamic>> checklist,
    int checked,
    List<String> photos,
  ) async {
    const findings = 'Loop 4 Round 1 controlled E2E — reinspection required.';
    const recommendations =
        'Loop 4 controlled E2E recommendation: perform reinspection.';
    const observations =
        'Actual land use: Single-detached residential. Boundary status: Non-compliant.';
    const discrepancies =
        'Observed site conditions require a controlled follow-up inspection.';
    await SupabaseService.updateJobInspectionProgress(
      jobId: _jobId,
      updateData: {
        'findings': findings,
        'observations': observations,
        'discrepancies': discrepancies,
        'recommendations': recommendations,
        'inspector_notes': findings,
      },
    );
    await advance(5);
    log('Step 5 Findings PASS');

    await SupabaseService.submitInspection(
      jobId: _jobId,
      findings: findings,
      isCompliant: false,
      inspectionResult: 'Requires Reinspection',
      observations: observations,
      discrepancies: discrepancies,
      recommendations: recommendations,
      inspectorNotes: findings,
      checklistData: checklist,
      checklistCompletedCount: checked,
      checklistTotalCount: checklist.length,
      photoPaths: photos,
      photoCount: photos.length,
      locationLabel: _reference,
    );
    await advance(6);
    log('Step 6 Requires Reinspection submitted');

    final completed = await SupabaseService.fetchJobDetail(_jobId);
    if (completed == null) stop('Completed job cannot be re-fetched');
    await verifyCompleted(completed);
    log('SNAPSHOT ${jsonEncode(snapshotOf(completed))}');
    log('Remote completed state and lifecycle mapper PASS');
    passed = true;
  }

  Future<void> verifyCompleted(Map<String, dynamic> completed) async {
    final assignerId = int.tryParse(
      completed['assigned_by_imaps_user_id']?.toString() ?? '',
    );
    if (completed['local_inspection_id'] != _localId ||
        completed['status'] != 'completed' ||
        completed['current_step'] != 6 ||
        completed['submitted_at'] == null ||
        completed['inspection_result'] != 'Requires Reinspection' ||
        completed['is_compliant'] != false ||
        completed['assigned_inspector_id'] != _userId ||
        assignerId != 4 ||
        completed['assigned_by_name'] != 'Jyerine Desunia') {
      stop('Completed-state verification failed');
    }
    if (mapTaskStatusToLifecycle(completed['status']?.toString()) !=
        TaskLifecycleCategory.completed) {
      stop('Lifecycle mapper did not return Completed');
    }
  }

  Map<String, dynamic> snapshotOf(Map<String, dynamic> row) {
    const keys = [
      'id',
      'local_inspection_id',
      'status',
      'current_step',
      'submitted_at',
      'inspection_result',
      'is_compliant',
      'findings',
      'observations',
      'discrepancies',
      'recommendations',
      'inspector_notes',
      'checklist_data',
      'checklist_completed_count',
      'checklist_total_count',
      'confirmed_latitude',
      'confirmed_longitude',
      'gps_accuracy_m',
      'gps_confirmed_at',
      'photo_paths',
      'photo_count',
      'step_timestamps',
      'assigned_inspector_id',
      'assigned_by_imaps_user_id',
      'assigned_by_name',
      'assignment_instructions',
      'created_at',
      'updated_at',
      'started_at',
      'rework_started_at',
    ];
    return {for (final key in keys) key: row[key]};
  }

  Future<void> advance(int step) async {
    final row = await SupabaseService.fetchJobDetail(_jobId);
    final existing = row?['step_timestamps'];
    final timestamps = <String, dynamic>{};
    if (existing is Map) {
      for (final entry in existing.entries) {
        timestamps[entry.key.toString()] = entry.value;
      }
    }
    timestamps['$step'] = DateTime.now().toUtc().toIso8601String();
    await SupabaseService.updateJobInspectionProgress(
      jobId: _jobId,
      updateData: {'current_step': step, 'step_timestamps': timestamps},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('LIVE Loop 4 Round 1 Runner')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  done ? (passed ? 'PASS' : 'STOPPED') : 'RUNNING',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: passed
                        ? Colors.green
                        : (done ? Colors.red : Colors.orange),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('LIVE / MUTATING / LOOP 4 ROUND-1 ONLY'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(messages[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
