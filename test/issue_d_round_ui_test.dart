import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imaps_fieldsync/core/navigation/parcel_detail_screen.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/inspection_progress.dart';
import 'package:imaps_fieldsync/modules/inspection/widgets/inspection_round_widgets.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'issue_d_round_context_test.dart' show issueDRound,issueDReason,issueDOwner;

Future<void> settleIssueD(WidgetTester tester) async {
  for(var i=0;i<8;i++) {
    await tester.pump(const Duration(milliseconds:100));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));
  }
}
void main() {
  final binding=TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching=false;
    final fonts=Directory('${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts');
    final bytes=ByteData.sublistView(fonts.listSync().whereType<File>()
      .firstWhere((f)=>f.path.endsWith('.ttf')).readAsBytesSync());
    final manifest=<String,Object>{};
    for(final family in ['Inter','Poppins','Urbanist','JetBrainsMono','Roboto']) {
      for(final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold','Light']) {
        final asset='$family-$weight.ttf'; manifest[asset]=[{'asset':asset}];
      }
    }
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async {
      final asset=const StringCodec().decodeMessage(m)!;
      if(asset=='AssetManifest.bin') return const StandardMessageCodec().encodeMessage(manifest);
      return asset.endsWith('.ttf')?bytes:null;
    });
  });
  setUp(() async {
    db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for(final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)')
      .allMatches(File('lib/core/services/db_helper.dart').readAsStringSync())) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting=issueDOwner;
    InspectionProgress.instance.reset();
    await DBHelper.cacheJobs([issueDRound(1,'completed'),issueDRound(2,'assigned')]);
    completedDetailFetcherOverride=(_)async=>issueDRound(1,'completed');
  });
  tearDown(()async {
    completedDetailFetcherOverride=null;
    DBHelper.inspectorIdForTesting=null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });
  Widget wrap(Widget child)=>ChangeNotifierProvider(create:(_)=>InspectionProvider(),
    child:MaterialApp(home:child));
  Future<int> writes()async=>(await db.rawQuery('SELECT total_changes() AS n')).single['n'] as int;

  testWidgets('reviewed old round has no rework controls and zero workflow writes',(tester)async {
    final before=await tester.runAsync(writes);
    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(task:TaskItem.fromJob(issueDRound(1,'completed')))));
    await settleIssueD(tester);
    expect(find.text('Historical inspection — Read only'),findsOneWidget);
    for(final title in ['Site Verification','GPS Verification','Photographic Evidence','Checklist','Field Findings','Review & Submit']) {
      await tester.dragUntilVisible(find.text(title).first,find.byType(ListView),const Offset(0,-250));
      await tester.tap(find.text(title).first);
      await settleIssueD(tester);
      expect(find.text('Rework this step'),findsNothing);
    }
    expect(await tester.runAsync(writes),before);
    expect((await tester.runAsync(DBHelper.getCachedJobs))!.firstWhere((r)=>r['id']=='round-1')['status'],'completed');
    expect(await tester.runAsync(()=>db.query('pending_actions')),isEmpty);
    expect(tester.takeException(),isNull);
  });
  testWidgets('historical mode blocks a previously captured mutation callback',(tester)async {
    completedDetailFetcherOverride=(_)async=>{...issueDRound(1,'completed'),'field_job_reviews':[]};
    final task=TaskItem.fromJob({...issueDRound(1,'completed'),'field_job_reviews':[]});
    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(task:task)));
    await settleIssueD(tester);
    await tester.tap(find.text('Site Verification').first);
    await settleIssueD(tester);
    final control=find.ancestor(of:find.text('Rework this step'),matching:find.byType(GestureDetector)).first;
    final staleCallback=tester.widget<GestureDetector>(control).onTap!;
    final before=await tester.runAsync(writes);
    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(task:task,historicalReadOnly:true)));
    staleCallback();
    await settleIssueD(tester);
    expect(find.byType(AlertDialog),findsNothing);
    expect(await tester.runAsync(writes),before);
  });
  testWidgets('active overview shows exact creator context without PO controls',(tester)async {
    final r1=TaskItem.fromJob(issueDRound(1,'completed'));
    final r2=TaskItem.fromJob(issueDRound(2,'assigned'));
    await tester.pumpWidget(wrap(ParcelDetailScreen(task:r2,relatedRounds:[r2,r1])));
    await settleIssueD(tester);
    expect(find.text('Task Overview'), findsOneWidget);
    // The compact round context container replaced the old loose round text.
    expect(find.text('INSPECTION ROUND'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Reinspection'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Planning Review'),find.byType(ListView),const Offset(0,-250));
    expect(find.text('Requires Reinspection'),findsOneWidget);
    expect(find.text(issueDReason),findsOneWidget);
    expect(find.text('Previous inspection: Round 1'),findsOneWidget);
    expect(find.textContaining('Reviewed:'),findsOneWidget);
    expect(find.byType(TextField),findsNothing);
    for(final label in ['Approved','Declined','Assign Inspector','Reassign Inspector','Edit Planning Review']) {
      expect(find.text(label),findsNothing);
    }
    expect(tester.takeException(),isNull);
  });
  testWidgets('completed task sent to overview is historical before start paths',(tester)async {
    final before=await tester.runAsync(writes);
    await tester.pumpWidget(wrap(ParcelDetailScreen(task:TaskItem.fromJob(issueDRound(1,'completed')))));
    await settleIssueD(tester);
    expect(find.text('Historical inspection — Read only'),findsOneWidget);
    expect(await tester.runAsync(writes),before);
    expect(await tester.runAsync(()=>db.query('inspection_job_retention')),isEmpty);
  });
  for(final status in ['assigned','in_progress','completed']) {
    testWidgets('round list keeps Completed Round 1 separate from $status Round 2',(tester)async {
      final r1=TaskItem.fromJob(issueDRound(1,'completed'));
      final r2=TaskItem.fromJob(issueDRound(2,status));
      String? opened;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:InspectionRoundList(
        rounds:[r1,r2],onOpen:(r)=>opened=r.id))));
      expect(find.text('Round 1'),findsOneWidget);
      expect(find.text('Reinspection — Round 2'),findsOneWidget);
      final old=find.byKey(const ValueKey('round-entry-round-1'));
      final active=find.byKey(const ValueKey('round-entry-round-2'));
      expect(find.descendant(of:old,matching:find.text('Completed')),findsOneWidget);
      expect(find.descendant(of:active,matching:find.text(r2.category)),findsOneWidget);
      await tester.tap(find.text('Round 1'));
      expect(opened,'round-1');
      await tester.tap(find.text('Reinspection — Round 2'));
      expect(opened,'round-2');
    });
  }
  testWidgets('normal Round 1 and unavailable previous round remain truthful',(tester)async {
    final r1=TaskItem.fromJob(issueDRound(1,'assigned'));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ReinspectionContextCard(task:r1))));
    expect(find.text('Planning Review'),findsNothing);
    expect(find.text('Reinspection'),findsNothing);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ReinspectionContextCard(
      task:TaskItem.fromJob(issueDRound(2,'assigned'))))));
    expect(find.text('Previous inspection: Previous inspection round'),findsOneWidget);
    expect(find.text('Previous inspection: Round 1'),findsNothing);
  });
}
