import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ② 작성의 `트레이너 피드백` 카드.
///
/// 편집기는 [child] 에 입력창을, 보낸 리포트와 PDF 는 [ReportFeedbackText] 를
/// 얹는다(#2425, #2424). 카드 틀과 제목이 한 곳에서 오므로, 회원이 받은 글이
/// 트레이너가 쓰던 카드와 다른 모양으로 보이는 일이 없다.
class ReportFeedbackCard extends StatelessWidget {
  /// Creates the feedback card.
  const ReportFeedbackCard({super.key, required this.child, this.trailing});

  /// 제목 줄 오른쪽 동작 — 편집기의 저장·되돌리기. 읽기 전용이면 비운다.
  final Widget? trailing;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return ReportSectionCard(
      key: const ValueKey<String>('report-feedback-card'),
      title: l.reportsFeedbackTitle,
      trailing: trailing,
      child: child,
    );
  }
}

/// 이미 정해진 피드백 글 — 입력창과 같은 칸 모양에 글만 담는다.
///
/// 보낸 글은 입력창에 담지 않는다. 고칠 수 없는 글을 고칠 수 있게 생긴 자리에
/// 두면 고친 뒤에야 못 보낸다는 걸 안다(#2232). 그래도 칸의 채움·테두리·여백은
/// 편집기의 입력창과 같게 둔다 — 트레이너가 ② 에서 본 모양 그대로 회원에게
/// 간다는 것을 한눈에 알 수 있어야 한다(#2425).
class ReportFeedbackText extends StatelessWidget {
  /// Creates the read-only body showing [text].
  const ReportFeedbackText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool blank = text.trim().isEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        // 여러 줄 입력창과 같은 규칙 — 웹에서만 회색 채움이다(#1836).
        color: tokens.density.isWeb
            ? OnCareColors.surfaceInput
            : OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(OnCareSpacing.s12),
        child: Text(
          // 빈 칸으로 두면 무엇이 빠졌는지 알 수 없다 — PDF 와 같은 말을 둔다.
          blank ? l.reportsPdfNoFeedback : text,
          key: const ValueKey<String>('report-feedback-text'),
          style: tokens
              .text(OnCareTypography.body)
              .copyWith(
                color: blank
                    ? OnCareColors.textTertiary
                    : OnCareColors.textPrimary,
              ),
        ),
      ),
    );
  }
}
