import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

export 'package:oncare_trainer/features/reports/domain/report_send_record.dart';

/// 전송 기록의 열쇠 — `회원 id|그 주 월요일`.
String sendLogKey(String clientId, DateTime weekStart) =>
    '$clientId|${ymd(weekStartOf(weekStart))}';

/// [log] 에서 [clientId] 의 [weekStart] 주 기록. 없으면 null.
///
/// 기록은 `Map` 하나가 전부라 읽는 쪽은 상태를 그대로 보면 된다 — 읽기를
/// notifier 에 두면 `watch` 가 상태 변화를 못 받는다.
ReportSendRecord? sendRecordFor(
  Map<String, ReportSendRecord> log,
  String clientId,
  DateTime weekStart,
) => log[sendLogKey(clientId, weekStart)];

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

/// 이번 세션에 방금 보낸 리포트.
///
/// 기록의 원본은 서버다([reportSendHistoryProvider]) — 이 저장소는 보낸 직후
/// 서버 기록을 다시 읽어 오는 사이에 작업대가 그 회원을 미전송으로 되돌리지
/// 않게 잠깐 들고 있는 자리다. 새로고침하면 비지만, 그때는 서버 기록이 같은
/// 사실을 들고 온다(#2288).
class ReportSendLog extends StateNotifier<Map<String, ReportSendRecord>> {
  /// Creates an empty log.
  ReportSendLog() : super(const <String, ReportSendRecord>{});

  /// [clientId] 의 [weekStart] 주 리포트를 방금 보냈다고 적는다.
  void record({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) {
    final DateTime monday = weekStartOf(weekStart);
    state = <String, ReportSendRecord>{
      ...state,
      sendLogKey(clientId, monday): ReportSendRecord(
        clientId: clientId,
        weekStart: monday,
        sentAt: nowKst(),
        message: message,
      ),
    };
  }
}

/// 이번 세션에 방금 보낸 리포트 기록.
///
/// 로그인한 계정의 기록이다 — 계정이 바뀌면 빈 기록에서 다시 시작한다(#2285).
final reportSendLogProvider =
    StateNotifierProvider<ReportSendLog, Map<String, ReportSendRecord>>((ref) {
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      return ReportSendLog();
    });

/// 그 주 리포트가 이미 나간 회원 — 서버(데모는 로컬 채팅)에 남은 기록. (#2288)
///
/// 열쇠는 그 주의 월요일이다. 작업대가 `전송 완료` 열을 세우고, 편집기가 이미
/// 보낸 회원에게 다시 보내기 전에 확인을 받는 근거다. 앱 메모리에만 있던 때는
/// 새로고침하면 보낸 회원이 미전송으로 돌아가 같은 리포트가 두 번 나갔다.
///
/// `autoDispose` 다 — 화면을 다시 열 때마다 새로 묻는다. 다른 기기나 탭에서
/// 보낸 것도 그때 들어온다. 보낸 뒤에는 이 provider 를 무효화한다.
final reportSendHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, ReportSendRecord>, DateTime>((ref, weekStart) async {
      final List<ReportSendRecord> records = await ref
          .watch(reportRepositoryProvider)
          .sentReports(weekStart: weekStartOf(weekStart));
      return <String, ReportSendRecord>{
        for (final ReportSendRecord r in records)
          sendLogKey(r.clientId, r.weekStart): r,
      };
    });

/// 서버 기록 [history] 에 이번 세션 기록 [session] 을 얹은 사본.
///
/// 같은 회원·같은 주의 기록이 둘 다 있으면 **더 늦게 보낸 것**이 남는다 —
/// 방금 다시 보낸 글이 서버에서 아직 돌아오지 않았을 때 옛 본문을 보여 주지
/// 않는다. 보낸 횟수는 둘 중 큰 쪽을 지킨다.
Map<String, ReportSendRecord> mergeSendLogs(
  Map<String, ReportSendRecord> history,
  Map<String, ReportSendRecord> session,
) {
  final merged = <String, ReportSendRecord>{...history};
  session.forEach((String key, ReportSendRecord mine) {
    final ReportSendRecord? theirs = merged[key];
    if (theirs == null) {
      merged[key] = mine;
      return;
    }
    if (theirs.sentAt.isAfter(mine.sentAt)) return;
    merged[key] = ReportSendRecord(
      clientId: mine.clientId,
      weekStart: mine.weekStart,
      sentAt: mine.sentAt,
      message: mine.message,
      // 방금 보낸 것은 아직 아무도 읽지 않았다.
      read: false,
      sendCount: theirs.sendCount > mine.sendCount
          ? theirs.sendCount
          : mine.sendCount,
    );
  });
  return merged;
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
