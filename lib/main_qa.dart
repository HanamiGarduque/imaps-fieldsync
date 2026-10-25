// ISOLATED QA PREVIEW ENTRY POINT - NOT THE PRODUCTION APP.
//
// This file is deliberately NOT `lib/main.dart`. It can only run when all of
// the following are true, so it cannot become the normal release entry point
// by accident:
//
//   1. the build is debug (`kReleaseMode` throws);
//   2. the build was started with `--dart-define=QA_PREVIEW=true`;
//   3. the Supabase endpoint in the bundled `.env` is a loopback address;
//   4. the Android application id was built with `FIELDSYNC_QA_BUILD=1`
//      (see android/app/build.gradle.kts), giving the app its own package,
//      its own private data sandbox and its own launcher icon.
//
// Everything here is synthetic: a fictional inspector, fictional assignments,
// fixtures generated on the device, and a loopback-only Supabase client that
// cannot reach the real environment. The QA build has no production keys
// because the build swaps in a QA `.env`.
//
// Nothing in this file is imported by `lib/main.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/models/user_profile.dart';
import 'core/navigation/main_shell_screen.dart';
import 'core/services/db_helper.dart';
import 'core/services/supabase_endpoint.dart';
import 'core/services/sync_outbox_service.dart';
import 'core/theme/insight_theme.dart';
import 'modules/inspection/screens/inspection_progress.dart';
import 'modules/inspection/providers/inspection_provider.dart';
import 'modules/auth_startup/services/screen_protection_service.dart';

/// Fictional QA inspector. Not a real account, not a real UUID from any
/// environment.
const String qaInspectorId = '11111111-1111-4111-8111-111111111111';

const String qaJobBlue = 'qa000000-0000-4000-8000-000000000001';
const String qaJobOrange = 'qa000000-0000-4000-8000-000000000002';
const String qaJobRed = 'qa000000-0000-4000-8000-000000000003';
const String qaJobDueToday = 'qa000000-0000-4000-8000-000000000004';
const String qaJobReschedule = 'qa000000-0000-4000-8000-000000000005';
const String qaJobOverdue = 'qa000000-0000-4000-8000-000000000006';
const String qaJobAvailable = 'qa000000-0000-4000-8000-000000000007';
const String qaJobInProgress = 'qa000000-0000-4000-8000-000000000008';
const String qaJobCompleted = 'qa000000-0000-4000-8000-000000000009';

Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('The QA preview entry point is debug-only.');
  }
  if (!const bool.fromEnvironment('QA_PREVIEW')) {
    throw StateError(
      'The QA preview entry point needs --dart-define=QA_PREVIEW=true.',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();
  // Capture-only: lets on-device screenshots record synthetic QA screens.
  ScreenProtectionService.allowQaScreenshots = true;
  await dotenv.load(fileName: '.env');

  // Structural isolation: the client can only ever talk to this device.
  final endpoint = validateSupabaseEndpoint(
    dotenv.env['SUPABASE_URL'],
    release: false,
  );
  final endpointHost = Uri.parse(endpoint).host;
  if (!const {'127.0.0.1', 'localhost', '::1'}.contains(endpointHost)) {
    throw StateError('The QA preview refuses a non-loopback endpoint.');
  }

  await Supabase.initialize(
    url: endpoint,
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? 'qa-local-only',
  );
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode(_qaSession()),
  );

  // Deterministic offline transport: every sync attempt sees "no network",
  // so nothing is ever sent anywhere, even to the loopback address. This is
  // the test hook the offline suites use; the QA preview is a test harness.
  // ignore: invalid_use_of_visible_for_testing_member
  SyncOutboxService.hasConnectionOverride = () async => false;

  await _seedSyntheticData();

  final now = DateTime.now();
  final profile = UserProfile(
    id: qaInspectorId,
    fullName: 'QA Inspector (Synthetic)',
    role: 'inspector',
    email: 'qa.inspector@example.invalid',
    phoneNumber: '+63 900 000 0000',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: _QaApp(profile: profile, seedDay: now),
    ),
  );
}

