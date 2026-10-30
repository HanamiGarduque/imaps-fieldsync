import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models/user_profile.dart';
import '../core/services/db_helper.dart';
import '../modules/auth_startup/services/screen_protection_service.dart';
import '../modules/inspection/services/spatial_offline_service.dart';
import '../modules/inspection/structured_checklist.dart';

enum DemoHardwareMode { production, synthetic, denied }

/// Private-sandbox fixtures, not an alternate production backend. The live
/// instance has no injectable trust source or global testing switch. Tests can
/// construct an isolated instance; they cannot install it into production seams.
class DemoFixtures {
  DemoFixtures._(this._verifyIdentity, this._demoBuild);

  @visibleForTesting
  factory DemoFixtures.forTesting({
    required Future<bool> Function() verifyIdentity,
    bool demoBuild = true,
  }) => DemoFixtures._(verifyIdentity, demoBuild);

  static final instance = DemoFixtures._(
    // ignore: invalid_use_of_visible_for_testing_member
    ScreenProtectionService.isVerifiedDemoContext,
    const bool.fromEnvironment('QA_PREVIEW') ||
        const String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'demo',
  );

  static const revision = 'demo-fixtures-20261028-v1';
  static const owner = '11111111-1111-4111-8111-111111111111';
  static final anchor = DateTime.parse('2026-10-28T10:00:00+08:00');
  static const timestamp = '2026-10-28T02:00:00.000Z';
  static const origin = 'http://127.0.0.1:54321';
  // Arbitrary open-ocean reference, not an inspection site or surveyed parcel.
  static const parcelLatitude = 0.0;
  static const parcelLongitude = -140.0;
  static const latitude = 0.00012;
  static const longitude = -139.99989;
  static final profile = UserProfile(
    id: owner,
    fullName: 'Demo Inspector (Synthetic)',
    role: 'inspector',
    email: 'demo.inspector@example.invalid',
  );

  // Unsigned, openly fictional local session. Nothing can redeem it, and every
  // auth/refresh endpoint is denied. A fixed expiry avoids clock-driven refresh.
  static final accessToken =
      'eyJhbGciOiJub25lIn0.'
      '${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'exp': 4102444800})))}'
      '.demo-fictional-not-a-signature';
  static Map<String, dynamic> session() => {
    'access_token': accessToken,
    'refresh_token': 'demo-fictional-no-refresh',
    'token_type': 'bearer',
    'expires_in': 2300000000,
    'expires_at': 4102444800,
    'user': {
      'id': owner,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'demo.inspector@example.invalid',
      'phone': '',
      'created_at': timestamp,
      'updated_at': timestamp,
      'email_confirmed_at': timestamp,
      'app_metadata': {
        'provider': 'demo-preview',
        'providers': ['demo-preview'],
      },
      'user_metadata': {
        'full_name': 'Demo Inspector (Synthetic)',
        'role': 'inspector',
      },
      'identities': <Map<String, dynamic>>[],
    },
  };

  static String jobId(int n) => '22222222-2222-4222-8222-${_suffix(n)}';
  static String applicationId(int n) => '33333333-3333-4333-8333-${_suffix(n)}';
  static String parcelId(int n) => '44444444-4444-4444-8444-${_suffix(n)}';
  static String activityId(int n) => '77777777-7777-4777-8777-${_suffix(n)}';
  static String _suffix(int n) => n.toString().padLeft(12, '0');

