import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';

/// 테스트용 홈 요약 저장소 — 식단 저장소 대역에서 영양 수치를 가져온다.
///
/// 예전에는 데모 모드(`useMockApi`)의 실제 구현(`MockDashboardRepository`)이었다.
/// 지금 데모 홈은 실서버와 같은 `DioDashboardRepository` → `LocalApiInterceptor`
/// 경로라(#2645) 이 구현은 **테스트 대역으로만** 남는다 — 위젯 테스트가 drift 를
/// 세우지 않고 홈을 그릴 수 있게 해 준다.
///
/// 영양 수치는 `FakeDietRepository` 등 넘겨받은 식단 저장소에서 읽으므로, 테스트
/// 중 식단을 추가·수정·삭제하면 홈 요약도 따라온다. 운동·조언은 고정값이다.
class FakeDashboardRepository implements DashboardRepository {
  const FakeDashboardRepository(this._diet, {this.fetchProfile});

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
