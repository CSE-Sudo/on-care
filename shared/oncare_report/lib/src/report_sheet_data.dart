/// 결과지 한 장이 읽는 자료의 **모양**. (#2652)
///
/// 트레이너 웹과 회원 앱은 같은 한 주를 서로 다른 타입으로 들고 있다 — 트레이너는
/// 로스터의 회원(`TrainerClient`)과 함께 `WeeklyReport` 로, 회원 앱은 자기 기록으로.
/// 결과지는 그 둘을 모두 받아야 하므로 여기서는 결과지가 실제로 읽는 칸만 인터페이스로
/// 두고, 두 앱의 타입이 그것을 구현한다. 계산 규칙(판정 폭·기본 목표)도 이 파일이
/// 원본이다 — 한쪽만 고치면 같은 주가 두 앱에서 다른 점수를 말한다.
library;

import 'package:oncare_ui/oncare_ui.dart'
    show
        kGoalDefaultDailyCalories,
        kGoalDefaultDailyCarbsG,
        kGoalDefaultDailyFatG,
        kGoalDefaultDailyProteinG,
        kGoalDefaultDailySodiumMg,
        kGoalDefaultDailySugarG;

/// 유형별로 재는 단위가 다르다 — 유산소·스트레칭은 **분**, 근력은 **세트**.
enum ExerciseKind { cardio, strength, stretching }

/// 칼로리가 목표에서 이만큼 벗어나면 주의로 본다. 백엔드와 같은 값이다.
const double calorieTolerance = 0.15;

/// 탄·단·지가 목표에서 이만큼 벗어나면 균형 이탈로 본다. 서버 리포트 요약의
/// `MACRO_TOLERANCE` 와 같은 값이다(#3246) — 결과지만 ±20% 로 보면 요약 카드가
/// 말하지 않은 `부족`·`초과` 가 결과지에만 찍힌다.
const double macroTolerance = 0.25;

/// 나트륨·당류를 이 날 수보다 많이 넘긴 주는 평균이 목표 안이어도 `초과` 다.
/// 서버 리포트 요약의 `SODIUM_OVER_DAYS`·`SUGAR_OVER_DAYS` 와 같은 값이다(#3246).
const int kReportSodiumOverDays = 2;
const int kReportSugarOverDays = 2;

// 회원 목표가 없을 때 쓰는 아래 기본값은 두 앱의 기준선과 같은 공용 정의
// (`oncare_ui` 의 `kGoalDefault…`)를 읽는다(#2906). 결과지만 다른 숫자를 들면
// 같은 회원의 같은 주가 홈 카드와 결과지에서 다른 목표선으로 그려진다.

/// 당류 하루 기준(g) — 회원 목표가 없을 때 쓴다.
const double sugarLimitG = kGoalDefaultDailySugarG * 1.0;

/// 하루 칼로리 목표(kcal) — 회원 목표가 없을 때 쓴다.
const int kReportCalorieTargetKcal = kGoalDefaultDailyCalories;

/// 하루 나트륨 목표(mg) — 회원 목표가 없을 때 쓴다. 백엔드 `SODIUM_TARGET_MG`.
const int kReportSodiumTargetMg = kGoalDefaultDailySodiumMg;

/// 하루 탄수화물·단백질·지방 목표(g) — 회원 목표가 없을 때 쓴다.
///
/// 단백질은 회원 앱 홈 카드·트레이너 웹 영양 카드·서버 식단 분석과 같은 60g 이다.
/// 예전 100g 은 결과지에만 남아 있어, 단백질 목표를 비워 둔 회원의 결과지만
/// 다른 선으로 견줬다.
const int kReportCarbsTargetG = kGoalDefaultDailyCarbsG;
const int kReportProteinTargetG = kGoalDefaultDailyProteinG;
const int kReportFatTargetG = kGoalDefaultDailyFatG;

/// `잘한 주` 로 보는 루틴 수행률·출석률(%).
const int kReportGoodCompletionThreshold = 80;

/// 한 주의 날 수.
const int kReportWeekdayCount = 7;

/// 기록된 날(0 초과)만의 평균. 하나도 없으면 null — 0 으로 보고하면
/// "아무것도 안 했다"는 거짓말이 된다.
double? recordedMean(List<num> series) {
  final List<num> recorded = series
      .where((num v) => v > 0)
      .toList(growable: false);
  if (recorded.isEmpty) return null;
  // fold<double> 로 더한다 — `List<int>` 를 `List<num>` 으로 받으면 reduce 의
  // 결합 함수가 런타임 타입(int)과 맞지 않아 던진다.
  return recorded.fold<double>(0, (double sum, num v) => sum + v) /
      recorded.length;
}

