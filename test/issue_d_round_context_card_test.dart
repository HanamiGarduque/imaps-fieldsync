// Focused widget tests for the compact round context container on Task Overview.
//
// Visual refinement only: no round identity, status, category, historical-mode,
// navigation, sync or Planning Review authority may change. These tests pin the
// PRESENTATION contract, including that Round 1 never claims to be a
// reinspection and that nothing overflows on a narrow phone.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_round_widgets.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'issue_d_round_context_test.dart' show issueDReason, issueDRound, issueDOwner;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget host(WidgetTester tester, Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(360, 800)),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = Directory(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    );
    final bytes = ByteData.sublistView(fonts.listSync().whereType<File>()
        .firstWhere((f) => f.path.endsWith('.ttf')).readAsBytesSync());
    final manifest = <String, Object>{};
    for (final family in ['Inter', 'Poppins', 'Urbanist', 'JetBrainsMono', 'Roboto']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Light']) {
        final asset = '$family-$weight.ttf';
        manifest[asset] = [
          {'asset': asset}
        ];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (m) async {
      final asset = const StringCodec().decodeMessage(m)!;
      if (asset == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(manifest);
      return asset.endsWith('.ttf') ? bytes : null;
    });
  });

  setUp(() {
    DBHelper.inspectorIdForTesting = issueDOwner;
  });
  tearDown(() => DBHelper.inspectorIdForTesting = null);

  testWidgets('normal Round 1 shows round, kind, status and reference', (tester) async {
    await tester.pumpWidget(host(tester, RoundContextCard(
      task: TaskItem.fromJob(issueDRound(1, 'assigned')),
    )));
    await settle(tester);

    expect(find.text('INSPECTION ROUND'), findsOneWidget);
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Original Inspection'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('APP-ISSUE-D'), findsOneWidget);
  });

  testWidgets('no false Reinspection label or PO context on Round 1', (tester) async {
    await tester.pumpWidget(host(tester, RoundContextCard(
      task: TaskItem.fromJob(issueDRound(1, 'assigned')),
    )));
    await settle(tester);

    expect(find.text('Reinspection'), findsNothing);
    expect(find.text('Planning Review'), findsNothing);
    expect(find.text(issueDReason), findsNothing);
    expect(find.textContaining('Previous inspection'), findsNothing);
  });

  testWidgets('active Round 2 shows Reinspection kind with its own status', (tester) async {
    await tester.pumpWidget(host(tester, RoundContextCard(
      task: TaskItem.fromJob(issueDRound(2, 'in_progress')),
    )));
    await settle(tester);

    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Reinspection'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Original Inspection'), findsNothing);
  });

  testWidgets('historical Round 1 keeps Completed and Read only', (tester) async {
    await tester.pumpWidget(host(tester, RoundContextCard(
      task: TaskItem.fromJob(issueDRound(1, 'completed')),
      readOnly: true,
    )));
    await settle(tester);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Read only'), findsOneWidget);
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Original Inspection'), findsOneWidget);
  });

  testWidgets('the card is contextual, not a control', (tester) async {
    await tester.pumpWidget(host(tester, RoundContextCard(
      task: TaskItem.fromJob(issueDRound(2, 'assigned')),
    )));
    await settle(tester);

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('no overflow and the status chip survives a long reference', (tester) async {
    final base = issueDRound(2, 'in_progress');
    final application = Map<String, dynamic>.from(base['supabase_zoning_applications'] as Map)
      ..['reference_number'] = 'APP-2026-00036-VERY-LONG-REFERENCE-NUMBER-SUFFIX';
    final long = TaskItem.fromJob({...base, 'supabase_zoning_applications': application});

    await tester.pumpWidget(host(tester, RoundContextCard(task: long)));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.byType(Row), findsWidgets);
  });

  // The card is rendered from the REAL Task Overview in
  // issue_d_round_ui_test.dart, which already boots the Supabase mock that the
  // overview's draft load needs. Duplicating that harness here would only add a
  // second, slower copy of the same assertion.
}