/// A locally recovered session for the loopback-only QA client. It is never
/// redeemable anywhere: the fictional refresh token and the loopback endpoint
/// both make a real server call impossible.
Map<String, dynamic> _qaSession() {
  final now = DateTime.now().toUtc();
  final expiresAt = now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/
      1000;
  return {
    'access_token': 'qa-preview-local-only',
    'token_type': 'bearer',
    'expires_in': 31536000,
    'expires_at': expiresAt,
    'refresh_token': 'qa-preview-local-only',
    'user': {
      'id': qaInspectorId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'qa.inspector@example.invalid',
      'email_confirmed_at': now.toIso8601String(),
      'phone': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'app_metadata': {'provider': 'qa-preview', 'providers': ['qa-preview']},
      'user_metadata': {
        'full_name': 'QA Inspector (Synthetic)',
        'role': 'inspector',
      },
      'identities': <Map<String, dynamic>>[],
    },
  };
}

String _day(int offsetDays) {
  final now = DateTime.now();
  final date = DateTime(now.year, now.month, now.day + offsetDays);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// A fictional assignment. All names, addresses and references are invented.
Map<String, dynamic> _job({
  required String id,
  required String applicant,
  required String reference,
  required String address,
  required String barangay,
  required String status,
  required bool selfScheduled,
  String? visitDate,
  String? deadlineDate,
  String? submittedAt,
  String? instructions,
}) {
  return {
    'id': id,
    'status': status,
    'scheduled_date': visitDate,
    'deadline_date': deadlineDate,
    'is_self_scheduled': selfScheduled,
    'supabase_application_id': 'qa-app-$reference',
    'supabase_parcel_id': 'qa-parcel-$reference',
    'assignment_instructions': instructions,
    'assigned_by_name': 'QA Planning Officer (Synthetic)',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'submitted_at': submittedAt,
    'inspection_round_number': 1,
    'supabase_zoning_applications': {
      'applicant_name': applicant,
      'reference_number': reference,
      'barangay': barangay,
      'application_type': 'Zoning Clearance',
      'location_address': address,
    },
    'supabase_parcels': {
      'latitude': 14.5995,
      'longitude': 120.9842,
      'lot_area_sqm': 250,
      'declared_land_use': 'Single-detached residential',
      'location_address': address,
    },
  };
}

Future<void> _seedSyntheticData() async {
  final jobs = <Map<String, dynamic>>[
    _job(
      id: qaJobBlue,
      applicant: 'Maria Santos (Fictional)',
      reference: 'QA-2026-0001',
      address: '12 Mabini Street, Barangay San Roque',
      barangay: 'San Roque',
      status: 'assigned',
      selfScheduled: true,
      visitDate: _day(10),
      deadlineDate: _day(20),
      instructions: 'Fictional instruction: verify the front setback.',
    ),
    _job(
      id: qaJobOrange,
      applicant: 'Juan Dela Cruz (Fictional)',
      reference: 'QA-2026-0002',
      address: '48 Rizal Avenue, Barangay Poblacion',
      barangay: 'Poblacion',
      status: 'assigned',
      selfScheduled: true,
      visitDate: _day(2),
      deadlineDate: _day(20),
    ),
    _job(
      id: qaJobRed,
      applicant: 'Ana Reyes (Fictional)',
      reference: 'QA-2026-0003',
      address: '7 Luna Street, Barangay Malinis',
      barangay: 'Malinis',
      status: 'assigned',
      selfScheduled: true,
      visitDate: _day(1),
      deadlineDate: _day(20),
    ),
    _job(
      id: qaJobDueToday,
      applicant: 'Pedro Bautista (Fictional)',
      reference: 'QA-2026-0004',
      address: '3 Bonifacio Street, Barangay Bagong Silang',
      barangay: 'Bagong Silang',
      status: 'assigned',
      selfScheduled: true,
      visitDate: _day(0),
      deadlineDate: _day(20),
    ),
    _job(
      id: qaJobReschedule,
      applicant: 'Liza Mercado (Fictional)',
      reference: 'QA-2026-0005',
      address: '91 Mabini Extension, Barangay San Isidro',
      barangay: 'San Isidro',
      status: 'assigned',
      selfScheduled: true,
      visitDate: _day(-3),
      deadlineDate: _day(10),
    ),
    _job(
      id: qaJobOverdue,
      applicant: 'Carlo Villanueva (Fictional)',
      reference: 'QA-2026-0006',
      address: '5 Sampaguita Lane, Barangay Mabuhay',
      barangay: 'Mabuhay',
      status: 'assigned',
      selfScheduled: false,
      visitDate: _day(-8),
      deadlineDate: _day(-2),
    ),
    _job(
      id: qaJobAvailable,
      applicant: 'Grace Lim (Fictional)',
      reference: 'QA-2026-0007',
      address: '22 Acacia Street, Barangay Poblacion',
      barangay: 'Poblacion',
      status: 'assigned',
      selfScheduled: false,
      deadlineDate: _day(15),
    ),
    _job(
      id: qaJobInProgress,
      applicant: 'Ramon Aquino (Fictional)',
      reference: 'QA-2026-0008',
      address: '66 Narra Street, Barangay San Roque',
      barangay: 'San Roque',
      status: 'in_progress',
      selfScheduled: true,
      visitDate: _day(5),
      deadlineDate: _day(15),
    ),
    _job(
      id: qaJobCompleted,
      applicant: 'Teresa Ong (Fictional)',
      reference: 'QA-2026-0009',
      address: '18 Kalachuchi Street, Barangay Malinis',
      barangay: 'Malinis',
      status: 'completed',
      selfScheduled: true,
      visitDate: _day(-6),
      deadlineDate: _day(4),
      submittedAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 4))
          .toIso8601String(),
    ),
  ];

  final cached = await DBHelper.cacheJobs(jobs);
  if (!cached) {
    throw StateError('QA seed could not cache the synthetic assignments.');
  }

  // Real local inspection state, written through the app's own services, so
  // Task Overview, the flexible steps and the Sync Center show genuine
  // records rather than painted-on mockups.
  InspectionProgress.instance.ensureActiveInspection(
    qaJobInProgress,
    label: 'QA-2026-0008',
    initialStep: 0,
  );
  for (final step in [1, 2, 3]) {
    InspectionProgress.instance.markStepComplete(step);
  }

  // A second queued inspection action, so Sync Center shows a grouped queue.
  InspectionProgress.instance.ensureActiveInspection(
    qaJobAvailable,
    label: 'QA-2026-0007',
    initialStep: 0,
  );
  for (final step in [1, 2]) {
    InspectionProgress.instance.markStepComplete(step);
  }

  // Leave the inspection with the photographic evidence active.
  InspectionProgress.instance.ensureActiveInspection(
    qaJobInProgress,
    label: 'QA-2026-0008',
    initialStep: 0,
  );

  // QA-only fixture: a timeline tick for Step 2 is not the immutable on-site
  // fix snapshot the Site Location Reference renders. Seed one fictional fix
  // per in-progress job — inside the production 30 m distance / 25 m accuracy
  // gate of the seeded parcel point — and only when the app has no snapshot
  // yet. Production logic and its checks are untouched.
  for (final jobId in [qaJobAvailable, qaJobInProgress]) {
    if (await DBHelper.getGpsVerification(jobId) == null) {
      final now = DateTime.now().toUtc();
      await DBHelper.saveGpsVerification(
        jobId: jobId,
        latitude: 14.59962,
        longitude: 120.98431,
        accuracyMeters: 8,
        fixAt: now,
        verifiedAt: now,
      );
    }
  }

  await _seedPhotos();
  // Let the progress write queue reach the local store before the UI reads.
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

