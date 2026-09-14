import 'package:flutter/material.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 등록 안내. (#1421, #1600, #1577)
///
/// 트레이너 앱의 `ReportRegisteredCard` 와 **같은 정보 구조**다 — 아이콘,
/// `리포트가 등록되었어요`, 대상 주, 그리고 다음 행동 한 줄. 같은 사건이
/// 한쪽에서는 파일 카드로, 다른 쪽에서는 안내 카드로 보이면 두 사람이 같은
/// 리포트를 두고 다른 것을 본 채로 이야기하게 된다.
///
/// 자리는 말풍선이 아니라 **대화 가운데**다. 누가 무슨 말을 했는가가 아니라
/// 스레드에 무슨 일이 있었는가를 적는 자리라, 같은 흐름의 다른 안내(`분석했어요`·
/// `개인 추천운동을 받았어요`)와 같은 안내 배너([AppBanner] info)를 쓴다(#1577).
///
/// 다음 행동은 역할마다 다르다. 회원은 리포트를 열어 보고([onOpenPdf]),
/// 트레이너는 리포트 탭으로 간다.
class CoachReportCard extends StatelessWidget {
  /// Creates the card.
  const CoachReportCard({
    required this.weekStart,
    required this.onOpenPdf,
    super.key,
  });

  /// 카드가 가리키는 주의 월요일.
  final DateTime weekStart;

  /// `PDF 미리보기` 를 눌렀을 때.
  ///
  /// 첨부가 있으면 그 파일을, 없으면 같은 주를 회원 기록으로 정리한 문서를
  /// 연다 — 어느 쪽이든 열 것이 있으므로 버튼을 감추지 않는다(#1600).
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    final String range = l.coachChatReportWeek(
      weekStart.month,
      weekStart.day,
      weekEnd.month,
      weekEnd.day,
    );
    // 제목·기간·다음 행동을 세로로 쌓는 배너라, 글자 배율이 커져도 잘리는 대신
    // 상자가 아래로 자란다.
    return AppBanner(
      icon: Icons.description_rounded,
      title: l.coachChatReportRegistered,
      message: range,
      actionLabel: l.coachChatReportPreviewPdf,
      onAction: onOpenPdf,
    );
  }
}
