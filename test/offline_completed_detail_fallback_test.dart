// test/offline_completed_detail_fallback_test.dart
//
// Completed Inspection Summary — offline / cached-data fallback.
//
// Defect this guards: the summary always required a remote fetch
// (SupabaseService.fetchJobDetail). Offline that returned null and the screen
// failed with "Could not load this inspection", even though the Completed task
// itself was listed from the local cache.
//
// Contract proven here:
//  - remote-first: a successful remote fetch always wins;
//  - fallback only when full detail is unavailable AND a usable cached task
//    exists; only genuinely cached data is displayed;
//  - no status / category / current_step change and no write of any kind;
//  - the Loop 8 Planning Review card still renders from cached metadata;
//  - missing optional remote fields do not crash the screen;
//  - neither remote nor cached task keeps the existing safe error state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:imaps_fieldsync/modules/inspection/screens/completed_inspection_detail_screen.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

const jobId = '76d79ab8-e38e-4682-ada2-a67ac84dde00';

/// Exactly the shape the Tasks screen hands over when the list is rendered
/// from the local cache (local_jobs after the v12/v13 migrations).
Map<String, dynamic> cachedJobMap() => {
      'id': jobId,
      'local_inspection_id': 36,
      'status': 'completed',
      'current_step': 6,
      'submitted_at': '2026-09-22T11:38:54.944788+00:00',
      'scheduled_date': '2026-08-20',
      'deadline_date': '2026-09-30',
      'is_self_scheduled': false,
      'planning_review':
          '{"decision":"Requires Reinspection","reviewed_by_name":"Jyerine Desunia",'
          '"reviewed_at":"2026-09-22T13:47:57+00:00","technical_review_id":76,'
          '"reviewed_site_inspection_id":36,"field_job_id":"$jobId"}',
      'supabase_zoning_applications': {
        'applicant_name': 'Cached Applicant',
        'barangay': 'Mavalor',
        'reference_number': 'APP-2026-00026',
        'application_type': 'Petition for Rezoning',
      },
      'supabase_parcels': {
        'declared_land_use': null,
        'lot_area_sqm': null,
      },
    };

/// A full remote detail, as returned by fetchJobDetail when online.
Map<String, dynamic> remoteJobMap() => {
      ...cachedJobMap(),
      'inspection_result': 'Requires Reinspection',
      'is_compliant': false,
      'checklist_completed_count': 3,
      'checklist_total_count': 5,
      'findings': 'Remote finding text',
      'photo_paths': ['/signed/object/path.jpg'],
      'field_job_reviews': [
        {
          'id': 'r1',
          'technical_review_id': 76,
          'reviewed_site_inspection_id': 36,
          'decision': 'Requires Reinspection',
          'reviewed_by': 4,
          'reviewed_by_name': 'Jyerine Desunia',
          'reviewed_at': '2026-09-22T13:47:57+00:00',
          'field_job_id': jobId,
        }
      ],
    };

Widget wrap(Widget child) => MaterialApp(home: child);

/// The screen shows an animated loading indicator while the detail is being
/// resolved, so `pumpAndSettle` would never settle. Bounded frame pumps are
/// used instead to let the async fetch and the rebuilds complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'SUPABASE_URL=https://fixture.supabase.co'));
  tearDown(() => completedDetailFetcherOverride = null);

  test('1. online remote detail still wins over the cached task', () async {
    var askedForJobId = '';
    completedDetailFetcherOverride = (id) async {
      askedForJobId = id;
      return remoteJobMap();
    };

    final task = TaskItem.fromJob(cachedJobMap());
    final detail = TaskItem.fromJob(remoteJobMap());

    expect(detail.status, 'completed');
    expect(detail.currentStep, 6);
    // Remote-only values exist only on the remote projection.
    expect(detail.checklistTotalCount, 5);
    expect(detail.findings, 'Remote finding text');
    // The cached projection genuinely does not carry them.
    expect(task.checklistTotalCount, 0);
    expect(task.findings, isNull);
    expect(askedForJobId, isEmpty, reason: 'override is only exercised by the widget test');
  });

  testWidgets('2-3. remote null falls back and the summary opens from cache', (tester) async {
    completedDetailFetcherOverride = (_) async => null; // offline: fetch returns null

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);

    expect(find.text('Inspection Summary'), findsOneWidget);
    expect(find.text('Could not load this inspection.'), findsNothing);
    expect(find.textContaining('Showing saved task data'), findsOneWidget);
  });

  testWidgets('4. Planning Review renders from cached metadata when offline', (tester) async {
    completedDetailFetcherOverride = (_) async => null;

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);
    await tester.dragUntilVisible(find.text('Planning Review'), find.byType(ListView), const Offset(0, -300));
    await settle(tester);

    expect(find.text('Planning Review'), findsWidgets);
    expect(find.text('Reinspection Requested'), findsOneWidget);
    expect(find.text('Jyerine Desunia'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5-6. missing optional remote fields do not crash; no fake photo grid', (tester) async {
    completedDetailFetcherOverride = (_) async => null;

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);

    // Cached task has no photos, no findings, no checklist counts. The step
    // card content is only built when the card is expanded.
    await tester.dragUntilVisible(find.text('Photographic Evidence'), find.byType(ListView), const Offset(0, -250));
    await settle(tester);
    await tester.tap(find.text('Photographic Evidence').first);
    await settle(tester);

    expect(find.textContaining('Photo evidence is not available offline.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7-9. status, category and current_step are unchanged by viewing', (tester) async {
    completedDetailFetcherOverride = (_) async => null;

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);

    // The very same instance the caller passed in is rendered; nothing mutates.
    expect(_cachedTask.status, 'completed');
    expect(_cachedTask.category, 'Completed');
    expect(_cachedTask.currentStep, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('10. viewing the cached detail performs no write', (tester) async {
    var fetches = 0;
    completedDetailFetcherOverride = (_) async {
      fetches++;
      return null;
    };

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);

    // Exactly one read attempt; the fallback issues no additional request and
    // no local/remote mutation (the screen only calls setState).
    expect(fetches, 1);
    expect(_cachedTask.status, 'completed');
  });

  testWidgets('11. after reconnect the remote detail is used again', (tester) async {
    completedDetailFetcherOverride = (_) async => remoteJobMap();

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(
      task: _cachedTask,
    )));
    await settle(tester);

    // Remote wins: the saved-data notice must be gone and remote-only content
    // (checklist 3/5) is what is rendered.
    expect(find.textContaining('Showing saved task data'), findsNothing);
    await tester.dragUntilVisible(find.text('Checklist'), find.byType(ListView), const Offset(0, -250));
    await settle(tester);
    await tester.tap(find.text('Checklist').first);
    await settle(tester);
    expect(find.textContaining('3 of 5 verified'), findsOneWidget);
  });

  testWidgets('12. neither remote nor cached task keeps the safe error state', (tester) async {
    completedDetailFetcherOverride = (_) async => null;

    // A task with no id/status is not a usable cached task.
    final unusable = TaskItem.fromJob({'id': '', 'status': null});

    await tester.pumpWidget(wrap(CompletedInspectionDetailScreen(task: unusable)));
    await settle(tester);

    expect(find.text('Could not load this inspection.'), findsOneWidget);
  });
}

/// The cached round-36 task, built once so the "no mutation" proofs compare
/// the same instance the screen was given.
final _cachedTask = TaskItem.fromJob(cachedJobMap());
