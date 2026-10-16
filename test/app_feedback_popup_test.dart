import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/app_feedback.dart';
import 'package:imaps_fieldsync/core/widgets/task_sync_indicator.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  fixture.widgetTest(
    'cloud feedback appears below the status bar with a dismiss control',
    (tester) async {
      await fixture.mount(
        tester,
        Scaffold(
          body: TaskSyncIndicator(
            phase: TaskRefreshPhase.fresh,
            hasSavedTasks: true,
            lastChecked: DateTime(2026, 10, 16, 15, 30),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Task data: up to date'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await fixture.capture(tester, 'cloud-top-popup-390-100');
      final message = find.textContaining('Task data is up to date.');
      expect(
        tester.getRect(message).top,
        inInclusiveRange(40, 150),
        reason: 'task feedback belongs in the top safe area',
      );
      final close = find.byTooltip('Dismiss notification');
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(message, findsNothing);
    },
  );

  fixture.widgetTest(
    'replacement cancels the previous timer and ignores its stale dismissal',
    (tester) async {
      VoidCallback? closeFirst;
      await fixture.mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => closeFirst = AppFeedback.show(
                    context,
                    message: 'First action completed.',
                  ),
                  child: const Text('First'),
                ),
                TextButton(
                  onPressed: () => AppFeedback.show(
                    context,
                    message: 'Second action completed.',
                  ),
                  child: const Text('Second'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('First'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Second'));
      await tester.pump();
      closeFirst!();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('First action completed.'), findsNothing);
      expect(find.text('Second action completed.'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-feedback-popup')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Second action completed.'), findsNothing);
    },
  );

  fixture.widgetTest(
    'large-text recovery stays readable and Retry invokes its action once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var retries = 0;
        await fixture.mount(
          tester,
          Scaffold(
            body: TaskSyncIndicator(
              phase: TaskRefreshPhase.failed,
              hasSavedTasks: false,
              onRetry: () => retries++,
            ),
          ),
          size: const Size(320, 640),
          textScale: 2,
        );
        await tester.tap(
          find.byTooltip('Task data: could not check for updates'),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        final popup = find.byKey(const ValueKey('app-feedback-popup'));
        final retry = find.byKey(const ValueKey('app-feedback-retry'));
        expect(popup, findsOneWidget, reason: 'recovery must not time out');
        expect(tester.getRect(popup).left, 16);
        expect(tester.getRect(popup).right, 304);
        expect(tester.getRect(popup).bottom, lessThanOrEqualTo(616));
        expect(retry.hitTestable(), findsOneWidget);
        expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
        expect(tester.getSemantics(popup).flagsCollection.isLiveRegion, isTrue);
        expect(tester.takeException(), isNull);
        await fixture.capture(tester, 'cloud-recovery-popup-320-200');
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(retries, 1);
        expect(popup, findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  fixture.widgetTest(
    'reduced motion is immediate and accessible feedback waits for dismissal',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            accessibleNavigation: true,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await fixture.mount(
        tester,
        Scaffold(
          body: TaskSyncIndicator(
            phase: TaskRefreshPhase.fresh,
            hasSavedTasks: true,
            lastChecked: DateTime(2026, 10, 16),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Task data: up to date'));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('app-feedback-popup'))).top,
        40,
        reason:
            'reduced-motion feedback appears at its final position immediately',
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('Last checked:'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss notification'));
      await tester.pump();
      expect(find.textContaining('Last checked:'), findsNothing);
    },
  );

  fixture.widgetTest(
    'action result survives its immediate navigation and releases the overlay on unmount',
    (tester) async {
      await fixture.mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open action page'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (pageContext) => Scaffold(
                    body: TextButton(
                      child: const Text('Save and return'),
                      onPressed: () {
                        AppFeedback.show(
                          pageContext,
                          message: 'Progress saved.',
                        );
                        Navigator.of(pageContext).pop();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open action page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and return'));
      await tester.pumpAndSettle();
      expect(find.text('Open action page'), findsOneWidget);
      expect(find.text('Progress saved.'), findsOneWidget);
      await fixture.unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
