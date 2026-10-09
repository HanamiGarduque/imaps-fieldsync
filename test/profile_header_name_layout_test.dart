import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/models/user_profile.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_edit_screen.dart';
import 'package:imaps_fieldsync/modules/profile_settings/screens/profile_screen.dart';

void main() {
  const fullName = 'Gemini Norawit Titipun';
  const email = 'gemini.norawit@example.com';

  Widget identityCard({
    double width = 320,
    String name = fullName,
    String role = 'Zoning Officer I',
    double textScale = 1,
    bool compact = false,
    VoidCallback? onEditTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: ProfileIdentityCard(
                      compact: compact,
                      avatarUrl: null,
                      initials: UserProfile.avatarInitials(name),
                      displayName: UserProfile.displayFullName(name),
                      positionLabel: role,
                      userEmail: email,
                      onEditTap: onEditTap ?? () {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('profile name helpers', () {
    test('visible name preserves the stored value without abbreviation', () {
      expect(UserProfile.displayFullName(fullName), fullName);
      expect(UserProfile.displayFullName('  $fullName  '), fullName);
      expect(
        UserProfile.displayFullName('Gemini  Norawit Titipun'),
        'Gemini  Norawit Titipun',
      );
    });

    test('avatar initials remain separate from visible-name formatting', () {
      expect(UserProfile.avatarInitials(fullName), 'GN');
      expect(UserProfile.avatarInitials('  Gemini   Norawit Titipun  '), 'GN');
      expect(UserProfile.avatarInitials('Prince'), 'PR');
      expect(UserProfile.avatarInitials(''), 'JR');
    });

    test(
      'Profile Edit accepts internal spaces and trims only outer spaces',
      () {
        expect(validateProfileFullName('  $fullName  '), isNull);
        expect(normalizeProfileFullName('  $fullName  '), fullName);
        expect(validateProfileFullName('Gemini  Norawit Titipun'), isNull);
        expect(validateProfileFullName('Juan Miguel Dela Cruz'), isNull);
        expect(validateProfileFullName('Gemini Norawit Example'), isNull);
        expect(
          normalizeProfileFullName('  Juan  Miguel Dela Cruz  '),
          'Juan  Miguel Dela Cruz',
        );
        expect(validateProfileFullName("José Anne-Marie O'Neil Jr."), isNull);
        expect(validateProfileFullName('Name123'), isNotNull);
        expect(validateProfileFullName('   '), isNotNull);
        expect(validateProfileFullName('A'), isNotNull);
        expect(validateProfileFullName('A' * 65), isNotNull);
      },
    );
  });

  testWidgets('identity card wraps the full name without ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(identityCard(width: 250));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(fullName), findsOneWidget);
    expect(find.text('G. Norawit Titipun'), findsNothing);

    final nameText = tester.widget<Text>(
      find.byKey(const Key('profile-visible-name')),
    );
    expect(nameText.data, fullName);
    expect(nameText.maxLines, isNull);
    expect(nameText.overflow, isNull);

    final narrowNameHeight = tester
        .getSize(find.byKey(const Key('profile-visible-name')))
        .height;

    await tester.pumpWidget(identityCard(width: 420));
    await tester.pumpAndSettle();
    final wideNameHeight = tester
        .getSize(find.byKey(const Key('profile-visible-name')))
        .height;

    expect(narrowNameHeight, greaterThan(wideNameHeight));
    expect(find.text(fullName), findsOneWidget);
    expect(find.text('GN'), findsOneWidget);
    expect(find.text(email), findsOneWidget);
  });

  testWidgets('role badge is content-sized and single-line', (tester) async {
    await tester.pumpWidget(identityCard(width: 320));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final badgeWidth = tester
        .getSize(find.byKey(const Key('profile-role-badge')))
        .width;
    final roleTextFinder = find.text('ZONING OFFICER I');
    final roleTextWidth = tester.getSize(roleTextFinder).width;
    expect(badgeWidth, closeTo(roleTextWidth + 22, 0.1));

    final paragraph = tester.renderObject<RenderParagraph>(roleTextFinder);
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 15),
    );
    expect(boxes.map((box) => box.top).toSet(), hasLength(1));

    await tester.pumpWidget(identityCard(role: 'Admin'));
    expect(
      tester.getSize(find.byKey(const Key('profile-role-badge'))).width,
      lessThan(badgeWidth),
    );
  });

  testWidgets('identity card height grows naturally with wrapped content', (
    tester,
  ) async {
    await tester.pumpWidget(identityCard(width: 420));
    await tester.pumpAndSettle();
    final wideHeight = tester.getSize(find.byType(ProfileIdentityCard)).height;

    await tester.pumpWidget(identityCard(width: 250));
    await tester.pumpAndSettle();
    final narrowHeight = tester
        .getSize(find.byType(ProfileIdentityCard))
        .height;

    expect(tester.takeException(), isNull);
    expect(narrowHeight, greaterThan(wideHeight));
    final cardBottom = tester
        .getBottomLeft(find.byType(ProfileIdentityCard))
        .dy;
    final emailBottom = tester.getBottomLeft(find.text(email)).dy;
    expect(cardBottom - emailBottom, closeTo(16, 0.1));
  });

  testWidgets('Edit action remains tappable on a narrow card', (tester) async {
    var editTapped = false;
    await tester.pumpWidget(
      identityCard(width: 250, onEditTap: () => editTapped = true),
    );
    await tester.pumpAndSettle();

    final editButton = find.byKey(const Key('profile-edit-button'));
    expect(find.text('Edit'), findsOneWidget);
    expect(tester.getSize(editButton).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(editButton);
    await tester.pump();

    expect(editTapped, isTrue);
  });

  testWidgets(
    'compact identity retains long names, role and email at 2x text',
    (tester) async {
      const name = 'Gemini Norawit Alexandria Maria Dela Cruz Example';
      var edited = false;
      await tester.pumpWidget(
        identityCard(
          width: 280,
          name: name,
          textScale: 2,
          compact: true,
          onEditTap: () => edited = true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(name), findsOneWidget);
      expect(find.text('Zoning Officer I'), findsOneWidget);
      expect(find.text(email), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getBottomLeft(find.text(email)).dy,
        lessThan(tester.getBottomLeft(find.byType(ProfileIdentityCard)).dy),
      );
      final edit = find.byKey(const Key('profile-edit-button'));
      expect(tester.getSize(edit).shortestSide, greaterThanOrEqualTo(48));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pump();
      expect(edited, isTrue);
    },
  );

  for (final name in [
    'Gemini Example',
    'Juan Miguel Dela Cruz',
    'Gemini Norawit Alexandria Maria Dela Cruz Example',
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full name at 320px phone width, scale $scale: $name', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          identityCard(width: 280, name: name, textScale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final nameFinder = find.text(name);
        expect(nameFinder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(nameFinder);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.maxLines, isNull);
        expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
        expect(find.text(email), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text(email)).dy,
          lessThanOrEqualTo(
            tester.getBottomLeft(find.byType(ProfileIdentityCard)).dy,
          ),
        );
      });
    }
  }
}
