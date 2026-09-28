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
/// 회원·같은 주·같은 오늘이면 새로고침해도 같은 시각이다.
///
/// 본문은 적지 않는다(#2423). 목표에 맞춘 고정 문장을 깔아 두었더니, 칼로리를
/// 매일 넘긴 주에도 "잘하고 계세요" 가 남아 그 주 수치와 어긋났다. 이번 주와
/// 같이 비워 두면, 보낸 리포트 화면과 이력 목록이 그 주 수치로 만든 초안
/// ([reportMessage])을 보여 준다.
///
/// 이번 주는 여기서 정하지 않는다. 작업대의 두 열을 가르는 [demoSentReports]
/// 가 정하고, 이 파일은 그 명단을 이력의 맨 위 한 줄로 그대로 옮긴다.
///
/// 실서버 로스터에는 `seed-client-*` 가 없어 여기서 나오는 것이 없다.

/// 데모 이력이 거슬러 올라가는 주 수(이번 주 포함). 지난 주만 열세 주 —
/// 석 달을 넘겨 "최근 3개월" 을 어느 요일에 열어도 채운다.
const int demoReportHistoryWeeks = 14;

/// 데모 로스터의 한 사람 — 이력을 만드는 데 필요한 것만 든다.
typedef DemoReportMember = ({String id});

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
  DateTime? today,
  int weeks = demoReportHistoryWeeks,
}) {
  if (!_isDemoMember(clientId)) return const <DemoReportWeek>[];
  final DateTime now = today ?? nowKst();
  final DateTime thisMonday = weekStartOf(now);
  final int joined = demoMemberJoinedWeeksAgo[clientId] ?? weeks;
  final DemoReportMember member = (id: clientId);
  return <DemoReportWeek>[
    for (int back = 0; back < weeks && back <= joined; back++)
      DemoReportWeek(
        weekStart: _mondayBefore(thisMonday, back),
        record: back == 0
            ? demoCurrentWeekRecord(clientId, now)
            : _pastWeekRecord(member, back, thisMonday, now),
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
        ?_pastWeekRecord(m, back, thisMonday, now),
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
    // 이번 주 기록([demoCurrentWeekRecord])과 같은 규칙 — 화면이 그 주
    // 수치에서 만든 초안으로 채운다(#2423).
    message: '',
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
