import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/korean_josa.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount;
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

export 'package:oncare_trainer/core/utils/korean_josa.dart'
    show hasFinalConsonant;

/// Monday of the week containing [day], stripped to a date.
DateTime weekStartOf(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

/// One client's week, as the trainer would summarise it to them.
///
/// This is the retention loop of an O2O coaching product: the member
/// stays because they can see they improved. Everything here is derived
/// from data the two apps already share — no new tracking.
class WeeklyReport {
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
    this.weekCompletion = const <int>[],
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
    this.days = const <ReportDay>[],
    this.mealCounts = const <int>[],
    this.memberFeedback,
    this.weekGoals = const <String>[],
  });

  /// Who the report is about.
  final TrainerClient client;

  /// Monday of the reported week.
  final DateTime weekStart;

  /// PT sessions booked in the week.
  final int sessionsBooked;

  /// Of those, how many were completed.
  final int sessionsDone;

  /// Mean routine completion (%) across recorded days; null when the
  /// client logged nothing.
  final int? completionAvg;

  /// Days over the sodium target; null when unknown for this week.
  final int? sodiumOverDays;

  /// Mean daily sodium (mg); null when there's no history.
  final int? sodiumAvg;

  /// Whether [weekStart] is the week we're currently in. Charts no longer
  /// depend on this — the report carries its own week — but the headline
  /// still says "이번 주" or "선택 주".
  final bool isCurrentWeek;

  /// 그 주(월→일)의 요일별 값. **로스터의 같은 이름 필드를 쓰지 않는다** —
  /// 그건 이번 주 것이라, 과거 주를 열면 지난 주 날짜 아래 이번 주 수치가
  /// 실린다. 트레이너는 그 리포트를 회원에게 그대로 보낼 수 있다(#752).
  final List<int> weekCompletion;

  /// 그 주의 일별 나트륨(mg).
  final List<int> sodiumWeek;

  /// 그 주의 일별 칼로리(kcal).
  final List<int> caloriesWeek;

  /// 그 주의 일별 당류(g). 소수를 유지한다.
  final List<double> sugarWeek;

  /// 그 주의 일별 탄수화물·단백질·지방(g).
  ///
  /// 칼로리 총량만으로는 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지
  /// 알 수 없다 — 비교 그래프가 칼로리를 이 셋으로 쌓아 그린다(#1177).
  final List<double> carbsWeek;
  final List<double> proteinWeek;
  final List<double> fatWeek;

  /// 그 회원이 적어 둔 하루 목표. 없으면 null 이고, 판정 쪽이 공통 상수로
  /// 되돌아간다(#1430) — 같은 1,900kcal 이 어떤 회원에게는 부족이고 어떤
  /// 회원에게는 초과다. null 과 상수를 구분해 둬야 근거 문장이 어느 기준을
  /// 썼는지 말할 수 있다.
  final int? calorieTarget;
  final int? sodiumTarget;
  final double? sugarTarget;
  final double? carbsTarget;
  final double? proteinTarget;
  final double? fatTarget;

  /// 요일별 상세(월→일). 이행률과 그날 배정된 운동을 함께 담는다 — 67% 가
  /// 어디서 나온 값인지 화면에서 보이게 하는 자료다(#754).
  final List<ReportDay> days;

  /// 그 주의 요일별 **끼니 기록 횟수**. (#2232)
  ///
  /// 칼로리 계열로는 이걸 대신할 수 없다. 0kcal 인 날은 "안 먹었다"가 아니라
  /// "안 적었다"이고, 리포트 ① 격자가 짚으려는 것이 정확히 그 날들이다.
  final List<int> mealCounts;

  /// 회원이 그 주에 남긴 세 문항. 아직 안 냈으면 null. (#2232)
  ///
  /// 수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽힌다.
  /// 그 둘은 다음 주 처방이 정반대라, 갈림길은 회원 본인의 답이 정한다.
  final MemberWeeklyFeedback? memberFeedback;

  /// 그 주에 **적용되어 있던** 목표 — 지난 주에 트레이너가 ② 에서 고른 것이다.
  ///
  /// 리포트 ③ 이 이걸 회수해 달성 여부를 판정한다. 회수되지 않는 목표는
  /// 공수표라, 목표를 고르는 화면(②)만 있고 이 자리가 비면 기능이 반쪽이다.
  final List<String> weekGoals;

  /// Sunday of the reported week.
  DateTime get weekEnd => weekStart.add(const Duration(days: 6));

  /// `M월 D일 – M월 D일` / `M/D – M/D`, in the current locale.
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
  bool get isGoodWeek =>
      (completionAvg ?? 0) >= 70 && (sodiumOverDays ?? 99) <= 2;
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
  List<String> weekGoals = const <String>[],
}) {
  final start = weekStartOf(weekStart);
  final end = start.add(const Duration(days: 6));
  final inWeek = sessions.where((s) {
    final day = DateTime.tryParse(s.date);
    if (day == null || s.isGap) return false;
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList();

  // 로스터가 준 계열(`client.*Week`)은 **이번 주** 것이라 그 주에만 붙인다.
  // 과거 주에 붙이면 지난 주 날짜 아래 이번 주 수치가 실리고, 트레이너는 그
  // 리포트를 회원에게 그대로 보낼 수 있다. 과거 주의 계열은 호출자가
  // [week] 로 넘겨 준다(데모는 drift 이력에서, 실서버는 리포트 응답에서).
  final isThisWeek = start == weekStartOf(today ?? nowKst());
  final series = week ?? (isThisWeek ? WeekSeries.of(client) : null);
  // Same "recorded days only" rule the 주의 badge and 고객 검색 use.
  final mean = series == null ? null : recordedMean(series.completion)?.round();

  return WeeklyReport(
    isCurrentWeek: isThisWeek,
    client: client,
    weekStart: start,
    sessionsBooked: inWeek.length,
    sessionsDone: inWeek.where((s) => s.isDone).length,
    completionAvg: mean,
    sodiumOverDays: series == null ? null : sodiumOverDaysOf(series.sodium),
    sodiumAvg: series == null ? null : recordedMean(series.sodium)?.round(),
    weekCompletion: series?.completion ?? const <int>[],
    days: series?.days ?? const <ReportDay>[],
    sodiumWeek: series?.sodium ?? const <int>[],
    caloriesWeek: series?.calories ?? const <int>[],
    sugarWeek: series?.sugar ?? const <double>[],
    carbsWeek: series?.carbs ?? const <double>[],
    proteinWeek: series?.protein ?? const <double>[],
    fatWeek: series?.fat ?? const <double>[],
    mealCounts: series?.mealCounts ?? const <int>[],
    memberFeedback: memberFeedback,
    weekGoals: weekGoals,
  );
}

/// 리포트의 하루 — 이행률과 그날 배정된 운동.
class ReportDay {
  /// Creates a day.
  const ReportDay({
    required this.completion,
    this.exercises = const <String>[],
    this.assigned,
  });

  /// 그날 이행률(%). 0 은 기록이 없다는 뜻이다.
  final int completion;

  /// 배정된 운동 이름. 끝의 '✗' 는 건너뛴 운동을 뜻하는 저장 규칙이다 —
  /// 운동 기록 탭과 같은 규칙을 쓴다.
  final List<String> exercises;

  /// 그날 **배정된** 개인 운동 수. 모르면 null 이고, 그때는 [exercises] 의
  /// 길이가 분모가 된다. (#2232)
  ///
  /// 데모의 [exercises] 는 실제로 한 운동만 담아서(#1288) 하나도 안 한 날이
  /// 빈 목록으로 남는다 — 그 길이를 분모로 쓰면 `0 / 0` 이 되어, 리포트 ①
  /// 격자가 짚으려는 바로 그 날이 아무 일도 없던 날처럼 보인다.
  final int? assigned;

  /// 건너뛰지 않은 운동 수.
  int get done => exercises.where((e) => !e.contains('✗')).length;

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
      for (final rate in client.weekCompletion) ReportDay(completion: rate),
    ],
    completion: client.weekCompletion,
    sodium: client.sodiumWeek,
    calories: client.caloriesWeek,
    sugar: client.sugarWeek,
  );

  /// 일별 이행률(%).
  final List<int> completion;

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

/// 기록된 날(0 초과)만의 평균. 하나도 없으면 null — 0 으로 보고하면
/// "아무것도 안 했다"는 거짓말이 된다.
double? recordedMean(List<num> series) {
  final recorded = series.where((v) => v > 0).toList(growable: false);
  if (recorded.isEmpty) return null;
  // fold<double> 로 더한다 — `List<int>` 를 `List<num>` 으로 받으면 reduce 의
  // 결합 함수가 런타임 타입(int)과 맞지 않아 던진다.
  return recorded.fold<double>(0, (sum, v) => sum + v) / recorded.length;
}

/// 나트륨 목표를 넘긴 날 수.
int sodiumOverDaysOf(List<int> sodium) =>
    sodium.where((mg) => mg > sodiumTargetMg).length;

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

  final workout = <String>[];
  final completion = report.completionAvg;
  if (completion != null) {
    workout.add(
      completion >= 70
          ? l.reportBodyCompletionGood(completion)
          : l.reportBodyCompletionLow(completion),
    );
  }
  // 요일을 짚어 준다. `이행률 62%` 만으로는 회원이 무엇을 바꿔야 할지 알 수
  // 없지만, `화·목에 기록이 없었다` 는 그 자리에서 답이 나온다 — 그 이틀의
  // 일정을 바꾸면 된다(#2232).
  final List<String> silent = silentWeekdayNames(l, report);
  if (silent.isNotEmpty) {
    workout.add(l.reportBodySilentDays(silent.join(' · ')));
  } else if (report.weekCompletion.length == weekdayCount &&
      completion != null &&
      completion >= 70) {
    workout.add(l.reportBodySteadyDays(weekdayNames(l).last));
  }
  final skipped = _skippedNames(report);
  if (skipped.isNotEmpty) {
    workout.add(l.reportBodySkipped(_topicParticle(l, skipped.join(', '))));
  }
  if (workout.isNotEmpty) paragraphs.add(workout.join(' '));

  final diet = <String>[];
  final sodium = report.sodiumAvg;
  if (sodium != null) {
    final over = report.sodiumOverDays ?? 0;
    // 회원이 그대로 받는 문장이라 수치를 화면과 같은 서식으로 적는다 —
    // `1916mg` 은 그래프의 `1,916mg` 과 다른 값처럼 읽힌다. 목표도 문장에
    // 박아 두지 않는다: 기준이 바뀌면 문장만 옛말을 하게 된다(#1177).
    final String avg = formatNumber(sodium);
    final String target = formatNumber(sodiumTargetMg);
    diet.add(
      over > 0
          ? l.reportBodySodiumOver(avg, target, over)
          : l.reportBodySodiumOk(avg, target),
    );
  }
  final recorded = report.caloriesWeek.where((v) => v > 0).toList();
  if (recorded.isNotEmpty) {
    final mean = recorded.fold<double>(0, (a, b) => a + b) / recorded.length;
    diet.add(l.reportBodyCalories(formatNumber(mean.round())));
  }
  if (diet.isNotEmpty) paragraphs.add(diet.join(' '));

  paragraphs.add(
    // 인사말만 남았으면 가리킬 '이 부분'이 없다. 기록이 없는 주에 격려부터
    // 하면 회원이 무엇을 하라는 말인지 알 수 없다.
    paragraphs.length == 1
        ? l.reportBodyNoRecords
        : (report.isGoodWeek ? l.reportBodyPraise : l.reportBodyEncourage),
  );
  return paragraphs.join('\n\n');
}

