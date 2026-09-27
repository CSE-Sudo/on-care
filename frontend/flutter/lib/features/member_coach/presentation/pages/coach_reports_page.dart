/// MY 탭 → 트레이너 리포트. 받은 리포트와 내가 보낸 주간 피드백. (#2232)
///
/// 대화 안에서만 리포트를 열 수 있던 동안에는, 지난주 리포트를 다시 보려면
/// 그 주의 메시지까지 스크롤을 올려야 했다. 리포트는 대화의 한 마디가 아니라
/// **쌓이는 기록**이라, 목록으로 볼 자리가 따로 있어야 한다.
///
/// 같은 화면에 주간 피드백을 둔 까닭: 회원 쪽에서 리포트와 피드백은 한 쌍이다.
/// 내가 보낸 답으로 트레이너가 리포트를 쓰고, 그 리포트가 여기로 돌아온다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/weekly_feedback_labels.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_opener.dart';
import 'package:oncare/features/member_coach/presentation/widgets/sent_weekly_feedback_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 받은 리포트 목록과 직전 주 피드백.
class CoachReportsPage extends ConsumerWidget {
  /// Creates the page.
  const CoachReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<SentReportNotice>> notices = ref.watch(
      sentReportNoticesProvider,
    );
    final AsyncValue<MemberWeeklyFeedback> feedback = ref.watch(
      lastWeekFeedbackProvider,
    );
    return AppPage(
      header: AppTopBar(title: l.myCoachReportsEntry),
      children: <Widget>[
        feedback.when(
          loading: () => const AppCard(
            child: AppLoading(placement: AppStatePlacement.card),
          ),
          // 피드백을 못 읽는 것이 리포트 목록을 막을 이유는 아니다 — 칸만 비운다.
          error: (Object _, StackTrace _) => AppCard(
            child: AppErrorState(
              title: l.weeklyFeedbackSendFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(lastWeekFeedbackProvider),
              placement: AppStatePlacement.card,
            ),
          ),
          data: (MemberWeeklyFeedback value) => SentWeeklyFeedbackCard(
            feedback: value,
            onSendNow: () => _openSheet(context, value),
          ),
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        AppSectionHeader(title: l.coachReportsSectionTitle),
        const SizedBox(height: OnCareSpacing.s12),
        notices.when(
          loading: () => const AppCard(
            child: AppLoading(placement: AppStatePlacement.card),
          ),
          error: (Object _, StackTrace _) => AppCard(
            child: AppErrorState(
              title: l.coachChatPdfOpenFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(sentReportNoticesProvider),
              placement: AppStatePlacement.card,
            ),
          ),
          data: (List<SentReportNotice> list) => list.isEmpty
              ? AppCard(
                  child: AppEmptyState(
                    key: const ValueKey<String>('coach-reports-empty'),
                    title: l.coachReportsEmpty,
                    message: l.coachReportsEmptyHint,
                    icon: AppIcons.document,
                    placement: AppStatePlacement.card,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final SentReportNotice notice in list) ...<Widget>[
                      _ReportRow(notice: notice),
                      if (notice != list.last)
                        const SizedBox(height: OnCareSpacing.s8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    MemberWeeklyFeedback feedback,
  ) async {
    await openWeeklyFeedbackSheet(
      context,
      weekStart: feedback.weekStart,
      // 이미 낸 주는 그 답을 채운 채로 연다 — 빈 칸으로 시작하면 회원이
      // 무엇을 보냈는지 모르는 채로 덮어쓴다.
      existing: feedback.submitted ? feedback : null,
    );
  }
}

/// 리포트 한 줄 — 누르면 그 주 문서를 연다.
class _ReportRow extends ConsumerStatefulWidget {
  const _ReportRow({required this.notice});

  final SentReportNotice notice;

  @override
  ConsumerState<_ReportRow> createState() => _ReportRowState();
}

class _ReportRowState extends ConsumerState<_ReportRow> {
  /// 문서를 만드는 동안 다시 누르지 못하게 한다 — 같은 문서를 두 번 그리면
  /// 미리보기가 두 겹으로 열린다.
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime sentAt = widget.notice.sentAt;
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListRow(
        key: ValueKey<String>(
          'coach-report-${ymdOfReportWeek(widget.notice.weekStart)}',
        ),
        title: weekRangeLabel(l, widget.notice.weekStart),
        subtitle: l.coachReportSentOn(sentAt.month, sentAt.day),
        leading: const AppIcon(AppIcons.document),
        trailing: _opening
            ? const AppLoading.inline()
            : const AppIcon(AppIcons.chevronRight),
        onTap: _opening ? null : _open,
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    try {
      await openCoachReport(
        context,
        ref,
        message: widget.notice.message,
        weekStart: widget.notice.weekStart,
      );
    } catch (_) {
      toast.show(l.coachChatPdfOpenFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
