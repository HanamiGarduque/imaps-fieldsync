// Reports & Support contract: remote payload shape per report type, the
// inspector-authored vs admin-review field split, the exact-identity gate, and
// local/remote history reconciliation.
//
// Pure logic only — no network, no database.

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/report_models.dart';
import 'package:imaps_fieldsync/core/services/report_submission_service.dart';
import 'package:imaps_fieldsync/modules/profile_settings/services/diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReportQueueService.resetTestHooks();
    ReportQueueService.inspectorIdOverride = () => 'inspector-uuid';
  });

  DiagnosticReport report(Map<String, dynamic> overrides) =>
      DiagnosticReport.fromMap({
        'id': 'remote-1',
        'reference_code': 'DR-2026-0001',
        'title': 't',
        'summary': 's',
        'status': 'submitted',
        'report_type': 'technical_issue',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
        ...overrides,
      });

  LocalReportRow localRow(
    String id,
    ReportQueueState state, {
    String? remoteId,
  }) => LocalReportRow(
    id: id,
    reportType: ReportType.technicalIssue,
    payload: const {'title': 't', 'summary': 's'},
    queueState: state,
    retryCount: 0,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
    remoteReportId: remoteId,
  );

  group('hasDetail — admin review signal only', () {
    test('repro_steps alone is NOT a review signal', () {
      expect(report({'repro_steps': 'tap it'}).hasDetail, isFalse);
    });

    test('technical_description is a review signal', () {
      expect(report({'technical_description': 'x'}).hasDetail, isTrue);
    });

    test('affected_file is a review signal', () {
      expect(report({'affected_file': 'lib/a.dart'}).hasDetail, isTrue);
    });

    test('recommended_action is a review signal', () {
      expect(report({'recommended_action': 'fix it'}).hasDetail, isTrue);
    });

    test('an official MPDO response IS a review signal', () {
      expect(
        report({
          'status': 'resolved',
          'response_message': 'testing. okay na beh',
          'responded_by_name': 'Jyerine Desunia',
          'responded_at': '2026-10-03T23:03:37Z',
        }).hasDetail,
        isTrue,
      );
    });

    test('a terminal status with NO response is still not reviewed', () {
      // Status alone is never evidence. Only a real response proves review.
      expect(report({'status': 'resolved'}).hasDetail, isFalse);
      expect(report({'status': 'wont_fix'}).hasDetail, isFalse);
    });
  });

  group('official response — parse, tolerate, never fabricate', () {
    test('parses response_message, responded_by_name and responded_at', () {
      final r = report({
        'status': 'resolved',
        'response_message': 'testing. okay na beh',
        'responded_by_name': 'Jyerine Desunia',
        'responded_at': '2026-10-03T23:03:37Z',
      });
      expect(r.responseMessage, 'testing. okay na beh');
      expect(r.respondedByName, 'Jyerine Desunia');
      expect(r.respondedAt, DateTime.utc(2026, 10, 3, 23, 3, 37));
    });

    test('wont_fix parses exactly like resolved', () {
      final r = report({
        'status': 'wont_fix',
        'response_message': 'Not a defect.',
        'responded_by_name': 'Jyerine Desunia',
        'responded_at': '2026-10-03T23:03:37Z',
      });
      expect(r.hasOfficialResponse, isTrue);
      expect(r.responseMessage, 'Not a defect.');
    });

    test('missing keys stay null and do not crash (legacy row)', () {
      final r = report({'status': 'submitted'});
      expect(r.responseMessage, isNull);
      expect(r.respondedByName, isNull);
      expect(r.respondedAt, isNull);
      expect(r.hasOfficialResponse, isFalse);
    });

    test('explicit nulls stay null and do not crash', () {
      final r = report({
        'status': 'in_review',
        'response_message': null,
        'responded_by_name': null,
        'responded_at': null,
      });
      expect(r.responseMessage, isNull);
      expect(r.respondedAt, isNull);
      expect(r.hasOfficialResponse, isFalse);
    });

    test('a malformed timestamp never crashes parsing', () {
      final r = report({
        'status': 'resolved',
        'response_message': 'ok',
        'responded_at': 'not-a-date',
      });
      expect(r.respondedAt, isNull);
      expect(r.responseMessage, 'ok');
    });

    test('a blank or whitespace-only response is NOT an official response', () {
      expect(
        report({'status': 'resolved', 'response_message': '   '})
            .hasOfficialResponse,
        isFalse,
      );
      expect(
        report({'status': 'resolved', 'response_message': ''})
            .hasOfficialResponse,
        isFalse,
      );
    });

    test('responder alone does not fabricate a response', () {
      final r = report({
        'status': 'submitted',
        'responded_by_name': 'Jyerine Desunia',
      });
      expect(r.hasOfficialResponse, isFalse);
      expect(r.responseMessage, isNull);
    });
  });

  group('Technical Issue remote payload', () {
    final row = LocalReportRow(
      id: 'rq-1',
      reportType: ReportType.technicalIssue,
      payload: const TechnicalIssueDraft(
        title: 'Crash on My Tasks',
        module: 'My Tasks',
        summary: 'Closed three times.',
        expectedBehavior: 'Task list opens.',
        reproSteps: 'Home > My Tasks > tap first card',
        blocksFieldWork: true,
        occurredAt: null,
        connectivityState: 'offline',
        appVersion: 'Version 1.2.3',
        osVersion: 'Android 13',
      ).toJson(),
      queueState: ReportQueueState.pending,
      retryCount: 0,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );

    test('is job-free and filed as submitted', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(insert['report_type'], 'technical_issue');
      expect(insert['field_job_id'], isNull);
      expect(insert['supabase_application_id'], isNull);
      expect(insert['bridge_source_id'], isNull);
      expect(insert['support_category'], isNull);
      expect(insert['status'], 'submitted');
    });

    test('carries inspector repro steps and auto-captured context', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(insert['repro_steps'], contains('My Tasks'));
      expect(insert['expected_behavior'], 'Task list opens.');
      expect(insert['blocks_field_work'], isTrue);
      expect(insert['connectivity_state'], 'offline');
      expect(insert['app_version'], 'Version 1.2.3');
      expect(insert['os_version'], 'Android 13');
    });

    test('never pre-fills admin review fields', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(insert['technical_description'], isNull);
      expect(insert['affected_file'], isNull);
      expect(insert['recommended_action'], isNull);
    });

    test('carries no Planning Officer field', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(
        insert.keys.where((k) => k.toLowerCase().contains('officer')),
        isEmpty,
      );
      expect(
        insert.keys.where((k) => k.toLowerCase().contains('po_')),
        isEmpty,
      );
    });
  });

  group('Application Support remote payload', () {
    const draft = ApplicationSupportDraft(
      fieldJobId: 'job-uuid-1',
      supabaseApplicationId: 'app-uuid-1',
      bridgeSourceId: 'rosario-imaps-local-0921-a',
      supportCategory: 'clarification_request',
      description: 'Land use does not match the site signage.',
      affectedField: 'Land use',
      requestedChange: 'Please confirm the correct classification.',
      blocksFieldWork: false,
    );
    final row = LocalReportRow(
      id: 'rq-2',
      reportType: ReportType.applicationSupport,
      payload: draft.toJson(),
      queueState: ReportQueueState.pending,
      retryCount: 0,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      fieldJobId: draft.fieldJobId,
      supabaseApplicationId: draft.supabaseApplicationId,
      bridgeSourceId: draft.bridgeSourceId,
    );

    test('carries the exact identity triple verbatim', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(insert['report_type'], 'application_support');
      expect(insert['field_job_id'], 'job-uuid-1');
      expect(insert['supabase_application_id'], 'app-uuid-1');
      expect(insert['bridge_source_id'], 'rosario-imaps-local-0921-a');
      expect(insert['support_category'], 'clarification_request');
      expect(insert['status'], 'submitted');
    });

    test('carries no Planning Officer field', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(
        insert.keys.where((k) => k.toLowerCase().contains('officer')),
        isEmpty,
      );
    });

    test('the title is the category label, never a fabricated UUID', () {
      final insert = ReportQueueService.remoteInsertFor(row);
      expect(insert['title'], 'Clarification Needed');
      expect(insert['title'], isNot(contains('app-uuid-1')));
    });

    test('an identity-incomplete draft cannot be built as submittable', () {
      const incomplete = ApplicationSupportDraft(
        fieldJobId: 'job-uuid-1',
        supabaseApplicationId: '',
        bridgeSourceId: 'rosario-imaps-local-0921-a',
        supportCategory: 'other',
        description: 'x',
      );
      expect(incomplete.hasExactIdentity, isFalse);
    });
  });

  group('support category vocabulary', () {
    test('exactly the six locked categories are accepted', () {
      expect(SupportCategories.labels.keys.toSet(), {
        'incorrect_information',
        'missing_information',
        'additional_site_information',
        'clarification_request',
        'correction_request',
        'other',
      });
    });

    test('anything else is rejected', () {
      expect(SupportCategories.isValid('invented'), isFalse);
      expect(SupportCategories.isValid(null), isFalse);
      expect(SupportCategories.isValid('other'), isTrue);
    });
  });

  group('history reconciliation', () {
    test('a sent local row plus its matching remote row render once', () {
      final local = [
        localRow('rq-a', ReportQueueState.sent, remoteId: 'remote-1'),
        localRow('rq-b', ReportQueueState.pending),
      ];
      final unconfirmed = DiagnosticsService.unconfirmedLocalRows(local, [
        report(const {}),
      ]);
      expect(unconfirmed.map((r) => r.id), ['rq-b']);
    });

    test('a sent local row the server never saw stays visible', () {
      final local = [
        localRow('rq-a', ReportQueueState.sent, remoteId: 'remote-x'),
      ];
      final unconfirmed = DiagnosticsService.unconfirmedLocalRows(local, [
        report(const {}),
      ]);
      expect(unconfirmed.map((r) => r.id), ['rq-a']);
    });

    test('every unconfirmed transport state stays visible', () {
      final local = [
        localRow('rq-pending', ReportQueueState.pending),
        localRow('rq-retry', ReportQueueState.failedRetryable),
        localRow('rq-unknown', ReportQueueState.deliveryUnknown),
      ];
      expect(
        DiagnosticsService.unconfirmedLocalRows(
          local,
          const [],
        ).map((r) => r.id),
        ['rq-pending', 'rq-retry', 'rq-unknown'],
      );
    });
  });

  group('local id is transport identity only', () {
    test('new ids never look like a remote reference code', () {
      final id = ReportQueueService.newLocalId();
      expect(id, startsWith('rq-'));
      expect(id, isNot(matches(RegExp(r'^DR-\d{4}-\d+$'))));
      expect(id, isNot(ReportQueueService.newLocalId()));
    });
  });
}
