import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// 데모 회원의 지난 리포트 이력. (#2399)
///
/// 데모 전송 기록은 예전에 **이번 주**에만 붙어, 주 이동으로 지난 주에 가면
/// 열다섯 명이 전부 미전송으로 섰다. PT 를 석 달 넘게 굴려 온 트레이너의
/// 작업대가 지난 주마다 비어 있으면 데모가 거짓말을 한다. 이 파일은 데모
/// 로스터 한 사람 한 사람의 지난 주 리포트를 **결정적으로** 만든다 — 같은
/// 회원·같은 주·같은 오늘이면 새로고침해도 같은 시각·같은 글이다.
///
/// 이번 주는 여기서 정하지 않는다. 작업대의 두 열을 가르는 [demoSentReports]
/// 가 정하고, 이 파일은 그 명단을 이력의 맨 위 한 줄로 그대로 옮긴다.
///
/// 실서버 로스터에는 `seed-client-*` 가 없어 여기서 나오는 것이 없다.

/// 데모 이력이 거슬러 올라가는 주 수(이번 주 포함). 지난 주만 열세 주 —
/// 석 달을 넘겨 "최근 3개월" 을 어느 요일에 열어도 채운다.
const int demoReportHistoryWeeks = 14;

/// 데모 로스터의 한 사람 — 이력을 만드는 데 필요한 것만 든다.
///
/// [goal] 은 로스터에 심긴 그대로의 목표다(`체중 감량 · 혈압 관리`,
/// `Weight loss · Blood pressure`). 피드백 문구가 이 목표를 따라간다.
typedef DemoReportMember = ({String id, String goal});

/// 데모 회원 한 명의 한 주 — 보냈으면 [record], 안 보냈으면 null.
class DemoReportWeek {
  /// Creates a week.
  const DemoReportWeek({required this.weekStart, this.record});

  /// 그 주 월요일.
  final DateTime weekStart;

  /// 그 주에 보낸 리포트. 미전송이면 null.
  ///
  /// 이번 주 기록은 본문이 비어 있다 — `보낸 리포트` 화면이 그 주 수치에서
  /// 만든 문구로 채운다(`withDemoSends` 와 같은 규칙). 지난 주 기록은 회원
  /// 목표에 맞춘 글을 든다.
  final ReportSendRecord? record;

  /// 그 주 리포트가 나갔는가.
  bool get sent => record != null;
}

/// 데모 로스터에서 **이미 리포트가 나간** 회원.
///
/// 작업대는 두 열이 다 차 있어야 무슨 화면인지 읽힌다. 세션을 새로 열면
/// 기록이 비어 있어 열다섯 명이 전부 미전송으로 서고, `전송 완료` 는 빈 칸만
/// 남는다 — 데모에서 가장 먼저 보이는 화면이 가장 설명이 안 되는 화면이 된다.
///
/// 그래서 로스터를 **둘로 갈라** 여섯 명은 이번 주 리포트가 나간 것으로
/// 둔다. 남는 쪽이 더 길다 — 작업대는 아직 할 일이 있는 화면이라야 한다. 누가 어느 쪽에 서는지는 임의가 아니라 그 회원의 한 주에서 나온다:
///
///  * 남는 쪽(미전송)은 **트레이너가 아직 할 말을 정하지 못한 회원**이다 —
///    김민수(시연의 주인공, 그의 리포트는 화면에서 직접 쓴다), 박성호·문가영
///    (휴면), 오세라(급성 악화), 배준혁(답장 대기), 임도현(신규), 노은채
///    (기록 하루), 강서연(주말 붕괴), 류태경(극단 진폭). 작업대 줄에 신호가
///    붙어야 할 회원이 전부 여기 있다.
///  * 나간 쪽(전송 완료)은 이야기가 이미 끝난 회원이다. 보낸 시각은 월요일
///    아침부터 어제 밤까지 흩어 두고, 열람 여부도 갈라 둔다 — 넷 중 하나쯤은
///    아직 안 읽은 것이 실제 비율에 가깝고, `우선 확인` 안내가 그 값을 읽는다.
///
/// 실서버 로스터에는 `seed-client-*` 가 없어 이 목록은 데모에서만 붙는다.
/// 데모 로컬 채팅의 시드 리포트 안내도 이 자리를 넘보지 않는다 — 전송 이력은
/// 실행 중에 보낸 것만 센다(#2288). (#2232)
const List<({String clientId, int daysAgo, int hour, bool read})>
demoSentReports = <({String clientId, int daysAgo, int hour, bool read})>[
  (clientId: 'seed-client-5', daysAgo: 5, hour: 9, read: true),
  (clientId: 'seed-client-4', daysAgo: 3, hour: 18, read: true),
  (clientId: 'seed-client-11', daysAgo: 3, hour: 21, read: false),
  (clientId: 'seed-client-10', daysAgo: 2, hour: 20, read: true),
  (clientId: 'seed-client-2', daysAgo: 1, hour: 9, read: true),
  (clientId: 'seed-client-14', daysAgo: 1, hour: 20, read: false),
];

