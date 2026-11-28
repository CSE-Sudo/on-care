import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

/// 건너뛴 회원이 MY 에서 **다시 연** 첫 설정(#3339).
///
/// 예전에는 회원의 지금 값을 읽지 않고 권장값으로만 칸을 채워, 끝내면 MY 에서
/// 정한 목표가 권장값으로 바뀌고 트레이너가 적은 주의사항이 지워졌다. 이제는
/// 있던 값으로 시작하고 바꾼 칸만 보낸다.

const List<String> _goalKeys = <String>[
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
];

/// 서버로 무엇이 나갔는지 붙잡아 두는 저장소. 프로필 읽기는 [latest] 를 주면
/// 그것을 — 편집을 연 뒤 트레이너가 고친 서버 값 — 돌려준다.
class _RecordingRepository extends MockAccountRepository {
  _RecordingRepository(UserProfile profile) : super(profile: profile);

  /// 첫 설정 저장으로 나간 값. 보내지 않은 칸은 null 이다.
  Map<String, Object?>? submitted;

  /// 건강 목표 저장으로 나간 목표 해제. 부르지 않았으면 null.
  Map<String, GoalUpdate?>? clearedGoals;

  /// 다음 프로필 읽기가 돌려줄 서버의 지금 값.
  UserProfile? latest;

  /// 참이면 프로필 읽기가 실패한다.
  bool failFetch = false;

  int fetchCount = 0;

  @override
  Future<UserProfile> fetchProfile() async {
    fetchCount++;
    if (failFetch) throw StateError('offline');
    return latest ?? await super.fetchProfile();
  }

