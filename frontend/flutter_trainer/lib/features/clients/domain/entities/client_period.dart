import 'package:oncare_trainer/core/utils/clock.dart';

/// 트레이너가 고객 기록을 보는 기간 — 회원 앱 식단·운동 탭의 토글과 **같은
/// 뜻·같은 순서**다(#914).
///
/// 회원은 자기 앱에서 `오늘 / 이번 주 / 이번 달` 을 골라 보는데, 정작 코칭하는
/// 트레이너 화면은 식단이 오늘 하루, 운동이 이번 주로 고정이었다. 회원이
/// "이번 주는 좀 과했어요" 라고 말해도 견줄 화면이 없었다.
enum ClientPeriod {
  /// 오늘 하루.
  today,

  /// 이번 주(월~일).
  week,

  /// 이번 달(1일~말일).
  month,
}

/// 기간이 덮는 날짜 범위. 시작·끝 모두 **포함**이다.
typedef ClientDateRange = ({DateTime from, DateTime to});

/// [period] 가 [today] 기준으로 덮는 날짜 범위.
///
/// 날짜를 `Duration` 이 아니라 성분으로 옮긴다 — 로컬 시간에 Duration 을 더하면
/// 서머타임이 있는 지역에서 주 전체가 하루씩 밀린다. `DateTime(y, m + 1, 0)` 은
/// 12월이면 다음 해 1월 0일 = 12월 31일로 알아서 넘어간다. 회원 앱
/// `dietRangeForTab` 과 같은 규칙이다.
/// `전체` 식단이 거슬러 올라가는 날 수. 회원 앱 식단 탭과 같은 12주다 — 두 앱이
/// 같은 기간을 보여야 나란히 놓고 이야기할 수 있다. (#1018)
const int kClientAllPeriodDays = 84;

/// `전체` 운동이 거슬러 올라가는 **주** 수. 회원 앱 운동 탭과 같은 **35주**다
/// (`kExerciseAllPeriodWeeks`). 식단보다 길다 — 운동은 한 칸이 한 주라 여덟 달을
/// 늘어놓아도 읽히지만, 식단은 한 칸이 하루라 그만큼 길면 막대가 실오라기가
/// 된다. (#1170)
///
/// 12주로 두었더니 회원 앱에는 작년 12월치 기록이 있는데 트레이너 화면은 6월
/// 이후만 보였다 — 같은 사람의 같은 이력을 두 화면이 다른 길이로 말했다.
///
/// 날 수(35 × 7)가 아니라 주 수로 센다(#2157). 오늘에서 245일을 거슬러 가면
/// 첫날이 주 한가운데에 떨어져, 첫 주가 잘린 채 한 칸 더 붙어 36칸이 됐다.
/// 회원 앱은 이번 주 월요일에서 34주를 거슬러 **월요일부터** 35칸이다.
const int kClientAllExerciseWeeks = 35;

/// [period] 가 덮는 날짜 범위. [exercise] 면 `전체` 가 운동 기준으로 길어진다.
ClientDateRange clientRangeFor(
  ClientPeriod period,
  DateTime today, {
  bool exercise = false,
}) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  switch (period) {
    case ClientPeriod.today:
      return (from: day, to: day);
    case ClientPeriod.week:
      final DateTime monday = DateTime(
        day.year,
        day.month,
        day.day - (day.weekday - 1),
      );
      return (
        from: monday,
        to: DateTime(monday.year, monday.month, monday.day + 6),
      );
    case ClientPeriod.month:
      // `이번 달` 이 아니라 `전체` 다 — 달이 바뀌었다고 앞의 기록이 사라지면
      // 추세를 볼 수 없다. 회원 앱과 같은 길이다(식단 12주 · 운동 35주).
      if (exercise) {
        // 운동은 한 칸이 한 주라 **월요일에서** 시작한다(#2157).
        final DateTime monday = clientMondayOf(day);
        return (
          from: DateTime(
            monday.year,
            monday.month,
            monday.day - (kClientAllExerciseWeeks - 1) * 7,
          ),
          to: day,
        );
      }
      const int days = kClientAllPeriodDays;
      return (
        from: DateTime(day.year, day.month, day.day - days + 1),
        to: day,
      );
  }
}