/// 데모 회원이 트레이너에게 붙은 주 — 이번 주에서 몇 주 전인가.
///
/// 적혀 있지 않은 회원은 이력 창([demoReportHistoryWeeks])보다 오래 PT 를
/// 받아 온 회원이다. 신규·적응 중인 회원은 붙은 주보다 앞선 리포트가 없다:
///
///  * 임도현 — 이번 주에 붙은 신규. 기록도 대화도 아직 없다.
///  * 노은채 — 지난 주에 붙어 첫 운동을 막 마쳤다(`첫 기록`).
const Map<String, int> demoMemberJoinedWeeksAgo = <String, int>{
  'seed-client-7': 0,
  'seed-client-15': 1,
};

/// 회원별 리포트 흐름 — 작업대 신호와 같은 이야기를 한다.
///
/// [skipPercent] 는 트레이너가 그 주 리포트를 건너뛴 비율, [unreadPercent] 는
/// 회원이 열어 보지 않은 비율이다. [quietWeeks] 는 최근 몇 주 동안 보낸
/// 리포트를 **하나도** 읽지 않았는가 — 기록이 끊긴 휴면 회원과 급성 악화
/// 회원이 여기 선다.
typedef _ReportHabit = ({int skipPercent, int unreadPercent, int quietWeeks});

const _ReportHabit _defaultHabit = (
  skipPercent: 8,
  unreadPercent: 12,
  quietWeeks: 0,
);

const Map<String, _ReportHabit> _habits = <String, _ReportHabit>{
  // 김민수 — 시연의 주인공. 매주 받고 거의 다 읽는다.
  'seed-client-1': (skipPercent: 0, unreadPercent: 5, quietWeeks: 0),
  // 이지수 — 주말만 비는 대조군.
  'seed-client-2': (skipPercent: 5, unreadPercent: 5, quietWeeks: 0),
  // 박성호 — 휴면. 최근 다섯 주는 보내도 읽지 않는다.
  'seed-client-3': (skipPercent: 15, unreadPercent: 30, quietWeeks: 5),
  // 최우진 — 완벽한 대조군. 빠짐없이 나가고 전부 읽는다.
  'seed-client-5': (skipPercent: 0, unreadPercent: 0, quietWeeks: 0),
  // 오세라 — 급성 악화. 최근 두 주는 읽지 않았다.
  'seed-client-8': (skipPercent: 5, unreadPercent: 10, quietWeeks: 2),
  // 배준혁 — 야근형·노쇼. 트레이너도 자주 건너뛰고, 회원도 자주 안 읽는다.
  'seed-client-9': (skipPercent: 25, unreadPercent: 35, quietWeeks: 0),
  // 문가영 — 휴면. 최근 세 주는 읽지 않았다.
  'seed-client-12': (skipPercent: 10, unreadPercent: 25, quietWeeks: 3),
  // 류태경 — 극단 진폭. 흐름도 들쭉날쭉하다.
  'seed-client-13': (skipPercent: 20, unreadPercent: 20, quietWeeks: 0),
};

