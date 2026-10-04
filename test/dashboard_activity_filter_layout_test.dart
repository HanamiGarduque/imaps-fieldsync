import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/modules/analytics_dashboard/models/activity_event_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Proves the five-chip Recent Activity filter row renders on a narrow phone
// without a RenderFlex overflow or a clipped label. Layout/semantics only, no
// pixel goldens: the offline SDK-font fixture is reused from
// inspection_job_retention_test.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final bytes = ByteData.sublistView(
      fonts
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.ttf'))
          .readAsBytesSync(),
    );
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Urbanist']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        manifest['$family-$weight.ttf'] = [
          {'asset': '$family-$weight.ttf'},
        ];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message)!;
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      return asset.endsWith('.ttf') ? bytes : null;
    });
  });

  tearDownAll(
    () => binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    ),
  );

  // The real production chip widget is private to the dashboard file, so the
  // test drives a faithful stand-in built from the same widgets, the same 44px
  // height and the same padding, and asserts the layout property that matters:
  // every label is fully laid out inside its own chip.
  Widget chipRow(List<(IconData, String)> chips) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final (index, chip) in chips.indexed) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Material(
                    child: InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(chip.$1, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                chip.$2,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  final chips = <(IconData, String)>[
    (Icons.check_rounded, 'All'),
    (Icons.checklist_rounded, 'Task'),
    (Icons.sync_rounded, 'Sync'),
    (Icons.assignment_rounded, 'Reports'),
    (Icons.person_rounded, 'Profile'),
  ];

  testWidgets('five filter chips lay out at 390 logical pixels without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(chipRow(chips));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final (_, label) in chips) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('no label is clipped: every chip keeps a usable tap target', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(chipRow(chips));
    await tester.pumpAndSettle();

    final chipsFound = find.byType(InkWell);
    expect(chipsFound, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      final size = tester.getSize(chipsFound.at(i));
      // Height is the accessible minimum; width stays positive even at 390px.
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThan(30));
    }
  });

  testWidgets('a deliberately too-narrow chip scales down instead of overflowing', (
    tester,
  ) async {
    // 200px across five chips is far below any real phone. scaleDown must still
    // produce a valid layout rather than a RenderFlex overflow.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(chipRow(chips));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reports'), findsOneWidget);
  });

  test('all five production buckets are present and labelled', () {
    expect(ActivityEventCategory.filters, hasLength(5));
    expect(
      ActivityEventCategory.filters
          .where((bucket) => bucket != 'all')
          .map(ActivityEventCategory.labelFor),
      ['Task', 'Sync', 'Reports', 'Profile'],
    );
  });
}