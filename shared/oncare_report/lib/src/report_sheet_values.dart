/// 결과지 자료의 값 타입 — 앱에 자기 타입이 없는 쪽(회원 앱)과 데모 빌더가 쓴다.
/// (#2652)
library;

import 'package:oncare_report/src/report_sheet_data.dart';

/// [ReportSheetDay] 의 값.
class ReportSheetDayData implements ReportSheetDay {
  /// Creates a day.
  const ReportSheetDayData({
    required this.completion,
    this.exercises = const <String>[],
    this.assigned,
    this.assignedDone,
  });

  @override
  final int completion;

  @override
  final List<String> exercises;

  @override
  final int? assigned;

  @override
  final int? assignedDone;
}

/// [ReportSheetAnswers] 의 값.
class ReportSheetAnswersData implements ReportSheetAnswers {
  /// Creates answers.
  const ReportSheetAnswersData({
    required this.conditionWire,
    required this.intensityWire,
    this.painArea = '',
    this.painOn,
    this.note = '',
  });

  /// 저장된 값에서 만든다. 컨디션·강도 중 하나라도 모르는 값이면 **답이 아니다**
  /// — 트레이너 웹 `MemberWeeklyFeedback.fromWire` 와 같은 규칙이다.
  static ReportSheetAnswersData? fromWire({
    String? condition,
    String? intensity,
    String painArea = '',
    String painOn = '',
    String note = '',
  }) {
    if (!kReportConditionWires.contains(condition) ||
        !kReportIntensityWires.contains(intensity)) {
      return null;
    }
    final String area = painArea.trim();
    return ReportSheetAnswersData(
      conditionWire: condition!,
      intensityWire: intensity!,
      painArea: area,
      // 아픈 곳을 적지 않았으면 날짜도 버린다 — "(빈칸) 이 아팠다" 를 그리지 않게.
      painOn: area.isEmpty ? null : DateTime.tryParse(painOn),
      note: note.trim(),
    );
  }

  @override
  final String conditionWire;

  @override
  final String intensityWire;

  @override
  final String painArea;

  @override
  final DateTime? painOn;

  @override
  final String note;

  @override
  bool get hasPain => painArea.isNotEmpty;
}

/// 컨디션 답의 서버 값 — 좋은 쪽에서 나쁜 쪽 순서다.
const List<String> kReportConditionWires = <String>[
  'great',
  'good',
  'ok',
  'tired',
  'bad',
];

/// 강도 답의 서버 값.
const List<String> kReportIntensityWires = <String>[
  'too_easy',
  'right',
  'hard',
  'too_hard',
];

/// [ReportSheetWeek] 의 값.
class ReportSheetWeekData implements ReportSheetWeek {
  /// Creates a week.
  const ReportSheetWeekData({
    required this.memberName,
    required this.weekStart,
    required this.sessionsBooked,
    required this.sessionsDone,
    required this.completionAvg,
    required this.sodiumAvg,
    required this.isCurrentWeek,
    this.weekCompletion = const <int?>[],
    this.sodiumWeek = const <int>[],
    this.caloriesWeek = const <int>[],
    this.sugarWeek = const <double>[],
    this.carbsWeek = const <double>[],
    this.proteinWeek = const <double>[],
    this.fatWeek = const <double>[],
    this.calorieTarget,
    this.sodiumTarget,
    this.sugarTarget,
    this.carbsTarget,
    this.proteinTarget,
    this.fatTarget,
    this.days = const <ReportSheetDay>[],
    this.mealCounts = const <int>[],
    this.answers,
  });

  @override
  final String memberName;
  @override
  final DateTime weekStart;
  @override
  final int sessionsBooked;
  @override
  final int sessionsDone;
  @override
  final int? completionAvg;
  @override
  final int? sodiumAvg;
  @override
  final bool isCurrentWeek;
  @override
  final List<int?> weekCompletion;
  @override
  final List<int> sodiumWeek;
  @override
  final List<int> caloriesWeek;
  @override
  final List<double> sugarWeek;
  @override
  final List<double> carbsWeek;
  @override
  final List<double> proteinWeek;
  @override
  final List<double> fatWeek;
  @override
  final int? calorieTarget;
  @override
  final int? sodiumTarget;
  @override
  final double? sugarTarget;
  @override
  final double? carbsTarget;
  @override
  final double? proteinTarget;
  @override
  final double? fatTarget;
  @override
  final List<ReportSheetDay> days;
  @override
  final List<int> mealCounts;
  @override
  final ReportSheetAnswers? answers;

