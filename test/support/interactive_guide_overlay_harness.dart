import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_overlay.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';

Widget guideOverlayHarness(
  GuideCoordinator guide,
  GuideTargetRegistry targets, {
  VoidCallback? realAction,
  VoidCallback? openSample,
  bool reducedMotion = true,
  TextScaler scaler = TextScaler.noScaling,
  EdgeInsets gestureInsets = EdgeInsets.zero,
  Widget? content,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: scaler,
          systemGestureInsets: gestureInsets,
        ),
        child: GuideOverlay(
          coordinator: guide,
          targets: targets,
          onOpenTask: openSample ?? guide.next,
          child: ListenableBuilder(
            listenable: guide,
            builder: (context, _) => Stack(
              children: [
                ?content,
                if (content == null &&
                    guide.phase == GuidePhase.active &&
                    guideStops[guide.stopIndex].targetId != 'guide_fingerprint')
                  Positioned(
                    key: const ValueKey('test-real-control'),
                    top: 40,
                    left: 24,
                    width: 200,
                    height: 56,
                    child: GuideTarget(
                      id: guideStops[guide.stopIndex].targetId,
                      child: FilledButton(
                        onPressed: realAction ?? () {},
                        child: const Text('Real control'),
                      ),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('test-fingerprint'),
                  right: 14,
                  bottom: 88,
                  child: GuideTarget(
                    id: 'guide_fingerprint',
                    child: SizedBox.square(
                      dimension: 64,
                      child: IconButton(
                        tooltip: 'Real Quick Actions',
                        onPressed: realAction ?? () {},
                        icon: const Icon(Icons.fingerprint),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> disposeGuideOverlay(
  WidgetTester tester,
  GuideCoordinator guide,
  GuideTargetRegistry targets,
) async {
  await tester.pumpWidget(const SizedBox());
  guide.dispose();
  targets.dispose();
}
