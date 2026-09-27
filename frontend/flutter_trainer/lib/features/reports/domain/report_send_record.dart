/// 한 회원에게 어느 주 리포트를 언제, 무슨 내용으로 보냈는가.
///
/// 작업대의 `전송 완료` 열과, 그 줄을 눌렀을 때 뜨는 `보낸 리포트` 화면이
/// 같은 기록을 읽는다. 실서버에서는 `GET /trainer/reports/sent` 가, 데모에서는
/// 로컬 채팅의 리포트 전송 표시가 이 기록을 만든다(#2288) — 새로고침해도
/// 보낸 회원이 미전송으로 돌아가지 않는다.
class ReportSendRecord {
  /// Creates a record.
  const ReportSendRecord({
    required this.clientId,
    required this.weekStart,
    required this.sentAt,
    required this.message,
    this.read = true,
    this.sendCount = 1,
  });

  /// 받은 회원.
  final String clientId;

  /// 어느 주의 리포트인가(월요일).
  final DateTime weekStart;

  /// 가장 최근에 보낸 시각(KST 벽시계).
  final DateTime sentAt;

  /// 그때 보낸 본문. 전송 뒤에 초안을 고쳐도 이 값은 그대로다 — 회원이 받은
  /// 것은 고치기 전 글이고, `보낸 리포트` 는 회원이 본 것을 보여 주는
  /// 화면이다.
  final String message;

  /// 회원이 열어 봤는가. 작업대는 이 값으로 다음 주 `우선 확인` 을 정한다.
  final bool read;

  /// 그 주 리포트를 몇 번 보냈는가. 다시 보낸 적이 있으면 2 이상이다.
  final int sendCount;
}
