/// 데모 김민수의 결과지 자료 — 트레이너 웹 데모와 **같은 규칙**으로 만든다. (#2652)
///
/// 트레이너 웹 데모는 픽스처(`demo_fixture`)를 drift 에 심고, 거기서 리포트를
/// 읽는다. 회원 앱 데모에는 그 저장소가 없으므로 같은 픽스처에서 같은 규칙으로
/// 바로 만든다. 규칙은 트레이너 웹 시드와 한 쌍이다 — 한쪽을 바꾸면 다른 쪽도
/// 바꿔야 두 앱이 같은 주를 같은 결과지로 보여 준다.
///
/// - 요일별 수치: 기록이 있는 날만, 픽스처 값 그대로(끼니 수·배정 수 포함).
/// - PT: 픽스처가 PT 날로 적은 지난 날마다 한 번, 그리고 이번 주에는 오늘
///   수업 한 번이다. 모두 진행했다 — 트레이너 웹 시드의 `seed-schedule-f…`
///   행과 오늘 수업 행과 같다(#2694).
/// - 목표: 회원이 적어 둔 하루 목표가 없어 공통 기본값으로 판정한다.
/// - 운동 추이: 실제로 한 운동을 유형별로 더한다(근력은 세트).
/// - 회원 답: 트레이너 웹 시드의 김민수 답과 같다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:oncare_report/src/report_sheet_data.dart';
import 'package:oncare_report/src/report_sheet_values.dart';

/// 데모 리포트 이력이 닿는 주 수(이번 주 포함) — 트레이너 웹
/// `demoReportHistoryWeeks` 와 같다. 이 창보다 앞선 주에는 픽스처 PT 날도 없다.
const int kDemoReportPtWeeks = 14;

/// 김민수가 MY 에 적어 둔 주간 운동 목표 — 트레이너 웹
/// `seedHealthProfiles[1]` 과 같다.
const ReportSheetGoals kDemoReportGoals = ReportSheetGoals(
  weeklyCardioMinutes: 180,
  weeklyStrengthSets: 18,
  // 스트레칭은 기본값(60분) 그대로다.
);

/// 근력 한 세트를 몇 분으로 보는가 — 세트 수 없이 분만 남은 기록을 세트로
/// 바꿀 때 쓴다. 두 앱의 `kStrengthMinutesPerSet` 과 같다.
const double kDemoStrengthMinutesPerSet = 3;

/// 김민수가 한 주를 끝내며 낸 답 하나.
class DemoReportAnswer {
  /// Creates an answer.
  const DemoReportAnswer({
    required this.weeksAgo,
    required this.condition,
    required this.intensity,
    this.painArea = '',
    this.painAreaEn = '',
    this.painDay = 0,
    this.note = '',
    this.noteEn = '',
  });

  /// 0 이면 이번 주, 1 이면 지난 주.
  final int weeksAgo;

  /// `great` · `good` · `ok` · `tired` · `bad`.
  final String condition;

  /// `too_easy` · `right` · `hard` · `too_hard`.
  final String intensity;

  /// 아픈 곳(한국어·영어).
  final String painArea;
  final String painAreaEn;

  /// 통증이 있던 요일(0 = 월).
  final int painDay;

  /// 한 줄 메모(한국어·영어).
  final String note;
  final String noteEn;

  /// [weekStart] 주의 답을 [languageCode] 로.
  ReportSheetAnswersData toAnswers(DateTime weekStart, String languageCode) {
    final bool en = languageCode == 'en';
    final String area = en ? painAreaEn : painArea;
    return ReportSheetAnswersData(
      conditionWire: condition,
      intensityWire: intensity,
      painArea: area,
      painOn: area.isEmpty
          ? null
          : DateTime(weekStart.year, weekStart.month, weekStart.day + painDay),
      note: en ? noteEn : note,
    );
  }
}

