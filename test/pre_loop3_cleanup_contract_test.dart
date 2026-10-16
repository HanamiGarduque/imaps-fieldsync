import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test(
    'scheduling writes only scheduling metadata and the reviewed pending status',
    () {
      final service = source('lib/core/services/supabase_service.dart');
      final method = RegExp(
        r'static Future<InspectionAuthorityResult> scheduleJob\([\s\S]*?(?=\n  // ─)',
      ).firstMatch(service)?.group(0);

      expect(method, isNotNull);
      expect(method, contains("'scheduled_date': dateStr"));
      expect(method, contains("'is_self_scheduled': true"));
      expect(method, isNot(contains("'remarks'")));
      // The reviewed transition (pinned by ongoing_task_reschedule_test.dart):
      // an owned assigned/in_progress job returns to `pending`. That is the
      // only lifecycle value scheduling may write - it can never complete a
      // round, and it can never resurrect one.
      expect(method, contains("'status': 'pending'"));
      expect(method, isNot(contains("'status': 'completed'")));
      expect(method, isNot(contains("'status': 'in_progress'")));
    },
  );

  test(
    'scheduling UI has no note input and keeps assignment deadline wording',
    () {
      final screen = source('lib/modules/tasks/screens/tasks_screen.dart');
      final method = RegExp(
        r'Future<void> _scheduleTask\([\s\S]*?^  }',
        multiLine: true,
      ).firstMatch(screen)?.group(0);

      expect(method, isNotNull);
      expect(method, contains('(assignment deadline)'));
      expect(method, isNot(contains('notesController')));
      expect(method, isNot(contains('Notes (optional)')));
      expect(method, contains('SupabaseService.scheduleJob'));
    },
  );

  test(
    'offline inspection sync omits remarks and preserves canonical evidence',
    () {
      final provider = source(
        'lib/modules/inspection/providers/inspection_provider.dart',
      );
      final syncBlock = RegExp(
        r'// 2\. Sync Pending Inspections[\s\S]*?markInspectionSynced',
      ).firstMatch(provider)?.group(0);

      expect(syncBlock, isNotNull);
      expect(syncBlock, isNot(contains("'remarks'")));
      expect(syncBlock, contains("'findings'"));
      expect(syncBlock, contains("'is_compliant'"));
      expect(syncBlock, contains("'inspection_result'"));
      expect(
        provider,
        contains("'observations': observations"),
        reason:
            'Boundary and actual-land-use evidence remains in observations.',
      );
    },
  );

  group('lifecycle presentation compatibility', () {
    for (final entry in const {
      'assigned': 'Pending',
      'in_progress': 'Ongoing',
      'completed': 'Completed',
      'Pending': 'Pending',
    }.entries) {
      test('${entry.key} displays as ${entry.value}', () {
        final task = TaskItem.fromJob({
          'id': 'cleanup-${entry.key}',
          'status': entry.key,
        });
        expect(task.category, entry.value);
      });
    }
  });

  test('assignment instructions and assigning provenance stay read only', () {
    final supabase = source('lib/core/services/supabase_service.dart');
    final outbox = source('lib/core/services/sync_outbox_service.dart');

    expect(supabase, contains('assignment_instructions'));
    expect(supabase, contains('assigned_by_imaps_user_id'));
    expect(supabase, contains('assigned_by_name'));
    expect(outbox, isNot(contains("'assignment_instructions'")));
    expect(outbox, isNot(contains("'assigned_by_imaps_user_id'")));
    expect(outbox, isNot(contains("'assigned_by_name'")));
  });
}