/// 데모 회원 한 명의 전체 리포트 이력 — **최신 주부터**.
///
/// 이번 주를 포함해 [weeks] 주를 거슬러 가되, 회원이 붙은 주보다 앞선 주는
/// 넣지 않는다([demoMemberJoinedWeeksAgo]). 안 보낸 주도 한 줄로 선다 —
/// 회원별 지난 리포트 화면(#2394)이 `미전송` 을 빈칸 대신 그 주로 보여 준다.
///
/// 데모 로스터가 아닌 회원(실서버 id, 실행 중에 연결한 `user-*`)은 빈
/// 목록이다. [today] 는 이력의 기준 시각(KST)이다. 비우면 [nowKst].
List<DemoReportWeek> demoReportHistoryFor({
  required String clientId,
  required String goal,
  DemoLanguage language = DemoLanguage.ko,
  DateTime? today,
  int weeks = demoReportHistoryWeeks,
}) {
  if (!_isDemoMember(clientId)) return const <DemoReportWeek>[];
  final DateTime now = today ?? nowKst();
  final DateTime thisMonday = weekStartOf(now);
  final int joined = demoMemberJoinedWeeksAgo[clientId] ?? weeks;
  final DemoReportMember member = (id: clientId, goal: goal);
  return <DemoReportWeek>[
    for (int back = 0; back < weeks && back <= joined; back++)
      DemoReportWeek(
        weekStart: _mondayBefore(thisMonday, back),
        record: back == 0
            ? demoCurrentWeekRecord(clientId, now)
            : _pastWeekRecord(member, back, thisMonday, now, language),
      ),
  ];
}

/// 지난 [weekStart] 주에 데모 로스터 [roster] 에게 나간 리포트.
///
/// 데모 저장소의 `sentReports` 가 읽는다 — 작업대가 지난 주로 가도 `전송
/// 완료`·`미전송` 이 그 주 이력대로 선다. 이번 주와 앞으로 올 주는 빈
/// 목록이다: 이번 주 데모 기록은 `withDemoSends` 가 화면에서 얹는다.
List<ReportSendRecord> demoSentReportsForWeek({
  required Iterable<DemoReportMember> roster,
  required DateTime weekStart,
  DemoLanguage language = DemoLanguage.ko,
  DateTime? today,
}) {
  final DateTime now = today ?? nowKst();
  final DateTime thisMonday = weekStartOf(now);
  final int back = _weeksBetween(weekStartOf(weekStart), thisMonday);
  if (back < 1 || back >= demoReportHistoryWeeks) {
    return const <ReportSendRecord>[];
  }
  return <ReportSendRecord>[
    for (final DemoReportMember m in roster)
      if (_isDemoMember(m.id) &&
          back <= (demoMemberJoinedWeeksAgo[m.id] ?? demoReportHistoryWeeks))
        ?_pastWeekRecord(m, back, thisMonday, now, language),
  ];
}

/// [clientId] 의 이번 주 데모 기록 — [demoSentReports] 에 없으면 null.
///
/// 보낸 날은 [now] 에서 며칠 전으로 흩어 두되, 그 주 월요일보다 앞설 수는
/// 없다 — 주 초에 데모를 열면 월요일로 맞춘다.
ReportSendRecord? demoCurrentWeekRecord(String clientId, DateTime now) {
  final DateTime monday = weekStartOf(now);
  for (final demo in demoSentReports) {
    if (demo.clientId != clientId) continue;
    final DateTime day = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: demo.daysAgo));
    final DateTime sentAt = day.isBefore(monday)
        ? DateTime(monday.year, monday.month, monday.day, demo.hour)
        : DateTime(day.year, day.month, day.day, demo.hour);
    return ReportSendRecord(
      clientId: clientId,
      weekStart: monday,
      sentAt: sentAt,
      // 본문은 비워 둔다. `보낸 리포트` 화면이 그 주 수치에서 만든 문구로
      // 채운다 — 손으로 적어 두면 화면의 수치와 어긋난 글이 남는다.
      message: '',
      read: demo.read,
    );
  }
  return null;
}

bool _isDemoMember(String clientId) => clientId.startsWith('seed-client-');

DateTime _mondayBefore(DateTime thisMonday, int back) =>
    DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * back);

/// [from] 주에서 [to] 주까지 몇 주인가. 벽시계 시각이 아니라 날짜로 센다.
int _weeksBetween(DateTime from, DateTime to) {
  final int days = DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  return (days / 7).round();
}

