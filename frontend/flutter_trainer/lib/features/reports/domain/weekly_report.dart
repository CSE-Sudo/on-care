import 'package:oncare_core/clock.dart';
import 'package:oncare_report/oncare_report.dart'
    show
        ReportSheetAnswers,
        ReportSheetDay,
        ReportSheetWeek,
        calorieTolerance,
        recordedMean,
        sugarLimitG;
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/korean_josa.dart';
import 'package:oncare_trainer/core/utils/korean_josa_l10n.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount;
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

export 'package:oncare_report/oncare_report.dart'
    show calorieTolerance, recordedMean, sugarLimitG;
export 'package:oncare_trainer/core/utils/korean_josa.dart'
    show hasFinalConsonant;
export 'package:oncare_trainer/core/utils/korean_josa_l10n.dart'
    show withParticle;

/// Monday of the week containing [day], stripped to a date.
///
/// 두 앱이 함께 쓰는 `oncare_ui` 의 [mondayOf] 로 센다(#2908) — 리포트 주 키가
/// 회원 앱·서버와 같은 날을 같은 주로 묶는다.
DateTime weekStartOf(DateTime day) => mondayOf(day);

/// [weekStart] 가 속한 주의 월요일에서 [weeks] 주 옮긴 월요일. 음수면 앞 주다.
///
/// 주를 옮기는 곳은 전부 이것을 쓴다(#2774). `Duration(days: 7)` 로 빼면
/// 서머타임이 시작된 주는 167시간뿐이라, 월요일 0시에서 빼면 전 주 월요일이
/// 아니라 그 전날 일요일 23시가 되고 — 그 날짜는 2주 전 주에 속한다.
DateTime shiftWeeks(DateTime weekStart, int weeks) {
  final DateTime monday = weekStartOf(weekStart);
  return DateTime(monday.year, monday.month, monday.day + 7 * weeks);
}

/// One client's week, as the trainer would summarise it to them.
///
/// This is the retention loop of an O2O coaching product: the member
/// stays because they can see they improved. Everything here is derived
/// from data the two apps already share — no new tracking.
///
/// 결과지(`oncare_report`)가 이 타입을 그대로 받는다 — 회원 앱이 여는 리포트와
/// 같은 위젯·같은 계산이다(#2652).
class WeeklyReport implements ReportSheetWeek {
  /// Creates a report.
  const WeeklyReport({
    required this.client,
    required this.weekStart,
    required this.sessionsBooked,
    required this.sessionsDone,
    required this.completionAvg,
    required this.sodiumOverDays,
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
    this.effectiveProteinTarget,
    this.fatTarget,
    this.days = const <ReportDay>[],
    this.mealCounts = const <int>[],
    this.memberFeedback,
    this.calorieBaseline,
  });

  /// Who the report is about.
  final TrainerClient client;

  /// Monday of the reported week.
  @override
  final DateTime weekStart;

  /// PT sessions booked in the week.
  @override
  final int sessionsBooked;

  /// Of those, how many were completed.
  @override
  final int sessionsDone;

  /// Mean routine completion (%) across recorded days; null when the
  /// client logged nothing.
  @override
  final int? completionAvg;

  /// Days over the sodium target; null when unknown for this week.
  final int? sodiumOverDays;

  /// Mean daily sodium (mg); null when there's no history.
  @override
  final int? sodiumAvg;

  /// Whether [weekStart] is the week we're currently in. Charts no longer
  /// depend on this — the report carries its own week — but the headline
  /// still says "이번 주" or "선택 주".
  @override
  final bool isCurrentWeek;

  /// 그 주(월→일)의 요일별 값. **로스터의 같은 이름 필드를 쓰지 않는다** —
  /// 그건 이번 주 것이라, 과거 주를 열면 지난 주 날짜 아래 이번 주 수치가
  /// 실린다. 트레이너는 그 리포트를 회원에게 그대로 보낼 수 있다(#752).
  @override
  final List<int?> weekCompletion;

  /// 그 주의 일별 나트륨(mg).
  @override
  final List<int> sodiumWeek;

  /// 그 주의 일별 칼로리(kcal).
  @override
  final List<int> caloriesWeek;

  /// 그 주의 일별 당류(g). 소수를 유지한다.
  @override
  final List<double> sugarWeek;

  /// 그 주의 일별 탄수화물·단백질·지방(g).
  ///
  /// 칼로리 총량만으로는 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지
  /// 알 수 없다 — 비교 그래프가 칼로리를 이 셋으로 쌓아 그린다(#1177).
  @override
  final List<double> carbsWeek;
  @override
  final List<double> proteinWeek;
  @override
  final List<double> fatWeek;

