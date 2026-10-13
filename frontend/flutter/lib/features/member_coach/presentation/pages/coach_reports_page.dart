/// MY 탭 → 트레이너 리포트. 받은 리포트와 내가 보낸 주간 피드백. (#2232)
///
/// 대화 안에서만 리포트를 열 수 있던 동안에는, 지난주 리포트를 다시 보려면
/// 그 주의 메시지까지 스크롤을 올려야 했다. 리포트는 대화의 한 마디가 아니라
/// **쌓이는 기록**이라, 목록으로 볼 자리가 따로 있어야 한다.
///
/// 같은 화면에 주간 피드백을 둔 까닭: 회원 쪽에서 리포트와 피드백은 한 쌍이다.
/// 내가 보낸 답으로 트레이너가 리포트를 쓰고, 그 리포트가 여기로 돌아온다.
///
/// 받은 리포트는 담당이 해제·교체된 뒤에도 남는다(#3348). 그때는 피드백 칸 없이
/// 목록만 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/weekly_feedback_labels.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_opener.dart';
import 'package:oncare/features/member_coach/presentation/widgets/sent_weekly_feedback_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_error_state_for.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 받은 리포트 목록과 직전 주 피드백.
class CoachReportsPage extends ConsumerWidget {
  /// Creates the page.
  const CoachReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<ReceivedReportsState> received = ref.watch(
      receivedReportsProvider,
    );
    // 담당이 없으면 피드백을 받을 사람이 없다 — 그 칸은 세우지 않고 받은
    // 리포트만 보여 준다(#3348). 담당을 아직 못 읽은 동안에는 그대로 둔다.
    final AsyncValue<MemberCoach?> coach = ref.watch(memberCoachProvider);
    final bool noCoach = coach.hasValue && coach.value == null;
    return AppPage(
      header: AppTopBar(title: l.myCoachReportsEntry),
      children: <Widget>[
        if (!noCoach) ...<Widget>[
          const _LastWeekFeedback(),
          const SizedBox(height: OnCareSpacing.sectionGap),
        ],
        AppSectionHeader(title: l.coachReportsSectionTitle),
        const SizedBox(height: OnCareSpacing.s12),
        received.when(
          loading: () => const AppCard(
            child: AppLoading(placement: AppStatePlacement.card),
          ),
          error: (Object error, StackTrace _) => AppCard(
            child: appErrorStateFor(
              context,
              // 목록을 읽지 못한 것이지 문서를 열지 못한 것이 아니다(#2643).
              error: error,
              title: l.coachReportsLoadFailed,
              onRetry: () => ref.invalidate(receivedReportsProvider),
              placement: AppStatePlacement.card,
            ),
          ),
          data: (ReceivedReportsState state) => state.reports.isEmpty
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
                    for (final ReceivedReport report
                        in state.reports) ...<Widget>[
                      _ReportRow(report: report),
                      if (report != state.reports.last)
                        const SizedBox(height: OnCareSpacing.s8),
                    ],
                    // 한 해치보다 오래 받은 회원만 본다 — 그 앞은 누를 때 받는다.
                    if (state.hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: OnCareSpacing.s12),
                        child: Center(
                          child: state.loadingMore
                              ? const AppLoading.inline()
                              : AppButton(
                                  key: const ValueKey<String>(
                                    'coach-reports-load-more',
                                  ),
                                  label: l.coachReportsLoadMore,
                                  variant: AppButtonVariant.text,
                                  size: OnCareButtonSize.small,
                                  onPressed: () => ref
                                      .read(receivedReportsProvider.notifier)
                                      .loadMore(),
                                ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 직전 주에 보낸 피드백 칸.
class _LastWeekFeedback extends ConsumerWidget {
  const _LastWeekFeedback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<MemberWeeklyFeedback> feedback = ref.watch(
      lastWeekFeedbackProvider,
    );
    return feedback.when(
      loading: () =>
          const AppCard(child: AppLoading(placement: AppStatePlacement.card)),
      // 피드백을 못 읽는 것이 리포트 목록을 막을 이유는 아니다 — 칸만 비운다.
      error: (Object error, StackTrace _) => AppCard(
        child: appErrorStateFor(
          context,
          // 읽기 실패다 — `보내지 못했어요` 로 안내하면 무엇을 다시 해야
          // 하는지 알 수 없다(#2643).
          error: error,
          title: l.weeklyFeedbackLoadFailed,
          onRetry: () => ref.invalidate(lastWeekFeedbackProvider),
          placement: AppStatePlacement.card,
        ),
      ),
      data: (MemberWeeklyFeedback value) => SentWeeklyFeedbackCard(
        feedback: value,
        onSendNow: () => _openSheet(context, value),
      ),
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
  const _ReportRow({required this.report});

  final ReceivedReport report;

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
    // 서버 시각(UTC 순간)을 표시 직전에 KST 로 바꾼다 — 그대로 쓰면 KST 오전
    // 0~9시에 보낸 리포트가 전날로 보인다(#2844). 정렬·비교는 원래 값을 쓴다.
    final DateTime sentAt = toKst(widget.report.sentAt);
    final String sentOn = l.coachReportSentOn(sentAt.month, sentAt.day);
    // 누가 보냈는지 함께 적는다 — 트레이너가 바뀐 회원은 이전 트레이너의
    // 리포트와 지금 트레이너의 것이 한 목록에 선다(#3348). 탈퇴한 트레이너는
    // 이름이 없어 보낸 날만 적는다.
    final String? trainerName = widget.report.trainerName;
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListRow(
        key: ValueKey<String>(
          'coach-report-${wireDate(widget.report.weekStart)}',
        ),
        title: weekRangeLabel(l, widget.report.weekStart),
        subtitle: trainerName == null
            ? sentOn
            : l.coachReportSentBy(trainerName, sentOn),
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
        message: widget.report.notice,
        weekStart: widget.report.weekStart,
      );
    } catch (e) {
      toast.show(reportOpenFailureText(l, e), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