  static List<Map<String, dynamic>> get jobs => [
    for (var n = 1; n <= 9; n++)
      {
        'id': jobId(n),
        'assigned_inspector_id': owner,
        'status': n == 9
            ? 'completed'
            : n == 8
            ? 'in_progress'
            : 'assigned',
        'is_self_scheduled': n <= 5 || n == 9,
        'scheduled_date': switch (n) {
          1 => '2026-11-07',
          2 => '2026-10-30',
          3 => '2026-10-29',
          4 => '2026-10-28',
          5 => '2026-10-25',
          9 => '2026-10-22',
          _ => null,
        },
        'deadline_date': n <= 4
            ? '2026-11-17'
            : switch (n) {
                5 => '2026-11-07',
                6 => '2026-10-26',
                9 => '2026-11-01',
                _ => '2026-11-12',
              },
        'submitted_at': n == 9 ? '2026-10-24T02:00:00.000Z' : null,
        'created_at': '2026-10-20T02:00:00.000Z',
        'updated_at': timestamp,
        'supabase_application_id': applicationId(n),
        'supabase_parcel_id': parcelId(n),
        'bridge_source_id': 'DEMO-SYNTHETIC-$n',
        'inspection_round_number': 1,
        'assignment_instructions':
            'DEMO ONLY: inspect the generated model site. '
            'No real applicant, property, visit or backend acknowledgment is represented.',
        'assigned_by_name': 'Demo Planning Officer (Synthetic)',
        'supabase_zoning_applications': {
          'id': applicationId(n),
          'applicant_name': 'Demo Applicant $n (Synthetic)',
          'reference_number': 'DEMO-2026-${n.toString().padLeft(4, '0')}',
          'barangay': 'Synthetic District $n',
          'application_type': 'Zoning Clearance',
          'purpose': 'DEMO model review only',
          'location_address':
              'Generated Model Site $n — fictional reference only',
          'email': 'applicant$n@example.invalid',
          'contact_number': null,
        },
        'supabase_parcels': {
          'id': parcelId(n),
          'latitude': parcelLatitude,
          'longitude': parcelLongitude,
          'lot_area_sqm': 250,
          'land_use_class': 'Single-detached residential',
          'declared_land_use': 'Single-detached residential',
          'location_address':
              'Generated Model Site $n — fictional reference only',
          'property_index_number': 'DEMO-NOT-CADASTRAL-$n',
        },
      },
  ];

  static List<Map<String, dynamic>> get activity => [
    for (var n = 1; n <= 8; n++)
      {
        'id': activityId(n),
        'inspector_id': owner,
        'field_job_id': n <= 6 ? jobId(n == 1 ? 9 : 8) : null,
        'event_type': [
          'inspection_completed',
          'step_completed',
          'gps_confirmed',
          'field_findings_updated',
          'sync_manual',
          'photos_synced',
          'report_resolved',
          'profile_updated',
        ][n - 1],
        'title': [
          'DEMO: fictional inspection completed',
          'DEMO: checklist saved locally',
          'DEMO: simulated GPS verified',
          'DEMO: synthetic findings prepared',
          'DEMO: manual sync demonstration — no delivery',
          'DEMO: SIMULATED photo receipt — no backend acknowledgment',
          'DEMO: fictional support response',
          'DEMO: synthetic profile reviewed',
        ][n - 1],
        'subtitle':
            'Synthetic fixture $n. ${n == 4 || n == 7 ? 'This deliberately long fictional message exercises wrapping and expanded details without disclosing any applicant information. ' : ''}'
            'Generated locally; not a Supabase/iMAPS receipt or a real inspection event.',
        'is_read': n.isEven,
        'occurred_at': anchor.subtract(Duration(hours: n)).toIso8601String(),
      },
  ];

  final Future<bool> Function() _verifyIdentity;
  final bool _demoBuild;
  bool _initialized = false;
  bool _closed = false;
  bool _watermark = false;
  int _watermarkGeneration = 0;
  Future<void>? _initializing;
  late final transport = MockClient(handle);

  bool get _sameSession {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      return DBHelper.currentInspectorId == owner &&
          session?.user.id == owner &&
          session?.accessToken == accessToken &&
          session?.user.appMetadata['provider'] == 'demo-preview';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _trusted({bool requireInitialized = true}) async {
    if (!_demoBuild || _closed) {
      _revokeReadiness();
      return false;
    }
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (!await _verifyIdentity() || _closed || !_sameSession ||
          !identical(session, Supabase.instance.client.auth.currentSession)) {
        _invalidateTrust();
        return false;
      }
      if (!requireInitialized) return true;
      if (!_initialized) {
        _revokeReadiness();
        return false;
      }
      final rows = await (await DBHelper.database).query(
        'demo_fixture_state',
        where: 'owner = ? AND revision = ? AND state = ?',
        whereArgs: [owner, revision, 'ready'],
      );
      if (rows.length == 1 && !_closed && _sameSession &&
          identical(session, Supabase.instance.client.auth.currentSession)) {
        return true;
      }
    } catch (_) {
      // Missing state or failed attestation is never permission to use hardware.
    }
    _invalidateTrust();
    return false;
  }

  void _revokeReadiness() {
    // Isolated test fixtures cannot alter the live service's authority.
    if (identical(this, instance)) {
      ScreenProtectionService.instance.revokeDemoReadiness();
    }
  }

