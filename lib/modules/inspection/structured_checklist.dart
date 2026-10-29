import 'package:flutter/foundation.dart';

/// CE-05 structured site-condition answers.
///
/// Answers are additive to the existing local `checklist_json` contract
/// (stored under [jsonKey]) so no database migration is required. A missing
/// key means "not recorded" and is never the same as "No". Conditional
/// answers only count while their parent answer still selects them.
class StructuredChecklist {
  StructuredChecklist._();

  static const jsonKey = '_structured';

  static const existingDevelopment = 'project_status.existing_development';
  static const existingUse = 'project_status.existing_use';
  static const extensionOfExisting = 'project_status.extension';
  static const proposalStage = 'project_status.proposal_stage';
  static const treesPresent = 'project_status.trees_present';
  static const canalWaterway = 'project_status.canal_waterway';
  static const mojonObserved = 'zoning.mojon_observed';

  static const yes = 'yes';
  static const no = 'no';
  static const unable = 'unable';
  static const notApplicable = 'not_applicable';

  static const Map<String, String> triStateLabels = {
    yes: 'Yes',
    no: 'No',
    unable: 'Unable to Verify',
  };

  static const Map<String, String> extensionLabels = {
    yes: 'Yes',
    no: 'No',
    unable: 'Unable to Verify',
    notApplicable: 'Not Applicable',
  };

  static const Map<String, String> questionLabels = {
    existingDevelopment: 'Existing project or development on site',
    existingUse: "Existing project's declared use",
    extensionOfExisting: 'Extension of an existing structure',
    proposalStage: 'Still at the project proposal stage',
    treesPresent: 'Trees present on the lot',
    canalWaterway: 'Canal or waterway on or adjoining the lot',
    mojonObserved: 'Existing mojon or property marker observed',
  };

  static const Map<String, String> questionHints = {
    existingDevelopment:
        'Record only what you verified. Not recorded is not the same as No.',
    existingUse: 'Optional. Enter the use declared by the owner or records.',
    extensionOfExisting:
        'Choose Not Applicable only when you explicitly determined the project is not an extension.',
    proposalStage:
        'Record only what you verified. Not recorded is not the same as No.',
    treesPresent: 'Recorded independently of any canal or waterway.',
    canalWaterway: 'Recorded independently of any trees on the lot.',
    mojonObserved:
        'Observing a marker does not verify or certify cadastral boundaries.',
  };

  static Map<String, String> optionsFor(String key) =>
      key == extensionOfExisting ? extensionLabels : triStateLabels;

  static bool isVisible(String key, Map<String, String?> answers) {
    switch (key) {
      case existingUse:
        return answers[existingDevelopment] == yes;
      case treesPresent:
      case canalWaterway:
        return answers[proposalStage] == yes;
      default:
        return questionLabels.containsKey(key);
    }
  }

