import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_coordinator.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'interactive_guide_preferences_test.dart' show inspectorA, inspectorB;

// Delay the external storage boundary, retaining real record serialization.
class DelayedPreferences extends GuidePreferences {
  Completer<void>? readGate;
  Completer<void>? writeGate;
  var writing = Completer<void>();

  @override
  Future<GuideRecord?> read(String inspectorId) async {
    await readGate?.future;
    return super.read(inspectorId);
  }

  @override
  Future<void> write(String inspectorId, GuideRecord record) async {
    if (!writing.isCompleted) writing.complete();
    await writeGate?.future;
    await super.write(inspectorId, record);
  }
}

class UnreadablePreferences extends GuidePreferences {
  @override
  Future<GuideRecord?> read(String inspectorId) async =>
      throw const FormatException('Unreadable guide metadata');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GuidePreferences preferences;
  late GuideCoordinator guide;
  var eligible = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = GuidePreferences();
    eligible = true;
    guide = GuideCoordinator(
      inspectorId: inspectorA,
      preferences: preferences,
      canPresent: () => eligible,
    );
  });
  tearDown(() => guide.dispose());

  for (final boundary in ['read', 'write']) {
    test(
      'suspending the first offer during $boundary still presents it after eligibility returns',
      () async {
        guide.dispose();
        final delayed = DelayedPreferences();
        if (boundary == 'read') {
          delayed.readGate = Completer<void>();
        } else {
          delayed.writeGate = Completer<void>();
        }
        guide = GuideCoordinator(
          inspectorId: inspectorA,
          preferences: delayed,
          canPresent: () => eligible,
        );
        final offer = guide.offerIfEligible();
        if (boundary == 'write') {
          await delayed.writing.future;
        }
        eligible = false;
        guide.suspend();
        delayed.readGate?.complete();
        delayed.writeGate?.complete();
        await offer;
        eligible = true;
        guide.resumeIfEligible();
        await guide.offerIfEligible();
        expect(guide.phase, GuidePhase.invitation);
        expect(
          (await preferences.read(inspectorA))?.status,
          GuideStatus.offered,
        );
      },
    );
  }

  for (final boundary in ['queued', 'writing']) {
    test(
      'Done survives $boundary interruption and replay Skip never downgrades completion',
      () async {
        guide.dispose();
        final delayed = DelayedPreferences();
        guide = GuideCoordinator(
          inspectorId: inspectorA,
          preferences: delayed,
          canPresent: () => eligible,
        );
        await guide.start(GuideLanguage.english);
        for (var i = 0; i < guideStops.length - 1; i++) {
          guide.next();
        }
        delayed.writing = Completer<void>();
        if (boundary == 'writing') {
          delayed.writeGate = Completer<void>();
        }
        final done = guide.finish();
        if (boundary == 'writing') {
          await delayed.writing.future;
        }
        guide.suspend();
        final replay = guide.start(GuideLanguage.tagalog, replay: true);
        delayed.writeGate?.complete();
        await Future.wait([done, replay]);
        await guide.skip();
        final record = await preferences.read(inspectorA);
        expect(record?.status, GuideStatus.completed);
        expect(record?.language, GuideLanguage.tagalog);
      },
    );
  }

  test('ineligible Home defers rather than consumes first offer', () async {
    eligible = false;
    await guide.offerIfEligible();
    expect(guide.phase, GuidePhase.idle);
    expect(await preferences.read(inspectorA), isNull);
    eligible = true;
    await guide.offerIfEligible();
    expect(guide.phase, GuidePhase.invitation);
    expect((await preferences.read(inspectorA))?.status, GuideStatus.offered);
  });

  test(
    'duplicate offers produce one invitation and Not Now suppresses relaunch',
    () async {
      await Future.wait([guide.offerIfEligible(), guide.offerIfEligible()]);
      expect(guide.phase, GuidePhase.invitation);
      await guide.skip();
      expect(guide.phase, GuidePhase.idle);
      expect((await preferences.read(inspectorA))?.status, GuideStatus.skipped);
      await guide.offerIfEligible();
      expect(guide.phase, GuidePhase.idle);
      final nextSession = GuideCoordinator(
        inspectorId: inspectorA,
        preferences: preferences,
        canPresent: () => true,
      );
      await nextSession.offerIfEligible();
      expect(nextSession.phase, GuidePhase.idle);
      nextSession.dispose();
    },
  );

  test('a prior offer at any version is not auto-enrolled', () async {
    for (final status in GuideStatus.values) {
      await preferences.write(
        inspectorB,
        GuideRecord(9, GuideLanguage.tagalog, status),
      );
      final other = GuideCoordinator(
        inspectorId: inspectorB,
        preferences: preferences,
        canPresent: () => true,
      );
      await other.offerIfEligible();
      expect(other.phase, GuidePhase.idle);
      expect(other.language, GuideLanguage.tagalog);
      other.dispose();
    }
    expect(await preferences.read(inspectorA), isNull);
  });

  test(
    'cursor clamps, completion requires final stop and persists Done',
    () async {
      await guide.start(GuideLanguage.tagalog);
      guide.back();
      expect(guide.stopIndex, 0);
      await guide.finish();
      expect(guide.phase, GuidePhase.active);
      for (var i = 0; i < guideStops.length + 5; i++) {
        guide.next();
      }
      expect(guide.stopIndex, guideStops.length - 1);
      await guide.finish();
      expect(guide.phase, GuidePhase.idle);
      final record = await preferences.read(inspectorA);
      expect(record?.status, GuideStatus.completed);
      expect(record?.language, GuideLanguage.tagalog);
      expect(record?.version, 1);
    },
  );

  test(
    'completed replay changes language without downgrading completion or version',
    () async {
      await preferences.write(
        inspectorA,
        const GuideRecord(9, GuideLanguage.english, GuideStatus.completed),
      );
      await guide.start(GuideLanguage.tagalog, replay: true);
      await guide.skip();
      final record = await preferences.read(inspectorA);
      expect(record?.status, GuideStatus.completed);
      expect(record?.language, GuideLanguage.tagalog);
      expect(record?.version, 9);
    },
  );

  test('duplicate Start does not reset an active walkthrough', () async {
    await Future.wait([
      guide.start(GuideLanguage.english),
      guide.start(GuideLanguage.tagalog),
    ]);
    guide.next();
    await guide.start(GuideLanguage.tagalog, replay: true);
    expect(guide.stopIndex, 1);
    expect(guide.language, GuideLanguage.english);
  });

  test(
    'Skip hides immediately while offered write is pending and wins storage ordering',
    () async {
      guide.dispose();
      final delayed = DelayedPreferences()..writeGate = Completer<void>();
      guide = GuideCoordinator(
        inspectorId: inspectorA,
        preferences: delayed,
        canPresent: () => eligible,
      );
      final offer = guide.offerIfEligible();
      await delayed.writing.future;
      final skip = guide.skip();
      expect(guide.phase, GuidePhase.idle);
      delayed.writeGate!.complete();
      await Future.wait([offer, skip]);
      expect(guide.phase, GuidePhase.idle);
      expect((await preferences.read(inspectorA))?.status, GuideStatus.skipped);
    },
  );

  test(
    'invalidation during a read cannot offer or write for an ended owner',
    () async {
      guide.dispose();
      final delayed = DelayedPreferences()..readGate = Completer<void>();
      guide = GuideCoordinator(
        inspectorId: inspectorA,
        preferences: delayed,
        canPresent: () => eligible,
      );
      final offer = guide.offerIfEligible();
      guide.invalidate();
      delayed.readGate!.complete();
      await offer;
      expect(guide.phase, GuidePhase.idle);
      expect(await preferences.read(inspectorA), isNull);
      expect(await preferences.read(inspectorB), isNull);
      await guide.start(GuideLanguage.english, replay: true);
      expect(guide.phase, GuidePhase.idle);
    },
  );

  test('dispose during loading has no late notification', () async {
    final delayed = DelayedPreferences()..readGate = Completer<void>();
    final disposed = GuideCoordinator(
      inspectorId: inspectorB,
      preferences: delayed,
      canPresent: () => true,
    );
    var notifications = 0;
    disposed.addListener(() => notifications++);
    final pending = disposed.offerIfEligible();
    disposed.dispose();
    delayed.readGate!.complete();
    await pending;
    expect(notifications, 0);
    expect(await preferences.read(inspectorB), isNull);
  });

  test(
    'corrupt preferences suppress automatic offer but allow ephemeral manual replay',
    () async {
      guide.dispose();
      guide = GuideCoordinator(
        inspectorId: inspectorA,
        preferences: UnreadablePreferences(),
        canPresent: () => true,
      );
      await guide.offerIfEligible();
      expect(guide.phase, GuidePhase.idle);
      await guide.start(GuideLanguage.tagalog, replay: true);
      expect(guide.phase, GuidePhase.active);
      expect(guide.language, GuideLanguage.tagalog);
      await guide.skip();
      expect(guide.phase, GuidePhase.idle);
    },
  );

  test(
    'suspension keeps only a cursor and cannot resume without eligibility',
    () async {
      await guide.start(GuideLanguage.english);
      guide.next();
      final before = guide.generation;
      eligible = false;
      guide.suspend();
      expect(guide.phase, GuidePhase.suspended);
      expect(guide.generation, greaterThan(before));
      guide.resumeIfEligible();
      expect(guide.phase, GuidePhase.suspended);
      eligible = true;
      guide.resumeIfEligible();
      expect(guide.phase, GuidePhase.active);
      expect(guide.stopIndex, 1);
    },
  );
}
