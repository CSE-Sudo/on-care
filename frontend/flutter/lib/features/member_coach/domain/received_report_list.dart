/// 받은 리포트 목록을 접고 쪽으로 자르는 규칙. (#3348)
///
/// 서버 `GET /me/coach/reports` 는 주마다 **마지막으로 받은 한 건**을 최신 주부터
/// 주고, 그 앞은 마지막 줄의 주를 커서로 넘겨 받는다. 데모 저장소와 테스트
/// 대역이 서버와 같은 목록·같은 쪽을 주게 하려고 여기 순수 함수로 둔다.
library;

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 서버가 한 번에 주는 주 수 — 한 해치다. 대화 길이와 무관하게 첫 요청 하나로
/// 목록이 선다.
const int receivedReportsPageSize = 52;

/// 대화에 남은 리포트 안내를 받은 리포트 목록으로 접는다(최신 주 → 오래된 주).
///
/// 같은 주 리포트를 두 번 받았으면 **마지막 것 하나만** 남긴다. 회원이 받은
/// 것은 마지막 글이고, 목록에 같은 주가 두 줄로 서면 어느 것을 열어야 하는지
/// 알 수 없다. 파일명이나 본문으로 추측하지 않는다 — 실려 온 주만 본다.
List<ReceivedReport> foldReceivedReports(
  Iterable<CoachMessage> chat, {
  String? trainerName,
}) {
  final Map<DateTime, ReceivedReport> latest = <DateTime, ReceivedReport>{};
  for (final CoachMessage message in chat) {
    final DateTime? week = message.reportWeekStart;
    if (week == null) continue;
    final DateTime monday = DateTime(week.year, week.month, week.day);
    final ReceivedReport? seen = latest[monday];
    if (seen != null && seen.sentAt.isAfter(message.createdAt)) continue;
    latest[monday] = ReceivedReport(
      id: message.id,
      weekStart: monday,
      sentAt: message.createdAt,
      trainerName: trainerName,
      body: message.body,
      attachment: message.attachment,
    );
  }
  return latest.values.toList()..sort(
    (ReceivedReport a, ReceivedReport b) => b.weekStart.compareTo(a.weekStart),
  );
}

/// [all] 에서 서버가 줄 한 쪽을 잘라 준다 — [before] 보다 앞선 주 중 최신
/// [size] 주. 그 앞에 더 있으면 마지막 줄의 주가 다음 커서다.
ReceivedReportsPage pageReceivedReports(
  Iterable<ReceivedReport> all, {
  DateTime? before,
  int size = receivedReportsPageSize,
}) {
  final List<ReceivedReport> earlier =
      <ReceivedReport>[
        for (final ReceivedReport report in all)
          if (before == null || report.weekStart.isBefore(before)) report,
      ]..sort(
        (ReceivedReport a, ReceivedReport b) =>
            b.weekStart.compareTo(a.weekStart),
      );
  if (earlier.length <= size) return ReceivedReportsPage(reports: earlier);
  final List<ReceivedReport> page = earlier.sublist(0, size);
  return ReceivedReportsPage(reports: page, nextBefore: page.last.weekStart);
}