/// 김민수의 주별 답 — 트레이너 웹 시드(`_demoFeedback[1]`)와 같다. 9주 전은
/// 메모 없이 답만 냈고, 13주 전부터는 답이 없다.
const List<DemoReportAnswer> kDemoReportAnswers = <DemoReportAnswer>[
  DemoReportAnswer(
    weeksAgo: 0,
    condition: 'ok',
    intensity: 'too_hard',
    painArea: '오른쪽 어깨',
    painAreaEn: 'Right shoulder',
    painDay: 3,
    note: '야근이 많아서 저녁 운동을 못 갔어요. 벤치 할 때 어깨가 좀 걸리는 느낌이 있습니다.',
    noteEn:
        'Lots of late nights, so I missed my evening workouts. My shoulder catches a bit on the bench.',
  ),
  DemoReportAnswer(
    weeksAgo: 1,
    condition: 'good',
    intensity: 'right',
    note: '지난주보다 컨디션은 나았는데 저녁 단백질은 계속 놓쳤어요.',
    noteEn:
        'I felt better than last week, but I kept missing protein at dinner.',
  ),
  DemoReportAnswer(
    weeksAgo: 2,
    condition: 'tired',
    intensity: 'right',
    note: '회식이 세 번이나 있어서 술이랑 안주를 많이 먹었어요. 운동은 그래도 빠지지 않았어요.',
    noteEn:
        'Three team dinners this week, so plenty of drinks and bar food. I still made every workout.',
  ),
  DemoReportAnswer(
    weeksAgo: 3,
    condition: 'good',
    intensity: 'right',
    note: '국물 절반 남기기 해 봤는데 생각보다 어렵지 않았어요.',
    noteEn: 'I tried leaving half the soup, and it was easier than I expected.',
  ),
  DemoReportAnswer(
    weeksAgo: 4,
    condition: 'ok',
    intensity: 'right',
    note: '구내식당 메뉴가 거의 국이라 나트륨 조절이 힘들었어요.',
    noteEn:
        'The cafeteria served soup almost every day, so sodium was hard to control.',
  ),
  DemoReportAnswer(
    weeksAgo: 5,
    condition: 'tired',
    intensity: 'hard',
    note: '야근 때문에 저녁을 늦게 먹어서 기록을 몇 번 빼먹었어요.',
    noteEn:
        'Late nights meant late dinners, and I skipped logging a few of them.',
  ),
  DemoReportAnswer(
    weeksAgo: 6,
    condition: 'ok',
    intensity: 'hard',
    note: '기록하는 게 아직 익숙하지 않아서 빠진 날이 있어요.',
    noteEn: 'Logging still feels new, so I missed a day or two.',
  ),
  DemoReportAnswer(
    weeksAgo: 7,
    condition: 'ok',
    intensity: 'right',
    note: '화·목은 여전히 바빴지만 나머지 날은 계획대로 했어요.',
    noteEn:
        'Tuesdays and Thursdays were still busy, but I stuck to the plan on the other days.',
  ),
  DemoReportAnswer(
    weeksAgo: 8,
    condition: 'good',
    intensity: 'too_easy',
    note: '이번 주는 몸이 가벼웠어요. 걷기 시간을 조금 늘려도 될 것 같아요.',
    noteEn: 'I felt light this week. I think I can walk a little longer.',
  ),
  DemoReportAnswer(weeksAgo: 9, condition: 'tired', intensity: 'right'),
  DemoReportAnswer(
    weeksAgo: 10,
    condition: 'good',
    intensity: 'right',
    note: '아침에 혈압을 재 보니 전보다 조금 내려갔어요.',
    noteEn: 'My morning blood pressure reading came down a little.',
  ),
  DemoReportAnswer(
    weeksAgo: 11,
    condition: 'ok',
    intensity: 'hard',
    painArea: '오른쪽 무릎',
    painAreaEn: 'Right knee',
    painDay: 3,
    note: '스쿼트 뒤로 계단 내려갈 때 무릎이 살짝 시큰했어요.',
    noteEn: 'After squats my knee twinged a bit going down stairs.',
  ),
  DemoReportAnswer(
    weeksAgo: 12,
    condition: 'tired',
    intensity: 'too_hard',
    note: '야근이 이어져서 운동 강도가 버거웠어요.',
    noteEn: 'Back-to-back late nights made the workouts feel too heavy.',
  ),
];

/// [weekStart] 주의 김민수 결과지 자료 — 그 주, 직전 네 주, 여덟 주 운동 추이.
///
/// [now] 는 지금 서울 시각이다. 픽스처는 [now] 까지의 날만 날짜를 붙인다 —
/// 오지 않은 요일은 비어 있다. [languageCode] 는 회원 답을 옮길 언어다.
ReportSheetInputs demoReportSheetInputs({
  required DemoFixture fixture,
  required DateTime weekStart,
  required DateTime now,
  String languageCode = 'ko',
}) {
  final DateTime monday = reportWeekStartOf(weekStart);
  final List<FixtureDay> days = fixture.daysFor(now);
  final DateTime thisMonday = reportWeekStartOf(now);
  ReportSheetWeekData week(DateTime start) => demoReportSheetWeek(
    fixture: fixture,
    days: days,
    weekStart: start,
    thisMonday: thisMonday,
    today: now,
    languageCode: languageCode,
  );
  return ReportSheetInputs(
    week: week(monday),
    history: <ReportSheetWeek>[
      for (int back = 1; back <= kReportSheetHistoryWeeks; back++)
        week(_addDays(monday, -7 * back)),
    ],
    trend: ReportSheetTrendData(
      goals: kDemoReportGoals,
      weeks: <ReportSheetTrendWeek>[
        for (int back = kReportSheetTrendWeeks - 1; back >= 0; back--)
          demoReportTrendWeek(days, _addDays(monday, -7 * back)),
      ],
    ),
  );
}

