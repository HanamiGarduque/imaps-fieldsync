import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'inspection_owner_fixture.dart';

TaskItem task({String status = 'in_progress'}) => TaskItem(
      id: 'job-1',
      name: 'Fixture',
      location: 'Fixture location',
      parcels: 'Fixture',
      status: status,
      inspectionNo: 'FIX-1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temp;
  late Database db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loop7e-delete-');
    db = await databaseFactoryFfi.openDatabase(
      '${temp.path}/fixture.db',
    );
    final source = await File('lib/core/services/db_helper.dart').readAsString();
    for (final match in RegExp(
      r'CREATE TABLE(?: IF NOT EXISTS)? (\w+)\([\s\S]*?\)',
    ).allMatches(source)) {
      await db.execute(match.group(0)!);
    }
    DBHelper.useDatabaseForTesting(db);
    useOwnerFixture();
  });

  tearDown(() async {
    clearOwnerFixture();
    DBHelper.useDatabaseForTesting(null);
    await db.close();
    await temp.delete(recursive: true);
  });

  test('pre-submit unsynced local photo removes file and local row', () async {
    final file = File('${temp.path}/evidence.jpg')..writeAsBytesSync([1, 2, 3]);
    final provider = InspectionProvider();
    await provider.startInspection(task());
    provider.addPhoto(
      photoPath: file.path,
      photoNotes: 'draft',
      latitude: null,
      longitude: null,
    );
    final id = provider.capturedPhotos.single['id'] as String;
    await DBHelper.savePhotoLocally(
      photoId: id,
      jobId: 'job-1',
      photoPath: file.path,
      notes: 'draft',
      latitude: null,
      longitude: null,
    );

    expect(await provider.removePhoto(0), isTrue);
    expect(provider.capturedPhotos, isEmpty);
    expect(await DBHelper.getLocalPhoto(id), isNull);
    expect(file.existsSync(), isFalse);
    provider.dispose();
  });

  test('completed and rework evidence cannot be removed', () async {
    final file = File('${temp.path}/completed.jpg')..writeAsBytesSync([1]);
    final provider = InspectionProvider();
    final item = task(status: 'completed');
    await provider.startInspection(item);
    provider.hydrateForRework(item);
    provider.addPhoto(
      photoPath: file.path,
      photoNotes: 'evidence',
      latitude: null,
      longitude: null,
    );
    expect(await provider.removePhoto(0), isFalse);
    expect(provider.capturedPhotos, hasLength(1));
    expect(file.existsSync(), isTrue);
    provider.dispose();
  });

  test('remote-work marker blocks removal even when local row is unsynced', () async {
    final file = File('${temp.path}/remote-work.jpg')..writeAsBytesSync([1]);
    final provider = InspectionProvider();
    await provider.startInspection(task());
    provider.addPhoto(
      photoPath: file.path,
      photoNotes: 'evidence',
      latitude: null,
      longitude: null,
    );
    provider.markPhotosSubmitted();

    expect(await provider.removePhoto(0), isFalse);
    expect(provider.capturedPhotos, hasLength(1));
    expect(file.existsSync(), isTrue);
    provider.dispose();
  });

  test('remote object and HTTP paths are never treated as local files', () async {
    final provider = InspectionProvider();
    await provider.startInspection(task());
    for (final path in [
      'inspections/job-1/photo_abc.jpg',
      'https://example.test/storage/v1/object/public/inspection-photos/x.jpg',
    ]) {
      provider.addPhoto(
        photoPath: path,
        photoNotes: 'remote',
        latitude: null,
        longitude: null,
      );
      expect(await provider.removePhoto(0), isFalse);
    }
    expect(provider.capturedPhotos, hasLength(2));
    provider.dispose();
  });

  test('canonical delete identity remains the canonical upload identity', () {
    const localPath = r'C:\photos\evidence.jpg';
    const jobId = 'job-1';
    final object = SupabaseService.photoStoragePath(jobId, localPath);
    final rowId = SupabaseService.photoRowId(object);
    expect(object, 'inspections/job-1/photo_${SupabaseService.stablePhotoKey(localPath)}.jpg');
    expect(rowId, isNotEmpty);
    expect(SupabaseService.photoRowId(object), rowId);
  });

  test('repository defines no remote photo DELETE policy', () async {
    final sql = await File('full.sql').readAsString();
    expect(sql.contains('FOR DELETE TO "authenticated" USING ((EXISTS'),
        isFalse);
    expect(sql.contains('field_job_photos" FOR DELETE'), isFalse);
    expect(sql.contains('storage.objects" FOR DELETE'), isFalse);
    expect(sql.contains('admins manage job photos'), isFalse);
  });
}
