import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_feedback_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart'
    show conditionLabel, intensityLabel;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 메모 창 `피드백` 탭 — 회원과 주고받은 피드백을 시간순으로 모아 본다. (#2615)
///
/// 읽기 전용이다. 쓰고 고치는 곳은 원래 자리(스케줄 일정·리포트 주) 하나뿐이라,
/// 항목을 누르면 창을 닫고 그 자리로 간다 — 고치는 곳이 둘이면 어느 쪽이
/// 최신인지 알 수 없다(#1011 과 같은 이유).
class ClientFeedbackSection extends ConsumerStatefulWidget {
  const ClientFeedbackSection({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClientFeedbackSection> createState() =>
      _ClientFeedbackSectionState();
}

class _ClientFeedbackSectionState extends ConsumerState<ClientFeedbackSection> {
  /// 피드백 검색어 — 메모 탭 검색칸(#2516)과 같은 모양, 화면에서만 거른다.
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<List<ClientFeedback>> feedbacks = ref.watch(
      clientFeedbacksProvider(widget.clientId),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 탭마다 공개 범위를 밝힌다 — 메모 탭은 `나만 보는 메모` 다(#2574).
        Text(
          key: const ValueKey<String>('client-feedback-scope'),
          l.clientFeedbackPrivate,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        feedbacks.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (Object error, _) => AppErrorState(
            key: const ValueKey<String>('client-feedback-retry'),
            placement: AppStatePlacement.card,
            title: error is AppError
                ? serverDetailOr(l, error.message, l.clientFeedbackLoadFailed)
                : l.clientFeedbackLoadFailed,
            retryLabel: l.actionRetry,
            onRetry: () =>
                ref.invalidate(clientFeedbacksProvider(widget.clientId)),
          ),
          data: (List<ClientFeedback> list) {
            if (list.isEmpty) {
              return AppEmptyState(
                key: const ValueKey<String>('client-feedback-empty'),
                placement: AppStatePlacement.card,
                title: l.clientFeedbackEmpty,
              );
            }
            final List<ClientFeedback> shown = _matching(l, list);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppSearchField(
                  key: const ValueKey<String>('client-feedback-search'),
                  controller: _query,
                  hint: l.clientFeedbackSearchHint,
                  clearTooltip: l.searchClear,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                if (shown.isEmpty)
                  AppEmptyState(
                    key: const ValueKey<String>('client-feedback-search-empty'),
                    placement: AppStatePlacement.card,
                    title: l.clientFeedbackSearchEmpty,
                  )
                else
                  for (final ClientFeedback item in shown) ...<Widget>[
                    _FeedbackTile(
                      clientId: widget.clientId,
                      item: item,
                      sourceLabel: feedbackSourceLabel(l, item),
                      directionLabel: feedbackDirectionLabel(l, item),
                    ),
                    const SizedBox(height: OnCareSpacing.s8),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// 검색어가 본문·출처·방향 문구에 든 피드백만. 주간 피드백은 칩 답(`지쳤어요`
  /// 등)과 아픈 곳으로도 찾힌다.
  List<ClientFeedback> _matching(
    AppLocalizations l,
    List<ClientFeedback> list,
  ) {
    final String query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return list;
    return <ClientFeedback>[
      for (final ClientFeedback item in list)
        if (<String>[
          item.body,
          feedbackSourceLabel(l, item),
          feedbackDirectionLabel(l, item),
          if (item.weekly case final MemberWeeklyFeedback weekly)
            weeklyAnswersLine(l, weekly),
        ].any((String text) => text.toLowerCase().contains(query)))
          item,
    ];
  }
}

/// 출처 태그 — `PT 세션 · 9/30`(메모 탭 출처 태그와 같은 이름), `리포트 · 9/22 주`, `주간 피드백 · 9/29 주`.
String feedbackSourceLabel(AppLocalizations l, ClientFeedback item) {
  final String date = '${item.date.month}/${item.date.day}';
  return switch (item.kind) {
    ClientFeedbackKind.ptSession => l.clientFeedbackSourcePt(date),
    ClientFeedbackKind.report => l.clientFeedbackSourceReport(date),
    ClientFeedbackKind.weekly => l.clientFeedbackSourceWeekly(date),
  };
}

/// 방향 태그 — 누가 누구에게 쓴 글인가.
String feedbackDirectionLabel(AppLocalizations l, ClientFeedback item) =>
    item.kind.fromMember
    ? l.clientFeedbackFromMember
    : l.clientFeedbackToMember;

/// 주간 피드백 세 문항을 한 줄로 — `컨디션 지쳤어요 · 운동 강도 힘들었어요 · 통증 무릎`.
/// 리포트 화면 ② 칸과 같은 문항 이름·답 문구다.
String weeklyAnswersLine(AppLocalizations l, MemberWeeklyFeedback weekly) =>
    <String>[
      _answer(
        l.reportsMemberFeedbackConditionLabel,
        conditionLabel(l, weekly.condition),
      ),
      _answer(
        l.reportsMemberFeedbackIntensityLabel,
        intensityLabel(l, weekly.intensity),
      ),
      _answer(
        l.reportsMemberFeedbackPainLabel,
        weekly.hasPain ? weekly.painArea : l.reportsMemberFeedbackPainNone,
      ),
    ].join(' · ');

String _answer(String question, String answer) => '$question $answer';

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({
    required this.clientId,
    required this.item,
    required this.sourceLabel,
    required this.directionLabel,
  });

  final String clientId;
  final ClientFeedback item;
  final String sourceLabel;
  final String directionLabel;

  /// 원래 자리 — PT 는 스케줄의 그 일정, 리포트·주간 피드백은 리포트의 그 주
  /// (리포트 ② 칸이 회원 주간 피드백을 보여 준다).
  String get _target => switch (item.kind) {
    ClientFeedbackKind.ptSession => AppRoutes.scheduleAt(
      date: ymd(item.date),
      sessionId: item.scheduleId,
    ),
    _ => AppRoutes.reportFor(clientId, weekStart: item.weekStart ?? item.date),
  };

  void _open(BuildContext context) {
    // 창을 닫은 뒤에는 이 context 가 사라진다 — 라우터를 먼저 잡아 둔다.
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(_target);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final MemberWeeklyFeedback? weekly = item.weekly;
    return AppTile(
      key: ValueKey<String>('client-feedback-${item.id}'),
      // 메모 목록과 같은 흰 바탕 테두리 — 탭을 바꿔도 같은 목록 모양이다.
      tone: AppTileTone.outline,
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 머리 줄: 왼쪽에 출처 태그, 오른쪽 끝에 방향. 방향은 출처보다 덜
          // 중요한 덧말이라 태그 모양 없이 회색 글자로 둔다.
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppTag(
                    key: ValueKey<String>('client-feedback-source-${item.id}'),
                    label: sourceLabel,
                    // PT 세션은 메모 탭의 `PT 세션 · 9/30` 태그와 같은 파랑이다.
                    tone: item.kind == ClientFeedbackKind.ptSession
                        ? AppTagTone.brand
                        : AppTagTone.neutral,
                    icon: switch (item.kind) {
                      ClientFeedbackKind.ptSession => AppIcons.exercise,
                      ClientFeedbackKind.report => AppIcons.reports,
                      ClientFeedbackKind.weekly => AppIcons.note,
                    },
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Text(
                key: ValueKey<String>('client-feedback-direction-${item.id}'),
                directionLabel,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 본문은 태그 글자와 같은 선에서 시작한다(태그 안쪽 여백 8).
          Padding(
            padding: const EdgeInsetsDirectional.only(start: OnCareSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (weekly != null) ...<Widget>[
                  _WeeklyAnswers(
                    key: ValueKey<String>('client-feedback-answers-${item.id}'),
                    weekly: weekly,
                  ),
                  // 고른 답과 회원이 직접 쓴 글은 다른 말이다 — 붙어 있으면
                  // 한 문단(인용)처럼 읽힌다.
                  const SizedBox(height: OnCareSpacing.s8),
                ],
                if (item.body.isNotEmpty)
                  Text(
                    item.body,
                    // 리포트 본문은 길다 — 목록에서는 앞부분만, 전문은 원래 자리에서.
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.body)
                        .copyWith(color: OnCareColors.textPrimary),
                  )
                else if (item.kind == ClientFeedbackKind.weekly)
                  Text(
                    l.clientFeedbackWeeklyNoNote,
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 주간 피드백 세 문항의 답 — `컨디션 지쳤어요` 처럼 문항 이름은 옅게, 답은
/// 진하게 칸을 나눠 둔다. 한 줄 문장이면 회원 글을 인용한 것처럼 읽혔다.
/// 세 답은 같은 색이다 — 아픈 곳만 빨강이면 한 칸만 튀어 어색했다.
class _WeeklyAnswers extends StatelessWidget {
  const _WeeklyAnswers({super.key, required this.weekly});

  final MemberWeeklyFeedback weekly;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    Widget answer(String question, String value) => Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '$question  ',
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          TextSpan(
            text: value,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: OnCareSpacing.s16,
      runSpacing: OnCareSpacing.s4,
      children: <Widget>[
        answer(
          l.reportsMemberFeedbackConditionLabel,
          conditionLabel(l, weekly.condition),
        ),
        answer(
          l.reportsMemberFeedbackIntensityLabel,
          intensityLabel(l, weekly.intensity),
        ),
        answer(
          l.reportsMemberFeedbackPainLabel,
          weekly.hasPain ? weekly.painArea : l.reportsMemberFeedbackPainNone,
        ),
      ],
    );
  }
}