/// 그 날짜가 든 주의 월요일(시각은 버린다). 달력 날짜로 뺀다 — `Duration` 으로
/// 빼면 서머타임이 있는 곳에서 자정이 한 시간 밀려 전날이 된다.
DateTime reportWeekStartOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// 지금 서울의 벽시계. 앱이 기준일을 넘기지 않았을 때만 쓴다.
DateTime reportNowKst() {
  final DateTime seoul = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(
    seoul.year,
    seoul.month,
    seoul.day,
    seoul.hour,
    seoul.minute,
    seoul.second,
  );
}

/// 결과지의 하루 — 루틴 수행률과 그날 한 운동.
abstract interface class ReportSheetDay {
  /// 그날 수행률(%). 0 은 기록이 없다는 뜻이다.
  int get completion;

  /// 그날 운동 이름. 끝의 '✗' 는 건너뛴 운동이다.
  List<String> get exercises;

  /// 그날 **배정된** 개인 운동 수. 모르면 null 이고, 그때는 [exercises] 의
  /// 길이가 분모가 된다.
  int? get assigned;

  /// 그중 그날 완료한 수 — [assigned] 의 짝인 분자다(#3115). 모르면(옛 응답·
  /// 데모) null 이고, 그때는 [exercises] 에서 센다. [exercises] 는 그날 남은
  /// 운동 기록 전부(직접 기록·PT 기록 포함)라 개인운동 완료 수보다 많을 수 있다.
  int? get assignedDone;
}

/// [ReportSheetDay] 의 셈.
extension ReportSheetDayCounts on ReportSheetDay {
  /// 완료한 운동 수 — 배정을 알면 그 완료, 모르면 건너뛰지 않은 운동 수.
  int get doneCount =>
      (assigned != null ? assignedDone : null) ??
      exercises.where((String e) => !e.contains('✗')).length;

  /// 배정된 운동 수.
  int get totalCount => assigned ?? exercises.length;
}

/// 회원이 한 주를 끝내며 낸 세 문항의 답.
///
/// 컨디션·강도는 서버·DB 가 쓰는 값(`great`·`too_hard` …)으로 둔다 — 두 앱이
/// 같은 이름의 enum 을 따로 갖고 있어, 여기서 또 하나를 만들면 이름이 부딪힌다.
abstract interface class ReportSheetAnswers {
  /// `great` · `good` · `ok` · `tired` · `bad`.
  String get conditionWire;

  /// `too_easy` · `right` · `hard` · `too_hard`.
  String get intensityWire;

  /// 아픈 곳. 없으면 빈 문자열.
  String get painArea;

  /// 아팠던 날. [painArea] 가 비면 null.
  DateTime? get painOn;

  /// 한 줄 자유 서술.
  String get note;

  /// 통증을 보고했는가.
  bool get hasPain;
}

/// 결과지가 싣는 한 주.
abstract interface class ReportSheetWeek {
  /// 머리 띠의 회원 이름.
  String get memberName;

  /// 그 주의 월요일.
  DateTime get weekStart;

  /// 그 주에 잡힌 PT 와 그중 진행한 수.
  int get sessionsBooked;
  int get sessionsDone;

  /// 기록된 날의 평균 루틴 수행률(%). 기록이 없으면 null.
  int? get completionAvg;

  /// 기록된 날의 하루 평균 나트륨(mg). 기록이 없으면 null.
  int? get sodiumAvg;

  /// 지금 지나고 있는 주인가 — 끼니를 적었어야 할 날 수가 달라진다.
  bool get isCurrentWeek;

  /// 요일별 값(월→일).
  List<int?> get weekCompletion;
  List<int> get sodiumWeek;
  List<int> get caloriesWeek;
  List<double> get sugarWeek;
  List<double> get carbsWeek;
  List<double> get proteinWeek;
  List<double> get fatWeek;

  /// 회원이 적어 둔 하루 목표. 없으면 null 이고 판정이 공통 기본값으로 간다.
  int? get calorieTarget;
  int? get sodiumTarget;
  double? get sugarTarget;
  double? get carbsTarget;
  double? get proteinTarget;
  double? get fatTarget;

  /// 서버가 정한 실효 단백질 목표 — 개인 목표, 없으면 체중 × 1.2g, 둘 다 없으면
  /// 공통 기본값(#2898). 이 칸이 없는 옛 응답·데모면 null 이다.
  double? get effectiveProteinTarget;

  /// 요일별 상세(월→일).
  List<ReportSheetDay> get days;

  /// 요일별 끼니 기록 횟수(월→일). 모르는 자료면 비어 있다.
  List<int> get mealCounts;

