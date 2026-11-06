import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_preferences.dart';
import 'package:imaps_fieldsync/modules/interactive_guide/guide_script.dart';

void main() {
  test(
    'short walkthrough retains core teaching and contiguous localized stages',
    () {
      expect(guideStops, hasLength(35));
      expect(guideStops.map((s) => s.id).toSet(), hasLength(35));
      expect(
        [
          for (var stage = 1; stage <= 6; stage++)
            guideStops.where((s) => s.stage == stage).length,
        ],
        [4, 3, 6, 9, 4, 9],
      );
      expect(guideStops.map((stop) => stop.id), [
        for (var index = 2; index <= 24; index++)
          if (index != 11) 'G${index.toString().padLeft(2, '0')}',
        'G32',
        'G33',
        'G34',
        'G35',
        'G36',
        'G36-summary',
        'G37',
        'G38',
        'G39',
        'G39-support',
        'G39-policies',
        'G39-about',
        'G41',
      ]);
      for (var i = 0; i < guideStops.length; i++) {
        final stop = guideStops[i];
        expect(stop.targetId, isNotEmpty);
        for (final language in GuideLanguage.values) {
          expect(stop.copyFor(language).title, isNotEmpty);
          expect(stop.copyFor(language).message, isNotEmpty);
          expect(stop.copyFor(language).summary, isNotEmpty);
          expect(stop.stageTitle(language), isNotEmpty);
        }
      }
      expect(
        guideStops.first.progress(GuideLanguage.english),
        'Stage 1 of 6 · Explanation 1 of 4',
      );
      expect(
        guideStops.last.progress(GuideLanguage.tagalog),
        'Yugto 6 ng 6 · Paliwanag 9 ng 9',
      );
    },
  );

  test('invitation and completion use the owner-approved bilingual messages', () {
    expect(
      guideInvitationEnglish.message,
      "Welcome to FieldSync! I'm your FieldSync Guide. Would you like a quick tour of the application? I'll show you where to find your inspection tasks and how the main features work.",
    );
    expect(
      guideInvitationTagalog.message,
      'Maligayang pagdating sa FieldSync! Ako ang iyong FieldSync Guide. Gusto mo bang maglibot muna tayo sa application? Ipapakita ko kung saan makikita ang iyong mga inspection task at kung paano gamitin ang mahahalagang feature.',
    );
    expect(
      guideStops.last.english.message,
      "You're ready to manage inspections and find help. Your saved work is unchanged.",
    );
    expect(
      guideStops.last.tagalog.message,
      'Handa ka nang mag-asikaso ng inspections at humingi ng tulong. Walang nabago sa naka-save mong gawain.',
    );
  });

  test(
    'both languages retain safety caveats and complete navigation controls',
    () {
      for (final language in GuideLanguage.values) {
        final labels = GuideLabels(language);
        expect([
          labels.start,
          labels.notNow,
          labels.back,
          labels.next,
          labels.skip,
          labels.done,
          labels.replay,
          labels.chooseLanguage,
          labels.moreDetails,
          labels.close,
          labels.navigation,
          labels.pageIntroduction,
          labels.examplesBody,
          labels.safety,
        ], everyElement(isNotEmpty));
        final protocol = guideStops.singleWhere((stop) => stop.id == 'G17');
        final gps = guideStops.singleWhere((stop) => stop.id == 'G19');
        expect(protocol.copyFor(language).message, contains('3, 4'));
        expect(gps.copyFor(language).details, contains('30m'));
        expect(gps.copyFor(language).details, contains('25m'));
        expect(gps.copyFor(language).details, contains('15'));
        expect(
          guideStops
              .singleWhere((stop) => stop.id == 'G35')
              .copyFor(language)
              .message,
          contains('Planning Officer'),
        );
      }
      expect(
        const GuideLabels(GuideLanguage.tagalog).skip,
        'Laktawan ang Gabay',
      );
    },
  );
}