  @override
  Future<UserProfile> submitOnboarding({
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
    String? conditions,
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
  }) {
    submitted = <String, Object?>{
      'birth_date': birthDate,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'conditions': conditions,
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
    return super.submitOnboarding(
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      conditions: conditions,
      dailyCalories: dailyCalories,
      dailySodiumMg: dailySodiumMg,
      dailySugarG: dailySugarG,
      dailyCarbsG: dailyCarbsG,
      dailyProteinG: dailyProteinG,
      dailyFatG: dailyFatG,
      dailyBurnKcal: dailyBurnKcal,
      weeklyCardioMinutes: weeklyCardioMinutes,
      weeklyStrengthSets: weeklyStrengthSets,
      weeklyFlexibilityMinutes: weeklyFlexibilityMinutes,
    );
  }

  @override
  Future<UserProfile> updateHealthGoals({
    String? conditions,
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
  }) {
    clearedGoals = <String, GoalUpdate?>{
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
    return super.updateHealthGoals(
      conditions: conditions,
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
}

/// 첫 설정을 건너뛴 뒤 MY 에서 목표를 정했고, 트레이너가 주의사항을 적어 준 회원.
UserProfile _member({
  String conditions = '재활, 왼쪽 무릎 수술 이력',
  int? dailyCalories = 1800,
  int? dailySodiumMg = 1900,
  int? dailySugarG = 40,
  int? dailyCarbsG = 220,
  int? dailyProteinG = 110,
  int? dailyFatG = 50,
  int? dailyBurnKcal = 350,
  int? weeklyCardioMinutes = 90,
  int? weeklyStrengthSets = 24,
  int? weeklyFlexibilityMinutes = 45,
}) => UserProfile(
  id: 'user-resume',
  onboardingSkipped: true,
  name: '이서연',
  email: 'seoyeon@oncare.com',
  birthDate: '1996-05-20',
  gender: 'female',
  heightCm: 160,
  weightKg: 55.5,
  conditions: conditions,
  dailyCalories: dailyCalories,
  dailySodiumMg: dailySodiumMg,
  dailySugarG: dailySugarG,
  dailyCarbsG: dailyCarbsG,
  dailyProteinG: dailyProteinG,
  dailyFatG: dailyFatG,
  dailyBurnKcal: dailyBurnKcal,
  weeklyCardioMinutes: weeklyCardioMinutes,
  weeklyStrengthSets: weeklyStrengthSets,
  weeklyFlexibilityMinutes: weeklyFlexibilityMinutes,
);

/// 목표를 하나도 정하지 않은 회원 — 기본 정보만 있다.
UserProfile _memberWithoutGoals() => _member(
  conditions: '',
  dailyCalories: null,
  dailySodiumMg: null,
  dailySugarG: null,
  dailyCarbsG: null,
  dailyProteinG: null,
  dailyFatG: null,
  dailyBurnKcal: null,
  weeklyCardioMinutes: null,
  weeklyStrengthSets: null,
  weeklyFlexibilityMinutes: null,
);

/// MY 자리에서 `첫 설정 이어서 하기` 로 들어온 것처럼 띄운다.
///
/// [warm] 이면 앱처럼 프로필을 이미 들고 있는 상태로 연다. 끝나고 **어디로
/// 가는지** 보려고 라우터를 세운다.
Future<_RecordingRepository> _open(
  WidgetTester tester,
  UserProfile profile, {
  bool warm = true,
  bool failFetch = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final _RecordingRepository repo = _RecordingRepository(profile);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[accountRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  if (warm) await container.read(profileProvider.future);
  repo
    ..fetchCount = 0
    ..failFetch = failFetch;
  final GoRouter router = GoRouter(
    initialLocation: '/my',
    routes: <RouteBase>[
      GoRoute(
        path: '/my',
        builder: (_, _) => const Scaffold(body: Text('MY 건강 목표')),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, GoRouterState state) =>
            OnboardingPage(resumed: state.uri.queryParameters['from'] == 'app'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push(AppRoutes.onboardingResume);
  await tester.pumpAndSettle();
  return repo;
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
}

/// 1단계에서 마지막 단계까지 넘긴 뒤 `완료` 를 누른다.
Future<void> _finishFromFirstStep(WidgetTester tester) async {
  await _tapNext(tester);
  await _tapNext(tester);
  await _tapNext(tester);
  await tester.tap(find.text('완료'));
  await tester.pumpAndSettle();
}

bool _chipSelected(WidgetTester tester, String label) => tester
    .widget<AppChoiceChip>(find.widgetWithText(AppChoiceChip, label))
    .selected;

void main() {
  group('초기값', () {
    testWidgets('기본 정보는 회원의 지금 값으로 차 있다', (tester) async {
      await _open(tester, _member());

      expect(
        tester
            .widget<AppSelectField<int>>(
              find.byKey(const Key('onboardBirthYear')),
            )
            .value,
        1996,
      );
      expect(
        tester
            .widget<AppSelectField<int>>(
              find.byKey(const Key('onboardBirthMonth')),
            )
            .value,
        5,
      );
      expect(
        tester
            .widget<AppSelectField<int>>(
              find.byKey(const Key('onboardBirthDay')),
            )
            .value,
        20,
      );
      // 소수점이 없는 키는 `160.0` 이 아니라 `160` 으로 보인다.
      expect(_text(tester, 'onboardHeightField'), '160');
      expect(_text(tester, 'onboardWeightField'), '55.5');
    });

    testWidgets('고른 건강 목표와 적혀 있던 주의사항이 2단계에 보인다', (tester) async {
      await _open(tester, _member());
      await _tapNext(tester);

      expect(_chipSelected(tester, '재활'), isTrue);
      expect(_chipSelected(tester, '체중 감량'), isFalse);
      expect(_text(tester, 'onboardConditionsField'), '왼쪽 무릎 수술 이력');
    });

    testWidgets('정해 둔 목표는 권장값이 아니라 그 값으로 차 있다', (tester) async {
      await _open(tester, _member());
      await _tapNext(tester);
      await _tapNext(tester);

      expect(_text(tester, 'onboardKcalField'), '1800');
      expect(_text(tester, 'onboardSodiumField'), '1900');
      expect(_text(tester, 'onboardSugarField'), '40');
      expect(_text(tester, 'onboardCarbsField'), '220');
      expect(_text(tester, 'onboardProteinField'), '110');
      expect(_text(tester, 'onboardFatField'), '50');

      await _tapNext(tester);
      expect(_text(tester, 'onboardBurnField'), '350');
    });

    testWidgets('비어 있는 칸만 권장값으로 시작한다', (tester) async {
      // 칼로리만 정해 둔 회원 — 나머지 식단 칸은 그 칼로리를 따라 나뉜다.
      await _open(
        tester,
        _member(
          dailyCalories: 2400,
          dailySugarG: null,
          dailyCarbsG: null,
          dailyFatG: null,
          weeklyCardioMinutes: null,
        ),
      );
      await _tapNext(tester);
      await _tapNext(tester);

      expect(_text(tester, 'onboardKcalField'), '2400');
      expect(_text(tester, 'onboardCarbsField'), '330'); // 2400×0.55/4
      expect(_text(tester, 'onboardFatField'), '67'); // 2400×0.25/9
      expect(_text(tester, 'onboardSugarField'), '60'); // 2400×0.10/4
      // 정해 둔 단백질은 칼로리를 따라가지 않는다.
      expect(_text(tester, 'onboardProteinField'), '110');
    });

    testWidgets('1단계 값을 고쳐도 있던 목표는 다시 계산되지 않는다', (tester) async {
      await _open(tester, _member());
      await tester.enterText(_field('onboardWeightField'), '70');
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await _tapNext(tester);

      expect(_text(tester, 'onboardKcalField'), '1800');
      expect(_text(tester, 'onboardProteinField'), '110');
    });

    testWidgets('되돌리기를 누르면 있던 목표가 권장값이 되고 그 칸이 나간다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await _tapNext(tester);

      final RecommendedGoals goals = recommendedGoalsFor(
        ageYears: ageFromBirthDate('1996-05-20', today: todayKst()),
        gender: 'female',
        heightCm: 160,
        weightKg: 55.5,
        focus: const <String>{'재활'},
      );
      await tester.tap(find.byKey(const Key('onboardResetDietGoals')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'onboardKcalField'), '${goals.dailyCalories}');

      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['daily_calories'], goals.dailyCalories);
      // 되돌리지 않은 운동 목표는 나가지 않는다.
      expect(repo.submitted!['daily_burn_kcal'], isNull);
      expect(repo.submitted!['weekly_cardio_minutes'], isNull);
    });

    testWidgets('들고 있는 프로필이 없으면 서버에서 읽어 채운다', (tester) async {
      final _RecordingRepository repo = await _open(
        tester,
        _member(),
        warm: false,
      );

      expect(repo.fetchCount, greaterThan(0));
      expect(_text(tester, 'onboardHeightField'), '160');
      await _tapNext(tester);
      await _tapNext(tester);
      expect(_text(tester, 'onboardKcalField'), '1800');
    });

    testWidgets('프로필을 읽지 못하면 열지 않고 연 자리로 돌아간다', (tester) async {
      final _RecordingRepository repo = await _open(
        tester,
        _member(),
        warm: false,
        failFetch: true,
      );

      expect(find.text('MY 건강 목표'), findsOneWidget);
      expect(find.byKey(const Key('onboardNextButton')), findsNothing);
      expect(find.text('내 정보를 불러오지 못했어요'), findsOneWidget);
      expect(repo.submitted, isNull);
      // 떠 있는 토스트의 타이머를 흘려보낸다.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });
  });

  group('저장', () {
    testWidgets('손대지 않고 끝내면 어떤 칸도 보내지 않는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());

      await _finishFromFirstStep(tester);

      // 끝냈다는 표시를 남기려고 저장은 나간다.
      expect(repo.submitted, isNotNull);
      expect(repo.submitted!.values.every((Object? v) => v == null), isTrue);
      expect(repo.clearedGoals, isNull);
      // 연 자리로 돌아간다.
      expect(find.text('MY 건강 목표'), findsOneWidget);
    });

    testWidgets('고친 목표 칸만 보낸다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.enterText(_field('onboardSodiumField'), '1500');
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      final Map<String, Object?> sent = repo.submitted!;
      expect(sent['daily_sodium_mg'], 1500);
      for (final String key in _goalKeys) {
        if (key == 'daily_sodium_mg') continue;
        expect(sent[key], isNull, reason: key);
      }
      expect(sent['conditions'], isNull);
      expect(sent['birth_date'], isNull);
      expect(sent['gender'], isNull);
      expect(sent['height_cm'], isNull);
      expect(sent['weight_kg'], isNull);
    });

    testWidgets('고쳤다가 원래 값으로 되돌린 칸은 보내지 않는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.enterText(_field('onboardSodiumField'), '1500');
      await tester.enterText(_field('onboardSodiumField'), '1900');
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['daily_sodium_mg'], isNull);
    });

    testWidgets('고친 기본 정보만 보낸다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await tester.enterText(_field('onboardWeightField'), '58');
      await tester.pumpAndSettle();

      await _finishFromFirstStep(tester);

      final Map<String, Object?> sent = repo.submitted!;
      expect(sent['weight_kg'], 58);
      expect(sent['height_cm'], isNull);
      expect(sent['birth_date'], isNull);
      expect(sent['gender'], isNull);
      // 체중이 바뀌어도 있던 목표는 그대로라 나가지 않는다.
      for (final String key in _goalKeys) {
        expect(sent[key], isNull, reason: key);
      }
    });

    testWidgets('값이 없던 칸은 권장값으로 나간다', (tester) async {
      final _RecordingRepository repo = await _open(
        tester,
        _member(weeklyCardioMinutes: null, weeklyFlexibilityMinutes: null),
      );

      await _finishFromFirstStep(tester);

      final Map<String, Object?> sent = repo.submitted!;
      expect(sent['weekly_cardio_minutes'], isNotNull);
      expect(sent['weekly_flexibility_minutes'], isNotNull);
      expect(sent['weekly_strength_sets'], isNull);
      expect(sent['daily_calories'], isNull);
    });

    testWidgets('목표가 하나도 없는 회원은 열 칸을 모두 보낸다', (tester) async {
      final _RecordingRepository repo = await _open(
        tester,
        _memberWithoutGoals(),
      );

      await _finishFromFirstStep(tester);

      final Map<String, Object?> sent = repo.submitted!;
      for (final String key in _goalKeys) {
        expect(sent[key], isNotNull, reason: key);
      }
      // 고른 목표도 적은 글도 없으면 `conditions` 는 나가지 않는다.
      expect(sent['conditions'], isNull);
    });

    testWidgets('있던 목표를 비우면 목표 해제로 나간다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.enterText(_field('onboardSugarField'), '');
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['daily_sugar_g'], isNull);
      final Map<String, GoalUpdate?> cleared = repo.clearedGoals!;
      expect(cleared['daily_sugar_g'], isNotNull);
      expect(cleared['daily_sugar_g']!.value, isNull);
      for (final String key in _goalKeys) {
        if (key == 'daily_sugar_g') continue;
        expect(cleared[key], isNull, reason: key);
      }
    });
  });

  group('건강 목표·주의사항', () {
    testWidgets('목표 칩만 바꾸면 주의사항 글은 그대로 남는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await tester.tap(find.text('근력 향상'));
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['conditions'], '근력 향상, 재활, 왼쪽 무릎 수술 이력');
    });

    testWidgets('그 사이 트레이너가 고친 주의사항 위에 칩만 얹는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      // 화면을 연 뒤 트레이너가 주의사항을 고쳤다.
      repo.latest = _member(conditions: '재활, 왼쪽 무릎 수술 이력, 스쿼트 금지');
      await _tapNext(tester);
      await tester.tap(find.text('근력 향상'));
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['conditions'], '근력 향상, 재활, 왼쪽 무릎 수술 이력, 스쿼트 금지');
    });