  /// 회원이 그 주에 낸 답. 아직 안 냈으면 null.
  ReportSheetAnswers? get answers;
}

/// [ReportSheetWeek] 에서 나오는 값 — 두 앱이 같은 규칙으로 읽는다.
extension ReportSheetWeekFigures on ReportSheetWeek {
  /// 그 주의 일요일.
  DateTime get weekEnd =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 6);

  /// PT 출석률(%). 잡힌 수업이 없으면 null.
  int? get attendanceRate => sessionsBooked == 0
      ? null
      : ((sessionsDone / sessionsBooked) * 100).round();

  /// 칼로리 판정에 쓰는 하루 목표.
  int get calorieGoal => calorieTarget ?? kReportCalorieTargetKcal;

  /// 기록된 날의 하루 평균 칼로리.
  double? get calorieMean => recordedMean(caloriesWeek);

  /// 당류 판정에 쓰는 하루 기준.
  double get sugarLimit => sugarTarget ?? sugarLimitG;

  /// 기록된 날의 하루 평균 당류.
  double? get sugarMean => recordedMean(sugarWeek);

  /// 나트륨 판정에 쓰는 하루 목표(mg).
  int get sodiumGoal => sodiumTarget ?? kReportSodiumTargetMg;

  /// 나트륨이 목표를 넘긴 날 수. 서버 `sodium_over_days` 와 같은 셈이다.
  int get sodiumOverGoalDays =>
      sodiumWeek.where((int mg) => mg > sodiumGoal).length;

  /// 당류가 기준을 넘긴 날 수.
  int get sugarOverLimitDays =>
      sugarWeek.where((double g) => g > sugarLimit).length;

  /// 단백질 막대를 견줄 하루 목표 — 트레이너 화면 탄단지 막대와 같은 규칙이다.
  double get proteinGoal =>
      proteinTarget ??
      effectiveProteinTarget ??
      kReportProteinTargetG.toDouble();

  /// 끼니를 하나라도 적은 날 수.
  int get mealLoggedDays => mealCounts.where((int n) => n > 0).length;
}

/// 결과지 추이가 읽는 한 주의 유형별 실적.
abstract interface class ReportSheetTrendWeek {
  /// 그 주의 월요일.
  DateTime get weekStart;

  /// 그 유형의 단위로 잰 실적(유산소·스트레칭은 분, 근력은 세트).
  num valueOf(ExerciseKind kind);

  /// 그 주에 아무 기록도 없었는가.
  bool get isEmpty;
}

/// 여덟 주치 운동 실적과 회원의 주간 목표.
abstract interface class ReportSheetTrend {
  /// 오래된 주 → 리포트가 보는 주.
  List<ReportSheetTrendWeek> get weeks;

  /// 그 유형의 주간 목표(그 유형의 단위).
  double goalOf(ExerciseKind kind);
}

/// [ReportSheetTrend] 의 비율 계산. 두 앱이 같은 함수를 쓴다.
extension ReportSheetTrendRates on ReportSheetTrend {
  /// 리포트가 보는 주. 목록이 비면 null.
  ReportSheetTrendWeek? get currentWeek => weeks.isEmpty ? null : weeks.last;

  /// 그 유형의 목표 대비 비율.
  double? kindRatio(ExerciseKind kind, ReportSheetTrendWeek week) =>
      reportTrendRatio(goalOf(kind), week.valueOf(kind));

  /// 한 주의 달성률 — 세 유형의 목표 대비 비율(0~1 로 자른다)의 평균.
  double? weekRate(ReportSheetTrendWeek week) => reportTrendRate(<double?>[
    for (final ExerciseKind kind in ExerciseKind.values) kindRatio(kind, week),
  ]);
}

/// 목표 대비 비율. 목표가 0 이하이면 견줄 기준이 없어 null.
double? reportTrendRatio(double goal, num value) =>
    goal <= 0 ? null : value / goal;

/// 유형별 비율의 평균(각각 0~1 로 자른다). 셋 다 없으면 null.
///
/// 셋을 더할 수 없으니(분·세트·분) 각자의 목표에 대한 비율로 바꿔 평균한다.
/// 한 유형만 두 배를 해도 전체가 잘된 주로 읽히지 않게 위를 1 에서 자른다.
double? reportTrendRate(List<double?> ratios) {
  final List<double> clamped = <double>[
    for (final double? r in ratios)
      if (r != null) r.clamp(0.0, 1.0),
  ];
  if (clamped.isEmpty) return null;
  return clamped.reduce((double a, double b) => a + b) / clamped.length;
}