  void _invalidateTrust() {
    _closed = true;
    _initialized = false;
    watermarkMounted(false);
  }

  Future<void> _requireTrust({bool requireInitialized = true}) async {
    if (!await _trusted(requireInitialized: requireInitialized)) {
      throw StateError(
        'Verified demo identity, session and fixture revision required.',
      );
    }
  }

  /// Fixture eligibility only; D26 separately validates the rendered watermark
  /// and live B1 identity. This never grants native capture permission.
  Future<bool> get captureSourceReady async {
    final generation = _watermarkGeneration;
    return await _trusted() && _watermark &&
        generation == _watermarkGeneration;
  }

  void watermarkMounted(bool mounted) {
    // A late mount callback cannot reopen a runtime that lost fixture trust.
    final visible = mounted && !_closed;
    if (_watermark != visible) _watermarkGeneration++;
    _watermark = visible;
    if (!visible) _revokeReadiness();
  }

  Future<DemoHardwareMode> hardwareMode({String? jobId}) async {
    if (!_demoBuild) return DemoHardwareMode.production;
    if (!await _trusted()) return DemoHardwareMode.denied;
    if (jobId != null) {
      if (!jobs.any((job) => job['id'] == jobId) ||
          await DBHelper.getCachedJob(jobId) == null) {
        return DemoHardwareMode.denied;
      }
    }
    return DemoHardwareMode.synthetic;
  }

  Future<Position> positionOrNative(Future<Position> Function() native) async {
    switch (await hardwareMode()) {
      case DemoHardwareMode.production:
        return native();
      case DemoHardwareMode.denied:
        throw StateError('Demo location trust is unavailable.');
      case DemoHardwareMode.synthetic:
        return Position(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
          accuracy: 8,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
          isMocked: true,
        );
    }
  }

  Future<void> cameraEntry({
    required String jobId,
    required Future<void> Function() native,
    required Future<void> Function() synthetic,
  }) async {
    switch (await hardwareMode(jobId: jobId)) {
      case DemoHardwareMode.production:
        await native();
      case DemoHardwareMode.denied:
        throw StateError('Demo evidence trust is unavailable.');
      case DemoHardwareMode.synthetic:
        await synthetic();
        await _requireTrust();
    }
  }

  Future<Uint8List> generateSitePhoto(String jobId) async {
    if (await hardwareMode(jobId: jobId) != DemoHardwareMode.synthetic) {
      throw StateError(
        'Generated evidence requires the verified demo sandbox.',
      );
    }
    return _imageBytes(reference: false, label: jobId);
  }

