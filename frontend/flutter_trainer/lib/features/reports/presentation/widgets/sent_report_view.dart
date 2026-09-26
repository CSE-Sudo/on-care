import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이미 보낸 리포트를 **회원이 받은 그대로** 다시 보는 화면.
///
/// 작업대의 `전송 완료` 줄을 누르면 열린다. 편집기가 아니다 — 여기서 고친
/// 글은 이미 회원 손에 있는 글을 바꾸지 못한다. 그래서 입력창 대신 보낸
/// 본문을 그대로 얹고, 다시 쓰려면 새 초안으로 편집기를 연다. (#2232)
class SentReportView extends StatelessWidget {
  /// Creates the view.
  const SentReportView({
    super.key,
    required this.report,
    required this.record,
    required this.onBack,
    required this.onRewrite,
  });

  /// 그 주의 수치.
  final WeeklyReport report;

  /// 무엇을 언제 보냈는가.
  final ReportSendRecord record;

  /// 작업대로 돌아간다.
  final VoidCallback onBack;

  /// 이 내용으로 편집기를 다시 연다.
  final VoidCallback onRewrite;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              key: const ValueKey<String>('reports-sent-back'),
              label: l.reportsBackToWorkbench,
              variant: AppButtonVariant.text,
              leadingIcon: Icons.chevron_left_rounded,
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
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppSectionHeader(
                  icon: Icons.mail_outline_rounded,
                  title: l.reportsSentBody,
                ),
                const SizedBox(height: OnCareSpacing.s12),
                // 보낸 글은 입력창에 담지 않는다 — 고칠 수 없는 글을 고칠 수
                // 있게 생긴 자리에 두면 고친 뒤에야 못 보낸다는 걸 안다.
                Text(
                  // 데모로 깔아 둔 기록은 본문이 비어 있다. 그 자리는 그 주
                  // 수치에서 만든 문구가 채운다 — 빈 카드를 보여 주는 대신,
                  // 회원이 받았을 글과 같은 규칙으로 만든 글을 세운다.
                  record.message.isEmpty
                      ? reportMessage(l, report)
                      : record.message,
                  style: tokens.text(OnCareTypography.bodySmall),
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppSectionHeader(
                  icon: Icons.insights_rounded,
                  title: l.reportsSentFigures,
                ),
                const SizedBox(height: OnCareSpacing.s12),
                // 보낼 때 트레이너가 본 것과 **같은 격자**다. 다른 그림으로
                // 되짚으면 "그때 이걸 보고 이렇게 썼다" 를 확인할 수 없다.
                ReportWeekGrid(report: report),
                const SizedBox(height: OnCareSpacing.s16),
              ],
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
