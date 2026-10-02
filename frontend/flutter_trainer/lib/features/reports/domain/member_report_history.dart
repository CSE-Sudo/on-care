import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// 회원별 지난 리포트의 한 줄 — 한 회원에게 한 주 리포트가 나간 기록. (#2394)
///
/// 주 단위 전송 기록([ReportSendRecord])과 근거·접는 규칙이 같다: 한 주에
/// 여러 번 보냈으면 가장 최근 전송 하나와 [sendCount]. 목록은 여러 주를
/// 한 번에 세우는 자리라 본문 전체 대신 [feedbackPreview](첫 줄)만 든다 —
/// 전문은 `보기` 로 여는 보낸 리포트 화면이 읽는다.
class MemberReportHistoryItem {
  /// Creates an item.
  const MemberReportHistoryItem({
    required this.weekStart,
    required this.sentAt,
    required this.read,
    required this.feedbackPreview,
    this.sendCount = 1,
    this.messageId,
    this.hasPdf = false,
  });

  /// [record] 에서 만든 줄 — 세션 기록·데모 기록을 목록에 얹을 때 쓴다.
  factory MemberReportHistoryItem.fromRecord(ReportSendRecord record) =>
      MemberReportHistoryItem(
        weekStart: weekStartOf(record.weekStart),
        sentAt: record.sentAt,
        read: record.read,
        sendCount: record.sendCount,
        feedbackPreview: reportFeedbackPreview(record.message),
      );

  /// 그 주 월요일.
  final DateTime weekStart;

  /// 가장 최근에 보낸 시각(KST 벽시계).
  final DateTime sentAt;

  /// 회원이 가장 최근 전송을 열어 봤는가.
  final bool read;

  /// 그 주 리포트를 몇 번 보냈는가.
  final int sendCount;

  /// 가장 최근 전송 본문의 첫 줄. 비어 있으면 화면이 그 주 수치에서 만든
  /// 문구의 첫 줄로 채운다(보낸 리포트 화면과 같은 규칙).
  final String feedbackPreview;

  /// 가장 최근 전송의 채팅 메시지 id. 데모·세션 기록에는 없다.
  final String? messageId;

  /// 가장 최근 전송이 PDF 첨부였는가.
  final bool hasPdf;
}

/// 회원별 지난 리포트 한 쪽 — 최신 주부터. (#2394)
class MemberReportHistoryPage {
  /// Creates a page.
  const MemberReportHistoryPage({required this.items, this.nextBefore});

  /// 빈 쪽 — 보낸 적이 없다.
  const MemberReportHistoryPage.empty()
    : items = const <MemberReportHistoryItem>[],
      nextBefore = null;

  /// 이 쪽의 줄, 최신 주부터.
  final List<MemberReportHistoryItem> items;

  /// 다음 쪽 커서 — 이 주보다 오래된 주가 더 있다. 더 없으면 null.
  final DateTime? nextBefore;

  /// 더 불러올 쪽이 있는가.
  bool get hasMore => nextBefore != null;
}

/// 목록에 적을 본문 첫 줄 — 비어 있지 않은 첫 줄, [maxLength] 를 넘으면
/// 잘라 `…` 를 붙인다. 서버의 `feedback_preview` 와 같은 규칙이다(#2393).
String reportFeedbackPreview(String body, {int maxLength = 80}) {
  for (final String raw in body.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (line.runes.length <= maxLength) return line;
    return '${String.fromCharCodes(line.runes.take(maxLength))}…';
  }
  return '';
}

/// 서버·저장소의 이력 [fetched] 에 이번 세션에 보낸 기록 [session] 을 얹는다.
///
/// [clientId] 의 기록만 본다. 같은 주가 둘 다 있으면 `mergeSendLogs` 와 같은
/// 규칙이다(#2885): 서버 기록의 보낸 횟수가 세션 기록만큼 찼으면 서버가 방금
/// 보낸 것을 돌려준 것이라 서버 줄(읽음 여부 포함)이 남고, 아직 덜 찼으면
/// 세션 기록이 이긴다 — 방금 다시 보낸 글이 서버에서 돌아오기 전에 옛 첫 줄을
/// 보여 주지 않는다. 결과는 최신 주부터다.
///
/// [oldestLoaded] 가 있으면 그보다 오래된 주의 세션 기록은 얹지 않는다 —
/// 아직 불러오지 않은 쪽에 속한 주가 목록 중간에 끼어들지 않게 한다.
List<MemberReportHistoryItem> mergeMemberHistory({
  required List<MemberReportHistoryItem> fetched,
  required Map<String, ReportSendRecord> session,
  required String clientId,
  DateTime? oldestLoaded,
}) {
  final Map<String, MemberReportHistoryItem> byWeek =
      <String, MemberReportHistoryItem>{
        for (final MemberReportHistoryItem item in fetched)
          ymd(weekStartOf(item.weekStart)): item,
      };
  for (final ReportSendRecord record in session.values) {
    if (record.clientId != clientId) continue;
    final DateTime monday = weekStartOf(record.weekStart);
    if (oldestLoaded != null && monday.isBefore(weekStartOf(oldestLoaded))) {
      continue;
    }
    final String key = ymd(monday);
    final MemberReportHistoryItem? theirs = byWeek[key];
    final MemberReportHistoryItem mine = MemberReportHistoryItem.fromRecord(
      record,
    );
    if (theirs != null && theirs.sendCount >= mine.sendCount) continue;
    byWeek[key] = theirs == null
        ? mine
        : MemberReportHistoryItem(
            weekStart: mine.weekStart,
            sentAt: mine.sentAt,
            // 방금 보낸 것은 아직 아무도 읽지 않았다.
            read: false,
            sendCount: mine.sendCount,
            feedbackPreview: mine.feedbackPreview,
            messageId: theirs.messageId,
            hasPdf: theirs.hasPdf,
          );
  }
  final List<MemberReportHistoryItem> merged = byWeek.values.toList()
    ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
  return merged;
}
