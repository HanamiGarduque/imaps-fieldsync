// Fake Supabase transport only; no live backend, credentials or real data.
// Regression: the optional parcel `location_address` must never take down a
// task list or lose a job detail when the column is absent from the schema.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/supabase_service.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

void main() {
  final fixture = OfflineReliabilityFixture();
  setUpAll(fixture.initialize);
  setUp(fixture.reset);
  tearDown(fixture.closeCase);
  tearDownAll(fixture.dispose);

  for (final detail in [false, true]) {
    for (final mode in [
      'present',
      'null',
      'omitted',
      '42703',
      'PGRST204',
      'permission-denied',
      'unrelated-column',
      'transport',
    ]) {
      test('${detail ? 'detail' : 'list'} address $mode', () async {
        final reads = <http.Request>[];
        fixture.requestOverride = (request) async {
          if (request.url.path != '/rest/v1/field_jobs') return null;
          expect(request.method, 'GET');
          reads.add(request);
          expect(
            request.url.queryParameters['assigned_inspector_id'],
            'eq.$offlineInspector',
          );
          if (detail) {
            expect(request.url.queryParameters['id'], 'eq.$offlineJob');
          } else {
            expect(
              request.url.queryParameters['order'],
              'scheduled_date.asc.nullslast',
            );
          }
          final select = request.url.queryParameters['select']!;
          expect(select, contains('field_jobs_supabase_parcel_id_fkey'));
          expect(select, contains('field_job_reviews'));
          if (detail) expect(select, contains('field_job_photos'));

          http.Response reply(Object data, int status) => http.Response(
            jsonEncode(data),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          if (mode == 'transport') {
            throw const SocketException('Synthetic transport unavailable');
          }
          if (mode == 'permission-denied') {
            return reply({
              'code': '42501',
              'message':
                  'permission denied for supabase_parcels.location_address',
            }, 403);
          }
          if (mode == 'unrelated-column') {
            return reply({
              'code': '42703',
              'message': 'column field_jobs.deadline_date does not exist',
            }, 400);
          }
          if ((mode == '42703' || mode == 'PGRST204') &&
              select.contains('location_address')) {
            return reply({
              'code': mode,
              'message': mode == '42703'
                  ? 'column supabase_parcels_1.location_address does not exist'
                  : "Could not find the 'location_address' column of 'supabase_parcels' in the schema cache",
            }, 400);
          }
          final row = {
            'id': offlineJob,
            'status': 'in_progress',
            'assigned_inspector_id': offlineInspector,
            'supabase_zoning_applications': {
              'applicant_name': 'Synthetic applicant',
            },
            'supabase_parcels': {
              'latitude': 13.84,
              'longitude': 121.12,
              if (mode == 'present') 'location_address': 'Synthetic address',
              if (mode == 'null') 'location_address': null,
            },
          };
          return reply(detail ? row : [row], 200);
        };

        if ([
          'permission-denied',
          'unrelated-column',
          'transport',
        ].contains(mode)) {
          if (detail) {
            expect(await SupabaseService.fetchJobDetail(offlineJob), isNull);
          } else {
            await expectLater(SupabaseService.fetchMyJobs(), throwsA(anything));
          }
          expect(
            reads,
            hasLength(mode == 'transport' ? 4 : 1),
            reason: 'never remove the address for unrelated failures',
          );
          expect(
            reads.every(
              (r) =>
                  r.url.queryParameters['select']!.contains('location_address'),
            ),
            isTrue,
          );
          return;
        }

        final row = detail
            ? await SupabaseService.fetchJobDetail(offlineJob)
            : (await SupabaseService.fetchMyJobs()).single;
        expect(
          row,
          isNotNull,
          reason: 'optional missing address must not lose the job',
        );
        expect(row!['id'], offlineJob);
        final expected = mode == 'present' ? 'Synthetic address' : null;
        expect(TaskItem.fromJob(row).locationAddress, expected);
        await DBHelper.cacheJobs([row]);
        final cached = (await DBHelper.getCachedJobs()).singleWhere(
          (r) => r['id'] == offlineJob,
        );
        expect(TaskItem.fromCachedJob(cached).locationAddress, expected);
        expect(reads, hasLength(mode == '42703' || mode == 'PGRST204' ? 2 : 1));
        if (reads.length == 2) {
          final first = reads.first.url.queryParameters['select']!;
          final retry = reads.last.url.queryParameters['select']!;
          expect(
            retry,
            first.replaceFirst(RegExp(r',\s*location_address\b'), ''),
          );
        }
        expect(fixture.remoteWrites, 0);
      });
    }
  }
}