/// 12 small, genuinely valid JPEG files written to the QA app's private
/// storage, recorded through the same local photo table the camera uses.
Future<void> _seedPhotos() async {
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/qa_photos',
  );
  await directory.create(recursive: true);
  final bytes = base64Decode(
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
    'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==',
  );
  for (var index = 1; index <= 12; index++) {
    final label = index.toString().padLeft(2, '0');
    final file = File('${directory.path}/qa_site_$label.jpg');
    await file.writeAsBytes(bytes, flush: true);
    await DBHelper.savePhotoLocally(
      photoId: 'qa-photo-$label',
      jobId: qaJobInProgress,
      photoPath: file.path,
      notes: index == 1
          ? 'QA synthetic note: front setback measured from the barangay road.'
          : 'QA synthetic site photo $label.',
      latitude: 14.5995,
      longitude: 120.9842,
      capturedAt: DateTime.now()
          .toUtc()
          .subtract(Duration(minutes: 30 - index * 2))
          .toIso8601String(),
    );
  }
}

class _QaApp extends StatelessWidget {
  const _QaApp({required this.profile, required this.seedDay});

  final UserProfile profile;
  final DateTime seedDay;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldSync QA (Synthetic)',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: InsightTheme.blue1,
        colorScheme: ColorScheme.light(
          primary: InsightTheme.blue1,
          secondary: InsightTheme.blue2,
          surface: InsightTheme.surface,
          error: InsightTheme.red,
        ),
        scaffoldBackgroundColor: InsightTheme.bg,
      ),
      home: MainShellScreen(
        profile: profile,
        initialIndex: 1,
        offlineSession: true,
      ),
    );
  }
}
