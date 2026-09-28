import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이미 보낸 리포트를 **회원이 받은 그대로** 다시 보는 화면.
///
/// 작업대의 `전송 완료` 줄을 누르면 열린다. 편집기가 아니다 — 여기서 고친
/// 글은 이미 회원 손에 있는 글을 바꾸지 못한다. 그래서 입력창 대신 보낸
/// 본문을 그대로 얹고, 다시 쓰려면 새 초안으로 편집기를 연다. (#2232)
///
/// 카드는 편집기 ① 확인·② 작성과 같은 위젯이다 — 따로 그린 요약 카드를 두면
/// 트레이너가 본 화면, 회원이 받은 PDF, 되짚는 화면이 서로 달라진다(#2425).
class SentReportView extends StatelessWidget {
  /// Creates the view.
  const SentReportView({
    super.key,
    required this.report,
    required this.record,
    required this.onBack,
    required this.onRewrite,
    this.onHistory,
    this.backLabel,
    this.calorieBaseline,
  });

  /// 그 주의 수치.
  final WeeklyReport report;

  /// 직전 넉 주의 하루 평균 섭취 칼로리 — 편집기 ① 칼로리 줄과 같은 `평소`.
  /// 아직 안 읽혔거나 견줄 기록이 없으면 null 이다.
  final double? calorieBaseline;

  /// 무엇을 언제 보냈는가.
  final ReportSendRecord record;

  /// 들어온 곳으로 돌아간다 — 작업대, 또는 그 회원의 지난 리포트(#2394).
  final VoidCallback onBack;

  /// 이 내용으로 편집기를 다시 연다.
  final VoidCallback onRewrite;

  /// 이 회원의 지난 리포트를 연다(#2394). null 이면 링크를 두지 않는다 —
  /// 지난 리포트에서 들어왔으면 돌아가기가 이미 그곳으로 간다.
  final VoidCallback? onHistory;

  /// 돌아가기 버튼의 글. 비우면 작업대로 돌아가는 글이다.
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppBackLink(
              key: const ValueKey<String>('reports-sent-back'),
              label: backLabel ?? l.reportsBackToWorkbench,
              onPressed: onBack,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          AppCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l.reportsSentHeadline(record.clientName(report)),
                        style: tokens.text(OnCareTypography.titleSmall),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        l.reportsSentAt(
                          dateLabel(l, record.sentAt),
                          _hhmm(record.sentAt),
                        ),
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (onHistory case final VoidCallback openHistory) ...<Widget>[
                  AppButton(
                    key: const ValueKey<String>('reports-sent-history'),
                    label: l.reportsHistoryButton,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    onPressed: openHistory,
                  ),
                  const SizedBox(width: OnCareSpacing.s4),
                ],
                AppButton(
                  key: const ValueKey<String>('reports-sent-rewrite'),
                  label: l.reportsSentRewrite,
                  variant: AppButtonVariant.secondary,
                  size: OnCareButtonSize.small,
                  onPressed: onRewrite,
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          // 편집기 ① 확인과 **같은 카드**다(#2425). 다른 그림으로 되짚으면
          // "그때 이걸 보고 이렇게 썼다" 를 확인할 수 없다. 회원이 받은 PDF 도
          // 같은 카드를 구워 담는다(#2424).
          ReportReviewCards(report: report, calorieBaseline: calorieBaseline),
          const SizedBox(height: OnCareSpacing.s16),
          // ② 작성의 피드백 카드 — 입력창 대신 보낸 글을 같은 칸에 얹는다.
          ReportFeedbackCard(
            child: ReportFeedbackText(
              // 데모로 깔아 둔 기록은 본문이 비어 있다. 그 자리는 그 주
              // 수치에서 만든 문구가 채운다 — 빈 카드를 보여 주는 대신,
              // 회원이 받았을 글과 같은 규칙으로 만든 글을 세운다.
              text: record.message.isEmpty
                  ? reportMessage(l, report)
                  : record.message,
            ),
          ),
        ],
      ),
    );
  }
}

/// `HH:MM` — 전송 시각은 초까지 볼 이유가 없다.
String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

extension on ReportSendRecord {
  /// 리포트가 누구 것인가 — 기록은 id 만 들고 있어 리포트에서 이름을 읽는다.
  String clientName(WeeklyReport report) => report.client.name;
}
