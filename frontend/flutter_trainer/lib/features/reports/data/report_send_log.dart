import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

export 'package:oncare_trainer/features/reports/data/demo_report_history.dart'
    show demoSentReports;
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
  ///
  /// [previousCount] 는 이 전송 앞까지 보낸 횟수다 — 기록은 그다음 번호로
  /// 선다(#2885). 예전에는 늘 1 로 적고 서버 기록과 큰 쪽을 골라, 세 번째로
  /// 보낸 직후에도 서버의 옛 `2회` 가 서버가 돌아올 때까지 남았다.
  void record({
    required String clientId,
    required DateTime weekStart,
    required String message,
    int previousCount = 0,
  }) {
    final DateTime monday = weekStartOf(weekStart);
    state = <String, ReportSendRecord>{
      ...state,
      sendLogKey(clientId, monday): ReportSendRecord(
        clientId: clientId,
        weekStart: monday,
        sentAt: nowKst(),
        message: message,
        read: false,
        sendCount: (previousCount < 0 ? 0 : previousCount) + 1,
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
/// 세션 기록은 서버가 방금 보낸 것을 돌려줄 때까지만 선다(#2885):
///  * 서버에 같은 회원·같은 주 기록이 없으면 세션 기록이 그 자리에 선다.
///  * 서버 기록의 보낸 횟수가 세션 기록만큼 찼으면 서버가 따라잡은 것이다 —
///    세션 기록을 버리고 서버 기록(읽음 여부 포함)을 그대로 둔다.
///  * 아직 덜 찼으면 방금 보낸 것이 서버에 없다 — 세션 기록이 이긴다.
///
/// 비교는 보낸 횟수로 한다. 예전에는 보낸 시각을 견줬는데, 세션 시각은 기기
/// 시계라 기기가 서버보다 빠르면 세션 기록이 계속 이겨, 회원이 읽은 뒤에도
/// `안 읽음` 으로 남았다.
Map<String, ReportSendRecord> mergeSendLogs(
  Map<String, ReportSendRecord> history,
  Map<String, ReportSendRecord> session,
) {
  final merged = <String, ReportSendRecord>{...history};
  session.forEach((String key, ReportSendRecord mine) {
    final ReportSendRecord? theirs = merged[key];
    if (theirs != null && theirs.sendCount >= mine.sendCount) return;
    merged[key] = mine;
  });
  return merged;
}

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
  // 이 함수가 얹는 곳은 지금 주 하나뿐이다. 지난 주 데모 이력은 데모 저장소의
  // `sentReports` 가 서버 기록 자리로 돌려준다(#2399) — 지난 주를 열어 놓고
  // 이번 주 명단을 보여 주지 않는다.
  if (monday != weekStartOf(now)) return log;
  final merged = <String, ReportSendRecord>{...log};
  for (final demo in demoSentReports) {
    if (!rosterIds.contains(demo.clientId)) continue;
    final String key = sendLogKey(demo.clientId, monday);
    if (merged.containsKey(key)) continue;
    final ReportSendRecord? record = demoCurrentWeekRecord(demo.clientId, now);
    if (record != null) merged[key] = record;
  }
  return merged;
}
