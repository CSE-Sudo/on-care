import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

/// 사용 가이드가 짚는 **예시 자료**. (#1857)
///
/// 가이드는 진짜 화면 위젯을 그대로 그리고, 그 안의 값만 이 자료로 채운다.
/// 가입 직후의 앱은 기록이 하나도 없어 빈 카드를 짚게 되기 때문이다 — "여기에
/// 오늘 먹은 것이 모여요" 라고 말하려면 모여 있는 모습이 보여야 한다.
///
/// 덮는 것은 **화면이 직접 읽는 provider 뿐이다.** 그 아래 단계(저장소 등)를
/// 덮으면, 그것을 읽는 provider 가 가이드 화면 밖에 있어 Riverpod 이 막는다.
List<Override> guideSampleOverrides() {
  // 데모 시드를 그대로 쓰는 자리 — 헬스장·트레이너·MY 는 이미 "연결된 회원"
  // 한 명분이 통째로 준비돼 있다. 한 벌만 만들어 가이드가 끝날 때까지 쓴다.
  final MockGymRepository gym = MockGymRepository();
  final MockMemberCoachRepository coach = MockMemberCoachRepository();
  const MockMyHealthRepository myHealth = MockMyHealthRepository();

  return <Override>[
    // 홈
    dashboardSummaryProvider.overrideWith((ref) async => kGuideSampleSummary),
    exerciseWeekViewProvider.overrideWithValue(
      const AsyncData<ExerciseWeek>(kGuideSampleWeek),
    ),
    dietRecommendationsProvider.overrideWith(
      (ref) async => MealRecommendations.fallback,
    ),
    // 알림을 받아 두는 편이 실제 화면에 가깝다.
    notificationUnreadProvider.overrideWith((ref) => Stream<int>.value(1)),
    // 식단 — 하루 뷰와 날짜별 캐시가 서로 다른 provider 라 둘 다 채운다.
    dietTodayProvider.overrideWith((ref) async => kGuideSampleDietDay),
    dietByDateFamily.overrideWith((ref, date) async => kGuideSampleDietDay),
    dietAdviceProvider.overrideWith((ref, key) async => kGuideSampleDietAdvice),
    // 운동
    exerciseAdviceProvider.overrideWith(
      (ref, period) async => kGuideSampleExerciseAdvice,
    ),
    // 헬스장·트레이너 — 연결된 모습이라야 무엇이 오는지 보여 줄 수 있다.
    myGymProvider.overrideWith((ref) => gym.fetchMyGym()),
    myTrainerProvider.overrideWith((ref) => gym.fetchMyTrainer()),
    myReservationsProvider.overrideWith((ref) => gym.fetchMyReservations()),
    memberCoachProvider.overrideWith((ref) => coach.fetchCoach()),
    coachRoutinesProvider.overrideWith((ref) => coach.fetchRoutines()),
    coachSessionsProvider.overrideWith((ref) => coach.fetchSessions()),
    coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
    // MY
    myHealthStateProvider.overrideWith((ref) => myHealth.fetchState()),
  ];
}

/// 예시 식단 조언 — 서버가 주는 것과 같은 **문장 키**로 싣는다(#2644).
///
/// 조언 카드는 키가 있으면 지금 언어의 ARB 문장을 그리고, 없으면 받은 문장을
/// 그대로 쓴다. 예전에는 한국어 문장만 넣어 영어 가이드에서도 한국어 조언이
/// 나왔다. `text` 는 키를 풀지 못할 때의 한국어 문장이다(ARB 와 같은 문장).
const DietAdvice kGuideSampleDietAdvice = DietAdvice(
  message: '오늘 **1480kcal**, 균형이 좋아요. 오늘 식단을 잘 마무리했어요!',
  analysis: DietAdviceLine(
    text: '오늘 **1480kcal**, 균형이 좋아요.',
    key: 'today_balanced',
    params: <String, Object>{'kcal': 1480},
  ),
  action: DietAdviceLine(text: '오늘 식단을 잘 마무리했어요!', key: 'today_done'),
);

/// 예시 운동 조언 — 예시 한 주(3일 95분, 유산소 60분·근력 35분)를 짚는 키.
const ExerciseAdvice kGuideSampleExerciseAdvice = ExerciseAdvice(
  message: '이번 주 3일 95분이 유산소에 몰렸어요. 근력도 섞어 볼까요?',
  key: 'record_week_skew',
  params: <String, Object>{
    'days': 3,
    'minutes': 95,
    'top': 'cardio',
    'missing': 'strength',
  },
);