/// 한 주의 김민수 — 트레이너 웹 데모의 `buildWeeklyReport` 와 같은 값.
ReportSheetWeekData demoReportSheetWeek({
  required DemoFixture fixture,
  required List<FixtureDay> days,
  required DateTime weekStart,
  required DateTime thisMonday,
  DateTime? today,
  String languageCode = 'ko',
}) {
  final DateTime monday = reportWeekStartOf(weekStart);
  final String mondayYmd = _ymd(monday);
  // 기록이 있는 날만 — 트레이너 웹 시드도 기록 없는 날은 행을 만들지 않는다.
  final Map<int, FixtureDay> byWeekday = <int, FixtureDay>{
    for (final FixtureDay d in days)
      if (d.weekStart == mondayYmd && d.hasRecord)
        DateTime.parse(d.date).weekday - 1: d,
  };
  final int back = _weeksBetween(monday, thisMonday);
  // 지난 PT 는 픽스처가 PT 날로 적은 날이고, 오늘 수업은 오늘 일정이 갖는다 —
  // 트레이너 웹 시드도 오늘의 픽스처 PT 날은 건너뛰고 오늘 일정으로 세운다.
  final String? todayYmd = today == null ? null : _ymd(today);
  final int pastPt = days
      .where(
        (FixtureDay d) =>
            d.weekStart == mondayYmd && d.isPt && d.date != todayYmd,
      )
      .length;
  final int sessions = pastPt + (back == 0 ? 1 : 0);
  DemoReportAnswer? answer;
  for (final DemoReportAnswer a in kDemoReportAnswers) {
    if (a.weeksAgo == back) answer = a;
  }
  final ReportSheetAnswersData? answers = answer?.toAnswers(
    monday,
    languageCode,
  );
  if (byWeekday.isEmpty) {
    // 기록이 하나도 없는 주 — 계열 없이 `미집계` 로 선다.
    return ReportSheetWeekData(
      memberName: fixture.memberName,
      weekStart: monday,
      sessionsBooked: sessions,
      sessionsDone: sessions,
      completionAvg: null,
      sodiumAvg: null,
      isCurrentWeek: back == 0,
      answers: answers,
    );
  }
  List<T> series<T extends num>(T zero, T Function(FixtureDay d) pick) => <T>[
    for (int i = 0; i < kReportWeekdayCount; i++)
      byWeekday[i] == null ? zero : pick(byWeekday[i]!),
  ];
  final List<int> completion = series<int>(0, (FixtureDay d) => d.completion);
  final List<int> sodium = series<int>(0, (FixtureDay d) => d.sodiumMg);
  return ReportSheetWeekData(
    memberName: fixture.memberName,
    weekStart: monday,
    sessionsBooked: sessions,
    sessionsDone: sessions,
    completionAvg: recordedMean(completion)?.round(),
    sodiumAvg: recordedMean(sodium)?.round(),
    isCurrentWeek: back == 0,
    weekCompletion: completion,
    sodiumWeek: sodium,
    caloriesWeek: series<int>(0, (FixtureDay d) => d.calories),
    sugarWeek: series<double>(0, (FixtureDay d) => d.sugarG),
    carbsWeek: series<double>(0, (FixtureDay d) => d.carbsG),
    proteinWeek: series<double>(0, (FixtureDay d) => d.proteinG),
    fatWeek: series<double>(0, (FixtureDay d) => d.fatG),
    mealCounts: series<int>(0, (FixtureDay d) => d.meals.length),
    days: <ReportSheetDay>[
      for (int i = 0; i < kReportWeekdayCount; i++)
        ReportSheetDayData(
          completion: byWeekday[i]?.completion ?? 0,
          // 요일 칸은 실제로 한 운동만 적는다 — 트레이너 웹 시드와 같다.
          exercises: <String>[
            for (final FixtureExercise e
                in byWeekday[i]?.doneExercises ?? const <FixtureExercise>[])
              e.name,
          ],
          // 0 은 "배정을 모른다" — 쉬는 날을 `0 / 0` 으로 적지 않는다.
          assigned: (byWeekday[i]?.exercises.length ?? 0) > 0
              ? byWeekday[i]!.exercises.length
              : null,
        ),
    ],
    answers: answers,
  );
}

/// 한 주의 유형별 운동 실적 — 트레이너 웹 데모의 픽스처 운동 주와 같은 규칙.
ReportSheetTrendWeekData demoReportTrendWeek(
  List<FixtureDay> days,
  DateTime weekStart,
) {
  final String mondayYmd = _ymd(reportWeekStartOf(weekStart));
  int cardio = 0;
  int strength = 0;
  int stretching = 0;
  for (final FixtureDay day in days) {
    if (day.weekStart != mondayYmd) continue;
    for (final FixtureExercise e in day.doneExercises) {
      switch (e.type) {
        case 'strength':
          strength +=
              e.sets ?? (e.minutes / kDemoStrengthMinutesPerSet).round();
        case 'flexibility' || 'stretching' || 'yoga':
          stretching += e.minutes;
        case 'cardio' || 'walking':
          cardio += e.minutes;
      }
    }
  }
  return ReportSheetTrendWeekData(
    weekStart: reportWeekStartOf(weekStart),
    cardioMinutes: cardio,
    strengthSets: strength,
    stretchingMinutes: stretching,
  );
}

/// [from] 주에서 [to] 주까지 몇 주인가(둘 다 월요일).
int _weeksBetween(DateTime from, DateTime to) =>
    (DateTime.utc(
              to.year,
              to.month,
              to.day,
            ).difference(DateTime.utc(from.year, from.month, from.day)).inDays /
            7)
        .round();

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
