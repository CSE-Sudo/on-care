import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩 3·4단계가 권장값을 미리 채우고, 회원이 고친 값을 지키고, 끝에서 그
/// 열 칸을 그대로 저장하는지. 1단계 기본 정보는 모두 채워야 넘어간다(#1830).
///
/// 예전 온보딩은 나트륨 한 칸만 받았다. 가입 직후의 홈·식단·운동 탭이 전부
/// 앱 기본값을 목표선으로 그려, 회원이 정한 적 없는 목표를 견주고 있었다.

/// 마지막에 무엇이 서버로 나갔는지 그대로 붙잡아 두는 저장소.
class _RecordingRepository implements AccountRepository {
  _RecordingRepository() : _inner = MockAccountRepository();
  final MockAccountRepository _inner;

  Map<String, Object?>? submitted;

  @override
  Future<UserProfile> submitOnboarding({
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
    String? conditions,
    String? goals,
    int? dailyCalories,
    int? dailySodiumMg,
    int? dailySugarG,
    int? dailyCarbsG,
    int? dailyProteinG,
    int? dailyFatG,
    int? dailyBurnKcal,
    int? weeklyCardioMinutes,
    int? weeklyStrengthSets,
    int? weeklyFlexibilityMinutes,
  }) async {
    submitted = <String, Object?>{
      'birth_date': birthDate,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'conditions': conditions,
      'goals': goals,
      'daily_calories': dailyCalories,
      'daily_sodium_mg': dailySodiumMg,
      'daily_sugar_g': dailySugarG,
      'daily_carbs_g': dailyCarbsG,
      'daily_protein_g': dailyProteinG,
      'daily_fat_g': dailyFatG,
      'daily_burn_kcal': dailyBurnKcal,
      'weekly_cardio_minutes': weeklyCardioMinutes,
      'weekly_strength_sets': weeklyStrengthSets,
      'weekly_flexibility_minutes': weeklyFlexibilityMinutes,
    };
    return _inner.fetchProfile();
  }

  @override
  Future<UserProfile> fetchProfile() => _inner.fetchProfile();

  @override
  Future<void> deleteAccount() => _inner.deleteAccount();

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
    String? goals,
  }) => _inner.updateProfile(
    name: name,
    email: email,
    phone: phone,
    birthDate: birthDate,
    gender: gender,
    heightCm: heightCm,
    weightKg: weightKg,
    goals: goals,
  );

  @override
  Future<UserProfile> updateHealthGoals({
    String? conditions,
    String? goals,
    GoalUpdate? dailyCalories,
    GoalUpdate? dailySodiumMg,
    GoalUpdate? dailySugarG,
    GoalUpdate? dailyCarbsG,
    GoalUpdate? dailyProteinG,
    GoalUpdate? dailyFatG,
    GoalUpdate? weeklyWorkoutGoal,
    GoalUpdate? weeklyExerciseMinutesGoal,
    GoalUpdate? weeklyBurnGoal,
    GoalUpdate? dailyBurnKcal,
    GoalUpdate? weeklyCardioMinutes,
    GoalUpdate? weeklyStrengthSets,
    GoalUpdate? weeklyFlexibilityMinutes,
  }) => _inner.updateHealthGoals(
    dailyCalories: dailyCalories,
    dailySodiumMg: dailySodiumMg,
    dailySugarG: dailySugarG,
    dailyCarbsG: dailyCarbsG,
    dailyProteinG: dailyProteinG,
    dailyFatG: dailyFatG,
    weeklyWorkoutGoal: weeklyWorkoutGoal,
    weeklyExerciseMinutesGoal: weeklyExerciseMinutesGoal,
    weeklyBurnGoal: weeklyBurnGoal,
    dailyBurnKcal: dailyBurnKcal,
    weeklyCardioMinutes: weeklyCardioMinutes,
    weeklyStrengthSets: weeklyStrengthSets,
    weeklyFlexibilityMinutes: weeklyFlexibilityMinutes,
  );
}