  Future<void> initialize({Directory? documents}) => _initializing ??=
      _initialize(documents).catchError((Object error, StackTrace stack) {
        _invalidateTrust();
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _initialize(Directory? documents) async {
    final session = Supabase.instance.client.auth.currentSession;
    void finish() {
      if (_closed || !_sameSession ||
          !identical(session, Supabase.instance.client.auth.currentSession)) {
        throw StateError('Demo initialization session was invalidated.');
      }
      _initialized = true;
    }
    await _requireTrust(requireInitialized: false);
    final db = await DBHelper.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS demo_fixture_state('
      'owner TEXT PRIMARY KEY, revision TEXT NOT NULL, state TEXT NOT NULL, '
      'activity_json TEXT NOT NULL)',
    );
    final state = await db.query(
      'demo_fixture_state',
      where: 'owner = ?',
      whereArgs: [owner],
    );
    if (state.isNotEmpty) {
      if (state.single['revision'] != revision) {
        throw StateError(
          'Existing demo revision is preserved; explicit migration is required.',
        );
      }
      if (state.single['state'] == 'ready') {
        await _requireTrust(requireInitialized: false);
        finish();
        return; // No reseeding, including deleted Activity, photos or cleared history.
      }
      if (state.single['state'] != 'initializing') {
        throw StateError('Invalid demo initialization state.');
      }
    } else {
      if ((await db.query('local_jobs', limit: 1)).isNotEmpty) {
        throw StateError(
          'Unrecognized demo work is preserved; automatic replacement is forbidden.',
        );
      }
      await db.insert('demo_fixture_state', {
        'owner': owner,
        'revision': revision,
        'state': 'initializing',
        'activity_json': jsonEncode(activity),
      });
    }
    await _requireTrust(requireInitialized: false);
    final cached = await DBHelper.getCachedJobs();
    if (cached.isEmpty) {
      if (!await DBHelper.cacheJobs(jobs)) {
        throw StateError('Demo assignments were not saved.');
      }
    } else if (cached.length != 9 ||
        cached.any((r) => !jobs.any((j) => j['id'] == r['id']))) {
      throw StateError('Incomplete or unknown demo assignments are preserved.');
    }
    final directory = Directory(
      '${(documents ?? await getApplicationDocumentsDirectory()).path}'
      '/demo_fixtures/$revision/$owner',
    );
    await directory.create(recursive: true);
    for (final n in [8, 9]) {
      await _seedInspection(n, directory);
    }
    await _seedQueueAndHistory();
    await _requireTrust(requireInitialized: false);
    final completed = await db.update(
      'demo_fixture_state',
      {'state': 'ready'},
      where: 'owner = ? AND revision = ? AND state = ?',
      whereArgs: [owner, revision, 'initializing'],
    );
    if (completed != 1) {
      throw StateError('Complete demo initialization was not recorded.');
    }
    await _requireTrust(requireInitialized: false);
    finish();
  }

  static const _legacyChecklist = {
    'Structure matches declared use': true,
    'Setback distances compliant': true,
    'Accessibility & road frontage': true,
    'Surrounding developments noted': true,
    'Signage / commercial activity present': false,
  };
  static const _notes =
      'DEMO ONLY: generated model facade and access observed. '
      'No physical visit, applicant contact or cadastral verification occurred.';
  static const _observations =
      'DEMO: synthetic residential model and fictional location coordinates only.';
  static const _recommendations =
      'DEMO ONLY: review the fictional model record; not a planning decision.';

  Future<void> _seedInspection(int n, Directory directory) async {
    final id = jobId(n);
    await _requireTrust(requireInitialized: false);
    final draft = await DBHelper.getLocalInspection(id);
    if (draft == null) {
      await DBHelper.saveInspectionLocally(
        jobId: id,
        expectedInspectorId: owner,
        actualLandUse: 'Single-detached residential',
        notes: _notes,
        isCompliant: true,
        inspectionResult: 'Compliant',
        checklist: _legacyChecklist,
        boundaryStatus: 'DEMO: not surveyed',
        currentStep: n == 8 ? 5 : 6,
        findings: {
          'discrepancies': '',
          'recommendations': _recommendations,
          'observations': _observations,
        },
      );
    }
    final times = {
      for (var step = 1; step <= (n == 8 ? 5 : 6); step++)
        '$step': anchor
            .subtract(Duration(days: n == 9 ? 4 : 0, minutes: 70 - step * 10))
            .toIso8601String(),
    };
    await DBHelper.saveInspectionStep(id, n == 8 ? 5 : 6, times, owner);
    final db = await DBHelper.database;
    await db.update(
      'local_inspections',
      {'updated_at': timestamp},
      where: 'id = ? AND inspector_id = ?',
      whereArgs: [id, owner],
    );
    if (await DBHelper.getGpsVerification(id) == null) {
      await DBHelper.saveGpsVerification(
        jobId: id,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 8,
        fixAt: DateTime.parse(times['2']!),
        verifiedAt: DateTime.parse(times['2']!),
      );
    }
    // Fresh fictional fixtures contain three clearly marked synthetic photos.
    // Previously seeded evidence is never deleted or reseeded.
    for (var index = 1; index <= 3; index++) {
      final photoId = '55555555-5555-4555-8555-${_suffix(n * 100 + index)}';
      if (await DBHelper.getLocalPhoto(photoId) != null) continue;
      final file = File('${directory.path}/${id}_site_$index.jpg');
      if (!await file.exists()) {
        await file.writeAsBytes(
          _imageBytes(reference: false, label: 'DEMO-$n / EVIDENCE $index'),
          flush: true,
        );
      }
      await DBHelper.savePhotoLocally(
        photoId: photoId,
        jobId: id,
        photoPath: file.path,
        notes: 'DEMO · SYNTHETIC DATA — generated evidence $index; NOT a camera photograph.',
        latitude: latitude,
        longitude: longitude,
        capturedAt: anchor
            .subtract(Duration(days: n == 9 ? 4 : 0, minutes: 35 - index))
            .toIso8601String(),
      );
    }
  }
  static Uint8List _imageBytes({
    required bool reference,
    required String label,
  }) {
    final image = img.Image(width: 960, height: 640);
    img.fill(image, color: img.ColorRgb8(244, 246, 250));
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 959,
      y2: 112,
      color: img.ColorRgb8(15, 23, 42),
    );
    final white = img.ColorRgb8(255, 255, 255);
    final ink = img.ColorRgb8(15, 23, 42);
    void text(String value, int y, {bool light = false}) => img.drawString(
      image,
      value,
      font: img.arial24,
      x: 32,
      y: y,
      color: light ? white : ink,
    );
    text('DEMO - SYNTHETIC DATA', 20, light: true);
    text(
      reference
          ? 'SITE LOCATION REFERENCE'
          : 'GENERATED EVIDENCE - NOT A CAMERA PHOTO',
      64,
      light: true,
    );
    if (reference) {
      text('Simulated inspector: 0.00012, -139.99989', 150);
      text('Fictional parcel point: 0.00000, -140.00000', 200);
      text('Open-ocean model coordinates. No real site.', 260);
      text('Not a surveyed boundary or a hardware GPS fix.', 320);
    } else {
      img.fillRect(
        image,
        x1: 300,
        y1: 210,
        x2: 650,
        y2: 440,
        color: img.ColorRgb8(180, 83, 9),
      );
      img.fillRect(image, x1: 435, y1: 310, x2: 515, y2: 440, color: white);
      text('Fictional model facade - no real property', 150);
    }
    text(label, 490);
    text('Fixture: demo-fixtures-20261028-v1', 540);
    text('No visit, image import or backend receipt.', 590);
    return Uint8List.fromList(img.encodeJpg(image, quality: 82));
  }

  Future<List<Map<String, dynamic>>> _photos(String id) async => [
    for (final row in await DBHelper.getLocalPhotos(id))
      {
        'id': row['id'],
        'photoPath': row['photo_path'],
        'notes': row['notes'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'capturedAt': row['captured_at'],
      },
  ];

  Future<Map<String, dynamic>?> _readJob(Map<String, dynamic> job) async {
    final id = job['id'] as String;
    final cached = await DBHelper.getCachedJob(id);
    if (cached == null) return null;
    final draft = await DBHelper.getLocalInspection(id);
    final gps = await DBHelper.getGpsVerification(id);
    final photos = await _photos(id);
    final checklist =
        jsonDecode(draft?['checklist_json'] as String? ?? '{}') as Map;
    final findings =
        checklist[DBHelper.inspectionDraftFindingsKey] as Map? ?? {};
    final legacy = {
      for (final key in _legacyChecklist.keys) key: checklist[key] == true,
    };
    final entries = StructuredChecklist.remoteChecklist(
      legacy: legacy,
      answers: StructuredChecklist.decode(
        checklist[StructuredChecklist.jsonKey],
      ),
    );
    return {
      ...job,
      'status': cached['status'],
      'scheduled_date': cached['scheduled_date'],
      'deadline_date': cached['deadline_date'],
      'is_self_scheduled': cached['is_self_scheduled'] == 1,
      'current_step': draft?['current_step'] ?? 0,
      'step_timestamps': jsonDecode(
        draft?['step_timestamps'] as String? ?? '{}',
      ),
      'findings': draft?['notes'],
      'inspector_notes': draft?['notes'],
      'observations': findings['observations'],
      'discrepancies': findings['discrepancies'],
      'recommendations': findings['recommendations'],
      'inspection_result': draft?['inspection_result'],
      'is_compliant': draft == null ? null : draft['is_compliant'] == 1,
      'checklist_data': entries,
      'checklist_total_count': 5,
      'checklist_completed_count': legacy.values.where((v) => v).length,
      'photo_count': photos.length,
      'photo_paths': [for (final p in photos) p['photoPath']],
      'field_job_photos': [
        for (final p in photos)
          {
            'id': p['id'],
            'photo_url': p['photoPath'],
            'notes': p['notes'],
            'latitude': p['latitude'],
            'longitude': p['longitude'],
            'captured_at': p['capturedAt'],
          },
      ],
      'confirmed_latitude': gps?['latitude'],
      'confirmed_longitude': gps?['longitude'],
      'gps_accuracy_m': gps?['accuracy_meters'],
      'gps_confirmed_at': gps?['verified_at'],
    };
  }

  static bool _supportedSelect(String? select, Iterable<String> fields) =>
      select == null ||
      select == '*' ||
      (select.isNotEmpty &&
          RegExp(r'^[A-Za-z0-9_*!(),\s]+$').hasMatch(select) &&
          RegExp(
            r'[A-Za-z_][A-Za-z0-9_]*',
          ).allMatches(select).every((m) => fields.contains(m.group(0))));

  Future<void> _seedQueueAndHistory() async {
    final photos8 = await _photos(jobId(8));
    final photos9 = await _photos(jobId(9));
    final checklist = StructuredChecklist.remoteChecklist(
      legacy: _legacyChecklist,
      answers: const {},
    );
    final scenarios = [
      (
        'current_step_update',
        jobId(8),
        'pending',
        <String, dynamic>{'currentStep': 5},
      ),
      (
        'photos_update',
        jobId(8),
        'failed',
        <String, dynamic>{'photos': photos8},
      ),
      (
        'findings_update',
        jobId(8),
        'conflict',
        <String, dynamic>{
          'findings': _notes,
          'inspectorNotes': _notes,
          'observations': _observations,
          'discrepancies': '',
          'recommendations': _recommendations,
          'inspectionResult': 'Compliant',
        },
      ),
      (
        'demo_history',
        jobId(9),
        'synced',
        <String, dynamic>{
          'receipt':
              'SIMULATED DEMO HISTORY — NO SUPABASE/iMAPS ACKNOWLEDGMENT',
        },
      ),
      (
        'submit_inspection',
        jobId(9),
        'pending',
        <String, dynamic>{
          'findings': _notes,
          'inspectorNotes': _notes,
          'isCompliant': true,
          'inspectionResult': 'Compliant',
          'observations': _observations,
          'discrepancies': '',
          'recommendations': _recommendations,
          'checklistData': checklist,
          'checklistCompletedCount': 4,
          'checklistTotalCount': 5,
          'photosData': photos9,
          'locationLabel': 'DEMO completed model — local queue only',
        },
      ),
    ];
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      DBHelper.requireSameInspector(owner);
      for (var index = 0; index < scenarios.length; index++) {
        final (type, job, status, payload) = scenarios[index];
        await DBHelper.requireOwnedJob(txn, job, owner);
        await txn.insert('pending_actions', {
          'id': '88888888-8888-4888-8888-${_suffix(index + 1)}',
          'inspector_id': owner,
          'job_id': job,
          'type': type,
          'status': status,
          'payload': jsonEncode({
            ...payload,
            'demoOnly': true,
            'fixtureRevision': revision,
            'locationLabel':
                payload['locationLabel'] ?? 'DEMO · SYNTHETIC DATA',
          }),
          'retry_count': status == 'failed' ? 1 : 0,
          'last_error': status == 'failed' || status == 'conflict'
              ? 'DEMO ONLY: simulated $status; no external delivery occurred.'
              : null,
          'created_at': anchor
              .subtract(Duration(minutes: 30 - index))
              .toIso8601String(),
          'updated_at': anchor
              .subtract(Duration(minutes: 20 - index))
              .toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (var n = 1; n <= 24; n++) {
        final result = ['info', 'success', 'warning', 'error'][(n - 1) % 4];
        await txn.insert('sync_log_entries', {
          'id': '66666666-6666-4666-8666-${_suffix(n)}',
          'inspector_id': owner,
          'job_id': jobId(n.isEven ? 8 : 9),
          'event_type': 'demo_$result',
          'result': result,
          'message':
              'DEMO $n: ${result == 'success' ? 'SIMULATED receipt — no backend acknowledgment.' : 'Fictional $result synchronization scenario.'} '
              'This locally generated history exercises pagination and long message wrapping. '
              'Nothing was uploaded to Supabase or iMAPS; no real inspection or report was delivered.',
          'technical_details': jsonEncode({
            'demoOnly': true,
            'fixtureRevision': revision,
            'receipt': 'SIMULATED — NO BACKEND ACKNOWLEDGMENT',
          }),
          'created_at': anchor
              .subtract(Duration(minutes: n * 7))
              .toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      DBHelper.requireSameInspector(owner);
    });
  }

  /// Nonforwarding handler: only read-only fixture resources and Activity
  /// read/delete state and one local distance calculation are supported.
  /// In particular no auth, storage, mutation RPC,
  /// field-job mutation, inspection submission, report or push endpoint exists.
  Future<http.Response> handle(http.Request request) async {
    http.Response reply(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {
        'content-type': 'application/json',
        'x-fieldsync-demo': revision,
      },
    );
    http.Response deny() => reply({
      'error': 'demo_offline',
      'message':
          'DEMO: unsupported request denied locally; nothing was forwarded.',
    }, 403);
    try {
      final uri = request.url;
      if (uri.origin != origin ||
          uri.userInfo.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          request.headers['authorization'] != 'Bearer $accessToken' ||
          !await _trusted()) {
        return deny();
      }
      if (uri.queryParametersAll.values.any((values) => values.length != 1)) {
        return deny();
      }
      final q = uri.queryParameters;
      if (uri.path == '/rest/v1/rpc/distance_to_parcel_boundary') {
        if (request.method != 'POST' || q.isNotEmpty) return deny();
        final data = jsonDecode(request.body);
        if (data is! Map ||
            data.length != 3 ||
            data['lat'] != latitude ||
            data['lng'] != longitude) {
          return deny();
        }
        final matching = jobs.where(
          (job) => job['supabase_parcel_id'] == data['parcel_id'],
        );
        if (matching.length != 1 ||
            await DBHelper.getCachedJob(matching.single['id'] as String) ==
                null ||
            !_sameSession) {
          return deny();
        }
        // The production RPC measures distance to a point, not a surveyed
        // boundary. Reuse the canonical offline calculation for fictional
        // coordinates; this is neither a GPS gate bypass nor an acceptance.
        return reply(
          SpatialOfflineService.haversineMeters(
            latitude,
            longitude,
            parcelLatitude,
            parcelLongitude,
          ),
          200,
        );
      }
      if (uri.path == '/rest/v1/activity_log') {
        if (!const ['GET', 'PATCH', 'DELETE'].contains(request.method) ||
            q.keys.any(
              (k) => !const [
                'select',
                'inspector_id',
                'id',
                'is_read',
                'order',
                'limit',
                'offset',
              ].contains(k),
            ) ||
            (q.containsKey('inspector_id') &&
                q['inspector_id'] != 'eq.$owner') ||
            (!q.containsKey('id') && q['inspector_id'] != 'eq.$owner') ||
            (q.containsKey('id') &&
                !activity.any((r) => q['id'] == 'eq.${r['id']}')) ||
            (q.containsKey('select') &&
                !const ['*', 'id'].contains(q['select'])) ||
            (q.containsKey('is_read') &&
                !const ['eq.true', 'eq.false'].contains(q['is_read'])) ||
            (q.containsKey('order') &&
                !const {
                  'occurred_at.desc',
                  'occurred_at.desc.nullslast',
                }.contains(q['order'])) ||
            (q.containsKey('limit') &&
                (int.tryParse(q['limit']!) == null ||
                    int.parse(q['limit']!) < 1 ||
                    int.parse(q['limit']!) > 100)) ||
            (q.containsKey('offset') &&
                (int.tryParse(q['offset']!) == null ||
                    int.parse(q['offset']!) < 0)) ||
            (request.method != 'GET' &&
                q.keys.any(
                  (k) => !const ['id', 'inspector_id', 'is_read'].contains(k),
                ))) {
          return deny();
        }
        if (request.method == 'PATCH') {
          final data = jsonDecode(request.body);
          if (data is! Map || data.length != 1 || data['is_read'] != true) {
            return deny();
          }
        } else if (request.body.isNotEmpty) {
          return deny();
        }
        final db = await DBHelper.database;
        return db.transaction((txn) async {
          if (!_sameSession) return deny();
          final state = await txn.query(
            'demo_fixture_state',
            where: 'owner = ? AND revision = ? AND state = ?',
            whereArgs: [owner, revision, 'ready'],
          );
          if (state.length != 1) return deny();
          final rows =
              (jsonDecode(state.single['activity_json'] as String) as List)
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList();
          bool matches(Map<String, dynamic> row) =>
              (q['id'] == null || q['id'] == 'eq.${row['id']}') &&
              (q['is_read'] == null || q['is_read'] == 'eq.${row['is_read']}');
          final selected = rows.where(matches).toList();
          if (request.method == 'GET') {
            selected.sort(
              (a, b) => (b['occurred_at'] as String).compareTo(
                a['occurred_at'] as String,
              ),
            );
            final page = selected
                .skip(int.parse(q['offset'] ?? '0'))
                .take(int.parse(q['limit'] ?? '100'));
            return reply([
              for (final row in page)
                q['select'] == 'id' ? {'id': row['id']} : row,
            ], 200);
          }
          if (request.method == 'PATCH') {
            for (final row in selected) {
              row['is_read'] = true;
            }
          } else {
            rows.removeWhere(matches);
          }
          await txn.update(
            'demo_fixture_state',
            {'activity_json': jsonEncode(rows)},
            where: 'owner = ? AND revision = ?',
            whereArgs: [owner, revision],
          );
          if (!_sameSession) throw StateError('Demo session changed.');
          return http.Response('', 204, request: request);
        });
      }
      if (request.method != 'GET' || request.body.isNotEmpty) return deny();
      List<Map<String, dynamic>> rows;
      switch (uri.path) {
        case '/rest/v1/profiles':
          if (q['id'] != 'eq.$owner' ||
              q.keys.any((k) => !const ['id', 'select'].contains(k)) ||
              !_supportedSelect(q['select'], profile.toMap().keys)) {
            return deny();
          }
          rows = [profile.toMap()];
        case '/rest/v1/field_jobs':
          if (q.keys.any(
                (k) => !const [
                  'select',
                  'id',
                  'assigned_inspector_id',
                  'order',
                ].contains(k),
              ) ||
              (q.containsKey('assigned_inspector_id') &&
                  q['assigned_inspector_id'] != 'eq.$owner') ||
              (!q.containsKey('id') &&
                  q['assigned_inspector_id'] != 'eq.$owner') ||
              (q.containsKey('id') &&
                  !jobs.any((j) => q['id'] == 'eq.${j['id']}')) ||
              (q.containsKey('order') &&
                  !const {
                    'scheduled_date.asc',
                    'scheduled_date.asc.nullslast',
                  }.contains(q['order'])) ||
              !_supportedSelect(q['select'], {
                ...jobs.first.keys,
                ...(jobs.first['supabase_zoning_applications'] as Map).keys
                    .cast<String>(),
                ...(jobs.first['supabase_parcels'] as Map).keys.cast<String>(),
                'field_jobs_supabase_application_id_fkey',
                'field_jobs_supabase_parcel_id_fkey',
                'local_inspection_id',
                'previous_site_inspection_id',
                'reinspection_reason',
                'reinspection_reviewed_at',
                'current_step',
                'step_timestamps',
                'rework_started_at',
                'started_at',
                'assigned_by_imaps_user_id',
                'field_job_photos',
                'photo_url',
                'captured_at',
                'notes',
                'field_job_reviews',
                'technical_review_id',
                'reviewed_site_inspection_id',
                'decision',
                'decision_reason',
                'reviewed_by',
                'reviewed_by_name',
                'reviewed_at',
              })) {
            return deny();
          }
          rows = [];
          for (final job in jobs.where(
            (j) => q['id'] == null || q['id'] == 'eq.${j['id']}',
          )) {
            final row = await _readJob(job);
            if (row == null) return deny();
            rows.add(row);
          }
        case '/rest/v1/supabase_parcels':
        case '/rest/v1/supabase_zoning_applications':
          if (q.keys.any((k) => !const ['id', 'select'].contains(k))) {
            return deny();
          }
          final key = uri.path.endsWith('supabase_parcels')
              ? 'supabase_parcels'
              : 'supabase_zoning_applications';
          if (!_supportedSelect(
            q['select'],
            (jobs.first[key] as Map).keys.cast<String>(),
          )) {
            return deny();
          }
          rows = [
            for (final job in jobs)
              if (q['id'] == 'eq.${(job[key] as Map)['id']}' &&
                  await DBHelper.getCachedJob(job['id'] as String) != null)
                Map<String, dynamic>.from(job[key] as Map),
          ];
          if (rows.length != 1) return deny();
        default:
          return deny();
      }
      if (!_sameSession) return deny();
      if (q['select'] == 'id' || q['select'] == 'updated_at') {
        rows = [
          for (final row in rows) {q['select']!: row[q['select']]},
        ];
      }
      if (request.headers['accept']?.contains(
            'application/vnd.pgrst.object+json',
          ) ==
          true) {
        return rows.length == 1
            ? reply(rows.single, 200)
            : reply({'message': 'No exact demo fixture'}, 406);
      }
      return reply(rows, 200);
    } catch (_) {
      return deny();
    }
  }
}
