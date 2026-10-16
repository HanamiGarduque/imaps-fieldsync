import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:imaps_fieldsync/core/theme/insight_theme.dart';
import 'package:imaps_fieldsync/core/widgets/insight_bottom_nav.dart';
import 'package:imaps_fieldsync/core/widgets/quick_actions_sheet.dart';

/// The redesigned Quick Actions trigger — a miniature of the nav rail:
/// a solid-white 64px pill with a 40px blue gradient core (the same fill
/// as the ACTIVE tab) and a white bolt; while the sheet is open the core
/// fills the whole button and the glyph becomes a close mark.
///
/// Functionality is exercised end to end through the real sheet and
/// overlay wiring: same open/close contract as before, every dismissal
/// path included.
const _actionTitles = [
  'Map',
  'Compass',
  'Analytics overview',
  'Sync history',
  'Edit profile',
];

/// Env-gated visual evidence: set IMAPS_QUICK_ACTIONS_TRIGGER_DIR to a
/// folder to write idle/open renders for review.
final String? _captureDir =
    Platform.environment['IMAPS_QUICK_ACTIONS_TRIGGER_DIR'];

class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.actions, this.initialOpen = false});

  final List<QuickAction> actions;

  /// Mirrors the shell's open flag so a test can mount straight into the
  /// open state (used by the visual captures).
  final bool initialOpen;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late bool _open = widget.initialOpen;

  void _close() {
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Stand-in for the dashboard behind the floating nav.
          const Positioned.fill(child: ColoredBox(color: InsightTheme.bg)),
          // Backdrop — mounted with the open flag, like the shell.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_open,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _open ? 1 : 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
                ),
              ),
            ),
          ),
          QuickActionsOverlay(
            child: IgnorePointer(
              ignoring: !_open,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _open ? 1 : 0,
                child: _open
                    ? QuickActionsSheet(
                        key: const ValueKey('quick_actions_open'),
                        actions: widget.actions,
                        onClose: _close,
                        fillAvailableSpace: true,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: InsightBottomNav(
        currentIndex: 0,
        items: const [
          InsightNavItem(icon: Icons.home_rounded, label: 'Home'),
          InsightNavItem(icon: Icons.assignment_rounded, label: 'Tasks'),
          InsightNavItem(icon: Icons.sync_rounded, label: 'Sync'),
          InsightNavItem(icon: Icons.person_rounded, label: 'Profile'),
        ],
        isQuickActionsOpen: _open,
        onQuickActionsTap: () => setState(() => _open = !_open),
        onTap: (_) => _close(),
      ),
    );
  }
}

List<QuickAction> _actions({void Function(String title)? onAction}) => [
      for (final title in _actionTitles)
        QuickAction(
          icon: Icons.map_outlined,
          title: title,
          onTap: () => onAction?.call(title),
        ),
    ];

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  List<QuickAction>? actions,
  double textScale = 1.0,
  double rightInset = 0,
  bool initialOpen = false,
  Key? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (rightInset > 0) {
    tester.view.padding = FakeViewPadding(right: rightInset);
    tester.view.viewPadding = FakeViewPadding(right: rightInset);
  }
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: captureKey == null
        ? null
        : (context, child) => RepaintBoundary(key: captureKey, child: child!),
    home: _Shell(
      // Fresh mount per pump so a previous capture's open state never leaks
      // into the next one.
      key: UniqueKey(),
      actions: actions ?? _actions(),
      initialOpen: initialOpen,
    ),
  ));
  await tester.pumpAndSettle();
  // Let the mocked font assets finish loading, then re-pump so text laid out
  // before they arrived re-renders with them (keeps captures free of the
  // test binding's placeholder glyphs).
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
}

/// The trigger's box, found the same way the existing nav tests do.
Rect _triggerRect(WidgetTester tester) => tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Quick actions',
      ),
    );

/// The trigger's own glyphs — the sheet has its own close icon, so icon
/// assertions are scoped to the trigger.
Finder _boltInTrigger() => find.descendant(
      of: find.bySemanticsLabel('Quick actions'),
      matching: find.byIcon(Icons.bolt_rounded),
    );

Finder _closeInTrigger() => find.descendant(
      of: find.bySemanticsLabel('Quick actions'),
      matching: find.byIcon(Icons.close_rounded),
    );

Rect _railRect(WidgetTester tester) {
  final railWidget = tester
      .widgetList<Container>(find.byType(Container))
      .firstWhere((c) => c.padding == const EdgeInsets.all(8));
  return tester.getRect(find.byWidget(railWidget));
}