/// [member] 의 [back] 주 전 리포트. 건너뛴 주면 null.
ReportSendRecord? _pastWeekRecord(
  DemoReportMember member,
  int back,
  DateTime thisMonday,
  DateTime now,
  DemoLanguage language,
) {
  final DateTime monday = _mondayBefore(thisMonday, back);
  final _ReportHabit habit = _habits[member.id] ?? _defaultHabit;
  int roll(String salt) => _seed(member.id, monday, salt) % 100;

  // 붙은 첫 주는 건너뛰지 않는다 — 첫 리포트는 트레이너가 꼭 보낸다.
  final bool firstWeek = demoMemberJoinedWeeksAgo[member.id] == back;
  if (!firstWeek && roll('skip') < habit.skipPercent) return null;

  final bool read =
      back > habit.quietWeeks && roll('read') >= habit.unreadPercent;
  return ReportSendRecord(
    clientId: member.id,
    weekStart: monday,
    sentAt: _sentAt(member.id, monday, now),
    message: demoReportMessage(
      goal: member.goal,
      language: language,
      variant: _seed(member.id, monday, 'text'),
    ),
    read: read,
  );
}

/// 그 주 리포트를 보낸 시각 — 주말(토·일)부터 다음 주 초(월·화) 사이.
///
/// 트레이너는 한 주가 끝나 갈 때 리포트를 쓴다. 지난 주 기록이 아직 오지
/// 않은 시각(이번 주 화요일 저녁 등)에 떨어지면, 그 주 일요일 저녁으로 당긴다.
DateTime _sentAt(String clientId, DateTime monday, DateTime now) {
  final int s = _seed(clientId, monday, 'sent');
  final int dayOffset = 5 + s % 4; // 토 5 · 일 6 · 월 7 · 화 8
  final int hour = 8 + (s ~/ 4) % 15; // 08~22시
  final int minute = ((s ~/ 60) % 6) * 10;
  final DateTime at = DateTime(
    monday.year,
    monday.month,
    monday.day + dayOffset,
    hour,
    minute,
  );
  if (!at.isAfter(now)) return at;
  return DateTime(monday.year, monday.month, monday.day + 6, 20);
}

/// 회원·주·용도로 정해지는 수. 같은 입력이면 어느 플랫폼에서든 같은 값이다 —
/// `String.hashCode` 는 실행 환경마다 달라도 되는 값이라 쓰지 않는다. 웹의
/// 정수는 2^53 까지만 정확해 곱하기 전에 늘 그 아래로 접는다.
int _seed(String clientId, DateTime monday, String salt) {
  int h = 17;
  for (final int c in '$clientId|${ymd(monday)}|$salt'.codeUnits) {
    h = (h * 31 + c) % 2147483647;
  }
  return h;
}

/// 목표 하나 — 로스터의 목표 문구가 이 중 하나 이상을 말한다.
enum DemoReportGoal {
  weightLoss,
  strength,
  bloodPressure,
  rehab,
  posture,
  eatingHabits,
  exerciseHabit,
  fitness,
}

/// 목표 문구를 이루는 낱말 — 한국어·영어 데모 로스터 둘 다 읽는다.
///
/// 순서가 판정 순서다. `운동 습관` 을 `체력` 보다 먼저 보는 것처럼, 더 좁은
/// 말이 앞에 선다.
const List<(DemoReportGoal, List<String>)> _goalWords =
    <(DemoReportGoal, List<String>)>[
      (DemoReportGoal.weightLoss, <String>['체중', '감량', 'weight']),
      (DemoReportGoal.strength, <String>['근력', 'strength']),
      (DemoReportGoal.bloodPressure, <String>['혈압', 'blood pressure']),
      (DemoReportGoal.rehab, <String>['재활', 'rehab']),
      (DemoReportGoal.posture, <String>['자세', 'posture']),
      (DemoReportGoal.eatingHabits, <String>['식습관', 'eating']),
      (DemoReportGoal.exerciseHabit, <String>['운동 습관', 'exercise habit']),
      (DemoReportGoal.fitness, <String>['체력', 'fitness']),
    ];

