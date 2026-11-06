import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_targets.dart';

void main() {
  testWidgets(
    'replacing a page releases its targets before the next page mounts',
    (tester) async {
      final targets = GuideTargetRegistry();
      Widget page(int index) => MaterialApp(
        home: GuideTargetScope(
          registry: targets,
          child: SizedBox(
            key: ValueKey(index),
            child: const GuideTarget(id: 'replay-entry', child: Text('Replay')),
          ),
        ),
      );
      await tester.pumpWidget(page(1));
      await tester.pumpWidget(page(2));
      expect(tester.takeException(), isNull);
      expect(targets.contextFor('replay-entry'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      targets.dispose();
    },
  );
  testWidgets(
    'targets measure actual scrolled and reflowed bounds then unregister',
    (tester) async {
      final targets = GuideTargetRegistry();
      final host = GlobalKey();
      final scroll = ScrollController();
      addTearDown(targets.dispose);
      addTearDown(scroll.dispose);
      Future<void> layout({
        double width = 360,
        double scale = 1,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 400,
              child: GuideTargetScope(
                registry: targets,
                child: SizedBox(
                  key: host,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      children: [
                        const SizedBox(height: 220),
                        GuideTarget(
                          id: 'measured',
                          child: Text(
                            'A target that wraps when text is larger or the viewport narrows.',
                            textScaler: TextScaler.linear(scale),
                          ),
                        ),
                        const SizedBox(height: 600),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await layout();
      final box = host.currentContext!.findRenderObject()! as RenderBox;
      final before = targets.rectFor('measured', box)!;
      final actual = tester.getRect(
        find.text(
          'A target that wraps when text is larger or the viewport narrows.',
        ),
      );
      expect(before.topLeft, box.globalToLocal(actual.topLeft));
      expect(before.size, actual.size);
      scroll.jumpTo(120);
      await tester.pump();
      expect(
        targets.rectFor('measured', box)!.top,
        closeTo(before.top - 120, .01),
      );
      await layout(width: 220, scale: 2);
      await tester.pump();
      final reflowed = targets.rectFor('measured', box)!;
      expect(reflowed.height, greaterThan(before.height));
      expect(reflowed.width, 220);
      expect(targets.rectFor('missing', box), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(targets.contextFor('measured'), isNull);
      expect(targets.rectFor('measured', box), isNull);
    },
  );

  testWidgets(
    'pinned header and transform animations are measured rather than cached',
    (tester) async {
      final targets = GuideTargetRegistry();
      final host = GlobalKey();
      final scroll = ScrollController();
      addTearDown(targets.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: GuideTargetScope(
            registry: targets,
            child: SizedBox(
              key: host,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 180,
                    flexibleSpace: FlexibleSpaceBar(
                      title: GuideTarget(
                        id: 'header',
                        child: const Text('Pinned target'),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 1400)),
                ],
              ),
            ),
          ),
        ),
      );
      final box = host.currentContext!.findRenderObject()! as RenderBox;
      final expanded = targets.rectFor('header', box)!;
      final animation = scroll.animateTo(
        200,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final actual = tester.getRect(find.text('Pinned target'));
      expect(
        targets.rectFor('header', box)!.top,
        closeTo(box.globalToLocal(actual.topLeft).dy, .01),
      );
      await tester.pumpAndSettle();
      await animation;
      expect(targets.rectFor('header', box)!.height, lessThan(expanded.height));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'duplicate IDs fail explicitly instead of highlighting a sibling',
    (tester) async {
      final targets = GuideTargetRegistry();
      await tester.pumpWidget(
        MaterialApp(
          home: GuideTargetScope(
            registry: targets,
            child: const Column(
              children: [
                GuideTarget(id: 'duplicate', child: Text('First')),
                SizedBox(
                  height: 48,
                  child: GuideTarget(id: 'duplicate', child: Text('Second')),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.toString(),
          'duplicate diagnostic',
          contains('Duplicate mounted guide target'),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      targets.dispose();
    },
  );
}