/// Drives the real interaction: tap the trigger and let the sheet settle.
Future<void> _openViaTrigger(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Quick actions',
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapTrigger(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Quick actions',
  ));
}

Future<void> _writePng(
  WidgetTester tester,
  Key captureKey,
  String name, {
  Rect? crop,
  double pixelRatio = 1,
}) async {
  final dir = _captureDir!;
  Directory(dir).createSync(recursive: true);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    ui.Image out = image;
    if (crop != null) {
      final src = Rect.fromLTRB(
        crop.left * pixelRatio,
        crop.top * pixelRatio,
        crop.right * pixelRatio,
        crop.bottom * pixelRatio,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, 0, src.width, src.height),
        Paint(),
      );
      out = await recorder
          .endRecording()
          .toImage(src.width.round(), src.height.round());
    }
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    File('$dir${Platform.pathSeparator}$name')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Same font wiring as the Home layout suite: the SDK's real font bytes are
  // served for every Google Fonts family the theme asks for, so no test ever
  // attempts an HTTP font fetch — those flake inside runAsync captures.
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
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
    for (final family in ['Inter', 'Urbanist', 'OpenSans']) {
      for (final weight in [
        'Thin',
        'Light',
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Black',
      ]) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset},
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
      if (!asset.endsWith('.ttf')) return null;
      return bytes;
    });
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(
        File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync(),
      )));
    await icons.load();
  });

  group('T1. the trigger sits in the band above the rail', () {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
      const Size(844, 390),
      const Size(800, 1280),
    ]) {
      testWidgets('fixed 64px button at $size', (tester) async {
        await _pumpShell(tester, size);
        final trigger = _triggerRect(tester);
        final rail = _railRect(tester);

        expect(trigger.width, closeTo(64, 0.01), reason: '$size');
        expect(trigger.height, closeTo(64, 0.01), reason: '$size');
        // Right-aligned inside the nav's 14px horizontal padding.
        expect(trigger.right, closeTo(size.width - 14, 0.5), reason: '$size');
        // Top band of the nav box: 76px above the box bottom edge, plus the
        // nav's 10px vertical padding.
        expect(trigger.bottom, closeTo(size.height - 86, 0.5), reason: '$size');
        expect(trigger.top, closeTo(size.height - 150, 0.5), reason: '$size');
        // Never covers the rail or the dashboard content above it.
        expect(trigger.bottom, lessThanOrEqualTo(rail.top),
            reason: 'the trigger floats above the rail at $size');
        expect(tester.takeException(), isNull, reason: '$size');
      });
    }

    testWidgets('an enlarged text scale does not move the trigger',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844), textScale: 1.3);
      final trigger = _triggerRect(tester);
      expect(trigger.width, closeTo(64, 0.01));
      expect(trigger.height, closeTo(64, 0.01));
      expect(trigger.right, closeTo(376, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a right safe-area inset keeps the button inside it',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844), rightInset: 24);
      final trigger = _triggerRect(tester);
      expect(trigger.right, closeTo(390 - 24 - 14, 0.5));
      expect(trigger.width, closeTo(64, 0.01));
      // Opening the sheet does not move the button.
      await _openViaTrigger(tester);
      expect(_triggerRect(tester).right, closeTo(390 - 24 - 14, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the bolt mark, not the old circular chevron',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      expect(_boltInTrigger(), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing,
          reason: 'the redesigned trigger replaces the circular arrow button');
      expect(find.bySemanticsLabel('Quick actions'), findsOneWidget);
    });
  });

  group('T2. tap the trigger → sheet opens; every dismissal closes it', () {
    testWidgets('the sheet opens with the live action list', (tester) async {
      final fired = <String>[];
      await _pumpShell(
        tester,
        const Size(390, 844),
        actions: _actions(onAction: fired.add),
      );

      await _openViaTrigger(tester);
      expect(find.byKey(const ValueKey('quick_actions_open')), findsOneWidget);
      for (final title in _actionTitles) {
        expect(find.text(title), findsOneWidget, reason: '$title still listed');
      }

      // Every action still fires its own callback.
      await tester.tap(find.text('Compass'));
      await tester.pumpAndSettle();
      expect(fired, ['Compass']);
    });

    testWidgets('the open state swaps the bolt for a close mark',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      await _openViaTrigger(tester);
      expect(_closeInTrigger(), findsOneWidget);
      expect(_boltInTrigger(), findsNothing);

      await tester.tap(find.byTooltip('Close quick actions'));
      await tester.pumpAndSettle();
      expect(_boltInTrigger(), findsOneWidget);
      expect(_closeInTrigger(), findsNothing);
    });

    testWidgets('closing via the close button resets the trigger',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      await _openViaTrigger(tester);

      await tester.tap(find.byTooltip('Close quick actions'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing);
      expect(_boltInTrigger(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing via the backdrop resets the trigger', (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      await _openViaTrigger(tester);

      await tester.tapAt(const Offset(24, 120));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing);
      expect(_boltInTrigger(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing by moving to another tab resets the trigger',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      await _openViaTrigger(tester);

      await tester.tap(find.byIcon(Icons.sync_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing);
      expect(_boltInTrigger(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the trigger still toggles the sheet closed when tapped open',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      await _openViaTrigger(tester);

      await _tapTrigger(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing);
      expect(_boltInTrigger(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the open → close cycle repeats without glitches',
        (tester) async {
      await _pumpShell(tester, const Size(390, 844));
      for (var cycle = 0; cycle < 3; cycle++) {
        await _openViaTrigger(tester);
        expect(find.byKey(const ValueKey('quick_actions_open')), findsOneWidget,
            reason: 'cycle $cycle open');
        expect(_closeInTrigger(), findsOneWidget,
            reason: 'cycle $cycle shows the close mark');

        await tester.tap(find.byTooltip('Close quick actions'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing,
            reason: 'cycle $cycle closed');
        expect(_boltInTrigger(), findsOneWidget,
            reason: 'cycle $cycle back to the bolt');
        expect(tester.takeException(), isNull, reason: 'cycle $cycle');
      }
    });

    testWidgets('the open sequence also works in landscape', (tester) async {
      await _pumpShell(tester, const Size(844, 390));
      await _openViaTrigger(tester);
      expect(find.byKey(const ValueKey('quick_actions_open')), findsOneWidget);
      expect(_triggerRect(tester).right, closeTo(844 - 14, 0.5));

      await tester.tap(find.byTooltip('Close quick actions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick_actions_open')), findsNothing);
      expect(_boltInTrigger(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('T3. visual evidence', () {
    testWidgets('writes idle and open renders', skip: _captureDir == null,
        (tester) async {
      const captureKey = ValueKey('capture');
      // Portrait, idle.
      await _pumpShell(tester, const Size(390, 844), captureKey: captureKey);
      var trigger = _triggerRect(tester);
      await _writePng(tester, captureKey, 'home-idle.png', pixelRatio: 2);
      await _writePng(
        tester,
        captureKey,
        'trigger-idle-zoom.png',
        crop: Rect.fromLTRB(
            trigger.left - 90, trigger.top - 70, 390, trigger.bottom + 42),
        pixelRatio: 4,
      );

      // Portrait, open with the sheet up.
      await _openViaTrigger(tester);
      trigger = _triggerRect(tester);
      await _writePng(tester, captureKey, 'home-open.png', pixelRatio: 2);
      await _writePng(
        tester,
        captureKey,
        'trigger-open-zoom.png',
        crop: Rect.fromLTRB(
            trigger.left - 90, trigger.top - 70, 390, trigger.bottom + 42),
        pixelRatio: 4,
      );

      // Landscape, idle.
      await _pumpShell(tester, const Size(844, 390), captureKey: captureKey);
      trigger = _triggerRect(tester);
      await _writePng(
          tester, captureKey, 'home-landscape-idle.png', pixelRatio: 2);
      await _writePng(
        tester,
        captureKey,
        'trigger-landscape-idle-zoom.png',
        crop: Rect.fromLTRB(
            trigger.left - 90, trigger.top - 70, 844, trigger.bottom + 42),
        pixelRatio: 4,
      );

      // Narrow phone, idle.
      await _pumpShell(tester, const Size(320, 568), captureKey: captureKey);
      await _writePng(
          tester, captureKey, 'home-narrow-idle.png', pixelRatio: 2);

      // 1.3x text on a tablet width, open (uses the initial-open path so the
      // sheet lays out immediately).
      await _pumpShell(tester, const Size(800, 1280),
          captureKey: captureKey, textScale: 1.3, initialOpen: true);
      await _writePng(
          tester, captureKey, 'home-tablet-open-1.3x.png', pixelRatio: 1);

      expect(tester.takeException(), isNull);
    });
  });
}
