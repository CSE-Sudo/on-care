import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// 한 회원에게 어느 주 리포트를 언제, 무슨 내용으로 보냈는가.
///
/// 작업대의 `전송 완료` 열과, 그 줄을 눌렀을 때 뜨는 `보낸 리포트` 화면이
/// 같은 기록을 읽는다.
class ReportSendRecord {
  /// Creates a record.
  const ReportSendRecord({
    required this.clientId,
    required this.weekStart,
    required this.sentAt,
    required this.message,
    this.read = true,
  });

  /// 받은 회원.
  final String clientId;

  /// 어느 주의 리포트인가(월요일).
  final DateTime weekStart;

  /// 보낸 시각.
  final DateTime sentAt;

  /// 그때 보낸 본문. 전송 뒤에 초안을 고쳐도 이 값은 그대로다 — 회원이 받은
  /// 것은 고치기 전 글이고, `보낸 리포트` 는 회원이 본 것을 보여 주는
  /// 화면이다.
  final String message;

  /// 회원이 열어 봤는가. 서버가 알려 줄 값이라 실전에서는 늘 최신이 아니고,
  /// 지금은 데모 기록만 이 값을 갈라 둔다 — 작업대는 이 값으로 다음 주
  /// `우선 확인` 을 정한다.
  final bool read;
}

/// 이번 세션에 나간 리포트.
///
/// 열람 여부·목표 확인 여부는 회원 앱이 알려 주는 값이라 서버가 기록해야
/// 하고, 그 자리는 아직 비어 있다. 이 저장소는 그 전까지 **보냈다는 사실**
/// 하나만 들고 있는다 — 그것만으로도 작업대가 "누가 남았나" 에 답할 수
/// 있다. (#2232)
/// [log] 에서 [clientId] 의 [weekStart] 주 기록. 없으면 null.
///
/// 기록은 `Map` 하나가 전부라 읽는 쪽은 상태를 그대로 보면 된다 — 읽기를
/// notifier 에 두면 `watch` 가 상태 변화를 못 받는다.
ReportSendRecord? sendRecordFor(
  Map<String, ReportSendRecord> log,
  String clientId,
  DateTime weekStart,
) => log['$clientId|${ymd(weekStartOf(weekStart))}'];

/// [log] 에서 그 주에 리포트가 나간 회원 id.
Set<String> sentClientsIn(
  Map<String, ReportSendRecord> log,
  DateTime weekStart,
) {
  final String monday = ymd(weekStartOf(weekStart));
  return <String>{
    for (final ReportSendRecord r in log.values)
      if (ymd(r.weekStart) == monday) r.clientId,
  };
}

class ReportSendLog extends StateNotifier<Map<String, ReportSendRecord>> {
  /// Creates an empty log.
  ReportSendLog() : super(const <String, ReportSendRecord>{});

  static String _key(String clientId, DateTime weekStart) =>
      '$clientId|${ymd(weekStartOf(weekStart))}';

  /// [clientId] 의 [weekStart] 주 리포트를 방금 보냈다고 적는다.
  void record({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) {
    final DateTime monday = weekStartOf(weekStart);
    state = <String, ReportSendRecord>{
      ...state,
      _key(clientId, monday): ReportSendRecord(
        clientId: clientId,
        weekStart: monday,
        sentAt: nowKst(),
        message: message,
      ),
    };
  }
}

/// 이번 세션에 나간 리포트 기록.
final reportSendLogProvider =
    StateNotifierProvider<ReportSendLog, Map<String, ReportSendRecord>>(
      (ref) => ReportSendLog(),
    );

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
/// 서버가 전송 이력을 들고 오면 이 목록은 통째로 사라진다. (#2232)
const List<({String clientId, int daysAgo, int hour, bool read})>
demoSentReports = <({String clientId, int daysAgo, int hour, bool read})>[
  (clientId: 'seed-client-5', daysAgo: 5, hour: 9, read: true),
  (clientId: 'seed-client-4', daysAgo: 3, hour: 18, read: true),
  (clientId: 'seed-client-11', daysAgo: 3, hour: 21, read: false),
  (clientId: 'seed-client-10', daysAgo: 2, hour: 20, read: true),
  (clientId: 'seed-client-2', daysAgo: 1, hour: 9, read: true),
  (clientId: 'seed-client-14', daysAgo: 1, hour: 20, read: false),
];

/// [log] 에 데모 기록을 얹은 사본.
///
/// 트레이너가 이번 세션에 실제로 보낸 것이 언제나 먼저다 — 같은 회원·같은
/// 주의 기록이 이미 있으면 데모 기록은 얹지 않는다. [rosterIds] 에 없는
/// 회원도 건너뛴다: 실 서버 로스터에는 `seed-client-*` 가 없다.
Map<String, ReportSendRecord> withDemoSends(
  Map<String, ReportSendRecord> log,
  Set<String> rosterIds,
  DateTime weekStart, {
  DateTime? today,
}) {
  final DateTime monday = weekStartOf(weekStart);
  final DateTime now = today ?? nowKst();
  // 지난 주를 열어 놓고 이번 주 기록을 보여 주지 않는다. 데모 기록이 붙는
  // 곳은 지금 주 하나뿐이다.
  if (monday != weekStartOf(now)) return log;
  final merged = <String, ReportSendRecord>{...log};
  for (final demo in demoSentReports) {
    if (!rosterIds.contains(demo.clientId)) continue;
    final String key = '${demo.clientId}|${ymd(monday)}';
    if (merged.containsKey(key)) continue;
    final DateTime day = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: demo.daysAgo));
    // 보낸 날이 그 주보다 앞설 수는 없다 — 주 초에 데모를 열면 월요일로 맞춘다.
    final DateTime sentAt = day.isBefore(monday)
        ? DateTime(monday.year, monday.month, monday.day, demo.hour)
        : DateTime(day.year, day.month, day.day, demo.hour);
    merged[key] = ReportSendRecord(
      clientId: demo.clientId,
      weekStart: monday,
      sentAt: sentAt,
      // 본문은 비워 둔다. `보낸 리포트` 화면이 그 주 수치에서 만든 문구로
      // 채운다 — 손으로 적어 두면 화면의 수치와 어긋난 글이 남는다.
      message: '',
      read: demo.read,
    );
  }
  return merged;
}