  /// 그 회원이 적어 둔 하루 목표. 없으면 null 이고, 판정 쪽이 공통 상수로
  /// 되돌아간다(#1430) — 같은 1,900kcal 이 어떤 회원에게는 부족이고 어떤
  /// 회원에게는 초과다. null 과 상수를 구분해 둬야 근거 문장이 어느 기준을
  /// 썼는지 말할 수 있다.
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

  /// 개인 목표가 없어도 채워지는 실효 단백질 목표(#2898) — 식단 분석과 같은
  /// 규칙(개인 목표 → 체중 × 1.2g → 60g). 리포트 막대 분모다. 판정은 여전히
  /// [proteinTarget] 만 본다 — 지어낸 기준으로 균형을 나무라지 않는다.
  final double? effectiveProteinTarget;
  @override
  final double? fatTarget;

  /// 요일별 상세(월→일). 이행률과 그날 배정된 운동을 함께 담는다 — 67% 가
  /// 어디서 나온 값인지 화면에서 보이게 하는 자료다(#754).
  @override
  final List<ReportDay> days;

  /// 그 주의 요일별 **끼니 기록 횟수**. (#2232)
  ///
  /// 칼로리 계열로는 이걸 대신할 수 없다. 0kcal 인 날은 "안 먹었다"가 아니라
  /// "안 적었다"이고, 리포트 ① 격자가 짚으려는 것이 정확히 그 날들이다.
  @override
  final List<int> mealCounts;

  /// 회원이 그 주에 남긴 세 문항. 아직 안 냈으면 null. (#2232)
  ///
  /// 수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽힌다.
  /// 그 둘은 다음 주 처방이 정반대라, 갈림길은 회원 본인의 답이 정한다.
  final MemberWeeklyFeedback? memberFeedback;

  /// 직전 4주(`kCalorieBaselineWeeks`) 동안 기록한 날의 하루 평균 칼로리 — ①
  /// 섭취 칼로리 줄이 견주는 `평소`. (#2232, #2863)
  ///
  /// 리포트와 함께 온다. 예전에는 화면이 직전 4주 리포트(와 회원 피드백)를
  /// 통째로 다시 불러 칼로리 배열만 꺼내 썼다. 기록이 없으면 null 이고, 그때는
  /// 비교 줄을 그리지 않는다 — `평소 0kcal` 은 굶었다는 뜻으로 읽힌다.
  final double? calorieBaseline;

  @override
  String get memberName => client.name;

  @override
  ReportSheetAnswers? get answers => memberFeedback;

