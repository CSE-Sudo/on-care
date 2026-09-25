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
/// 기록이 없을 때 `전체` 가 그리는 날 수 — **하루**다(오늘만).
///
/// `전체` 는 모든 기록을 그린다(#2079). 거슬러 올라갈 곳은 그 회원의 첫 기록일
/// (`GET /trainer/clients/{id}/records/span`)이 정하고, 그 값이 없을 때(기록이
/// 없거나 아직 못 읽었을 때)만 이 값이 쓰인다 — 지어낸 기간보다 하루가 낫다.
const int kClientMinPeriodDays = 1;

/// AI 맞춤 조언이 **읽는** 날 수. 서버 `period_window.ALL_PERIOD_DAYS` 와 같다.
///
/// 그래프가 보여 주는 기간과 뜻이 다르다(#2079) — 그래프는 "지금까지 어땠나",
/// 조언은 "무엇을 근거로 말하나" 다. 그래서 `전체` 그래프가 모든 기록으로
/// 넓어져도 이 값은 그대로이고, 대신 조언 문구가 제 기간을 밝힌다.
const int kAdvicePeriodDays = 84;

/// 기록이 없을 때 `전체` 운동이 그리는 주 수 — **한 주**다(이번 주만).
/// 회원 앱 `kExerciseMinPeriodWeeks` 와 같다.
const int kClientMinExerciseWeeks = 1;

/// [period] 가 덮는 날짜 범위. [exercise] 면 `전체` 가 운동 기준으로 길어진다.
/// [firstRecord] 는 그 회원이 **처음 기록한 날**이다(#2079). `전체` 가 거기서
/// 시작한다 — 없으면(기록이 없거나 아직 못 읽었으면) 식단은 오늘 하루, 운동은
/// 이번 주 한 주다.
ClientDateRange clientRangeFor(
  ClientPeriod period,
  DateTime today, {
  bool exercise = false,
  DateTime? firstRecord,
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
      // `이번 달` 이 아니라 `전체` 다 — **모든 기록**을 그린다(#2079). 고정 창을
      // 두면 그보다 오래된 기록이 그래프에서 사라져, 회원 앱에는 있는 이력이
      // 트레이너 화면에는 없게 된다(#1170 에서 겪은 일이다).
      final DateTime? first = firstRecord == null
          ? null
          : DateTime(firstRecord.year, firstRecord.month, firstRecord.day);
      if (exercise) {
        // 운동은 한 칸이 한 주라 **월요일에서** 시작한다(#2157). 기록이 주
        // 한가운데에서 시작해도 그 주는 통째로 한 칸이다.
        final DateTime thisMonday = clientMondayOf(day);
        final DateTime firstMonday = first == null
            ? thisMonday
            : clientMondayOf(first);
        return (
          from: firstMonday.isAfter(thisMonday) ? thisMonday : firstMonday,
          to: day,
        );
      }
      return (from: first == null || first.isAfter(day) ? day : first, to: day);
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

/// 고객이 식단·운동을 **처음 남긴 날**. (#2079, #2236)
///
/// `전체` 그래프가 어디서부터 그릴지를 정한다. 식단과 운동이 각자 제 첫
/// 기록일을 가진다 — 한쪽만 기록해 온 회원의 빈 칸이 다른 쪽 때문에 늘어나지
/// 않게 한다. 기록이 없으면 null 이고, 그때 `전체` 는 오늘 하루(운동은 이번
/// 주)만 그린다.
class ClientRecordSpan {
  const ClientRecordSpan({this.dietFirstDate, this.exerciseFirstDate});

  factory ClientRecordSpan.fromJson(Map<String, Object?> json) =>
      ClientRecordSpan(
        dietFirstDate: _dateOrNull(json['diet_first_date']),
        exerciseFirstDate: _dateOrNull(json['exercise_first_date']),
      );

  /// 기록이 하나도 없거나 아직 못 읽은 상태.
  static const ClientRecordSpan empty = ClientRecordSpan();

  final DateTime? dietFirstDate;
  final DateTime? exerciseFirstDate;

  static DateTime? _dateOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
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
    this.typeSplitFromPayload,
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
  /// **응답이 말해 주면 그 말을 따른다**(#2195). 주간 응답에 유형 배열이 실려
  /// 왔는지는 `ClientExerciseWeek.hasTypeSplit` 이 알고, 회원 앱
  /// (`dayLoadsOfWeek`)도 같은 기준 — 배열이 있으면 그 값을 그대로 쓴다.
  /// 값으로 되짚으면 **네 유형이 모두 0 인 날**(쉰 날, 또는 분 없이 칼로리만
  /// 있는 날)이 분해가 없는 날로 읽혀, 그날 분이 통째로 유산소로 간다.
  ///
  /// 그 말을 듣지 못한 날([typeSplitFromPayload] 가 null — 직접 만든 값)만 값으로
  /// 되짚는다. `기타` 도 분해의 한 칸이다(#2157).
  /// 주간 응답이 말한 분해 여부. 직접 만든 값이면 null 이다.
  final bool? typeSplitFromPayload;

  bool get hasTypeSplit =>
      typeSplitFromPayload ??
      (cardioMinutes > 0 ||
          strengthMinutes > 0 ||
          stretchingMinutes > 0 ||
          otherMinutes > 0);
}

/// 한 기간의 운동 집계.
class ClientExercisePeriod {
  /// Creates a period from its per-day rows (오래된 → 최근).
  const ClientExercisePeriod({
    required this.range,
    required this.days,
    this.weeklyGoalMinutes = 0,
    this.weeklyGoalCalories = 0,
    this.streakDays = 0,
  });

  final ClientDateRange range;
  final List<ClientExerciseDay> days;

  /// 운동한 날의 최장 연속 구간 — **서버가 센 값**이다(#2195). 여러 주를 이어
  /// 붙인 기간이면 마지막(가장 최근) 주의 값이다. `이번 주` 도넛 옆의 연속
  /// 태그가 이 값을 읽는다 — 회원 앱도 같은 필드를 쓴다.
  final int streakDays;

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