/// [goal] 이 말하는 목표 — 적힌 순서대로. `체중 감량 · 혈압 관리` 는
/// `[weightLoss, bloodPressure]` 다. 알아듣는 말이 없으면 빈 목록.
List<DemoReportGoal> demoReportGoalsOf(String goal) {
  final List<DemoReportGoal> goals = <DemoReportGoal>[];
  for (final String part in goal.split('·')) {
    final String text = part.trim().toLowerCase();
    if (text.isEmpty) continue;
    for (final (DemoReportGoal kind, List<String> words) in _goalWords) {
      if (words.any(text.contains)) {
        if (!goals.contains(kind)) goals.add(kind);
        break;
      }
    }
  }
  return goals;
}

/// 데모로 깔아 둔 지난 주 리포트의 본문 — 회원 목표에 맞춘 피드백.
///
/// 여는 말 · 목표마다 한 문장 · 맺는 말. [variant] 로 문장을 골라 주마다
/// 글이 달라진다. 숫자는 적지 않는다 — 데모 수치는 여는 요일에 따라
/// 흔들려, 글에 숫자를 박으면 어떤 날에는 격자와 어긋난다.
///
/// 언어는 로스터를 심은 데모 내용의 언어([DemoLanguage])다. 회원이 받은 글은
/// 그때 쓴 언어 그대로라 화면 문구(ARB)를 거치지 않는다.
String demoReportMessage({
  required String goal,
  required DemoLanguage language,
  int variant = 0,
}) {
  final _ReportCopy copy = language.isEnglish ? _en : _ko;
  final List<DemoReportGoal> goals = demoReportGoalsOf(goal);
  String pick(List<String> options, int shift) =>
      options[(variant ~/ shift) % options.length];
  return <String>[
    pick(copy.openers, 1),
    if (goals.isEmpty)
      pick(copy.general, 3)
    else
      for (final (int i, DemoReportGoal g) in goals.take(2).indexed)
        pick(copy.byGoal[g]!, 3 + i * 5),
    pick(copy.closers, 7),
  ].join(' ');
}

typedef _ReportCopy = ({
  List<String> openers,
  List<String> closers,
  List<String> general,
  Map<DemoReportGoal, List<String>> byGoal,
});

const _ReportCopy _ko = (
  openers: <String>['이번 주도 수고 많으셨어요.', '한 주 기록 잘 봤어요.', '이번 주 리포트 보내 드려요.'],
  closers: <String>[
    '다음 수업에서 뵐게요!',
    '궁금한 점은 채팅으로 편하게 물어봐 주세요.',
    '다음 주도 같이 가 봐요 🙂',
  ],
  general: <String>['지금 흐름을 다음 주에도 그대로 이어가 봐요.', '다음 주에는 기록을 하루만 더 채워 봐요.'],
  byGoal: <DemoReportGoal, List<String>>{
    DemoReportGoal.weightLoss: <String>[
      '체중 감량은 한 주의 숫자보다 흐름이 중요해요 — 저녁 한 끼의 양만 꾸준히 지켜 봐요.',
      '감량 중에는 끼니를 거르기보다 규칙적으로 드시는 게 더 효과적이에요.',
      '다음 주에는 유산소를 한 번만 더 넣어 감량 흐름을 이어가 볼게요.',
    ],
    DemoReportGoal.strength: <String>[
      '근력은 반복한 만큼 올라와요. 다음 주에는 주 운동 무게를 무리 없는 선에서 조금 올려 볼게요.',
      '근력 향상에는 회복이 운동만큼 중요해요 — 운동한 날은 단백질을 한 끼 더 챙겨 주세요.',
      '세트 사이 휴식을 지켜야 근력 운동의 질이 올라가요. 다음 주엔 휴식 시간도 같이 재 봐요.',
    ],
    DemoReportGoal.bloodPressure: <String>[
      '혈압 관리는 나트륨이 가장 큰 변수예요. 국물은 절반만 드시는 습관을 이어가 봐요.',
      '꾸준한 유산소가 혈압을 안정시키는 데 도움이 돼요. 빠르게 걷기 30분을 세 번 채워 봐요.',
      '혈압약 드시는 시간과 운동 시간이 겹치지 않게 다음 주 일정도 그대로 맞춰 둘게요.',
    ],
    DemoReportGoal.rehab: <String>[
      '재활은 통증 없는 범위를 지키는 게 먼저예요. 불편한 동작이 있으면 바로 말씀해 주세요.',
      '재활 운동으로 가동 범위가 조금씩 넓어지고 있어요. 운동 전후 스트레칭을 꼭 챙겨 주세요.',
    ],
    DemoReportGoal.posture: <String>[
      '자세 교정은 짧게라도 매일 하는 게 효과가 커요. 한 시간에 한 번 어깨를 펴 주세요.',
      '운동할 때 거울로 자세를 한 번씩 확인해 보세요. 다음 수업에서 코어 버티기를 늘려 볼게요.',
    ],
    DemoReportGoal.eatingHabits: <String>[
      '식습관은 한 가지씩 바꾸는 게 오래가요. 간식 한 번을 과일이나 견과로 바꿔 봐요.',
      '식습관은 기록에서 시작해요 — 끼니를 적으면 흐름이 보여요. 채소 반찬을 한 끼에 하나씩 더해 봐요.',
    ],
    DemoReportGoal.exerciseHabit: <String>[
      '운동 습관은 횟수를 지키는 데서 시작해요. 다음 주도 주 3회만 채워 봐요.',
      '운동 습관은 요일과 시간을 미리 정해 두면 훨씬 단단해져요. 다음 주 계획을 먼저 세워 봐요.',
    ],
    DemoReportGoal.fitness: <String>[
      '체력은 쉬지 않고 이어 가는 게 핵심이에요. 다음 주에는 유산소 시간을 조금씩 늘려 볼게요.',
      '회복이 빨라졌다면 체력이 붙고 있다는 신호예요. 다음 주엔 인터벌을 한 세트 더해 볼게요.',
    ],
  },
);

