import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const inspectorA = '11111111-1111-4111-8111-111111111111';
const inspectorB = '22222222-2222-4222-8222-222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('records and language stay separate for two inspectors', () async {
    final preferences = GuidePreferences();
    expect(await preferences.read(inspectorA), isNull);
    await preferences.write(
      inspectorA,
      const GuideRecord(1, GuideLanguage.tagalog, GuideStatus.completed),
    );
    await preferences.write(
      inspectorB,
      const GuideRecord(1, GuideLanguage.english, GuideStatus.skipped),
    );
    final a = await preferences.read(inspectorA);
    final b = await preferences.read(inspectorB);
    expect(a?.status, GuideStatus.completed);
    expect(a?.language, GuideLanguage.tagalog);
    expect(b?.status, GuideStatus.skipped);
    expect(b?.language, GuideLanguage.english);
    final store = await SharedPreferences.getInstance();
    expect(store.getKeys(), hasLength(2));
    expect(store.getKeys().any((key) => key.contains(inspectorA)), isFalse);
    expect(
      store.getKeys().every(
        (key) => RegExp(r'^fieldsync\.guide\.[a-f0-9]{64}$').hasMatch(key),
      ),
      isTrue,
    );
  });

  test('only missing is first use; malformed records fail closed', () async {
    final key = 'fieldsync.guide.${sha256.convert(utf8.encode(inspectorA))}';
    final store = await SharedPreferences.getInstance();
    for (final raw in [
      'not json',
      'null',
      '{"version":0,"language":"english","status":"offered"}',
      '{"version":1,"language":"other","status":"offered"}',
      '{"version":1,"language":"english","status":"unknown"}',
      '{"language":"english","status":"offered"}',
    ]) {
      await store.setString(key, raw);
      await expectLater(
        GuidePreferences().read(inspectorA),
        throwsFormatException,
      );
    }
    await store.setBool(key, true);
    await expectLater(
      GuidePreferences().read(inspectorA),
      throwsFormatException,
    );
  });

  test(
    'future metadata survives reading without automatic version migration',
    () async {
      await GuidePreferences().write(
        inspectorA,
        const GuideRecord(9, GuideLanguage.tagalog, GuideStatus.completed),
      );
      expect((await GuidePreferences().read(inspectorA))?.version, 9);
    },
  );

  test(
    'empty and non-account identifiers cannot create a shared record',
    () async {
      for (final id in ['', ' ', 'inspector@example.com']) {
        await expectLater(GuidePreferences().read(id), throwsArgumentError);
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
}
