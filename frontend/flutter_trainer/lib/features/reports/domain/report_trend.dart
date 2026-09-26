import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';

/// ④ 운동 추세가 거슬러 보는 주 수. (#2232)
///
/// 여덟 주인 까닭: 한 주는 아프거나 출장 가면 무너진다. 두세 주로는 그 한 주와
/// 진짜 내리막을 구분할 수 없고, 반대로 반년을 보면 이번 달에 바꾼 것이 흐름에
/// 묻힌다. 두 달이 그 사이다.
const int kReportTrendWeeks = 8;

/// 한 주의 유형별 실적.
class ReportTrendWeek {
  /// Creates a week.
  const ReportTrendWeek({
    required this.weekStart,
    required this.cardioMinutes,
    required this.strengthSets,
    required this.stretchingMinutes,
    required this.cardioCalories,
    required this.strengthCalories,
    required this.stretchingCalories,
  });

  /// 그 주의 월요일.
  final DateTime weekStart;

  final int cardioMinutes;
  final int strengthSets;
  final int stretchingMinutes;

  final int cardioCalories;
  final int strengthCalories;
  final int stretchingCalories;

  /// 그 유형의 단위로 잰 실적(유산소·스트레칭은 분, 근력은 세트).
  num valueOf(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => cardioMinutes,
    ExerciseKind.strength => strengthSets,
    ExerciseKind.stretching => stretchingMinutes,
  };

  /// 그 유형이 낸 소모 칼로리.
  int caloriesOf(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => cardioCalories,
    ExerciseKind.strength => strengthCalories,
    ExerciseKind.stretching => stretchingCalories,
  };

  /// 그 주에 아무 기록도 없었는가. 빈 주는 추세 계산에서 빠진다 — 아직 오지
  /// 않은 주(리포트를 주 중에 여는 경우)까지 `감소` 로 세면 매주 내리막이다.
  bool get isEmpty =>
      cardioMinutes == 0 && strengthSets == 0 && stretchingMinutes == 0;
}

/// 여덟 주치 실적. 오래된 주 → 최근 주 순서이고, 마지막이 리포트가 보는 주다.
class ReportTrend {
  /// Creates a trend.
  const ReportTrend({required this.weeks, required this.goals});

  final List<ReportTrendWeek> weeks;

  /// 회원이 MY 에서 정한 주간 목표. 유형마다 단위가 다르다.
  final ExerciseBurnGoals goals;

  /// 리포트가 보는 주. 목록이 비면 null 이다.
  ReportTrendWeek? get current => weeks.isEmpty ? null : weeks.last;

  /// 그 유형의 목표 대비 비율(0 이상). 목표가 0 이면 견줄 기준이 없어 null.
  double? ratioOf(ExerciseKind kind, ReportTrendWeek week) {
    final double goal = goals.weeklyGoalOf(kind).toDouble();
    if (goal <= 0) return null;
    return week.valueOf(kind) / goal;
  }

  /// 한 주의 **달성률** — 세 유형의 목표 대비 비율을 평균한 값(0~1 로 자른다).
  ///
  /// 셋을 더할 수 없으니(분·세트·분) 각자의 목표에 대한 비율로 바꿔 평균한다.
  /// 한 유형만 두 배를 해도 전체가 잘된 주로 읽히지 않게 위를 1 에서 자른다.
  double? rateOf(ReportTrendWeek week) {
    final List<double> ratios = <double>[
      for (final ExerciseKind kind in ExerciseKind.values)
        if (ratioOf(kind, week) case final double r) r.clamp(0.0, 1.0),
    ];
    if (ratios.isEmpty) return null;
    return ratios.reduce((double a, double b) => a + b) / ratios.length;
  }

  /// 기록이 있는 주들의 달성률 평균. 하나도 없으면 null.
  double? get averageRate {
    final List<double> rates = <double>[
      for (final ReportTrendWeek week in weeks)
        if (!week.isEmpty)
          if (rateOf(week) case final double r) r,
    ];
    if (rates.isEmpty) return null;
    return rates.reduce((double a, double b) => a + b) / rates.length;
  }

  /// 달성률이 내리 떨어진 주 수(마지막 주 기준). 2 미만이면 0 — 한 주 내려간
  /// 것은 흐름이 아니다.
  int get fallingWeeks => _runLength(<double>[
    for (final ReportTrendWeek week in weeks)
      if (rateOf(week) case final double r) r,
  ], down: true);

  /// 그 유형이 내리(또는 오르내리지 않고) 이어 온 주 수와 방향.
  ReportTrendRun runOf(ExerciseKind kind) {
    final List<double> series = <double>[
      for (final ReportTrendWeek week in weeks) week.valueOf(kind).toDouble(),
    ];
    final int down = _runLength(series, down: true);
    if (down > 0) return (weeks: down, rising: false);
    final int up = _runLength(series, down: false);
    if (up > 0) return (weeks: up, rising: true);
    return (weeks: 0, rising: false);
  }

  /// 지난 주 대비 변화율(%). 지난 주가 없거나 0 이면 null — 0 에서 늘어난
  /// 것은 몇 퍼센트가 아니라 `없다가 생긴 것` 이다.
  int? deltaOf(ExerciseKind kind) {
    if (weeks.length < 2) return null;
    final num previous = weeks[weeks.length - 2].valueOf(kind);
    if (previous <= 0) return null;
    final num now = weeks.last.valueOf(kind);
    return (((now - previous) / previous) * 100).round();
  }

  /// [series] 끝에서 이어지는 단조 구간의 **주 수**. 2 주 이상일 때만 센다.
  static int _runLength(List<double> series, {required bool down}) {
    if (series.length < 3) return 0;
    int run = 0;
    for (int i = series.length - 1; i > 0; i--) {
      final bool stepped = down
          ? series[i] < series[i - 1]
          : series[i] > series[i - 1];
      if (!stepped) break;
      run++;
    }
    return run >= 2 ? run : 0;
  }
}

/// 이어진 흐름 — 몇 주째인지와 오르막인지.
typedef ReportTrendRun = ({int weeks, bool rising});

/// [weeks] 를 오래된 주 → 최근 주로 이어 붙인다.
List<ReportTrendWeek> reportTrendWeeks(
  List<DateTime> mondays,
  List<ClientExerciseWeek> weeks,
) => <ReportTrendWeek>[
  for (int i = 0; i < mondays.length && i < weeks.length; i++)
    ReportTrendWeek(
      weekStart: mondays[i],
      cardioMinutes: _sum(weeks[i].cardioMinutes),
      strengthSets: _sum(weeks[i].strengthSets),
      stretchingMinutes: _sum(weeks[i].stretchingMinutes),
      cardioCalories: _sum(weeks[i].cardioCalories),
      strengthCalories: _sum(weeks[i].strengthCalories),
      stretchingCalories: _sum(weeks[i].stretchingCalories),
    ),
];

int _sum(List<int> xs) => xs.fold<int>(0, (int a, int b) => a + b);
