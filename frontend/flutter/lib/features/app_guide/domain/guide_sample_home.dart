import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 사용 가이드가 짚는 **예시 자료**. (#1857)
///
/// 가이드는 진짜 홈 화면 위젯을 그대로 그리고, 그 안의 값만 이 자료로 채운다.
/// 가입 직후의 홈은 기록이 하나도 없어 빈 카드를 짚게 되기 때문이다 — "여기에
/// 오늘 먹은 것이 모여요" 라고 말하려면 모여 있는 모습이 보여야 한다.
///
/// 하루를 절반쯤 지낸, 가장 흔한 모습으로 고른다.
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
  exerciseCalories: 420,
  exerciseCount: 3,
  nutritionWeek: <NutritionDay>[
    NutritionDay(label: '월', calories: 1820, sodiumMg: 2100, sugarG: 41),
    NutritionDay(label: '화', calories: 1650, sodiumMg: 1800, sugarG: 28),
    NutritionDay(label: '수', calories: 1980, sodiumMg: 2450, sugarG: 52),
    NutritionDay(label: '목', calories: 1720, sodiumMg: 1900, sugarG: 33),
    NutritionDay(label: '금', calories: 1560, sodiumMg: 1640, sugarG: 26),
    NutritionDay(label: '토', calories: 2050, sodiumMg: 2380, sugarG: 58),
    NutritionDay(label: '일', calories: 1480, sodiumMg: 1720, sugarG: 32),
  ],
  todaySchedule: <ScheduleItem>[],
  weekScore: 82,
  weekScoreDelta: 4,
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
  aiCoachMessage: '',
  dailyCalories: <double>[140, 0, 110, 0, 170, 0, 0],
  cardioMinutes: <double>[30, 0, 0, 0, 30, 0, 0],
  strengthMinutes: <double>[0, 0, 25, 0, 10, 0, 0],
  stretchingMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  strengthSets: <double>[0, 0, 12, 0, 9, 0, 0],
);
