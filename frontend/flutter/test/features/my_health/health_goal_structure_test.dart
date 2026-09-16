/// 프로필·건강 목표·온보딩이 같은 구조와 용어를 쓴다. (#1471)
///
/// 건강 목표는 진단받은 질환이 아니라 **운동을 시작하는 이유**다(#1814).
/// 그래서 내 프로필에는 기본 정보만 두고, 관리 초점과 자유 입력 운동 목표는
/// `건강 목표` 화면에 모은다 — 온보딩이 저장한 값을 그대로 이어받는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/health_focus_label.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const UserProfile _saved = UserProfile(
  id: 'member',
  name: '김민수',
  email: 'minsu@oncare.com',
  // 트레이너가 적은 주의사항이 같은 칸에 함께 있다.
  conditions: '혈압 관리, 무릎 통증으로 러닝 자제',
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
  group('건강 목표 문자열', () {
    test('저장된 값을 읽고, 목표가 아닌 글은 칩으로 만들지 않는다', () {
      expect(parseHealthFocus('체중 감량, 혈압 관리'), <String>{
        kHealthFocusWeightLoss,
        kHealthFocusBloodPressure,
      });
      expect(parseHealthFocus('허리 통증'), isEmpty);
      expect(parseHealthFocus(''), isEmpty);
    });

    test('옛 질환 이름은 새 목표로 읽거나 지운다', () {
      expect(parseHealthFocus('고혈압, 당뇨 전단계'), <String>{
        kHealthFocusBloodPressure,
      });
      expect(parseHealthFocus('비만, 고지혈증, 당뇨'), <String>{
        kHealthFocusWeightLoss,
      });
    });

    test('고른 목표는 늘 목록 순서로 저장된다', () {
      expect(
        formatHealthFocus(<String>{
          kHealthFocusBloodPressure,
          kHealthFocusWeightLoss,
        }),
        '체중 감량, 혈압 관리',
      );
      expect(formatHealthFocus(<String>{}), '');
    });

    test('목표를 고쳐도 목표가 아닌 글은 뒤에 남는다', () {
      expect(
        mergeHealthFocus('혈압 관리, 무릎 통증으로 러닝 자제', <String>{
          kHealthFocusStrength,
        }),
        '근력 향상, 무릎 통증으로 러닝 자제',
      );
      expect(mergeHealthFocus('고혈압, 당뇨', <String>{}), '');
    });

    test('건강 목표는 두 개까지 — 넘치면 목록 순서로 앞의 둘만 읽는다', () {
      expect(kHealthFocusMaxSelected, 2);
      expect(parseHealthFocus('재활, 체중 감량, 근력 향상'), <String>{
        kHealthFocusWeightLoss,
        kHealthFocusStrength,
      });
      expect(
        normalizeHealthFocusText('고혈압, 비만, 체력 강화, 무릎 통증'),
        '체중 감량, 체력 강화, 무릎 통증',
      );
    });

    test('두 개를 고르면 새 칩은 못 고르고 고른 칩은 풀 수 있다', () {
      const Set<String> two = <String>{kHealthFocusRehab, kHealthFocusPosture};
      expect(canPickHealthFocus(two, kHealthFocusRehab), isTrue);
      expect(canPickHealthFocus(two, kHealthFocusFitness), isFalse);
      expect(
        canPickHealthFocus(const <String>{
          kHealthFocusRehab,
        }, kHealthFocusFitness),
        isTrue,
      );
    });

    test('서버와 같은 정리 — 옛 이름은 바꾸고 겹침은 합친다', () {
      expect(
        normalizeHealthFocusText('고혈압, 혈압 관리, 무릎 통증, 비만'),
        '체중 감량, 혈압 관리, 무릎 통증',
      );
    });
  });

  test('모든 건강 목표에 ko·en 문구가 있고 영어에 한글이 없다', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    expect(kHealthFocusOptions, hasLength(8));
    for (final String option in kHealthFocusOptions) {
      expect(healthFocusLabel(ko, option), option);
      expect(healthFocusLabel(en, option), isNot(matches(RegExp('[가-힣]'))));
    }
    expect(healthFocusLabel(en, '무릎 통증'), '무릎 통증');
  });

  testWidgets('건강 목표 화면이 관리 초점과 운동 목표를 먼저 보여 준다', (tester) async {
    final (AppLocalizations l, _) = await _openGoals(tester);

    expect(find.text(l.myGoalsFocusSection), findsOneWidget);
    // 질환 보유 여부로 읽히는 문구를 쓰지 않는다.
    expect(find.textContaining('만성질환'), findsNothing);

    // 여덟 목표가 모두 칩으로 있고 옛 질환 칩은 없다(#1814).
    for (final String option in kHealthFocusOptions) {
      expect(
        find.byKey(ValueKey<String>('goal-focus-$option')),
        findsOneWidget,
      );
    }
    expect(find.text('고혈압'), findsNothing);
    expect(find.text('당뇨'), findsNothing);

    // 자유 입력 `운동 목표` 칸은 없다 — 목표는 칩만 고른다(#1829). 저장돼 있던
    // 문구도 이 화면에는 보이지 않는다.
    expect(find.byKey(const Key('goalExerciseNoteField')), findsNothing);
    expect(find.text('3개월 안에 5km 완주'), findsNothing);

    // 순서: 건강 목표 → 수치형 운동 목표 → 식단 목표.
    final double focus = tester.getTopLeft(find.text(l.myGoalsFocusSection)).dy;
    final double exercise = tester
        .getTopLeft(find.text(l.myGoalsExerciseSection))
        .dy;
    final double diet = tester.getTopLeft(find.text(l.myGoalsDietSection)).dy;
    expect(focus, lessThan(exercise));
    expect(exercise, lessThan(diet));
  });

  testWidgets('건강 목표를 저장하고 자유 입력 목표는 보내지 않는다', (tester) async {
    final (AppLocalizations l, MockAccountRepository repository) =
        await _openGoals(tester);

    // 근력 향상을 추가로 고른다.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('goal-focus-근력 향상')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('goal-focus-근력 향상')));
    await tester.pumpAndSettle();

    // 두 개를 채웠으니 다른 칩은 잠긴다.
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(const ValueKey<String>('goal-focus-재활')),
          )
          .onSelected,
      isNull,
    );

    await tester.tap(find.text(l.mySave).last);
    await tester.pumpAndSettle();

    final UserProfile saved = await repository.fetchProfile();
    // 트레이너가 적은 주의사항은 지워지지 않는다.
    expect(saved.conditions, '근력 향상, 혈압 관리, 무릎 통증으로 러닝 자제');
    // 회원이 이 화면에서 적지 않는 값이라 그대로 남는다(#1829).
    expect(saved.goals, '3개월 안에 5km 완주');
  });
}
