import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';

void main() {
  for (final size in [
    const Size(844, 390),
    const Size(932, 430),
    const Size(640, 360),
    const Size(1280, 800),
    const Size(800, 1280),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('panel and trigger stay separate at $size / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.viewPadding = const FakeViewPadding(left: 24, bottom: 24);
        tester.view.padding = const FakeViewPadding(left: 24, bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              extendBody: true,
              body: Stack(
                children: [
                  const Positioned.fill(child: SizedBox()),
                  QuickActionsOverlay(
                    child: QuickActionsSheet(
                      fillAvailableSpace: true,
                      onClose: () {},
                      actions: [
                        for (final title in [
                          'Map',
                          'Compass',
                          'Analytics',
                          'Sync history',
                          'Edit profile',
                        ])
                          QuickAction(
                            icon: Icons.map,
                            title: title,
                            onTap: () => tapped = true,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: InsightBottomNav(
                currentIndex: 3,
                items: const [
                  InsightNavItem(icon: Icons.home, label: 'Home'),
                  InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
                  InsightNavItem(icon: Icons.sync, label: 'Sync'),
                  InsightNavItem(icon: Icons.person, label: 'Profile'),
                ],
                onTap: (_) {},
                isQuickActionsOpen: true,
                onQuickActionsTap: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panelWidget = tester
            .widgetList<Container>(find.byType(Container))
            .firstWhere(
              (c) => c.padding == const EdgeInsets.fromLTRB(8, 6, 8, 10),
            );
        final panel = tester.getRect(find.byWidget(panelWidget));
        final trigger = tester.getRect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Quick actions',
          ),
        );
        if (size.width >= 600) {
          expect(panel.right, lessThan(trigger.left));
          expect(panel.height, greaterThan(size.height * .5));
        } else {
          expect(panel.bottom, lessThan(trigger.top));
        }
        expect(panel.top, greaterThanOrEqualTo(16));
        final railWidget = tester
            .widgetList<Container>(find.byType(Container))
            .firstWhere((c) => c.padding == const EdgeInsets.all(8));
        final rail = tester.getRect(find.byWidget(railWidget));
        expect(panel.bottom, lessThanOrEqualTo(rail.top - 10));
        expect(tester.takeException(), isNull);
        // The last row must be reachable and tappable, not merely mounted.
        await tester.ensureVisible(find.text('Edit profile'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit profile'));
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'every row fits inside the panel without a half-cut row / $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.viewPadding = const FakeViewPadding(left: 24, bottom: 24);
          tester.view.padding = const FakeViewPadding(left: 24, bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                extendBody: true,
                body: Stack(
                  children: [
                    const Positioned.fill(child: SizedBox()),
                    QuickActionsOverlay(
                      child: QuickActionsSheet(
                        fillAvailableSpace: true,
                        onClose: () {},
                        actions: [
                          for (final title in [
                            'Map',
                            'Compass',
                            'Sync history',
                            'Edit profile',
                          ])
                            QuickAction(
                              icon: Icons.map,
                              title: title,
                              onTap: () {},
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: InsightBottomNav(
                  currentIndex: 3,
                  items: const [
                    InsightNavItem(icon: Icons.home, label: 'Home'),
                    InsightNavItem(icon: Icons.assignment, label: 'Tasks'),
                    InsightNavItem(icon: Icons.sync, label: 'Sync'),
                    InsightNavItem(icon: Icons.person, label: 'Profile'),
                  ],
                  onTap: (_) {},
                  isQuickActionsOpen: true,
                  onQuickActionsTap: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final panelWidget = tester
              .widgetList<Container>(find.byType(Container))
              .firstWhere(
                (c) => c.padding == const EdgeInsets.fromLTRB(8, 6, 8, 10),
              );
          final panel = tester.getRect(find.byWidget(panelWidget));
          if (size.height >= 380) {
            for (final label in [
              'Map',
              'Compass',
              'Sync history',
              'Edit profile',
            ]) {
              final text = find.text(label);
              expect(
                tester.getRect(text).top >= panel.top &&
                    tester.getRect(text).bottom <= panel.bottom,
                isTrue,
                reason:
                    'row $label must sit fully inside the panel at $size / $scale',
              );
            }
          } else {
            // Too short to show every row at once: the panel must still scroll
            // far enough to reveal the final row whole, never cut it off.
            await tester.dragFrom(panel.center, const Offset(0, -220));
            await tester.pumpAndSettle();
            final last = find.text('Edit profile');
            final row = tester.getRect(
              find
                  .ancestor(of: last, matching: find.byType(GestureDetector))
                  .last,
            );
            expect(
              row.bottom,
              lessThanOrEqualTo(panel.bottom + 1),
              reason: 'last row must be fully revealable at $size',
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