/// 예시 홈 요약 — 하루를 절반쯤 지낸, 가장 흔한 모습으로 고른다.
const DashboardSummary kGuideSampleSummary = DashboardSummary(
  indicators: <HealthIndicator>[
    HealthIndicator(label: '칼로리', current: 1480, max: 2000, unit: 'kcal'),
    HealthIndicator(label: '나트륨', current: 1720, max: 2000, unit: 'mg'),
    HealthIndicator(label: '당류', current: 32, max: 50, unit: 'g'),
  ],
  macros: DietMacros(
    carbsPct: 52,
    proteinPct: 25,
    fatPct: 23,
    carbsG: 192,
    proteinG: 92,
    fatG: 38,
  ),
  dietEntries: 3,
  exerciseMinutes: 95,
  nutritionWeek: <NutritionDay>[
    NutritionDay(label: '월', calories: 1820),
    NutritionDay(label: '화', calories: 1650),
    NutritionDay(label: '수', calories: 1980),
    NutritionDay(label: '목', calories: 1720),
    NutritionDay(label: '금', calories: 1560),
    NutritionDay(label: '토', calories: 2050),
    NutritionDay(label: '일', calories: 1480),
  ],
  // 오늘 따로 짚을 식단 피드백은 없다 — 홈은 기본 AI 조언 문구를 그린다.
  sodiumWarning: null,
);

/// 예시 한 주의 운동 — 주 3회, 95분, 420kcal.
const ExerciseWeek kGuideSampleWeek = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[30, 0, 25, 0, 40, 0, 0],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 95,
  totalCalories: 420,
  streakDays: 3,
  // 화면이 그리는 조언은 [kGuideSampleExerciseAdvice] 다. 이 값은 같은 뜻의
  // 한국어 문장으로 맞춰 둔다.
  aiCoachMessage: '이번 주 3일 95분이 유산소에 몰렸어요. 근력도 섞어 볼까요?',
  dailyCalories: <double>[140, 0, 110, 0, 170, 0, 0],
  cardioMinutes: <double>[30, 0, 0, 0, 30, 0, 0],
  strengthMinutes: <double>[0, 0, 25, 0, 10, 0, 0],
  stretchingMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  strengthSets: <double>[0, 0, 12, 0, 9, 0, 0],
);

/// 예시 하루 식단 — 홈 요약과 같은 하루다(칼로리 1,480 · 나트륨 1,720 · 당류 32).
/// 두 화면이 다른 하루를 말하면 가이드 도중 숫자가 바뀌는 것처럼 보인다.
const DietDay kGuideSampleDietDay = DietDay(
  entries: <DietEntry>[
    DietEntry(
      id: 'guide-breakfast',
      mealType: MealType.breakfast,
      timeLabel: '08:20',
      foods: <FoodItem>[
        FoodItem(
          name: '스크램블에그',
          calories: 180,
          sodiumMg: 220,
          sugarG: 1,
          carbsG: 2,
          proteinG: 13,
          fatG: 13,
        ),
        FoodItem(
          name: '통밀 토스트',
          calories: 140,
          sodiumMg: 180,
          sugarG: 3,
          carbsG: 26,
          proteinG: 5,
          fatG: 2,
        ),
      ],
      totalCalories: 320,
      sodiumMg: 400,
      sugarG: 4,
      carbsG: 28,
      proteinG: 18,
      fatG: 15,
      aiComment: '단백질로 하루를 연 좋은 시작이에요.',
    ),
    DietEntry(
      id: 'guide-lunch',
      mealType: MealType.lunch,
      timeLabel: '12:40',
      foods: <FoodItem>[
        FoodItem(
          name: '닭가슴살 샐러드',
          calories: 380,
          sodiumMg: 520,
          sugarG: 8,
          carbsG: 22,
          proteinG: 38,
          fatG: 14,
        ),
        FoodItem(
          name: '현미밥',
          calories: 230,
          sodiumMg: 10,
          sugarG: 1,
          carbsG: 49,
          proteinG: 5,
          fatG: 2,
        ),
      ],
      totalCalories: 610,
      sodiumMg: 530,
      sugarG: 9,
      carbsG: 71,
      proteinG: 43,
      fatG: 16,
      aiComment: '단백질이 넉넉하고 나트륨도 낮게 잡혔어요.',
    ),
    DietEntry(
      id: 'guide-dinner',
      mealType: MealType.dinner,
      timeLabel: '19:10',
      foods: <FoodItem>[
        FoodItem(
          name: '연어구이',
          calories: 330,
          sodiumMg: 480,
          sugarG: 2,
          carbsG: 3,
          proteinG: 31,
          fatG: 21,
        ),
        FoodItem(
          name: '구운 채소',
          calories: 220,
          sodiumMg: 310,
          sugarG: 17,
          carbsG: 34,
          proteinG: 6,
          fatG: 7,
        ),
      ],
      totalCalories: 550,
      sodiumMg: 790,
      sugarG: 19,
      carbsG: 37,
      proteinG: 37,
      fatG: 28,
      aiComment: '채소를 함께 담아 식이섬유가 충분해요.',
    ),
  ],
  totalCalories: 1480,
  macros: DietMacros(
    carbsPct: 52,
    proteinPct: 25,
    fatPct: 23,
    carbsG: 136,
    proteinG: 98,
    fatG: 59,
  ),
  totalSodiumMg: 1720,
  totalSugarG: 32,
  // 화면이 그리는 조언은 [kGuideSampleDietAdvice] 다(가이드는 오늘을 보여 준다).
  aiCoachMessage: '오늘 1480kcal, 균형이 좋아요. 오늘 식단을 잘 마무리했어요!',
);