  /// Sunday of the reported week.
  ///
  /// 달력 날짜로 더한다 — 그 주 안에 서머타임 전환이 있으면 `Duration` 은
  /// 자정을 한 시간 밀어 날짜가 어긋난다(#2774).
  DateTime get weekEnd =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 6);

  /// 문서에 실리는 내용 전부를 이은 열쇠. (#2484)
  ///
  /// 리포트는 스트림으로 온다 — 데모는 일정 표를 지켜보다 내용이 같은 리포트를
  /// 새 객체로 다시 보낸다. ③ 미리보기가 객체 동일성으로 재료를 가르면 그때마다
  /// PDF 를 처음부터 다시 만든다. 내용이 같으면 열쇠도 같다.
  String get contentKey {
    final MemberWeeklyFeedback? member = memberFeedback;
    return <Object?>[
      client.id,
      client.name,
      weekStart.toIso8601String(),
      sessionsBooked,
      sessionsDone,
      completionAvg,
      sodiumOverDays,
      sodiumAvg,
      isCurrentWeek,
      weekCompletion.join(','),
      sodiumWeek.join(','),
      caloriesWeek.join(','),
      sugarWeek.join(','),
      carbsWeek.join(','),
      proteinWeek.join(','),
      fatWeek.join(','),
      calorieTarget,
      sodiumTarget,
      sugarTarget,
      carbsTarget,
      proteinTarget,
      effectiveProteinTarget,
      fatTarget,
      for (final ReportDay day in days)
        '${day.completion}:${day.assigned}:${day.assignedDone}:${day.exercises.join('␟')}',
      mealCounts.join(','),
      calorieBaseline,
      if (member == null)
        '-'
      else
        <Object?>[
          member.condition.name,
          member.intensity.name,
          member.painArea,
          member.painOn?.toIso8601String(),
          member.note,
        ].join('␟'),
    ].join('␞');
  }

  /// `M월 D일 ~ M월 D일` / `M/D – M/D`, in the current locale.
  String rangeLabel(AppLocalizations l) => l.dateRange(
    l.dateMonthDay(weekStart.month, weekStart.day),
    l.dateMonthDay(weekEnd.month, weekEnd.day),
  );

  /// Session attendance as a percentage; null when nothing was booked.
  int? get attendanceRate => sessionsBooked == 0
      ? null
      : ((sessionsDone / sessionsBooked) * 100).round();

  /// Whether the week is worth celebrating — drives the headline's tone.
  /// An unknown figure is not a good one: praise has to be earned by
  /// data we actually have.
  ///
  /// 식단은 나트륨만 보지 않는다 — 칼로리가 매일 목표를 넘은 주에 "정말
  /// 잘하셨어요" 로 끝나던 초안이 그렇게 생겼다(#2422). 기록이 없는 지표는
  /// 판정에서 빠진다: 모르는 값으로 칭찬을 막지도, 허락하지도 않는다.
  bool get isGoodWeek =>
      (completionAvg ?? 0) >= goodCompletionThreshold &&
      (sodiumOverDays ?? 99) <= 2 &&
      !caloriesOffTarget &&
      !sugarOverLimit;

  /// 칼로리 판정에 쓰는 하루 목표 — 회원 목표가 없으면 공통 기본값.
  int get calorieGoal => calorieTarget ?? calorieTargetKcal;

  /// 기록된 날의 하루 평균 칼로리. 기록이 없으면 null.
  double? get calorieMean => recordedMean(caloriesWeek);

  /// 목표를 넘긴 날 수.
  int get calorieOverDays => caloriesWeek.where((k) => k > calorieGoal).length;

  /// 평균이 목표에서 벗어난 비율(+ 초과, - 부족). 기록이 없으면 null.
  double? get calorieGap {
    final mean = calorieMean;
    if (mean == null || calorieGoal <= 0) return null;
    return (mean - calorieGoal) / calorieGoal;
  }

  /// 칼로리가 목표를 벗어난 주인가. 평균이 허용 폭을 넘었거나, 평균은
  /// 맞아도 주의 절반을 넘는 날이 목표를 넘겼으면 그렇다 — 며칠 폭식하고
  /// 며칠 굶은 주가 평균만으로 `잘 맞춘 주` 가 되면 안 된다.
  bool get caloriesOffTarget {
    final gap = calorieGap;
    if (gap == null) return false;
    return gap.abs() > calorieTolerance || calorieOverDays > weekdayCount ~/ 2;
  }

  /// 당류 판정에 쓰는 하루 기준.
  double get sugarLimit => sugarTarget ?? sugarLimitG;

  /// 나트륨 초과를 가르는 하루 기준(mg) — 회원 목표, 없으면 공통 기준.
  /// [sodiumOverDays] 를 센 기준과 같다(#2885). 문장에 적는 목표가 이것과
  /// 다르면 `목표 1,500mg` 옆에 2,000mg 기준 초과일이 선다.
  int get sodiumLimit => sodiumLimitOf(sodiumTarget);

  /// 기록된 날의 하루 평균 당류. 기록이 없으면 null.
  double? get sugarMean => recordedMean(sugarWeek);

  /// 당류 기준을 넘긴 날 수.
  int get sugarOverDays => sugarWeek.where((g) => g > sugarLimit).length;

  /// 당류가 기준을 넘은 주인가 — 나트륨과 같은 규칙이다.
  bool get sugarOverLimit {
    final mean = sugarMean;
    if (mean == null) return false;
    return sugarOverDays > 2 || mean > sugarLimit;
  }

  /// 끼니를 하나라도 적은 날 수.
  int get mealLoggedDays => mealCounts.where((n) => n > 0).length;
}