/// [day] 가 속한 주의 월요일(시각은 0시).
///
/// 서버도 데모도 운동·리포트 이력을 주 단위로 들고 있고, 그 키가 언제나
/// 월요일이다. 읽는 쪽과 쓰는 쪽이 같은 함수를 써야 주가 어긋나지 않는다.
DateTime clientMondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// 범위가 덮는 모든 날짜(시작·끝 포함).
List<DateTime> clientRangeDates(ClientDateRange range) {
  final List<DateTime> out = <DateTime>[];
  DateTime cursor = DateTime(range.from.year, range.from.month, range.from.day);
  final DateTime last = DateTime(range.to.year, range.to.month, range.to.day);
  while (!cursor.isAfter(last)) {
    out.add(cursor);
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return out;
}

/// 범위가 걸치는 모든 주의 월요일(오래된 → 최근).
///
/// 서버도 데모도 운동·식단 이력을 **주 단위**로 읽는다. 한 달을 그리려면 그
/// 달에 걸친 4~6개의 주를 각각 읽어 이어 붙인다.
List<DateTime> clientRangeWeekStarts(ClientDateRange range) {
  final DateTime first = DateTime(
    range.from.year,
    range.from.month,
    range.from.day - (range.from.weekday - 1),
  );
  final DateTime last = DateTime(
    range.to.year,
    range.to.month,
    range.to.day - (range.to.weekday - 1),
  );
  final List<DateTime> out = <DateTime>[];
  DateTime cursor = first;
  while (!cursor.isAfter(last)) {
    out.add(cursor);
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
  }
  return out;
}

/// 하루치 식단 집계.
class ClientDietDay {
  /// Creates one day's totals.
  const ClientDietDay({
    required this.date,
    this.calories = 0,
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });

  final DateTime date;
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 그날의 탄·단·지(g). `이번 달` 칼로리 막대를 3색으로 쌓는 재료다(#944).
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 그날 기록이 있었는가. 셋 다 0 이면 **적지 않은 날**이다 — 0kcal 을 먹은
  /// 날과 같은 말로 그리면 평균이 실제보다 낮아진다.
  bool get logged => calories > 0 || sodiumMg > 0 || sugarG > 0;

  /// 탄단지가 실제로 있는가. 영양을 주지 않은 날은 쌓지 않고 한 색으로 그린다 —
  /// 억지로 쌓으면 0 짜리 칸이 생겨 막대가 빈 것처럼 보인다.
  bool get hasMacros => carbsG > 0 || proteinG > 0 || fatG > 0;

  /// 탄단지가 내는 칼로리 — 탄·단 4kcal/g, 지 9kcal/g.
  ///
  /// 막대를 쌓을 때 쓰는 값이다. 그램으로 쌓으면 지방 1g 이 탄수화물 1g 과 같은
  /// 높이를 차지해, 칼로리 막대인데 칼로리와 다른 이야기를 하게 된다.
  double get carbsKcal => carbsG * 4;
  double get proteinKcal => proteinG * 4;
  double get fatKcal => fatG * 9;
}

/// 한 기간의 식단 집계.
class ClientDietPeriod {
  /// Creates a period from its per-day rows (오래된 → 최근).
  const ClientDietPeriod({required this.range, required this.days});

  final ClientDateRange range;
  final List<ClientDietDay> days;

  /// 기록이 있는 날 수.
  int get loggedDays => days.where((ClientDietDay d) => d.logged).length;

  bool get isEmpty => loggedDays == 0;

  /// 하루 평균은 **기록이 있는 날만으로** 나눈다. 아직 오지 않은 날까지 나누면
  /// 달 초에는 평균이 실제보다 늘 낮게 나온다.
  double get avgCalories => _avg((ClientDietDay d) => d.calories.toDouble());
  double get avgSodiumMg => _avg((ClientDietDay d) => d.sodiumMg.toDouble());
  double get avgSugarG => _avg((ClientDietDay d) => d.sugarG);

  double _avg(double Function(ClientDietDay) pick) {
    final Iterable<ClientDietDay> recorded = days.where(
      (ClientDietDay d) => d.logged,
    );
    if (recorded.isEmpty) return 0;
    return recorded.fold<double>(
          0,
          (double a, ClientDietDay d) => a + pick(d),
        ) /
        recorded.length;
  }
}

/// 하루치 운동 집계.
class ClientExerciseDay {
  /// Creates one day's totals.
  const ClientExerciseDay({
    required this.date,
    this.minutes = 0,
    this.calories = 0,
    this.cardioMinutes = 0,
    this.strengthMinutes = 0,
    this.stretchingMinutes = 0,
    this.otherMinutes = 0,
    this.cardioCalories = 0,
    this.strengthCalories = 0,
    this.stretchingCalories = 0,
    this.otherCalories = 0,
    this.strengthSets = 0,
  });

  final DateTime date;
  final int minutes;
  final int calories;

  /// 그날의 유형별 분. 회원 앱과 같은 3색 누적 막대를 그리는 재료다(#943).
  final int cardioMinutes;
  final int strengthMinutes;
  final int stretchingMinutes;

  /// 목표가 없는 나머지 운동. 그래프에는 그리지 않고 분 수만 적는다.
  final int otherMinutes;

  /// 그날의 유형별 **칼로리**. 리포트 막대를 칼로리로 쌓는 재료다(#1289).
  /// 분과 따로 두는 이유는 유형마다 분당 소모가 다르기 때문이다.
  final int cardioCalories;
  final int strengthCalories;
  final int stretchingCalories;
  final int otherCalories;

  /// 그날의 근력 **세트 수**.
  final int strengthSets;

  bool get logged => minutes > 0 || calories > 0;

  /// 유형 분해가 있는가. 없으면 막대를 쌓지 않고 전부 유산소로 본다 —
  /// 임의로 나누면 없는 근력 시간을 지어내는 셈이다.
  ///
  /// `기타` 도 분해의 한 칸이다(#2157). 예전에는 세 유형만 봐서, `기타` 만
  /// 기록한 날을 분해가 없는 날로 읽고 그날 분 전체(= 기타 분)를 유산소에
  /// 넣었다 — 기타 30분이 `유산소 30분` 과 `기타 30분` 으로 두 번 셌다. 회원
  /// 앱(`dayLoadsOfWeek`)은 분해가 실려 오면 그 값을 그대로 써 유산소 0분 +
  /// 기타 N분이다.
  bool get hasTypeSplit =>
      cardioMinutes > 0 ||
      strengthMinutes > 0 ||
      stretchingMinutes > 0 ||
      otherMinutes > 0;
}

/// 한 기간의 운동 집계.
class ClientExercisePeriod {
  /// Creates a period from its per-day rows (오래된 → 최근).
  const ClientExercisePeriod({
    required this.range,
    required this.days,
    this.weeklyGoalMinutes = 0,
    this.weeklyGoalCalories = 0,
  });

  final ClientDateRange range;
  final List<ClientExerciseDay> days;

  /// 회원의 주간 운동 시간 목표(분). 그래프의 목표선은 이 값을 7 로 나눠
  /// 하루 목표로 그린다 — 식단 그래프가 하루 목표를 그리는 것과 같은 뜻이다.
  /// (#1015)
  final int weeklyGoalMinutes;

  /// 회원의 주간 **소모 칼로리** 목표. 리포트 막대가 칼로리 축을 쓰면서
  /// 눈금 끝을 정하는 값이 됐다(#1289) — 이행률(%)일 때는 늘 100 이었다.
  final int weeklyGoalCalories;

  /// 하루 목표(분). 목표가 없으면 0 이고, 그러면 목표선을 그리지 않는다.
  double get dailyGoalMinutes => weeklyGoalMinutes / 7;

  /// 하루 소모 칼로리 목표. 목표가 없으면 0 이다.
  double get dailyGoalCalories => weeklyGoalCalories / 7;

  int get totalMinutes =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.minutes);

  int get totalCalories =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.calories);

  int get totalCardioMinutes =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.cardioMinutes);

  int get totalStrengthMinutes =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.strengthMinutes);

  int get totalStretchingMinutes => days.fold<int>(
    0,
    (int a, ClientExerciseDay d) => a + d.stretchingMinutes,
  );

  int get totalOtherMinutes =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.otherMinutes);

  int get totalStrengthSets =>
      days.fold<int>(0, (int a, ClientExerciseDay d) => a + d.strengthSets);

  /// 운동한 날 수 — 기간이 길어져도 "몇 번 했나" 의 뜻이 흔들리지 않는다.
  int get workoutDays => days.where((ClientExerciseDay d) => d.logged).length;

  bool get isEmpty => workoutDays == 0;
}

/// 오늘(KST) 기준 [period] 범위.
ClientDateRange clientRangeNow(ClientPeriod period, {bool exercise = false}) =>
    clientRangeFor(period, nowKst(), exercise: exercise);
