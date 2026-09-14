import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩 3·4단계가 권장값을 미리 채우고, 회원이 고친 값을 지키고, 끝에서 그
/// 열 칸을 그대로 저장하는지.
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
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repo),
      ],
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

void main() {
  testWidgets('기본 정보를 비워 둬도 목표 칸은 기본 권장값으로 차 있다', (tester) async {
    await _open(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    // 2,000kcal 기준 — 탄 55% / 단 20% / 지 25%.
    expect(_text(tester, 'onboardKcalField'), '2000');
    expect(_text(tester, 'onboardCarbsField'), '275');
    expect(_text(tester, 'onboardProteinField'), '100');
    expect(_text(tester, 'onboardFatField'), '56');
    expect(_text(tester, 'onboardSodiumField'), '2000');
    expect(_text(tester, 'onboardSugarField'), '50');
    expect(find.textContaining('기본 권장값이에요'), findsOneWidget);
  });

  testWidgets('키·체중·성별을 적으면 목표 칸이 그 몸에 맞춰 다시 찬다', (tester) async {
    await _open(tester);

    await tester.tap(find.text('남성'));
    await tester.pump();
    await tester.enterText(_field('onboardHeightField'), '175');
    await tester.pump();
    await tester.enterText(_field('onboardWeightField'), '70');
    await tester.pumpAndSettle();

    // 생년월일이 없으면 추정식이 서지 않는다 — 아직 기본값이다.
    expect(find.text('BMI 22.9 · 정상'), findsOneWidget);

    await _tapNext(tester);
    await _tapNext(tester);
    expect(_text(tester, 'onboardKcalField'), '2000');
    expect(find.textContaining('기본 권장값이에요'), findsOneWidget);
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
    await _tapNext(tester);
    await _tapNext(tester);

    expect(find.byKey(const Key('onboardResetDietGoals')), findsNothing);

    await tester.enterText(_field('onboardKcalField'), '3000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboardResetDietGoals')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardResetDietGoals')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'onboardKcalField'), '2000');
    expect(_text(tester, 'onboardCarbsField'), '275');
    expect(find.byKey(const Key('onboardResetDietGoals')), findsNothing);
  });

  testWidgets('운동 목표는 WHO 권고로 차 있고 따로 되돌릴 수 있다', (tester) async {
    await _open(tester);
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

  testWidgets('건강 상태는 고혈압·당뇨만 묻고, 건너뛰면 고른 것이 비워진다', (tester) async {
    final _RecordingRepository repo = await _open(tester);
    await _tapNext(tester);

    expect(find.text('고혈압'), findsOneWidget);
    expect(find.text('당뇨'), findsOneWidget);
    expect(find.text('고지혈증'), findsNothing);
    expect(find.text('비만'), findsNothing);
    // 안 채워도 되는 단계라고 제목 옆에 적혀 있다.
    expect(find.text('(선택)'), findsOneWidget);

    await tester.tap(find.text('고혈압'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('onboardGoalTextField'), '혈압 관리');
    await tester.pumpAndSettle();

    // 건너뛰면 그냥 넘어가는 것이 아니라 이 단계에서 적은 것을 비운다.
    await tester.tap(find.byKey(const Key('onboardSkipStep')));
    await tester.pumpAndSettle();
    await _tapNext(tester);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(repo.submitted!['conditions'], isNull);
    expect(repo.submitted!['goals'], isNull);
  });

  testWidgets('완료는 열 칸을 모두 보낸다', (tester) async {
    final _RecordingRepository repo = await _open(tester);

    await tester.tap(find.text('여성'));
    await tester.pump();
    await tester.enterText(_field('onboardHeightField'), '160');
    await tester.enterText(_field('onboardWeightField'), '55');
    await tester.pumpAndSettle();

    await _tapNext(tester);
    await tester.tap(find.text('고혈압'));
    await tester.pumpAndSettle();

    await _tapNext(tester);
    await _tapNext(tester);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    final Map<String, Object?> sent = repo.submitted!;
    expect(sent['gender'], 'female');
    expect(sent['height_cm'], 160);
    expect(sent['weight_kg'], 55);
    expect(sent['conditions'], '고혈압');
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