const _ReportCopy _en = (
  openers: <String>[
    'Great work this week.',
    'I went through your week.',
    "Here's your weekly report.",
  ],
  closers: <String>[
    'See you at the next session!',
    'Message me anytime if you have questions.',
    "Let's keep going next week 🙂",
  ],
  general: <String>[
    "Let's carry this rhythm into next week.",
    'Next week, try to log just one more day.',
  ],
  byGoal: <DemoReportGoal, List<String>>{
    DemoReportGoal.weightLoss: <String>[
      'For weight loss the trend matters more than any single week — just keep dinner portions steady.',
      'While losing weight, regular meals work better than skipping them.',
      "Next week we'll add one more cardio session to keep the weight-loss trend going.",
    ],
    DemoReportGoal.strength: <String>[
      "Strength comes with repetition. Next week we'll add a little weight to your main lift.",
      'Recovery matters as much as training for strength — add protein to one more meal on workout days.',
      'Keeping rest between sets improves your strength work. Time your rests next week too.',
    ],
    DemoReportGoal.bloodPressure: <String>[
      'Sodium is the biggest lever for blood pressure. Keep leaving half the soup.',
      'Steady cardio helps stabilise blood pressure. Aim for three 30-minute brisk walks.',
      "I'll keep next week's sessions clear of the time you take your blood-pressure medication.",
    ],
    DemoReportGoal.rehab: <String>[
      'In rehab, staying pain-free comes first. Tell me right away if any movement feels off.',
      'Rehab is paying off — your range of motion is slowly improving. Keep stretching before and after each workout.',
    ],
    DemoReportGoal.posture: <String>[
      'Posture work pays off when done daily, even briefly. Open up your shoulders once an hour.',
      "Check your posture in the mirror now and then. We'll extend core holds next session.",
    ],
    DemoReportGoal.eatingHabits: <String>[
      'Eating habits stick when you change one thing at a time. Swap one snack for fruit or nuts.',
      'Better eating habits start with logging — add one vegetable side to each meal.',
    ],
    DemoReportGoal.exerciseHabit: <String>[
      'An exercise habit starts with showing up. Aim for three sessions again next week.',
      "Your exercise habit gets stronger when you plan workout days ahead. Let's set next week's plan first.",
    ],
    DemoReportGoal.fitness: <String>[
      "Fitness is about consistency. Next week we'll stretch your cardio time a little.",
      "Faster recovery means your fitness is building. Next week we'll add one more interval set.",
    ],
  },
);
