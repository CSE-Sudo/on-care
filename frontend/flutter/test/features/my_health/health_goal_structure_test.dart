/// 프로필·건강 목표·온보딩이 같은 구조와 용어를 쓴다. (#1471)
///
/// 고혈압·당뇨는 진단받은 질환을 단정하는 값이 아니라 **어디에 초점을 둘지**다.
/// 그래서 내 프로필에는 기본 정보만 두고, 관리 초점과 자유 입력 운동 목표는
/// `건강 목표` 화면에 모은다 — 온보딩이 저장한 값을 그대로 이어받는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';

import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const UserProfile _saved = UserProfile(
  id: 'member',
  name: '김민수',
  email: 'minsu@oncare.com',
  conditions: '고혈압',
  goals: '3개월 안에 5km 완주',
);

Future<(AppLocalizations, MockAccountRepository)> _openGoals(
  WidgetTester tester, {
  UserProfile profile = _saved,
}) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final MockAccountRepository repository = MockAccountRepository(
    profile: profile,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthGoalsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    AppLocalizations.of(tester.element(find.byType(HealthGoalsPage))),
    repository,
  );
}

void main() {
  group('관리 초점 문자열', () {
    test('저장된 값을 읽고, 모르는 값은 버린다', () {
      expect(parseHealthFocus('고혈압, 당뇨'), <String>{'고혈압', '당뇨'});
      expect(parseHealthFocus('고혈압'), <String>{'고혈압'});
      // 예전 자유 입력이 섞여 있어도 칩을 지어내지 않는다.
      expect(parseHealthFocus('허리 통증'), isEmpty);
      expect(parseHealthFocus(''), isEmpty);
    });

    test('고른 항목은 늘 같은 순서로 저장된다', () {
      expect(
        formatHealthFocus(<String>{
          kHealthFocusDiabetes,
          kHealthFocusHypertension,
        }),
        '고혈압, 당뇨',
      );
      expect(formatHealthFocus(<String>{}), '');
    });
  });

  testWidgets('건강 목표 화면이 관리 초점과 운동 목표를 먼저 보여 준다', (tester) async {
    final (AppLocalizations l, _) = await _openGoals(tester);

    expect(find.text(l.myGoalsFocusSection), findsOneWidget);
    // 질환 보유 여부로 읽히는 문구를 쓰지 않는다.
    expect(find.textContaining('만성질환'), findsNothing);

    // 저장돼 있던 값이 그대로 열린다.
    expect(find.text('3개월 안에 5km 완주'), findsOneWidget);

    // 순서: 관리 초점 → 운동 목표 → 수치형 운동 목표 → 식단 목표.
    final double focus = tester.getTopLeft(find.text(l.myGoalsFocusSection)).dy;
    final double exercise = tester
        .getTopLeft(find.text(l.myGoalsExerciseSection))
        .dy;
    final double diet = tester.getTopLeft(find.text(l.myGoalsDietSection)).dy;
    expect(focus, lessThan(exercise));
    expect(exercise, lessThan(diet));
  });

  testWidgets('관리 초점과 운동 목표를 함께 저장한다', (tester) async {
    final (AppLocalizations l, MockAccountRepository repository) =
        await _openGoals(tester);

    // 당뇨를 추가로 고르고 목표 문구를 고친다.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('goal-focus-당뇨')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('goal-focus-당뇨')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('goalExerciseNoteField')),
      '주 3회 근력 운동',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.mySave).last);
    await tester.pumpAndSettle();

    final UserProfile saved = await repository.fetchProfile();
    expect(saved.conditions, '고혈압, 당뇨');
    expect(saved.goals, '주 3회 근력 운동');
  });
}
