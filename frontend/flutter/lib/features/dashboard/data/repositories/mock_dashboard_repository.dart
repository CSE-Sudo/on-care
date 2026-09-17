import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';

/// 데모 홈 요약. 영양 수치는 **직접 들고 있지 않고** 식단 저장소에서 가져온다.
///
/// 예전에는 세 지표·매크로·끼니 수를 여기에 따로 적어 뒀는데, 식단 탭이 보는
/// 값과 어긋나 홈은 나트륨 2,329mg·4끼, 식단은 3,428mg·3끼를 보여줬다. 식단이
/// 기준이므로 홈이 그쪽을 읽게 한다 — 데모 중 식단을 추가·수정·삭제해도
/// (`MockDietRepository` 는 세션 동안 상태를 유지한다) 홈이 따라온다.
///
/// 운동·일정·주간 점수는 아직 식단과 무관한 데모 값이라 그대로 둔다.
class MockDashboardRepository implements DashboardRepository {
  const MockDashboardRepository(this._diet, {this.fetchProfile});

  final DietRepository _diet;
  final Future<UserProfile> Function()? fetchProfile;

  @override
  Future<DashboardSummary> fetchSummary() async {
    final DietDay today = await _diet.fetchToday();
    final UserProfile? profile = await fetchProfile?.call();
    final int calorieGoal =
        profile?.effectiveDailyCalories ?? UserProfile.defaultDailyCalories;
    final int sodiumGoal =
        profile?.effectiveDailySodiumMg ?? UserProfile.defaultDailySodiumMg;
    final int sugarGoal =
        profile?.effectiveDailySugarG ?? UserProfile.defaultDailySugarG;
    final DateTime now = nowKst();
    final DateTime monday = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final List<NutritionDay> nutritionWeek = <NutritionDay>[];
    for (var index = 0; index < 7; index++) {
      final DateTime date = monday.add(Duration(days: index));
      final bool isToday =
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
      final DietDay day = isToday ? today : await _diet.fetchByDate(date);
      nutritionWeek.add(
        NutritionDay(
          label: _weekdayLabels[index],
          calories: day.totalCalories,
          sodiumMg: day.totalSodiumMg,
          sugarG: day.totalSugarG,
          // 실서버가 싣는 것을 데모도 똑같이 싣는다(#1879). 합산 규칙은
          // 식단 탭과 공유한다([DietDayTotals]) — 따로 더하면 같은 날이 두
          // 화면에서 다른 값으로 나온다.
          carbsG: day.effectiveCarbsG,
          proteinG: day.effectiveProteinG,
          fatG: day.effectiveFatG,
        ),
      );
    }

    return DashboardSummary(
      indicators: <HealthIndicator>[
        HealthIndicator(
          label: '칼로리',
          current: today.totalCalories,
          max: calorieGoal,
          unit: 'kcal',
          overBudget: today.totalCalories > calorieGoal,
        ),
        HealthIndicator(
          label: '나트륨',
          current: today.totalSodiumMg,
          max: sodiumGoal,
          unit: 'mg',
          overBudget: today.totalSodiumMg > sodiumGoal,
        ),
        HealthIndicator(
          label: '당류',
          current: today.totalSugarG,
          max: sugarGoal,
          unit: 'g',
          overBudget: today.totalSugarG > sugarGoal,
        ),
      ],
      macros: today.macros,
      dietEntries: today.entries.length,
      exerciseMinutes: 45,
      exerciseCalories: 520,
      exerciseCount: 4,
      nutritionWeek: nutritionWeek,
      todaySchedule: const <ScheduleItem>[
        ScheduleItem(time: '10:00', title: '병원 정기검진', emoji: '🏥'),
        ScheduleItem(time: '18:00', title: '헬스장 운동', emoji: '💪'),
      ],
      weekScore: 85,
      weekScoreDelta: 12,
      // 홈 '오늘의 AI 통합 조언' 자리. 문구가 아니라 키만 싣는다 — 문장은
      // ARB 가 ko·en 양쪽으로 갖고 있고, 화면이 로케일에 맞게 고른다(#435).
      aiAdviceKey: kDailyCombinedAdviceKey,
      sodiumWarning: null,
      // `exerciseFeedback` 은 서버가 만든 문장이 들어오는 자리라 데모에서는
      // 채우지 않는다(기본값 null). 한국어를 넣어 두면 조언 키가 못 풀렸을 때
      // 영어 로케일로 한국어가 새고, 그때 ARB 기본 문구로 떨어져야 한다(#435).
    );
  }
}

const List<String> _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];