  /// Answers that may be persisted or displayed as current: non-empty and
  /// still selected by their parent. Hidden legacy values stay in memory but
  /// must never be silently submitted.
  static Map<String, String> activeAnswers(Map<String, String?> answers) {
    final present = <String, String>{
      for (final entry in answers.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          entry.key: entry.value!.trim(),
    };
    return {
      for (final entry in present.entries)
        if (isVisible(entry.key, present)) entry.key: entry.value,
    };
  }

  /// Production default stays off until the corrected iMAPS reader is
  /// released and verified. This is a reviewed code constant, not a runtime
  /// or build toggle, so a deployment cannot switch it on accidentally.
  static const bool remoteTransmissionEnabled = false;

  /// Local tests may exercise the enabled path; app code must never set this.
  @visibleForTesting
  static bool? remoteTransmissionEnabledForTesting;

  static bool get isRemoteTransmissionEnabled =>
      remoteTransmissionEnabledForTesting ?? remoteTransmissionEnabled;

  /// The remote checklist contract: the five legacy boolean rows first, in
  /// their existing order, then one row per active structured answer when
  /// transmission is enabled. Missing answers and hidden conditional children
  /// are omitted; they are never serialized as "No". Legacy counts remain the
  /// five boolean rows, so structured answers never change historical totals.
  static List<Map<String, dynamic>> remoteChecklist({
    required Map<String, bool> legacy,
    required Map<String, String?> answers,
  }) {
    final entries = <Map<String, dynamic>>[
      for (final entry in legacy.entries)
        {'item': entry.key, 'checked': entry.value},
    ];
    if (!isRemoteTransmissionEnabled) return entries;

    final emitted = entries.map((entry) => entry['item'] as String).toSet();
    final active = activeAnswers(answers);
    for (final key in questionLabels.keys) {
      final answer = active[key];
      if (answer == null) continue;
      final item = questionLabels[key]!;
      if (!emitted.add(item)) continue;
      entries.add({'item': item, 'answer': answer});
    }
    return entries;
  }

  /// Tolerant decode: ignores unknown keys, unknown option tokens and
  /// non-string values left by older or newer app versions.
  static Map<String, String> decode(Object? raw) {
    if (raw is! Map) return {};
    final decoded = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) continue;
      if (!questionLabels.containsKey(key)) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (key != existingUse && !optionsFor(key).containsKey(trimmed)) {
        continue;
      }
      decoded[key] = trimmed;
    }
    return decoded;
  }

  /// Decodes the label-based rows stored on a remote inspection. Ambiguous
  /// rows are omitted so callers keep them as unrecorded rather than guessing.
  static Map<String, String> decodeRemoteChecklist(
    Object? raw, {
    required String inspectorId,
    int? inspectionRoundNumber,
  }) {
    if (raw is! List) return {};

    final keysByLabel = {
      for (final entry in questionLabels.entries) entry.value: entry.key,
    };
    final rowsByKey = <String, List<Map>>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = value['item'];
      if (item is! String) continue;
      final key = keysByLabel[item.trim()];
      if (key == null) continue;
      rowsByKey.putIfAbsent(key, () => []).add(value);
    }

    final decoded = <String, String>{};
    for (final entry in rowsByKey.entries) {
      final rows = entry.value;
      if (rows.length != 1) continue;
      final row = rows.single;
      if (row.containsKey('checked') || row.containsKey('passed')) continue;

      final rowInspector = row['inspector_id'];
      if (row.containsKey('inspector_id') &&
          (rowInspector is! String || rowInspector != inspectorId)) {
        continue;
      }
      final rowRound = row['inspection_round_number'];
      if (row.containsKey('inspection_round_number') &&
          (rowRound is! num ||
              inspectionRoundNumber == null ||
              rowRound != inspectionRoundNumber)) {
        continue;
      }

      final rawAnswer = row['answer'];
      if (rawAnswer is! String) continue;
      final answer = rawAnswer.trim();
      if (answer.isEmpty) continue;
      if (entry.key == existingUse) {
        decoded[entry.key] = answer;
        continue;
      }

      final normalized = answer.toLowerCase();
      String? allowedValue;
      for (final option in optionsFor(entry.key).entries) {
        if (normalized == option.key ||
            normalized == option.value.toLowerCase()) {
          allowedValue = option.key;
          break;
        }
      }
      if (allowedValue != null) decoded[entry.key] = allowedValue;
    }

    return activeAnswers(decoded);
  }

  static String labelFor(String key, String? value) {
    if (value == null || value.isEmpty) return 'Not recorded';
    if (key == existingUse) return value;
    return optionsFor(key)[value] ?? 'Not recorded';
  }

  /// Ordered review rows. Unanswered top-level questions are shown as
  /// "Not recorded"; conditional rows appear only while their parent is Yes.
  static List<StructuredChecklistRow> reviewRows(Map<String, String?> answers) {
    final rows = <StructuredChecklistRow>[];
    void add(String key) {
      rows.add(
        StructuredChecklistRow(
          questionLabels[key]!,
          labelFor(key, answers[key]),
        ),
      );
    }

    add(existingDevelopment);
    if (answers[existingDevelopment] == yes) {
      add(existingUse);
    }
    add(extensionOfExisting);
    add(proposalStage);
    if (answers[proposalStage] == yes) {
      add(treesPresent);
      add(canalWaterway);
    }
    add(mojonObserved);
    return rows;
  }
}

class StructuredChecklistRow {
  const StructuredChecklistRow(this.label, this.value);

  final String label;
  final String value;
}