Future<_RecordingRepository> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final _RecordingRepository repo = _RecordingRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[accountRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

/// 드롭다운 하나를 열어 값을 고른다.
Future<void> _selectBirthPart(
  WidgetTester tester,
  String key,
  int value,
) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  // 연도는 121칸이라 한 화면에 다 들어오지 않는다 — 목록을 끌어 내려 찾는다.
  final Finder item = find.text('$value${_unitOf(key)}');
  await tester.dragUntilVisible(
    item,
    find.byType(Scrollable).last,
    const Offset(0, -160),
  );
  await tester.tap(item.first);
  await tester.pumpAndSettle();
}

String _unitOf(String key) => switch (key) {
  'onboardBirthYear' => '년',
  'onboardBirthMonth' => '월',
  _ => '일',
};

Future<void> _pickBirth(
  WidgetTester tester, {
  required int year,
  required int month,
  required int day,
}) async {
  await _selectBirthPart(tester, 'onboardBirthYear', year);
  await _selectBirthPart(tester, 'onboardBirthMonth', month);
  await _selectBirthPart(tester, 'onboardBirthDay', day);
}

int? _birthValue(WidgetTester tester, String key) =>
    tester.widget<AppSelectField<int>>(find.byKey(Key(key))).value;

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
}

/// 1단계 기본 정보를 모두 채운다 — 1996-05-20 · 여성 · 160cm · 55kg.
Future<void> _fillBasics(WidgetTester tester) async {
  await _pickBirth(tester, year: 1996, month: 5, day: 20);
  await tester.tap(find.text('여성'));
  await tester.pump();
  await tester.enterText(_field('onboardHeightField'), '160');
  await tester.enterText(_field('onboardWeightField'), '55');
  await tester.pumpAndSettle();
}

/// [_fillBasics] 로 채운 몸에 대한 권장 목표.
RecommendedGoals _basicsGoals({Set<String> focus = const <String>{}}) =>
    recommendedGoalsFor(
      ageYears: ageFromBirthDate('1996-05-20', today: todayKst()),
      gender: 'female',
      heightCm: 160,
      weightKg: 55,
      focus: focus,
    );