/// Builds [client]'s report for the week starting [weekStart].
///
/// [sessions] should be that client's sessions; entries outside the week
/// are ignored here rather than at the call site, so a caller passing
/// the full history still gets a correct week.
WeeklyReport buildWeeklyReport({
  required TrainerClient client,
  required List<ScheduleSession> sessions,
  required DateTime weekStart,
  DateTime? today,
  WeekSeries? week,
  MemberWeeklyFeedback? memberFeedback,
  ReportTargets targets = const ReportTargets(),
  double? calorieBaseline,
}) {
  final start = weekStartOf(weekStart);
  final end = start.add(const Duration(days: 6));
  // 상담은 PT 가 아니다(#2741) — 리포트가 세는 것은 PT 횟수다. 상담이 있던 주가
  // PT 1회 더로 읽히고 이행률 분모도 커졌다. 실서버 `build_weekly_report` 와 같다.
  final inWeek = sessions.where((s) {
    final day = DateTime.tryParse(s.date);
    if (day == null || s.isGap || s.type == SessionType.consultation) {
      return false;
    }
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList();

  // 로스터가 준 계열(`client.*Week`)은 **이번 주** 것이라 그 주에만 붙인다.
  // 과거 주에 붙이면 지난 주 날짜 아래 이번 주 수치가 실리고, 트레이너는 그
  // 리포트를 회원에게 그대로 보낼 수 있다. 과거 주의 계열은 호출자가
  // [week] 로 넘겨 준다(데모는 drift 이력에서, 실서버는 리포트 응답에서).
  final isThisWeek = start == weekStartOf(today ?? nowKst());
  final series = week ?? (isThisWeek ? WeekSeries.of(client) : null);
  // Same "recorded days only" rule the 주의 badge and 고객 검색 use.
  final mean = series == null
      ? null
      : completionMean(series.completion)?.round();

  return WeeklyReport(
    isCurrentWeek: isThisWeek,
    client: client,
    weekStart: start,
    sessionsBooked: inWeek.length,
    sessionsDone: inWeek.where((s) => s.isDone).length,
    completionAvg: mean,
    // 초과일은 그 회원의 나트륨 목표로 센다 — 실서버 `sodium_over_days` 와
    // 같은 기준이다(#2885).
    sodiumOverDays: series == null
        ? null
        : sodiumOverDaysOf(series.sodium, sodiumLimitOf(targets.sodium)),
    sodiumAvg: series == null ? null : recordedMean(series.sodium)?.round(),
    weekCompletion: series?.completion ?? const <int?>[],
    days: series?.days ?? const <ReportDay>[],
    sodiumWeek: series?.sodium ?? const <int>[],
    caloriesWeek: series?.calories ?? const <int>[],
    sugarWeek: series?.sugar ?? const <double>[],
    carbsWeek: series?.carbs ?? const <double>[],
    proteinWeek: series?.protein ?? const <double>[],
    fatWeek: series?.fat ?? const <double>[],
    mealCounts: series?.mealCounts ?? const <int>[],
    calorieTarget: targets.calories,
    sodiumTarget: targets.sodium,
    sugarTarget: targets.sugar,
    carbsTarget: targets.carbs,
    proteinTarget: targets.protein,
    effectiveProteinTarget: targets.effectiveProtein,
    fatTarget: targets.fat,
    memberFeedback: memberFeedback,
    calorieBaseline: calorieBaseline,
  );
}

/// 이행률 평균 — 걸린 것이 있던 날(null 이 아닌 날)만. 0% 인 날도 든다(#2513).
double? completionMean(List<int?> week) {
  final List<int> recorded = <int>[for (final int? v in week) ?v];
  if (recorded.isEmpty) return null;
  return recorded.reduce((int a, int b) => a + b) / recorded.length;
}

/// 회원이 적어 둔 하루 목표 — 리포트 판정이 공통 상수보다 먼저 쓴다(#1430).
///
/// 실서버는 리포트 응답의 `*_target` 으로 받고(`weeklyReportFromJson`),
/// 데모는 건강 프로필에서 읽어 [buildWeeklyReport] 에 넘긴다(#2669). 적어 두지
/// 않은 칸은 null 이고, 그 칸만 공통 상수로 되돌아간다.
class ReportTargets {
  /// Creates targets. 기본값은 "목표 없음" 이다.
  const ReportTargets({
    this.calories,
    this.sodium,
    this.sugar,
    this.carbs,
    this.protein,
    this.effectiveProtein,
    this.fat,
  });

  final int? calories;
  final int? sodium;
  final double? sugar;
  final double? carbs;
  final double? protein;

  /// 실효 단백질 목표(#2898) — [WeeklyReport.effectiveProteinTarget].
  final double? effectiveProtein;
  final double? fat;
}

/// 리포트의 하루 — 이행률과 그날 배정된 운동.
class ReportDay implements ReportSheetDay {
  /// Creates a day.
  const ReportDay({
    required this.completion,
    this.exercises = const <String>[],
    this.assigned,
    this.assignedDone,
  });

  /// 그날 이행률(%). 0 은 기록이 없다는 뜻이다.
  @override
  final int completion;

  /// 배정된 운동 이름. 끝의 '✗' 는 건너뛴 운동을 뜻하는 저장 규칙이다 —
  /// 운동 기록 탭과 같은 규칙을 쓴다.
  @override
  final List<String> exercises;

  /// 그날 **배정된** 개인 운동 수. 모르면 null 이고, 그때는 [exercises] 의
  /// 길이가 분모가 된다. (#2232)
  ///
  /// 데모의 [exercises] 는 실제로 한 운동만 담아서(#1288) 하나도 안 한 날이
  /// 빈 목록으로 남는다 — 그 길이를 분모로 쓰면 `0 / 0` 이 되어, 리포트 ①
  /// 격자가 짚으려는 바로 그 날이 아무 일도 없던 날처럼 보인다.
  @override
  final int? assigned;

  /// 그중 그날 완료한 수(#3115). 모르면(옛 응답·데모) null 이다.
  @override
  final int? assignedDone;

  /// 완료한 운동 수 — 배정을 알면 그 완료, 모르면 건너뛰지 않은 운동 수.
  ///
  /// [exercises] 는 그날 남은 운동 기록 전부(직접 기록·PT 기록 포함)라, 분모가
  /// 그날 걸린 개인운동일 때 그 길이를 분자로 쓰면 실제보다 많아진다(#3115).
  int get done =>
      (assigned != null ? assignedDone : null) ??
      exercises.where((e) => !e.contains('✗')).length;

  /// 배정된 운동 수.
  int get total => assigned ?? exercises.length;
}

/// 한 주의 요일별 값 묶음(월→일). 데모는 drift 이력에서, 실서버는 리포트
/// 응답에서 만든다.
class WeekSeries {
  /// Creates a week's series.
  const WeekSeries({
    required this.completion,
    required this.sodium,
    required this.calories,
    required this.sugar,
    this.carbs = const <double>[],
    this.protein = const <double>[],
    this.fat = const <double>[],
    this.days = const <ReportDay>[],
    this.mealCounts = const <int>[],
  });

  /// 로스터가 준 이번 주 계열.
  factory WeekSeries.of(TrainerClient client) => WeekSeries(
    days: <ReportDay>[
      for (final rate in client.weekCompletion)
        ReportDay(completion: rate ?? 0),
    ],
    completion: client.weekCompletion,
    sodium: client.sodiumWeek,
    calories: client.caloriesWeek,
    sugar: client.sugarWeek,
  );

  /// 일별 이행률(%). 걸린 것이 없던 날은 null(#2513).
  final List<int?> completion;

  /// 일별 나트륨(mg).
  final List<int> sodium;

  /// 일별 칼로리(kcal).
  final List<int> calories;

  /// 일별 당류(g).
  final List<double> sugar;

  /// 일별 탄수화물·단백질·지방(g).
  final List<double> carbs;
  final List<double> protein;
  final List<double> fat;

  /// 요일별 상세. 데모는 drift 이력에서, 실서버는 리포트 응답에서 온다.
  final List<ReportDay> days;

  /// 일별 끼니 기록 횟수. 칼로리가 답하지 못하는 값이다(#2232) — 0kcal 인
  /// 날은 안 먹은 날이 아니라 안 적은 날이다.
  final List<int> mealCounts;
}

/// 나트륨 초과를 가르는 하루 기준(mg) — 회원 목표 [target], 없거나 0 이하면
/// 공통 기준. 실서버 `sodium_limit_mg` 와 같은 규칙이다(#2885).
int sodiumLimitOf(int? target) =>
    target != null && target > 0 ? target : sodiumTargetMg;

/// 나트륨 하루 기준 [limit](기본: 공통 기준)을 넘긴 날 수.
///
/// 리포트는 회원 목표를 넘긴다(#2885) — 공통 기준으로 세면 목표가 1,500mg 인
/// 회원의 1,800mg 날이 목표 안으로 읽힌다.
int sodiumOverDaysOf(List<int> sodium, [int limit = sodiumTargetMg]) =>
    sodium.where((mg) => mg > limit).length;

/// The message body sent to the member's chat thread.
///
/// Plain text on purpose: it lands in the same thread the member already
/// reads, so it must look like something their trainer wrote, not a
/// system dump.
String reportMessage(AppLocalizations l, WeeklyReport report) {
  final paragraphs = <String>[
    // 첫 줄에 무슨 메시지인지가 있어야 한다 — 회원의 대화방에는 다른 메시지도
    // 함께 쌓인다.
    l.reportBodyGreeting(report.client.name, report.rangeLabel(l)),
  ];

  final workout = _workoutSentences(l, report);
  final diet = _dietSentences(l, report);
  if (workout.isEmpty && diet.isEmpty) {
    // 인사말만 남았으면 가리킬 '이 부분'이 없다. 기록이 없는 주에 격려부터
    // 하면 회원이 무엇을 하라는 말인지 알 수 없다.
    paragraphs.add(l.reportBodyNoRecords);
    return paragraphs.join('\n\n');
  }
  if (workout.isNotEmpty) paragraphs.add(workout.join(' '));
  if (diet.isNotEmpty) paragraphs.add(diet.join(' '));

  final member = _memberFeedbackSentence(l, report.memberFeedback);
  if (member != null) paragraphs.add(member);

  // 다음 주 할 일은 그 주에 걸린 항목에서만 나온다. 판정과 제안이 같은 값을
  // 보므로, 칼로리를 넘긴 주에 "지금 루틴 그대로" 가 나가지 않는다(#2422).
  paragraphs.add(
    <String>[l.reportBodyNextWeek, ..._nextWeekTips(l, report)].join(' '),
  );
  paragraphs.add(
    report.isGoodWeek ? l.reportBodyPraise : l.reportBodyEncourage,
  );
  return paragraphs.join('\n\n');
}

/// 운동 문단 — PT 세션, 이행률, 개인 운동 개수, 빈 요일, 건너뛴 운동.
List<String> _workoutSentences(AppLocalizations l, WeeklyReport report) {
  final workout = <String>[];
  final completion = report.completionAvg;
  final hasWorkoutData = completion != null || _exerciseTotal(report) > 0;
  // PT 는 운동 기록이 있는 주에만 말한다. 아무것도 남지 않은 주에 "PT 0회"
  // 한 줄만 보내면 그 주를 정리한 글이 아니라 출석부가 된다.
  if (hasWorkoutData || report.sessionsBooked > 0) {
    workout.add(
      report.sessionsBooked == 0
          ? l.reportBodySessionsNone
          : report.sessionsDone >= report.sessionsBooked
          ? l.reportBodySessionsAll(report.sessionsBooked)
          : l.reportBodySessionsSome(
              report.sessionsBooked,
              report.sessionsDone,
            ),
    );
  }
  if (completion != null) {
    // 좋음·보통·낮음 세 구간 — 75% 에게 "잘 따라오셨어요" 도, "많이
    // 바쁘셨나 봐요" 도 맞지 않는다(#2345).
    workout.add(
      completion >= goodCompletionThreshold
          ? l.reportBodyCompletionGood(completion)
          : completion >= lowCompletionThreshold
          ? l.reportBodyCompletionSteady(completion)
          : l.reportBodyCompletionLow(completion),
    );
  }
  final total = _exerciseTotal(report);
  if (total > 0) {
    final done = report.days.fold<int>(0, (sum, d) => sum + d.done);
    workout.add(l.reportBodyExerciseCount(total, done.clamp(0, total)));
  }
  // 요일을 짚어 준다. `이행률 62%` 만으로는 회원이 무엇을 바꿔야 할지 알 수
  // 없지만, `화·목에 기록이 없었다` 는 그 자리에서 답이 나온다 — 그 이틀의
  // 일정을 바꾸면 된다(#2232).
  final List<String> silent = silentWeekdayNames(l, report);
  if (silent.isNotEmpty) {
    workout.add(l.reportBodySilentDays(silent.join(' · ')));
  } else if (report.weekCompletion.length == weekdayCount &&
      completion != null &&
      completion >= goodCompletionThreshold) {
    workout.add(l.reportBodySteadyDays(weekdayNames(l).last));
  }
  final skipped = _skippedNames(report);
  if (skipped.isNotEmpty) {
    workout.add(l.reportBodySkipped(_topicParticle(l, skipped.join(', '))));
  }
  // PT 한 줄만 남았으면 운동 문단이라 할 것이 없다.
  return hasWorkoutData ? workout : const <String>[];
}

int _exerciseTotal(WeeklyReport report) =>
    report.days.fold<int>(0, (sum, d) => sum + d.total);

/// 식단 문단 — 기록 일수, 칼로리·나트륨·당류를 각자의 목표와 견준다.
List<String> _dietSentences(AppLocalizations l, WeeklyReport report) {
  final diet = <String>[];
  final meals = _mealSentence(l, report);
  if (meals != null) diet.add(meals);

  final calorieMean = report.calorieMean;
  final gap = report.calorieGap;
  if (calorieMean != null && gap != null) {
    // 회원이 그대로 받는 문장이라 수치를 화면과 같은 서식으로 적는다 —
    // `1916mg` 은 그래프의 `1,916mg` 과 다른 값처럼 읽힌다. 목표도 문장에
    // 박아 두지 않는다: 기준이 바뀌면 문장만 옛말을 하게 된다(#1177).
    final avg = formatNumber(calorieMean.round());
    final target = formatNumber(report.calorieGoal);
    final pct = '${(gap.abs() * 100).round()}';
    final overDays = report.calorieOverDays;
    diet.add(
      gap > calorieTolerance
          ? l.reportBodyCaloriesOver(avg, target, pct, overDays)
          : gap < -calorieTolerance
          ? l.reportBodyCaloriesUnder(avg, target, pct)
          : overDays > 0
          ? l.reportBodyCaloriesNearOver(avg, target, overDays)
          : l.reportBodyCaloriesOk(avg, target),
    );
  }

  final sodium = report.sodiumAvg;
  if (sodium != null) {
    final over = report.sodiumOverDays ?? 0;
    final String avg = formatNumber(sodium);
    // 초과일을 센 기준과 같은 목표를 적는다(#2885).
    final String target = formatNumber(report.sodiumLimit);
    diet.add(
      over > 0
          ? l.reportBodySodiumOver(avg, target, over)
          : l.reportBodySodiumOk(avg, target),
    );
  }

  final sugarMean = report.sugarMean;
  if (sugarMean != null) {
    final avg = formatNumber(sugarMean.round());
    final target = formatNumber(report.sugarLimit.round());
    diet.add(
      report.sugarOverDays > 0
          ? l.reportBodySugarOver(avg, target, report.sugarOverDays)
          : l.reportBodySugarOk(avg, target),
    );
  }
  return diet;
}

/// 끼니를 적은 날 수. 이번 주라면 아직 오지 않은 날은 세지 않는다.
///
/// 하루도 적지 않은 주는 말하지 않는다 — 다른 기록도 없는 주라면 그 주는
/// `기록 없음` 한 줄로 끝나야 하고, 운동 기록만 있는 주라면 다음 주 할 일이
/// 끼니 기록을 권한다.
String? _mealSentence(AppLocalizations l, WeeklyReport report) {
  final total = _mealDaysDue(report);
  final days = report.mealLoggedDays;
  if (total == null || days == 0) return null;
  return days >= total
      ? l.reportBodyMealDaysAll(total)
      : l.reportBodyMealDays(total, days);
}

/// 끼니를 적었어야 할 날 수. 끼니 수를 모르는 자료면 null.
int? _mealDaysDue(WeeklyReport report) {
  if (report.mealCounts.length != weekdayCount) return null;
  // 끼니 수가 비어 있는데 칼로리가 있으면 끼니 수를 모르는 자료다 — `0일
  // 기록` 이라고 하면 적어 둔 식단을 없던 일로 만든다.
  if (report.mealLoggedDays == 0 && report.calorieMean != null) return null;
  final total = report.isCurrentWeek ? elapsedWeekdays(nowKst()) : weekdayCount;
  return total > 0 ? total : null;
}

/// 회원이 남긴 답에 대한 한 문장. 답이 없으면 null.
String? _memberFeedbackSentence(
  AppLocalizations l,
  MemberWeeklyFeedback? feedback,
) {
  if (feedback == null) return null;
  if (feedback.hasPain) {
    return l.reportBodyMemberPain(withParticle(l, feedback.painArea, '이', '가'));
  }
  return switch (feedback.intensity) {
    WeekIntensity.tooHard => l.reportBodyMemberTooHard,
    WeekIntensity.tooEasy => l.reportBodyMemberTooEasy,
    _ => l.reportBodyMemberNoted,
  };
}

/// 다음 주에 할 일. 걸린 항목이 없을 때만 `지금 루틴 유지` 를 권한다.
List<String> _nextWeekTips(AppLocalizations l, WeeklyReport report) {
  final tips = <String>[];
  final gap = report.calorieGap;
  if (gap != null && report.caloriesOffTarget) {
    tips.add(gap < 0 ? l.reportTipCaloriesUnder : l.reportTipCaloriesOver);
  }
  if (report.sugarOverLimit) tips.add(l.reportTipSugar);
  if ((report.sodiumOverDays ?? 0) > 2) tips.add(l.reportTipSodium);
  final completion = report.completionAvg;
  if ((completion != null && completion < goodCompletionThreshold) ||
      silentWeekdayNames(l, report).isNotEmpty) {
    tips.add(l.reportTipWorkout);
  }
  final due = _mealDaysDue(report);
  if (due != null && report.mealLoggedDays < due) tips.add(l.reportTipMeals);
  if (report.sessionsBooked == 0) {
    tips.add(l.reportTipSessionsNone);
  } else if (!report.isCurrentWeek &&
      report.sessionsDone < report.sessionsBooked) {
    tips.add(l.reportTipSessionsMissed);
  }
  if (tips.isEmpty || (tips.length == 1 && report.sessionsBooked == 0)) {
    tips.add(l.reportTipKeep);
  }
  return tips;
}

/// 그 주에 기록이 하나도 없던 요일 이름.
///
/// 이번 주라면 아직 오지 않은 요일은 세지 않는다 — 목요일에 "금·토·일이
/// 비었다" 고 하면 오지도 않은 날을 나무라는 말이 된다.
List<String> silentWeekdayNames(AppLocalizations l, WeeklyReport report) {
  // 0 은 걸렸는데 하나도 안 한 날이다. 걸린 것이 없던 날(null)은 회원이
  // 비운 날이 아니다(#2513).
  final List<int?> week = report.weekCompletion;
  if (week.length != weekdayCount) return const <String>[];
  final int upTo = report.isCurrentWeek
      ? elapsedWeekdays(nowKst())
      : weekdayCount;
  final List<String> names = weekdayNames(l);
  final found = <String>[
    for (int i = 0; i < upTo && i < week.length; i++)
      if (week[i] == 0) names[i],
  ];
  // 하루쯤 쉬는 것은 그 주의 이야기가 아니다. 이틀부터가 일정의 문제다.
  return found.length >= 2 ? found : const <String>[];
}

/// 그 주에 건너뛴 운동 이름. 이행률이 왜 100%가 아닌지의 답이다.
///
/// 분량을 뗀 이름으로 묶는다 — 같은 스트레칭을 요일마다 건너뛰면 예전에는
/// `하체 스트레칭 10분, 하체 스트레칭 5분, 하체 스트레칭 15분` 이 되어, 서로
/// 다른 운동 셋을 빠뜨린 것처럼 읽혔다(#1177).
List<String> _skippedNames(WeeklyReport report) {
  final names = <String>[];
  for (final day in report.days) {
    for (final line in day.exercises) {
      if (!line.contains('✗')) continue;
      final name = exerciseBaseName(line);
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
  }
  return names.take(3).toList(growable: false);
}

/// 운동 한 줄에서 분량 표기를 떼어 낸 이름.
///
/// 저장 규칙은 `하체 스트레칭 10분`, `벤치프레스 4세트 · 10회 · 40kg` 처럼 이름 뒤에
/// 그날의 분량이 붙는다. 초안·요약이 운동을 **묶어 세는** 자리에서는 그 분량이
/// 서로 다른 운동으로 갈라 놓는다.
///
/// 분량은 하나가 아닐 수 있다 — 근력 한 줄은 세트·횟수·중량 셋을 잇달아 단다
/// (`레그프레스 3세트 12회 80kg`, #1276). 뒤에서부터 붙어 있는 만큼 뗀다:
/// 한 번만 떼면 `레그프레스 3세트 12회` 가 남아, 같은 운동이 무게를 올린 날마다
/// 다른 운동으로 세어졌다.
String exerciseBaseName(String line) {
  var name = line.replaceAll('✗', '').replaceAll('✓', '').trim();
  final cut = name.indexOf('·');
  if (cut > 0) name = name.substring(0, cut).trim();
  // 영어 분량(`30 min`, `12 reps`)도 뗀다 — 영어 리포트에서 같은 운동이
  // 분량마다 다른 운동으로 세어지지 않게(#2885).
  final RegExp amount = RegExp(
    r'\s*\d+(?:\.\d+)?\s*(?:분|초|kg|km|회|세트|mins?|secs?|reps?|sets?)$',
    caseSensitive: false,
  );
  while (amount.hasMatch(name)) {
    name = name.replaceAll(amount, '').trim();
  }
  return name;
}

/// `은`/`는` 을 받침에 맞춰 붙인다. 규칙은 [withTopicJosa] 에 있다.
String _topicParticle(AppLocalizations l, String word) =>
    withParticle(l, word, '은', '는');