/// 그 주에 기록이 하나도 없던 요일 이름.
///
/// 이번 주라면 아직 오지 않은 요일은 세지 않는다 — 목요일에 "금·토·일이
/// 비었다" 고 하면 오지도 않은 날을 나무라는 말이 된다.
List<String> silentWeekdayNames(AppLocalizations l, WeeklyReport report) {
  final List<int> week = report.weekCompletion;
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
  final RegExp amount = RegExp(r'\s*\d+(?:\.\d+)?\s*(?:분|초|kg|km|회|세트)$');
  while (amount.hasMatch(name)) {
    name = name.replaceAll(amount, '').trim();
  }
  return name;
}

/// `은`/`는` 을 받침에 맞춰 붙인다. 규칙은 [withTopicJosa] 에 있다.
String _topicParticle(AppLocalizations l, String word) =>
    withParticle(l, word, '은', '는');

/// 한국어일 때만 받침에 맞는 조사를 붙인다. 다른 언어에는 조사가 없다 —
/// 영어 문장에 `Squat은` 이 남으면 안 된다.
String withParticle(
  AppLocalizations l,
  String word,
  String afterConsonant,
  String afterVowel,
) {
  if (l.localeName != 'ko') return word;
  return '$word${hasFinalConsonant(word) ? afterConsonant : afterVowel}';
}

/// The trainer's own week — the numbers that answer "how am I doing?".
class TrainerWeekStats {
  /// Creates the stats.
  const TrainerWeekStats({
    required this.sessionsBooked,
    required this.sessionsDone,
    required this.activeClients,
    required this.programsSent,
  });

  /// Sessions booked this week.
  final int sessionsBooked;

  /// Sessions completed this week.
  final int sessionsDone;

  /// Clients marked 활성.
  final int activeClients;

  /// Sessions that carry a program (i.e. a routine was prepared).
  final int programsSent;

  /// Completion rate as a percentage; null when nothing was booked.
  int? get completionRate => sessionsBooked == 0
      ? null
      : ((sessionsDone / sessionsBooked) * 100).round();
}

/// Aggregates the trainer's week from every session in the range.
TrainerWeekStats buildTrainerWeekStats({
  required List<ScheduleSession> sessions,
  required List<TrainerClient> clients,
}) {
  final booked = sessions.where((s) => !s.isGap).toList();
  return TrainerWeekStats(
    sessionsBooked: booked.length,
    sessionsDone: booked.where((s) => s.isDone).length,
    activeClients: clients.where((c) => c.active).length,
    programsSent: booked.where((s) => s.program.isNotEmpty).length,
  );
}
