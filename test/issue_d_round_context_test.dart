import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const issueDOwner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const issueDReason = 'Controlled Issue D reinspection context test';
Map<String, dynamic> issueDRound(int round, String status) => {
  'id': 'round-$round', 'local_inspection_id': 100 + round,
  'supabase_application_id': 'application', 'bridge_source_id': 'bridge',
  'inspection_round_number': round,
  'previous_site_inspection_id': round == 1 ? null : 100 + round - 1,
  'reinspection_reason': round == 1 ? null : issueDReason,
  'reinspection_reviewed_at': round == 1 ? null : '2026-10-07T01:02:03Z',
  'status': status, 'current_step': status == 'completed' ? 6 : 0,
  'supabase_zoning_applications': {'reference_number': 'APP-ISSUE-D',
    'applicant_name': 'Controlled Applicant', 'barangay': 'Alupay'},
  'supabase_parcels': <String,dynamic>{},
  'field_job_reviews': round != 1 ? [] : [{
    'decision': 'Requires Reinspection', 'decision_reason': issueDReason,
    'reviewed_site_inspection_id': 101, 'technical_review_id': 501,
    'reviewed_at': '2026-10-07T01:02:03Z',
  }],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  final selects = <String>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://issue-d.test', publishableKey: 'test-key',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((r) async {
        expect(r.method, 'GET', reason: 'Fetching context never mutates it');
        selects.add(r.url.queryParameters['select'] ?? '');
        return http.Response(jsonEncode(r.url.queryParameters['id'] != null
          ? issueDRound(2,'assigned') : [issueDRound(1,'completed'),issueDRound(2,'assigned')]),
          200, headers: {'content-type':'application/json'}, request: r);
      }));
    await SupabaseService.client.auth.setInitialSession(jsonEncode({
      'access_token':'isolated-token','refresh_token':'isolated-refresh',
      'token_type':'bearer','expires_in':3600,
      'user':{'id':issueDOwner,'app_metadata':{},'user_metadata':{},
        'aud':'authenticated','created_at':'2026-01-01T00:00:00Z'},
    }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    selects.clear();
  });
  tearDown(() async { DBHelper.useDatabaseForTesting(null); await db.close(); });

  test('cache preserves authoritative context and reviewed-round reason', () async {
    await DBHelper.cacheJobs([issueDRound(1,'completed'),issueDRound(2,'assigned')]);
    final rows = await DBHelper.getCachedJobs();
    final old = rows.firstWhere((r)=>r['id']=='round-1');
    final active = rows.firstWhere((r)=>r['id']=='round-2');
    expect(active['inspection_round_number'],2);
    expect(active['previous_site_inspection_id'],101);
    expect(active['reinspection_reason'],issueDReason);
    expect(active['reinspection_reviewed_at'],'2026-10-07T01:02:03Z');
    expect(old['reinspection_reason'],isNull);
    expect(jsonDecode(old['planning_review'] as String)['decision_reason'],issueDReason);
  });
  test('list and completed fetches request context, detail embeds review reason', () async {
    await SupabaseService.fetchMyJobs();
    await SupabaseService.fetchCompletedJobs();
    await SupabaseService.fetchJobDetail('round-2');
    for (final select in selects.take(2)) {
      for (final field in ['inspection_round_number','previous_site_inspection_id',
        'reinspection_reason','reinspection_reviewed_at']) { expect(select,contains(field)); }
    }
    expect(selects.first,contains('decision_reason'));
    expect(selects.last,contains('decision_reason'));
  });
  test('remote and offline model agree without sharing round state', () async {
    await DBHelper.cacheJobs([issueDRound(1,'completed'),issueDRound(2,'assigned')]);
    final rows = await DBHelper.getCachedJobs();
    final active = TaskItem.fromCachedJob(rows.firstWhere((r)=>r['id']=='round-2'));
    expect(active.localInspectionId,102);
    expect(active.roundLabel,'Reinspection — Round 2');
    expect(active.previousSiteInspectionId,101);
    expect(active.reinspectionReason,issueDReason);
    expect(active.reinspectionReviewedAt,'2026-10-07T01:02:03Z');
    final old = TaskItem.fromCachedJob(rows.firstWhere((r)=>r['id']=='round-1'));
    expect(old.roundLabel,'Round 1');
    expect(old.planningReview!.decisionReason,issueDReason);
    expect(active.previousRoundLabel([active,old]),'Round 1');
    expect(active.previousRoundLabel([]),'Previous inspection round');
    final wrongApplication = TaskItem.fromJob({...issueDRound(1,'completed'),
      'supabase_application_id':'unrelated'});
    expect(active.previousRoundLabel([wrongApplication]),'Previous inspection round');
    expect(old.category,'Completed');
    expect(active.category,'Pending');
    expect(old.isReinspection,isFalse);
    expect(old.reinspectionReason,isNull);
  });
  test('v17 upgrade preserves cached rows and evidence across reopen', () async {
    final dir = await Directory.systemTemp.createTemp('issue-d-v18-');
    final path='${dir.path}/upgrade.db';
    var oldDb=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(
      version:17,onCreate:(d,_) async {
        await d.execute('CREATE TABLE local_jobs(id TEXT PRIMARY KEY, status TEXT, local_inspection_id INTEGER)');
        await d.execute('CREATE TABLE local_inspections(id TEXT PRIMARY KEY, notes TEXT, current_step INTEGER)');
        await d.insert('local_jobs',{'id':'legacy','status':'completed','local_inspection_id':101});
        await d.insert('local_inspections',{'id':'legacy','notes':'preserved findings','current_step':6});
      }));
    final jobs=await oldDb.query('local_jobs');
    final evidence=await oldDb.query('local_inspections');
    await oldDb.close();
    oldDb=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(
      version:18,onUpgrade:(d,_,_)=>DBHelper.applyV18(d)));
    await DBHelper.applyV18(oldDb);
    final row=(await oldDb.query('local_jobs')).single;
    for (final key in ['inspection_round_number','previous_site_inspection_id',
      'reinspection_reason','reinspection_reviewed_at']) { expect(row[key],isNull); }
    expect({for(final key in jobs.single.keys) key:row[key]},jobs.single);
    expect(await oldDb.query('local_inspections'),evidence);
    final legacy=TaskItem.fromCachedJob(Map<String,dynamic>.from(row));
    expect(legacy.roundLabel,isNull);
    expect(legacy.isReinspection,isFalse);
    await oldDb.update('local_jobs',{'inspection_round_number':2,
      'previous_site_inspection_id':100,'reinspection_reason':issueDReason,
      'reinspection_reviewed_at':'2026-10-07T01:02:03Z'});
    await oldDb.close();
    oldDb=await databaseFactoryFfi.openDatabase(path);
    final restored=TaskItem.fromCachedJob(Map<String,dynamic>.from((await oldDb.query('local_jobs')).single));
    expect(restored.roundLabel,'Reinspection — Round 2');
    expect(restored.reinspectionReason,issueDReason);
    expect(restored.reinspectionReviewedAt,'2026-10-07T01:02:03Z');
    await oldDb.close();
    await dir.delete(recursive:true);
  });
}
