import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/services/db_helper.dart';
import 'package:imaps_fieldsync/core/services/sync_outbox_service.dart';
import 'package:imaps_fieldsync/modules/inspection/providers/inspection_provider.dart';
import 'package:imaps_fieldsync/modules/inspection/structured_checklist.dart';
import 'package:imaps_fieldsync/modules/tasks/screens/tasks_screen.dart';

import 'support/offline_reliability_fixture.dart';

/// CE-05T — structured checklist transmission contract.
///
/// Production transmission is hard-disabled by
/// [StructuredChecklist.remoteTransmissionEnabled]. These fixtures exercise the
/// enabled serializer and the real outbox locally; no backend is contacted.
void main() {
  final fixture = OfflineReliabilityFixture();

  Future<void> settleOfflineDrain() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (SyncOutboxService.isDraining && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(SyncOutboxService.isDraining, isFalse);
  }

  setUpAll(fixture.initialize);
  setUp(() async {
    StructuredChecklist.remoteTransmissionEnabledForTesting = null;
    await fixture.reset();
  });
  tearDown(() async {
    StructuredChecklist.remoteTransmissionEnabledForTesting = null;
    // saveStepChecklist starts an unawaited drain. Let it observe the offline
    // fixture and finish before the fixture resets the outbox session.
    await settleOfflineDrain();
    await fixture.closeCase();
  });
  tearDownAll(fixture.dispose);

  const legacyQuestions = [
    'Structure matches declared use',
    'Setback distances compliant',
    'Accessibility & road frontage',
    'Surrounding developments noted',
    'Signage / commercial activity present',
  ];

  Map<String, bool> legacy({
    bool firstChecked = true,
    bool secondChecked = false,
  }) => {
    for (final question in legacyQuestions)
      question: question == legacyQuestions[0]
          ? firstChecked
          : question == legacyQuestions[1]
          ? secondChecked
          : false,
  };

  List<Map<String, dynamic>> remoteStructuredAnswers({
    int round = 1,
    String inspectorId = offlineInspector,
  }) => [
    for (final (key, answer) in <(String, String)>[
      (StructuredChecklist.existingDevelopment, 'Yes'),
      (StructuredChecklist.existingUse, 'Fictional clinic'),
      (StructuredChecklist.extensionOfExisting, 'Not Applicable'),
      (StructuredChecklist.proposalStage, 'Yes'),
      (StructuredChecklist.treesPresent, 'No'),
      (StructuredChecklist.canalWaterway, 'Unable to Verify'),
      (StructuredChecklist.mojonObserved, 'No'),
    ])
      {
        'item': StructuredChecklist.questionLabels[key],
        'answer': answer,
        'inspector_id': inspectorId,
        'inspection_round_number': round,
      },
  ];

  TaskItem taskWithRemoteChecklist({
    String id = offlineJob,
    int round = 1,
    required List<Map<String, dynamic>> checklistData,
  }) => TaskItem(
    id: id,
    parcelId: 'fictional-parcel',
    name: 'Fictional site',
    location: 'Isolated fixture only',
    parcels: '1',
    status: 'in_progress',
    inspectionNo: 'DEMO-FS05-R$round',
    inspectionRoundNumber: round,
    checklistData: checklistData,
  );

  Future<List<Map<String, dynamic>>> actionRows(
    String type, {
    String jobId = offlineJob,
  }) => fixture.db.query(
    'pending_actions',
    where: 'job_id = ? AND type = ?',
    whereArgs: [jobId, type],
  );

  Future<Map<String, dynamic>> actionPayload(
    String type, {
    String jobId = offlineJob,
  }) async {
    final rows = await actionRows(type, jobId: jobId);
    return jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
  }

  /// Applies one FieldSync checklist action to a simulated `field_jobs` row.
  /// Supabase receives the JSON array as-is; a retry replaces the value rather
  /// than appending to it.
  Map<String, dynamic> applyRemote(
    Map<String, dynamic> remote,
    Map<String, dynamic> payload,
  ) => {
    ...remote,
    'checklist_data': [
      for (final entry in payload['checklistData'] as List)
        Map<String, dynamic>.from(entry as Map),
    ],
    'checklist_completed_count': payload['checklistCompletedCount'],
    'checklist_total_count': payload['checklistTotalCount'],
  };

  void recordAll() {
    fixture.provider
      ..setSiteCondition(legacyQuestions[0], true)
      ..setSiteCondition(legacyQuestions[1], true)
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.existingUse,
        '  Fictional residential  ',
      )
      ..setStructuredAnswer(
        StructuredChecklist.extensionOfExisting,
        StructuredChecklist.notApplicable,
      )
      ..setStructuredAnswer(
        StructuredChecklist.proposalStage,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.treesPresent,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.canalWaterway,
        StructuredChecklist.unable,
      )
      ..setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        StructuredChecklist.no,
      );
  }

  test('production default keeps the remote payload legacy-only', () async {
    expect(StructuredChecklist.remoteTransmissionEnabled, isFalse);
    expect(StructuredChecklist.isRemoteTransmissionEnabled, isFalse);

    fixture.provider
      ..setSiteCondition(legacyQuestions[0], true)
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.existingUse,
        'Fictional clinic',
      );

    expect(await fixture.provider.saveStepChecklist(), isTrue);
    final payload = await actionPayload('checklist_update');
    expect(payload['checklistCompletedCount'], 1);
    expect(payload['checklistTotalCount'], 5);

    final data = payload['checklistData'] as List;
    expect(data, hasLength(5));
    for (final entry in data) {
      expect((entry as Map).keys.toSet(), {'item', 'checked'});
    }
    expect(jsonEncode(data), isNot(contains('_structured')));
    expect(jsonEncode(data), isNot(contains('Existing project')));
  });

  test('enabled serializer preserves all five legacy rows and every state', () {
    StructuredChecklist.remoteTransmissionEnabledForTesting = true;

    final entries = StructuredChecklist.remoteChecklist(
      legacy: legacy(),
      answers: {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: '  Fictional clinic  ',
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.proposalStage: StructuredChecklist.yes,
        StructuredChecklist.treesPresent: StructuredChecklist.yes,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: StructuredChecklist.no,
      },
    );

    expect(entries, hasLength(12));
    expect(
      entries.take(5).map((entry) => entry['item']).toList(),
      legacyQuestions,
    );
    expect(entries.take(5).every((entry) => entry['checked'] is bool), isTrue);
    expect(entries[0]['checked'], isTrue);
    expect(entries[1]['checked'], isFalse);

    final structured = entries.skip(5).toList();
    expect(
      structured.map((entry) => entry['item']).toList(),
      StructuredChecklist.questionLabels.values.toList(),
    );
    expect(structured.map((entry) => entry['answer']).toList(), [
      StructuredChecklist.yes,
      'Fictional clinic',
      StructuredChecklist.notApplicable,
      StructuredChecklist.yes,
      StructuredChecklist.yes,
      StructuredChecklist.unable,
      StructuredChecklist.no,
    ]);
    for (final entry in structured) {
      expect(entry.keys.toSet(), {'item', 'answer'});
    }
    expect(jsonEncode(entries), isNot(contains('_structured')));
  });

  test('missing and hidden answers are never serialized as No', () {
    StructuredChecklist.remoteTransmissionEnabledForTesting = true;

    final entries = StructuredChecklist.remoteChecklist(
      legacy: legacy(),
      answers: {
        StructuredChecklist.existingDevelopment: StructuredChecklist.no,
        StructuredChecklist.existingUse: 'Stale declared use',
        StructuredChecklist.proposalStage: StructuredChecklist.no,
        StructuredChecklist.treesPresent: StructuredChecklist.yes,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: '',
      },
    );

    expect(entries, hasLength(7));
    final structured = entries.skip(5).toList();
    expect(structured, hasLength(2));
    expect(structured.map((entry) => entry['item']).toList(), [
      StructuredChecklist.questionLabels[StructuredChecklist
          .existingDevelopment],
      StructuredChecklist.questionLabels[StructuredChecklist.proposalStage],
    ]);
    expect(structured.map((entry) => entry['answer']).toList(), [
      StructuredChecklist.no,
      StructuredChecklist.no,
    ]);

    final encoded = jsonEncode(structured);
    expect(encoded, isNot(contains('Stale declared use')));
    expect(encoded, isNot(contains('Trees present')));
    expect(encoded, isNot(contains('Canal or waterway')));
    expect(encoded, isNot(contains('mojon')));
    expect(encoded, isNot(contains('Not recorded')));

    final unanswered = StructuredChecklist.remoteChecklist(
      legacy: legacy(),
      answers: const {},
    );
    expect(unanswered, hasLength(5));
    expect(unanswered.every((entry) => !entry.containsKey('answer')), isTrue);
  });

  test('remote label rows decode only the seven allowed structured questions', () {
    final decoded = StructuredChecklist.decodeRemoteChecklist(
      remoteStructuredAnswers(),
      inspectorId: offlineInspector,
      inspectionRoundNumber: 1,
    );
    expect(decoded, {
      StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
      StructuredChecklist.existingUse: 'Fictional clinic',
      StructuredChecklist.extensionOfExisting:
          StructuredChecklist.notApplicable,
      StructuredChecklist.proposalStage: StructuredChecklist.yes,
      StructuredChecklist.treesPresent: StructuredChecklist.no,
      StructuredChecklist.canalWaterway: StructuredChecklist.unable,
      StructuredChecklist.mojonObserved: StructuredChecklist.no,
    });
  });

  test('malformed duplicate contradictory and wrong-owner rows stay uncertain', () {
    final rows = [
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.existingDevelopment],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.existingDevelopment],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.extensionOfExisting],
        'answer': 'Maybe',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.proposalStage],
        'answer': 'No',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.treesPresent],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.mojonObserved],
        'answer': 'Yes',
        'checked': false,
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.canalWaterway],
        'answer': 'Unable to Verify',
      },
      {
        'item': StructuredChecklist.questionLabels[
            StructuredChecklist.existingUse],
        'answer': 'Wrong-owner value',
        'inspector_id': otherOfflineInspector,
      },
    ];

    final decoded = StructuredChecklist.decodeRemoteChecklist(
      rows,
      inspectorId: offlineInspector,
      inspectionRoundNumber: 1,
    );
    // Proposal "No" makes the canal question inactive, so it is not accepted.
    expect(decoded, {
      StructuredChecklist.proposalStage: StructuredChecklist.no,
    });
    expect(
      StructuredChecklist.decodeRemoteChecklist(
        remoteStructuredAnswers(round: 1),
        inspectorId: offlineInspector,
        inspectionRoundNumber: 2,
      ),
      isEmpty,
    );
  });

  test('remote answers restore without a local draft for the selected round', () async {
    final task = taskWithRemoteChecklist(
      id: offlineRound2,
      round: 2,
      checklistData: remoteStructuredAnswers(round: 2),
    );
    expect(await DBHelper.getLocalInspection(offlineRound2), isNull);

    await fixture.provider.startInspection(task);

    expect(fixture.provider.structuredAnswers, {
      StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
      StructuredChecklist.existingUse: 'Fictional clinic',
      StructuredChecklist.extensionOfExisting:
          StructuredChecklist.notApplicable,
      StructuredChecklist.proposalStage: StructuredChecklist.yes,
      StructuredChecklist.treesPresent: StructuredChecklist.no,
      StructuredChecklist.canalWaterway: StructuredChecklist.unable,
      StructuredChecklist.mojonObserved: StructuredChecklist.no,
    });
  });

  test('owned local answers and in-session edits take precedence over remote data', () async {
    fixture.provider
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.no,
      )
      ..setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        StructuredChecklist.yes,
      );
    expect(await fixture.provider.saveStepChecklist(), isTrue);

    final task = taskWithRemoteChecklist(
      checklistData: remoteStructuredAnswers(),
    );
    await fixture.provider.startInspection(task);
    expect(
      fixture.provider.structuredAnswers[
          StructuredChecklist.existingDevelopment],
      StructuredChecklist.no,
    );
    expect(
      fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
      StructuredChecklist.yes,
    );
    expect(
      fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
      isNull,
      reason: 'A remote child answer cannot override a local No parent.',
    );

    fixture.provider
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.existingUse,
        'In-session declared use',
      );
    await fixture.provider.restoreStructuredChecklist();
    expect(
      fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
      'In-session declared use',
    );
    expect(
      fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
      StructuredChecklist.yes,
    );
  });

  test(
    'remote label rows decode only the seven allowed structured questions',
    () {
      final decoded = StructuredChecklist.decodeRemoteChecklist(
        remoteStructuredAnswers(),
        inspectorId: offlineInspector,
        inspectionRoundNumber: 1,
      );
      expect(decoded, {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: 'Fictional clinic',
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.proposalStage: StructuredChecklist.yes,
        StructuredChecklist.treesPresent: StructuredChecklist.no,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: StructuredChecklist.no,
      });
    },
  );

  test('ambiguous rows are omitted and inactive children stay hidden', () {
    final rows = [
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.existingDevelopment],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.existingDevelopment],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.extensionOfExisting],
        'answer': 'Maybe',
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.proposalStage],
        'answer': 'No',
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.treesPresent],
        'answer': 'Yes',
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.mojonObserved],
        'answer': 'Yes',
        'checked': false,
      },
      {
        'item': StructuredChecklist
            .questionLabels[StructuredChecklist.canalWaterway],
        'answer': 'Unable to Verify',
      },
      {
        'item':
            StructuredChecklist.questionLabels[StructuredChecklist.existingUse],
        'answer': 'Wrong-owner value',
        'inspector_id': otherOfflineInspector,
      },
    ];

    final decoded = StructuredChecklist.decodeRemoteChecklist(
      rows,
      inspectorId: offlineInspector,
      inspectionRoundNumber: 1,
    );
    expect(decoded, {
      // A hidden child does not invalidate its explicitly recorded parent.
      StructuredChecklist.proposalStage: StructuredChecklist.no,
    });
    expect(
      StructuredChecklist.decodeRemoteChecklist(
        remoteStructuredAnswers(round: 1),
        inspectorId: offlineInspector,
        inspectionRoundNumber: 2,
      ),
      isEmpty,
    );
    expect(
      StructuredChecklist.decodeRemoteChecklist(
        [
          {
            'item': 'Existing mojon or property marker observed',
            'answer': 'Yes',
            'inspection_round_number': 1.5,
          },
        ],
        inspectorId: offlineInspector,
        inspectionRoundNumber: 1,
      ),
      isEmpty,
      reason: 'A fractional round must not be truncated into this round.',
    );
  });

  test(
    'remote answers restore without a local draft for the selected round',
    () async {
      final task = taskWithRemoteChecklist(
        id: offlineRound2,
        round: 2,
        checklistData: remoteStructuredAnswers(round: 2),
      );
      expect(await DBHelper.getLocalInspection(offlineRound2), isNull);

      await fixture.provider.startInspection(task);

      expect(fixture.provider.structuredAnswers, {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: 'Fictional clinic',
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.proposalStage: StructuredChecklist.yes,
        StructuredChecklist.treesPresent: StructuredChecklist.no,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: StructuredChecklist.no,
      });
    },
  );

  test(
    'owned local answers and in-session edits take precedence over remote data',
    () async {
      fixture.provider
        ..setStructuredAnswer(
          StructuredChecklist.existingDevelopment,
          StructuredChecklist.no,
        )
        ..setStructuredAnswer(
          StructuredChecklist.mojonObserved,
          StructuredChecklist.yes,
        );
      expect(await fixture.provider.saveStepChecklist(), isTrue);

      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      await fixture.provider.startInspection(task);
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist
            .existingDevelopment],
        StructuredChecklist.no,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
        StructuredChecklist.yes,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        isNull,
        reason: 'A remote child answer cannot override a local No parent.',
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist
            .extensionOfExisting],
        isNull,
        reason:
            'Not recorded in an owned snapshot must not become a remote answer.',
      );

      fixture.provider
        ..setStructuredAnswer(
          StructuredChecklist.existingDevelopment,
          StructuredChecklist.yes,
        )
        ..setStructuredAnswer(
          StructuredChecklist.existingUse,
          'In-session declared use',
        );
      await fixture.provider.restoreStructuredChecklist();
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        'In-session declared use',
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
        StructuredChecklist.yes,
      );
    },
  );

  test(
    'rework keeps remote answers when no structured local snapshot exists',
    () async {
      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      fixture.provider.hydrateForRework(task);
      await fixture.provider.restoreStructuredChecklist();
      expect(fixture.provider.structuredAnswers, {
        StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
        StructuredChecklist.existingUse: 'Fictional clinic',
        StructuredChecklist.extensionOfExisting:
            StructuredChecklist.notApplicable,
        StructuredChecklist.proposalStage: StructuredChecklist.yes,
        StructuredChecklist.treesPresent: StructuredChecklist.no,
        StructuredChecklist.canalWaterway: StructuredChecklist.unable,
        StructuredChecklist.mojonObserved: StructuredChecklist.no,
      });
      expect(
        fixture.requests,
        isEmpty,
        reason: 'Opening rework is not an edit.',
      );
      expect(await DBHelper.getLocalInspection(offlineJob), isNull);
    },
  );

  test(
    'edits and clears made during restore win over its awaited read',
    () async {
      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      fixture.provider.hydrateForRework(task);
      final restoring = fixture.provider.restoreStructuredChecklist();
      fixture.provider
        ..setStructuredAnswer(
          StructuredChecklist.mojonObserved,
          StructuredChecklist.yes,
        )
        ..setStructuredAnswer(StructuredChecklist.existingUse, null);
      await restoring;
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
        StructuredChecklist.yes,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        isNull,
      );
    },
  );

  test(
    'revisiting the same rework preserves unsaved answers and clears',
    () async {
      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      fixture.provider.hydrateForRework(task);
      fixture.provider
        ..setStructuredAnswer(
          StructuredChecklist.mojonObserved,
          StructuredChecklist.yes,
        )
        ..setStructuredAnswer(StructuredChecklist.existingUse, null);
      fixture.provider.hydrateForRework(task);
      await fixture.provider.restoreStructuredChecklist();
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.mojonObserved],
        StructuredChecklist.yes,
      );
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        isNull,
      );
    },
  );

  test(
    'saved empty structured snapshot stays empty after restart and rework',
    () async {
      final task = taskWithRemoteChecklist(
        checklistData: [
          {
            'item': 'Existing mojon or property marker observed',
            'answer': 'Yes',
          },
        ],
      );
      fixture.provider.hydrateForRework(task);
      fixture.provider.setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        null,
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      await settleOfflineDrain();
      await fixture.restartDatabase();

      final restored = InspectionProvider();
      addTearDown(restored.dispose);
      await restored.startInspection(task);
      expect(restored.structuredAnswers, isEmpty);
      restored.hydrateForRework(task);
      await restored.restoreStructuredChecklist();
      expect(restored.structuredAnswers, isEmpty);
      final payload = await actionPayload('checklist_update');
      expect((payload['checklistData'] as List), hasLength(5));
    },
  );

  test(
    'stale restore cannot write into a reentered session of the same round',
    () async {
      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      fixture.provider.hydrateForRework(task);
      final restoring = fixture.provider.restoreStructuredChecklist();
      fixture.provider.hydrateForRework(task);
      await expectLater(restoring, throwsStateError);
      expect(
        fixture.provider.structuredAnswers[StructuredChecklist.existingUse],
        'Fictional clinic',
      );
    },
  );

  test('pending start cannot replace a newly selected rework round', () async {
    final starting = fixture.provider.startInspection(
      taskWithRemoteChecklist(checklistData: remoteStructuredAnswers()),
    );
    final selected = taskWithRemoteChecklist(
      id: offlineRound2,
      round: 2,
      checklistData: remoteStructuredAnswers(round: 2),
    );
    fixture.provider.hydrateForRework(selected);
    await expectLater(starting, throwsStateError);
    expect(fixture.provider.activeTask?.id, offlineRound2);
    expect(fixture.provider.isReworkMode, isTrue);
  });

  test(
    'foreign structured drafts and remote rows cannot cross inspectors',
    () async {
      recordAll();
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      final task = taskWithRemoteChecklist(
        checklistData: remoteStructuredAnswers(),
      );
      DBHelper.inspectorIdForTesting = otherOfflineInspector;
      try {
        fixture.provider.hydrateForRework(task);
        await fixture.provider.restoreStructuredChecklist();
        expect(fixture.provider.structuredAnswers, isEmpty);
      } finally {
        DBHelper.inspectorIdForTesting = null;
      }
    },
  );

  test(
    'offline saves replace one queued action without duplicate entries',
    () async {
      StructuredChecklist.remoteTransmissionEnabledForTesting = true;
      recordAll();

      expect(await fixture.provider.saveStepChecklist(), isTrue);
      var rows = await actionRows('checklist_update');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'checklist_update_$offlineJob');
      expect(rows.single['inspector_id'], offlineInspector);
      expect(rows.single['status'], 'pending');

      var payload = await actionPayload('checklist_update');
      expect(payload['checklistCompletedCount'], 2);
      expect(payload['checklistTotalCount'], 5);
      expect((payload['checklistData'] as List), hasLength(12));

      fixture.provider.setStructuredAnswer(
        StructuredChecklist.canalWaterway,
        StructuredChecklist.no,
      );
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      rows = await actionRows('checklist_update');
      expect(rows, hasLength(1), reason: 'repeated saves coalesce per job');

      payload = await actionPayload('checklist_update');
      final data = (payload['checklistData'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      expect(data, hasLength(12));
      final items = data.map((entry) => entry['item']).toList();
      expect(items.toSet(), hasLength(items.length), reason: 'no duplicates');
      expect(
        data.singleWhere(
          (entry) =>
              entry['item'] ==
              StructuredChecklist.questionLabels[StructuredChecklist
                  .canalWaterway],
        )['answer'],
        StructuredChecklist.no,
        reason: 'the latest answer replaces the previous queued value',
      );
    },
  );

  test(
    'a retried payload is idempotent against the simulated Supabase row',
    () async {
      StructuredChecklist.remoteTransmissionEnabledForTesting = true;
      recordAll();
      expect(await fixture.provider.saveStepChecklist(), isTrue);
      final payload = await actionPayload('checklist_update');

      var remote = applyRemote(const {}, payload);
      final first = jsonEncode(remote);
      remote = applyRemote(remote, payload);
      expect(
        jsonEncode(remote),
        first,
        reason: 'retry replaces, never appends',
      );

      final data = remote['checklist_data'] as List;
      expect(data, hasLength(12));
      final items = data.map((entry) => (entry as Map)['item']).toList();
      expect(items.toSet(), hasLength(items.length));
      expect(remote['checklist_completed_count'], 2);
      expect(remote['checklist_total_count'], 5);
    },
  );

  test('R1/R2 and owner isolation survive structured serialization', () async {
    StructuredChecklist.remoteTransmissionEnabledForTesting = true;
    fixture.provider
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.yes,
      )
      ..setStructuredAnswer(
        StructuredChecklist.existingUse,
        'R1 fictional clinic',
      );
    expect(await fixture.provider.saveStepChecklist(), isTrue);
    final round1 = await actionPayload('checklist_update');
    expect(
      jsonEncode(round1['checklistData']),
      contains('R1 fictional clinic'),
    );

    final round2 = InspectionProvider();
    addTearDown(round2.dispose);
    await round2.startInspection(
      TaskItem(
        id: offlineRound2,
        parcelId: 'fictional-parcel-2',
        name: 'Fictional round 2',
        location: 'Isolated fixture only',
        parcels: '1',
        status: 'assigned',
        inspectionNo: 'DEMO-FS05T-R2',
      ),
    );
    round2
      ..setStructuredAnswer(
        StructuredChecklist.existingDevelopment,
        StructuredChecklist.no,
      )
      ..setStructuredAnswer(
        StructuredChecklist.mojonObserved,
        StructuredChecklist.unable,
      );
    expect(await round2.saveStepChecklist(), isTrue);

    final round2Payload = await actionPayload(
      'checklist_update',
      jobId: offlineRound2,
    );
    final round2Encoded = jsonEncode(round2Payload['checklistData']);
    expect(round2Encoded, isNot(contains('R1 fictional clinic')));
    expect(round2Encoded, contains(StructuredChecklist.unable));

    final round1Rows = await actionRows('checklist_update');
    final round2Rows = await actionRows(
      'checklist_update',
      jobId: offlineRound2,
    );
    expect(round1Rows, hasLength(1));
    expect(round2Rows, hasLength(1));
    expect(round1Rows.single['inspector_id'], offlineInspector);
    expect(round2Rows.single['inspector_id'], offlineInspector);
    expect(round1Rows.single['job_id'], isNot(round2Rows.single['job_id']));

    DBHelper.inspectorIdForTesting = otherOfflineInspector;
    try {
      expect(fixture.provider.structuredAnswers, isEmpty);
      expect(
        () => fixture.provider.setStructuredAnswer(
          StructuredChecklist.mojonObserved,
          StructuredChecklist.no,
        ),
        throwsStateError,
      );
    } finally {
      DBHelper.inspectorIdForTesting = null;
    }
  });

  test(
    'mocked FieldSync -> Supabase -> iMAPS reader contract stays truthful',
    () {
      StructuredChecklist.remoteTransmissionEnabledForTesting = true;
      final entries = StructuredChecklist.remoteChecklist(
        legacy: legacy(),
        answers: {
          StructuredChecklist.existingDevelopment: StructuredChecklist.yes,
          StructuredChecklist.existingUse: 'Fictional residential',
          StructuredChecklist.extensionOfExisting:
              StructuredChecklist.notApplicable,
          StructuredChecklist.proposalStage: StructuredChecklist.yes,
          StructuredChecklist.treesPresent: StructuredChecklist.yes,
          StructuredChecklist.canalWaterway: StructuredChecklist.unable,
          StructuredChecklist.mojonObserved: StructuredChecklist.no,
        },
      );

      // PostgREST JSON transport into the existing field_jobs JSON column and
      // SiteInspection::checklist_data array cast. No schema change.
      final remote =
          jsonDecode(
                jsonEncode({
                  'checklist_data': entries,
                  'checklist_completed_count': 2,
                  'checklist_total_count': 5,
                }),
              )
              as Map<String, dynamic>;
      final ingested = (remote['checklist_data'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      expect(ingested, hasLength(12));

      // CE-06 reader at iMAPS `4a90464` (Show.jsx); the real JSX reader is
      // covered separately by tests/js/check-inspection-report.cjs. Tokens map to
      // labels, free text stays verbatim, legacy booleans keep their meaning,
      // and a missing answer is "Not recorded" rather than "No".
      const labels = {
        'yes': 'Yes',
        'no': 'No',
        'unable': 'Unable to Verify',
        'unable to verify': 'Unable to Verify',
        'not applicable': 'Not Applicable',
        'not_applicable': 'Not Applicable',
      };
      String read(Map<String, dynamic> entry) {
        final raw = entry['answer'];
        final answer = raw is String ? raw.trim() : '';
        if (answer.isNotEmpty) {
          return labels[answer.toLowerCase()] ?? answer;
        }
        final checked = entry.containsKey('checked')
            ? entry['checked']
            : entry['passed'];
        if (checked == true || checked == 1) return 'Checked';
        if (checked == false || checked == 0) return 'Not checked';
        return 'Not recorded';
      }

      final rendered = [
        for (final entry in ingested)
          {'item': entry['item'], 'answer': read(entry)},
      ];
      expect(rendered.map((row) => row['answer']).skip(5).toList(), [
        'Yes',
        'Fictional residential',
        'Not Applicable',
        'Yes',
        'Yes',
        'Unable to Verify',
        'No',
      ]);
      expect(rendered[0]['answer'], 'Checked');
      expect(rendered[1]['answer'], 'Not checked');
      expect(rendered.where((row) => row['answer'] == 'Not recorded'), isEmpty);

      final missing = [
        {'item': 'Extension of an existing structure', 'answer': null},
        {'item': 'Still at the project proposal stage'},
        {'item': 'Legacy boolean only', 'checked': false},
      ].map(read).toList();
      expect(missing, ['Not recorded', 'Not recorded', 'Not checked']);
      expect(missing, isNot(contains('No')));
    },
  );
}
