import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/widgets/home_guide_sections.dart';
import 'package:imaps_fieldsync/modules/profile_settings/widgets/profile_action_sections.dart';
import 'package:imaps_fieldsync/modules/tasks/widgets/task_card_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/interactive_guide_test_support.dart';

void main() {
  setUpAll(prepareGuideTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets(
    'Home identity preserves greeting, connection, badge and normal callbacks',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = <String>[];
      await show(
        tester,
        HomeInspectorSection(
          initials: 'AL',
          displayName: 'Ana Li',
          greeting: 'Good morning,',
          online: false,
          hasUnread: true,
          onEditProfile: () => actions.add('edit'),
          onNotifications: () => actions.add('bell'),
        ),
      );
      expect(find.text('Ana Li'), findsOneWidget);
      expect(find.text('Good morning,'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification_unread_badge')),
        findsOneWidget,
      );
      expect(actions, isEmpty);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Edit profile\b')));
      expect(actions, ['bell', 'edit']);
      semantics.dispose();
    },
  );

  testWidgets(
    'Home chart keeps category counts, colors, overdue and detail dispatch',
    (tester) async {
      var details = 0;
      await show(
        tester,
        HomeTaskStatusChart(
          total: 10,
          labels: const ['Scheduled', 'Pending', 'Ongoing', 'Completed'],
          colors: const [
            InsightTheme.orange,
            InsightTheme.blue1,
            InsightTheme.lightBlue,
            InsightTheme.green,
          ],
          counts: const [1, 2, 3, 4],
          overdueCount: 1,
          isLoading: false,
          hasTasks: true,
          onMoreDetails: () => details++,
        ),
      );
      for (final label in [
        'Scheduled',
        'Pending',
        'Ongoing',
        'Completed',
        'Overdue',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final dot = tester.widget<Container>(
        find.byKey(const ValueKey('completion_icon_Overdue')),
      );
      expect((dot.decoration as BoxDecoration).color, InsightTheme.red);
      await tester.tap(find.text('More details'));
      expect(details, 1);
    },
  );

  testWidgets(
    'calendar preview is display-only without writing saved view selection',
    (tester) async {
      final store = await SharedPreferences.getInstance();
      await store.setInt('home_calendar_view_owner', 1);
      await show(
        tester,
        SizedBox(
          height: 180,
          child: HomeCalendarPreview(
            month: DateTime(2026, 11),
            selectedDay: 2,
            dayColors: const {},
          ),
        ),
      );
      expect(find.text('November 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next preview month'));
      expect(store.getInt('home_calendar_view_owner'), 1);
      expect(store.getKeys(), {'home_calendar_view_owner'});
    },
  );

  testWidgets(
    'task display keeps separate date labels, progress and inert actions',
    (tester) async {
      await show(
        tester,
        TaskCardContent(
          name: 'Sample Applicant — Fictional',
          reference: 'GUIDE-SAMPLE',
          location: 'Sample District — Fictional',
          visitDate: 'Nov 4, 2026',
          deadline: 'Nov 10, 2026',
          statusLabel: 'In Progress',
          step: 2,
          statusColor: InsightTheme.orange,
        ),
      );
      expect(find.text('Visit date'), findsOneWidget);
      expect(find.text('PO Deadline'), findsOneWidget);
      expect(find.text('STEP 2/6'), findsOneWidget);
      expect(find.text('GUIDE-SAMPLE'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Profile groups preserve order and dispatch only supplied actions',
    (tester) async {
      final actions = <String>[];
      await show(
        tester,
        ProfileActionSections(
          appVersion: 'Version 1',
          onSecurity: () => actions.add('security'),
          onHelp: () => actions.add('help'),
          onSupport: () => actions.add('support'),
          onTerms: () => actions.add('terms'),
          onPrivacy: () => actions.add('privacy'),
          onStorage: () => actions.add('storage'),
          onAbout: () => actions.add('about'),
          onLogout: () => actions.add('logout'),
        ),
      );
      final labels = [
        'Security & Protection',
        'Help & FAQ',
        'Support Desk',
        'Terms & Conditions',
        'Privacy Policy',
        'Cookie & Storage Policy',
        'About iMAPS',
        'Log Out',
      ];
      expect(actions, isEmpty);
      for (final label in labels) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
      }
      expect(actions, [
        'security',
        'help',
        'support',
        'terms',
        'privacy',
        'storage',
        'about',
        'logout',
      ]);
      await show(tester, const ProfileActionSections(appVersion: 'Sample'));
      await tester.tap(find.text('Security & Protection'));
      expect(actions, hasLength(8));
      expect(
        tester
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('Security & Protection'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );
    },
  );
}