/// 헤더의 `n / 4`.
String _stepLabel(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .firstWhere((String s) => RegExp(r'^\d / 4$').hasMatch(s));

void main() {
  group('1단계 기본 정보는 필수다(#1830)', () {
    testWidgets('제목 옆에 필수라고 적혀 있다', (tester) async {
      await _open(tester);

      expect(find.text('기본 정보'), findsOneWidget);
      expect(find.text('(필수)'), findsOneWidget);
      // 처음 연 화면부터 안내가 줄지어 있지는 않다.
      expect(find.text('생년월일을 골라 주세요'), findsNothing);
    });

    testWidgets('비워 두고 다음을 누르면 넘어가지 않고 빠진 칸마다 알려 준다', (tester) async {
      final _RecordingRepository repo = await _open(tester);

      await _tapNext(tester);

      expect(_stepLabel(tester), '1 / 4');
      expect(find.text('생년월일을 골라 주세요'), findsOneWidget);
      expect(find.text('성별을 골라 주세요'), findsOneWidget);
      expect(find.text('키를 입력해 주세요'), findsOneWidget);
      expect(find.text('체중을 입력해 주세요'), findsOneWidget);
      expect(repo.submitted, isNull);
    });

    testWidgets('생년월일만 비어 있으면 그 칸만 알려 주고, 채우면 안내가 사라진다', (tester) async {
      await _open(tester);

      await tester.tap(find.text('남성'));
      await tester.pump();
      await tester.enterText(_field('onboardHeightField'), '175');
      await tester.enterText(_field('onboardWeightField'), '70');
      await tester.pumpAndSettle();
      // 적은 값은 그 자리에서 되읽어 준다.
      expect(find.text('BMI 22.9 · 정상'), findsOneWidget);

      await _tapNext(tester);
      expect(_stepLabel(tester), '1 / 4');
      expect(find.text('생년월일을 골라 주세요'), findsOneWidget);
      expect(find.text('성별을 골라 주세요'), findsNothing);
      expect(find.text('키를 입력해 주세요'), findsNothing);

      await _pickBirth(tester, year: 1990, month: 1, day: 1);
      expect(find.text('생년월일을 골라 주세요'), findsNothing);

      await _tapNext(tester);
      expect(_stepLabel(tester), '2 / 4');
    });

    testWidgets('서버가 받지 않는 키·체중이면 범위를 알려 주고 머문다', (tester) async {
      await _open(tester);
      await _fillBasics(tester);
      await tester.enterText(_field('onboardHeightField'), '30');
      await tester.enterText(_field('onboardWeightField'), '900');
      await tester.pumpAndSettle();

      await _tapNext(tester);

      expect(_stepLabel(tester), '1 / 4');
      expect(find.text('키는 50~300cm 사이로 입력해 주세요'), findsOneWidget);
      expect(find.text('체중은 20~500kg 사이로 입력해 주세요'), findsOneWidget);
    });

    testWidgets('영어 문구도 같은 범위를 말한다', (tester) async {
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(en.onboardRequiredTag, '(required)');
      expect(
        en.onboardHeightRange(50, 300),
        'Height must be between 50 and 300 cm',
      );
      expect(
        en.onboardWeightRange(20, 500),
        'Weight must be between 20 and 500 kg',
      );
    });
  });

  group('하단 버튼', () {
    testWidgets('1단계는 다음 하나, 2~4단계는 이전·다음 2분할이다', (tester) async {
      await _open(tester);

      expect(find.byType(AppButtonPair), findsNothing);
      expect(find.byKey(const Key('onboardBackButton')), findsNothing);

      await _fillBasics(tester);
      for (final String step in <String>['2 / 4', '3 / 4', '4 / 4']) {
        await _tapNext(tester);
        expect(_stepLabel(tester), step);
        final AppButtonPair pair = tester.widget<AppButtonPair>(
          find.byType(AppButtonPair),
        );
        expect(pair.cancelLabel, '이전');
        expect(pair.confirmLabel, step == '4 / 4' ? '완료' : '다음');
        // 왼쪽은 흰 바탕 보조 버튼, 오른쪽은 파란 주 버튼이다.
        final AppButton back = tester.widget<AppButton>(
          find.byKey(const Key('onboardBackButton')),
        );
        final AppButton next = tester.widget<AppButton>(
          find.byKey(const Key('onboardNextButton')),
        );
        expect(back.variant, AppButtonVariant.secondary);
        expect(next.variant, AppButtonVariant.primary);
        if (step == '4 / 4') break;
      }

      await tester.tap(find.byKey(const Key('onboardBackButton')));
      await tester.pumpAndSettle();
      expect(_stepLabel(tester), '3 / 4');
    });
  });

  testWidgets('생년월일은 달력 창 없이 세 드롭다운으로 고른다', (tester) async {
    await _open(tester);

    // 1986-03-10 → 오늘(테스트 실행일) 기준 만 나이로 읽힌다.
    await _pickBirth(tester, year: 1986, month: 3, day: 10);
    await tester.tap(find.text('남성'));
    await tester.pump();
    await tester.enterText(_field('onboardHeightField'), '175');
    await tester.enterText(_field('onboardWeightField'), '70');
    await tester.pumpAndSettle();

    final int age = ageFromBirthDate('1986-03-10', today: todayKst())!;
    expect(find.text('만 $age세'), findsOneWidget);

    await _tapNext(tester);
    await _tapNext(tester);

    final int kcal = estimatedEnergyRequirement(
      ageYears: age,
      gender: 'male',
      heightCm: 175,
      weightKg: 70,
    )!;
    expect(_text(tester, 'onboardKcalField'), '$kcal');
    expect(_text(tester, 'onboardCarbsField'), '${(kcal * 0.55 / 4).round()}');
    expect(find.textContaining('나이·성별·키·체중으로 계산한'), findsOneWidget);
    expect(find.textContaining('기본 권장값이에요'), findsNothing);
  });

  testWidgets('있을 수 없는 날은 남지 않는다 — 1월 31일에서 2월로 바꾸면 줄어든다', (tester) async {
    await _open(tester);
    await _pickBirth(tester, year: 1987, month: 1, day: 31);
    expect(_birthValue(tester, 'onboardBirthDay'), 31);

    await _selectBirthPart(tester, 'onboardBirthMonth', 2);
    // 1987년 2월은 28일까지다.
    expect(_birthValue(tester, 'onboardBirthDay'), 28);
  });

  testWidgets('고친 칸은 지키고, 손대지 않은 칸만 칼로리를 따라간다', (tester) async {
    await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    // 단백질만 직접 고쳐 둔다.
    await tester.enterText(_field('onboardProteinField'), '120');
    await tester.pump();

    // 칼로리를 바꾸면 손대지 않은 탄수화물·지방·당류는 따라오고…
    await tester.enterText(_field('onboardKcalField'), '2400');
    await tester.pumpAndSettle();
    expect(_text(tester, 'onboardCarbsField'), '330'); // 2400×0.55/4
    expect(_text(tester, 'onboardFatField'), '67'); // 2400×0.25/9
    expect(_text(tester, 'onboardSugarField'), '60'); // 2400×0.10/4
    // …고친 칸은 그대로다.
    expect(_text(tester, 'onboardProteinField'), '120');
  });

  testWidgets('되돌리기는 고친 뒤에만 나오고, 누르면 권장값으로 돌아간다', (tester) async {
    await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    final RecommendedGoals goals = _basicsGoals();
    expect(_text(tester, 'onboardKcalField'), '${goals.dailyCalories}');
    expect(find.byKey(const Key('onboardResetDietGoals')), findsNothing);

    await tester.enterText(_field('onboardKcalField'), '3000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboardResetDietGoals')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardResetDietGoals')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'onboardKcalField'), '${goals.dailyCalories}');
    expect(_text(tester, 'onboardCarbsField'), '${goals.dailyCarbsG}');
    expect(find.byKey(const Key('onboardResetDietGoals')), findsNothing);
  });

  testWidgets('운동 목표는 WHO 권고로 차 있고 따로 되돌릴 수 있다', (tester) async {
    await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    expect(_text(tester, 'onboardBurnField'), '300');
    expect(_text(tester, 'onboardCardioField'), '150');
    expect(_text(tester, 'onboardStrengthField'), '21');
    expect(_text(tester, 'onboardFlexibilityField'), '60');
    expect(find.byKey(const Key('onboardResetExerciseGoals')), findsNothing);

    await tester.enterText(_field('onboardCardioField'), '90');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboardResetExerciseGoals')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardResetExerciseGoals')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'onboardCardioField'), '150');
  });

  testWidgets('2단계에서 고른 건강 목표가 식단·운동 권장값에 반영된다', (tester) async {
    await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);

    // 건강 목표는 두 개까지다(#1814).
    await tester.tap(find.text('체중 감량'));
    await tester.tap(find.text('식습관 개선'));
    await tester.pumpAndSettle();
    await _tapNext(tester);

    // 감량은 칼로리를 줄이고, 식습관 개선은 당류를 5% 로 낮춘다.
    final RecommendedGoals base = _basicsGoals();
    final RecommendedGoals focused = _basicsGoals(
      focus: <String>{'체중 감량', '식습관 개선'},
    );
    expect(focused.dailyCalories, lessThan(base.dailyCalories));
    expect(_text(tester, 'onboardKcalField'), '${focused.dailyCalories}');
    expect(_text(tester, 'onboardCarbsField'), '${focused.dailyCarbsG}');
    expect(_text(tester, 'onboardProteinField'), '${focused.dailyProteinG}');
    expect(_text(tester, 'onboardFatField'), '${focused.dailyFatG}');
    expect(_text(tester, 'onboardSugarField'), '${focused.dailySugarG}');
    expect(find.textContaining('고른 건강 목표를 반영한 값이에요'), findsOneWidget);
    expect(find.textContaining('목표 반영 기준'), findsOneWidget);

    await _tapNext(tester);
    expect(_text(tester, 'onboardBurnField'), '400');
    expect(_text(tester, 'onboardCardioField'), '200');
    expect(_text(tester, 'onboardStrengthField'), '21');
    expect(_text(tester, 'onboardFlexibilityField'), '60');
    expect(find.textContaining('고른 건강 목표를 반영한 값이에요'), findsOneWidget);
  });

  testWidgets('목표를 바꾸면 손대지 않은 칸만 따라가고, 건너뛰면 기준값으로 돌아간다', (tester) async {
    await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);
    await tester.tap(find.text('운동 습관'));
    await tester.pumpAndSettle();
    await _tapNext(tester);
    await _tapNext(tester);

    expect(_text(tester, 'onboardCardioField'), '90');
    // 근력은 직접 고쳐 둔다.
    await tester.enterText(_field('onboardStrengthField'), '10');
    await tester.pumpAndSettle();

    // 2단계로 돌아가 목표를 비우고 건너뛴다.
    await tester.tap(find.byKey(const Key('onboardBackButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardBackButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardSkipStep')));
    await tester.pumpAndSettle();
    await _tapNext(tester);

    expect(_text(tester, 'onboardCardioField'), '150');
    expect(_text(tester, 'onboardStrengthField'), '10');
    expect(find.textContaining('고른 건강 목표를 반영한 값이에요'), findsNothing);
  });

  testWidgets('건강 목표는 여덟 목표를 묻고, 건너뛰면 고른 것이 비워진다', (tester) async {
    final _RecordingRepository repo = await _open(tester);
    await _fillBasics(tester);
    await _tapNext(tester);

    // 옛 질환 선택지 대신 PT 회원의 목표를 고른다(#1814).
    for (final String option in kHealthFocusOptions) {
      expect(find.text(option), findsOneWidget, reason: option);
    }
    for (final String legacy in <String>['고혈압', '당뇨', '고지혈증', '비만']) {
      expect(find.text(legacy), findsNothing, reason: legacy);
    }
    // 안 채워도 되는 단계라고 제목 옆에 적혀 있다.
    expect(find.text('(선택)'), findsOneWidget);

    await tester.tap(find.text('혈압 관리'));
    await tester.pumpAndSettle();
    // 자유 입력 `운동 목표` 칸은 없다 — 목표는 칩만 고른다(#1829).
    expect(find.byKey(const Key('onboardGoalTextField')), findsNothing);

    // 건너뛰면 그냥 넘어가는 것이 아니라 이 단계에서 적은 것을 비운다.
    await tester.tap(find.byKey(const Key('onboardSkipStep')));
    await tester.pumpAndSettle();
    await _tapNext(tester);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(repo.submitted!['conditions'], isNull);
    expect(repo.submitted!['goals'], isNull);
  });

  testWidgets('완료는 기본 정보와 열 칸을 모두 보낸다', (tester) async {
    final _RecordingRepository repo = await _open(tester);
    await _fillBasics(tester);

    await _tapNext(tester);
    await tester.tap(find.text('근력 향상'));
    await tester.tap(find.text('혈압 관리'));
    await tester.pumpAndSettle();
    // 두 개를 골랐으니 세 번째는 잠긴다(#1814).
    expect(
      tester
          .widget<AppChoiceChip>(find.widgetWithText(AppChoiceChip, '재활'))
          .onSelected,
      isNull,
    );

    await _tapNext(tester);
    await _tapNext(tester);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    final Map<String, Object?> sent = repo.submitted!;
    expect(sent['birth_date'], '1996-05-20');
    expect(sent['gender'], 'female');
    expect(sent['height_cm'], 160);
    expect(sent['weight_kg'], 55);
    expect(sent['conditions'], '근력 향상, 혈압 관리');
    // 목표 열 칸이 하나도 빠지지 않는다 — 빠진 칸은 목표 없는 프로필이 된다.
    for (final String key in <String>[
      'daily_calories',
      'daily_sodium_mg',
      'daily_sugar_g',
      'daily_carbs_g',
      'daily_protein_g',
      'daily_fat_g',
      'daily_burn_kcal',
      'weekly_cardio_minutes',
      'weekly_strength_sets',
      'weekly_flexibility_minutes',
    ]) {
      expect(sent[key], isNotNull, reason: key);
    }
    expect(sent['weekly_cardio_minutes'], 150);
  });
}