    testWidgets('주의사항만 고치면 고른 목표는 서버의 지금 값을 따른다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      repo.latest = _member(conditions: '체력 강화, 왼쪽 무릎 수술 이력');
      await _tapNext(tester);
      await tester.enterText(_field('onboardConditionsField'), '오른쪽 어깨 통증');
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['conditions'], '체력 강화, 오른쪽 어깨 통증');
    });

    testWidgets('최신 값을 읽지 못하면 들고 있던 값 위에 얹는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      repo.failFetch = true;
      await _tapNext(tester);
      await tester.tap(find.text('근력 향상'));
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['conditions'], '근력 향상, 재활, 왼쪽 무릎 수술 이력');
    });

    testWidgets('단계를 건너뛰면 있던 값으로 되돌리고 보내지 않는다', (tester) async {
      final _RecordingRepository repo = await _open(tester, _member());
      await _tapNext(tester);
      await tester.tap(find.text('재활'));
      await tester.enterText(_field('onboardConditionsField'), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboardSkipStep')));
      await tester.pumpAndSettle();
      await _tapNext(tester);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      // 건너뛴 단계는 손대지 않은 단계다 — 트레이너가 적은 글이 지워지지 않는다.
      expect(repo.submitted!['conditions'], isNull);
    });

    testWidgets('건너뛰고 돌아오면 있던 목표와 글이 다시 보인다', (tester) async {
      await _open(tester, _member());
      await _tapNext(tester);
      await tester.tap(find.text('재활'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboardSkipStep')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboardBackButton')));
      await tester.pumpAndSettle();

      expect(_chipSelected(tester, '재활'), isTrue);
      expect(_text(tester, 'onboardConditionsField'), '왼쪽 무릎 수술 이력');
    });
  });
}