  /// 같은 주에 회원의 답만 바꿔 끼운다 — 답은 다른 응답에서 온다.
  ReportSheetWeekData withAnswers(ReportSheetAnswers? value) =>
      ReportSheetWeekData(
        memberName: memberName,
        weekStart: weekStart,
        sessionsBooked: sessionsBooked,
        sessionsDone: sessionsDone,
        completionAvg: completionAvg,
        sodiumAvg: sodiumAvg,
        isCurrentWeek: isCurrentWeek,
        weekCompletion: weekCompletion,
        sodiumWeek: sodiumWeek,
        caloriesWeek: caloriesWeek,
        sugarWeek: sugarWeek,
        carbsWeek: carbsWeek,
        proteinWeek: proteinWeek,
        fatWeek: fatWeek,
        calorieTarget: calorieTarget,
        sodiumTarget: sodiumTarget,
        sugarTarget: sugarTarget,
        carbsTarget: carbsTarget,
        proteinTarget: proteinTarget,
        fatTarget: fatTarget,
        days: days,
        mealCounts: mealCounts,
        answers: value,
      );
}

/// [ReportSheetTrendWeek] 의 값.
class ReportSheetTrendWeekData implements ReportSheetTrendWeek {
  /// Creates a week.
  const ReportSheetTrendWeekData({
    required this.weekStart,
    required this.cardioMinutes,
    required this.strengthSets,
    required this.stretchingMinutes,
  });

  @override
  final DateTime weekStart;

  final int cardioMinutes;
  final int strengthSets;
  final int stretchingMinutes;

  @override
  num valueOf(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => cardioMinutes,
    ExerciseKind.strength => strengthSets,
    ExerciseKind.stretching => stretchingMinutes,
  };

  @override
  bool get isEmpty =>
      cardioMinutes == 0 && strengthSets == 0 && stretchingMinutes == 0;
}

/// 회원의 주간 운동 목표 — 유형마다 그 유형의 단위로.
class ReportSheetGoals {
  /// Creates goals.
  const ReportSheetGoals({
    this.weeklyCardioMinutes = kReportWeeklyCardioMinutes,
    this.weeklyStrengthSets = kReportWeeklyStrengthSets,
    this.weeklyStretchingMinutes = kReportWeeklyStretchingMinutes,
  });

  final double weeklyCardioMinutes;
  final double weeklyStrengthSets;
  final double weeklyStretchingMinutes;

  /// 유형의 주간 목표.
  double of(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => weeklyCardioMinutes,
    ExerciseKind.strength => weeklyStrengthSets,
    ExerciseKind.stretching => weeklyStretchingMinutes,
  };
}

/// 주간 유산소 목표(분)의 기본값 — WHO 의 주 150분 권고.
const double kReportWeeklyCardioMinutes = 150;

/// 주간 근력 목표(세트)의 기본값 — 하루 3세트 × 7일.
const double kReportWeeklyStrengthSets = 21;

/// 주간 스트레칭 목표(분)의 기본값.
const double kReportWeeklyStretchingMinutes = 60;

/// [ReportSheetTrend] 의 값.
class ReportSheetTrendData implements ReportSheetTrend {
  /// Creates a trend.
  const ReportSheetTrendData({required this.weeks, required this.goals});

  @override
  final List<ReportSheetTrendWeek> weeks;

  final ReportSheetGoals goals;

  @override
  double goalOf(ExerciseKind kind) => goals.of(kind);
}

/// 추이가 거슬러 보는 주 수 — 트레이너 웹 `kReportTrendWeeks` 와 같다.
const int kReportSheetTrendWeeks = 8;

/// 4주 평균 대비에 쓰는 직전 주 수 — 트레이너 웹 `kCalorieBaselineWeeks` 와 같다.
const int kReportSheetHistoryWeeks = 4;

/// 결과지 한 장을 그리는 데 필요한 것 전부.
class ReportSheetInputs {
  /// Creates the inputs.
  const ReportSheetInputs({
    required this.week,
    this.trend,
    this.history = const <ReportSheetWeek>[],
  });

  /// 리포트가 보는 주.
  final ReportSheetWeek week;

  /// 여덟 주 운동 실적. 읽지 못했으면 null.
  final ReportSheetTrend? trend;

  /// 직전 주들(최근 주 → 오래된 주).
  final List<ReportSheetWeek> history;
}
