import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'inspection_owner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('accepted offline GPS start must be Ongoing after restart', () async {
    const a = '11111111-1111-4111-8111-111111111111';
    const b = '22222222-2222-4222-8222-222222222222';
    final directory = await Directory.systemTemp.createTemp('fieldsync-start-verification-');
    final path = '${directory.path}/fixture.db';
    var db = await databaseFactoryFfi.openDatabase(path);
    try {
      final source = await File('lib/core/services/db_helper.dart').readAsString();
      for (final match in RegExp(
        r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
      ).allMatches(source)) {
        await db.execute(match.group(0)!);
      }
      DBHelper.useDatabaseForTesting(db);
      useOwnerFixture();
      await DBHelper.cacheJobs([
        {'id': a, 'status': 'assigned'},
        {'id': b, 'status': 'assigned'},
      ]);
      await DBHelper.retainInspectionJob(a);
      expect((await DBHelper.getCachedJobs()).first['status'], 'assigned');

      // Actual fallback called by normal GPS confirmation; synthetic coordinates
      // only. No Supabase initialization, HTTP, device GPS or drain is used.
      await SyncOutboxService.enqueueGpsConfirm(
        jobId: a, latitude: 0, longitude: 0, accuracyMeters: 1,
      );
      final queued = (await DBHelper.getActionableActions()).single;
      expect(queued['id'], 'gps_confirm_$a');
      expect(queued['job_id'], a);
      expect(queued['type'], 'gps_confirm');
      expect(queued['status'], 'pending');
      expect(queued['retry_count'], 0);
      expect(jsonDecode(queued['payload'] as String)['latitude'], 0);

      // Fixture completed-step persistence mirrors InspectionProgress's separate
      // local_inspections write; this is not a GPS widget/progress integration test.
      await DBHelper.saveInspectionLocally(
        jobId: a, actualLandUse: '', notes: '', isCompliant: false,
        inspectionResult: '', checklist: {}, boundaryStatus: '', currentStep: 2,
      );
      // Repeated exit fallback preserves canonical lifecycle and deduplicates.
      await SyncOutboxService.enqueueMarkOngoing(jobId: a);
      await SyncOutboxService.enqueueMarkOngoing(jobId: a);
      expect(await DBHelper.getActionableActions(), hasLength(2));
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      db = await databaseFactoryFfi.openDatabase(path);
      DBHelper.useDatabaseForTesting(db);
      final rows = await DBHelper.getCachedJobs();
      final rowA = rows.firstWhere((row) => row['id'] == a);
      final category = TaskItem.fromJob({...rowA, 'is_self_scheduled': false}).category;
      expect(category, 'Ongoing');
      expect(rows.firstWhere((row) => row['id'] == b)['status'], 'assigned');
      expect((await DBHelper.getLocalInspection(a))!['current_step'], 2);
      expect(await DBHelper.getLocalInspection(b), isNull);
      expect((await db.query('inspection_job_retention')).single['job_id'], a);
      expect(await DBHelper.getActionableActions(), hasLength(2));
      expect(rowA['status'], 'in_progress',
          reason: 'Accepted offline GPS start must establish local Ongoing lifecycle; '
              'reconstructed category was $category');
    } finally {
      clearOwnerFixture();
      DBHelper.useDatabaseForTesting(null);
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
