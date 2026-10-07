import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/report_queue_schema.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const ownerA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const ownerB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const report = TechnicalIssueDraft(title: 'Ownership fixture', module: 'Home',
  summary: 'Isolated ownership regression fixture.');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  String? reportOwner;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final source = File('lib/core/services/db_helper.dart').readAsStringSync();
    for (final m in RegExp(r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)').allMatches(source)) {
      await db.execute(m.group(0)!);
    }
    await ReportQueueSchema.createTable(db);
    DBHelper.useDatabaseForTesting(db);
    DBHelper.inspectorIdForTesting = ownerA;
    reportOwner = ownerA;
    ReportQueueService.inspectorIdOverride = () => reportOwner;
    ReportQueueService.connectivityOverride = () async => false;
  });
  tearDown(() async {
    ReportQueueService.resetTestHooks();
    DBHelper.inspectorIdForTesting = null;
    DBHelper.useDatabaseForTesting(null);
    await db.close();
  });

  test('new task flow records an owner in every ownership-bearing writer', () async {
    await DBHelper.cacheJobs([{'id': 'new-job', 'status': 'assigned'}]);
    await DBHelper.retainInspectionJob('new-job');
    await DBHelper.saveInspectionLocally(jobId: 'new-job', actualLandUse: 'Residential',
      notes: 'preserved', isCompliant: true, inspectionResult: 'Compliant',
      checklist: {}, boundaryStatus: 'Compliant', currentStep: 1);
    await DBHelper.savePhotoLocally(photoId: 'photo', jobId: 'new-job',
      photoPath: '/fixture/photo.jpg', notes: '', latitude: null, longitude: null);
    await DBHelper.enqueueAction(id: 'action', type: 'mark_ongoing',
      jobId: 'new-job', payload: {});
    await DBHelper.logSyncEvent(eventType: 'fixture', result: 'info', message: 'fixture', jobId: 'new-job');
    await ReportQueueService.enqueueTechnicalIssue(report);
    for (final table in ['local_jobs', 'local_inspections', 'local_photos',
      'pending_actions', 'inspection_job_retention', 'sync_log_entries', 'local_report_queue']) {
      expect((await db.query(table)).single['inspector_id'], ownerA, reason: table);
    }
  });

  test('session switch while sync event waits prevents persistence', () async {
    final write = DBHelper.logSyncEvent(eventType: 'fixture', result: 'info', message: 'A event');
    DBHelper.inspectorIdForTesting = ownerB;
    await expectLater(write, throwsStateError);
    expect(await db.query('sync_log_entries'), isEmpty);
  });

  test('session switch while report enqueue waits prevents persistence', () async {
    final write = ReportQueueService.enqueueTechnicalIssue(report);
    reportOwner = ownerB;
    await expectLater(write, throwsA(isA<ReportSubmissionException>()));
    expect(await db.query('local_report_queue'), isEmpty);
  });

  test('absent report identity never creates an unowned report', () async {
    reportOwner = null;
    await expectLater(ReportQueueService.enqueueTechnicalIssue(report),
      throwsA(isA<ReportSubmissionException>()));
    expect(await db.query('local_report_queue'), isEmpty);
  });

  test('fresh cache writer preserves existing legacy NULL and foreign rows', () async {
    await db.insert('local_jobs', {'id': 'legacy', 'status': 'assigned'});
    await db.insert('local_jobs', {'id': 'foreign', 'status': 'assigned', 'inspector_id': ownerB});
    final before = await db.query('local_jobs', orderBy: 'id');
    await DBHelper.cacheJobs([{'id': 'legacy', 'status': 'assigned'}, {'id': 'foreign', 'status': 'assigned'}]);
    expect(await db.query('local_jobs', orderBy: 'id'), before);
    await expectLater(DBHelper.requireOwnedJob(db, 'legacy', ownerA), throwsStateError);
    await expectLater(DBHelper.requireOwnedJob(db, 'foreign', ownerA), throwsStateError);
  });
}
