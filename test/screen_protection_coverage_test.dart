import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/auth_startup/services/screen_protection_service.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/screens/home_dashboard_screen.dart';
import 'package:imaps_fieldsync/modules/offline_sync/screens/updates_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_edit_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/application_support_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/reports_support_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/report_history_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/technical_issue_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/help_faq_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/about_insight_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/terms_privacy_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/photo_viewer.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/review_submit_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  final profile = UserProfile.fromMap(offlineProfile);
  setUpAll(fixture.initialize);
  setUp(() async {
    // The production service reaches the real plugin channel; answer it with a
    // successful no-op so the tests observe protection policy, not a
    // harness-missing plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('screen_protector'),
          (call) async => null,
        );
    await fixture.reset();
  });
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  final sensitivePages = <String, Widget Function()>{
    'Home dashboard': () => HomeDashboardScreen(profile: profile),
    'Sync Center': () => UpdatesScreen(profile: profile),
    'Profile': () => ProfileScreen(profile: profile),
    'Profile Edit': () => ProfileEditScreen(profile: profile),
    'Application Support': () =>
        ApplicationSupportScreen(loadTasks: () async => []),
    'Support Desk': () => ReportsSupportScreen(loadLocal: () async => []),
    'Report History list': () => ReportHistoryScreen(
      loadLocal: () async => [],
      loadRemote: () async => [],
    ),
    'Technical Issue': () => const TechnicalIssueScreen(),
    'Fullscreen inspection photograph': () =>
        const FullscreenPhotoViewer(photoPaths: [], startIndex: 0),
    'Submission reference and assessment': () => const SubmissionSuccessScreen(
      referenceNo: 'FICTIONAL-REFERENCE',
      finalStatus: 'Fictional assessment',
    ),
  };
  for (final entry in sensitivePages.entries) {
    fixture.widgetTest('${entry.key} activates a sensitive policy', (
      tester,
    ) async {
      expect(ScreenProtectionService.instance.requiresProtection, isFalse);
      await fixture.mount(tester, entry.value());
      await fixture.flush(tester);
      expect(ScreenProtectionService.instance.requiresProtection, isTrue);
      expect(ScreenProtectionService.instance.appliedProtection, isTrue);
    });
  }
  for (final page in <String, Widget Function()>{
    'Help FAQ': () => const HelpFaqScreen(),
    'About': () => const AboutInsightScreen(),
    'Legal information': () => const TermsPrivacyScreen(),
  }.entries) {
    fixture.widgetTest('${page.key} does not activate sensitive policy', (
      tester,
    ) async {
      await fixture.mount(tester, page.value());
      await fixture.flush(tester);
      expect(ScreenProtectionService.instance.requiresProtection, isFalse);
    });
  }
}
