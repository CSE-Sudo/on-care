/// 감지 기록 창 — AI 코치 채팅과 운동 탭의 AI 추천 개인운동이 나눠 쓴다.
///
/// 두 화면이 같은 것을 가리키므로 창·삭제 흐름을 한 벌만 둔다(#1824 · #1975 ·
/// #2015). 예전에는 AI 코치 화면 안에만 있어, 운동 탭에서는 무엇이 반영됐는지
/// 볼 수도 잘못 잡힌 감지를 치울 수도 없었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 감지 기록 창을 연다. 열 때마다 다시 읽는다 — 다른 화면에서 지운 것이
/// 그대로 남아 있으면 안 된다.
void showInsightHistorySheet(BuildContext context, WidgetRef ref) {
  ref.invalidate(aiCoachInsightsProvider);
  showAppSheet<void>(
    context: context,
    builder: (BuildContext _) => const InsightHistorySheet(),
  );
}

/// 감지 한 줄의 이름 — `무릎 통증 감지` / `통증 감지` / `부정적 반응 감지`.
String insightLabel(AppLocalizations l, ChatInsight insight) =>
    switch (insight.kind) {
      ChatInsightKind.discomfort => switch (insight.bodyPart) {
        final String part => l.aicInsightDiscomfortPart(part),
        null => l.aicInsightDiscomfort,
      },
      ChatInsightKind.negativeFeedback => l.aicInsightNegative,
    };

/// 최근 30일 감지 기록 창(#1824).
class InsightHistorySheet extends ConsumerWidget {
  const InsightHistorySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<ChatInsightHistory> history = ref.watch(
      aiCoachInsightsProvider,
    );
    final int days = history.valueOrNull?.windowDays ?? kChatInsightWindowDays;
    return AppSheet(
      key: const Key('aiCoachInsightHistorySheet'),
      showClose: false,
      title: l.aicInsightHistoryTitle,
      subtitle: l.aicInsightHistorySubtitle(days),
      child: history.when(
        loading: () => const AppLoading(),
        error: (_, _) => Text(
          l.aicInsightHistoryFailed,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        data: (ChatInsightHistory value) => value.records.isEmpty
            ? Text(
                l.aicInsightHistoryEmpty(value.windowDays),
                key: const Key('aiCoachInsightHistoryEmpty'),
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int i, ChatInsightRecord record)
                      in value.records.indexed) ...<Widget>[
                    if (i > 0) const AppDivider(),
                    _InsightRow(record: record),
                  ],
                ],
              ),
      ),
    );
  }
}

class _InsightRow extends ConsumerWidget {
  const _InsightRow({required this.record});

  final ChatInsightRecord record;

  /// 이 줄의 감지를 기록에서 치운다. (#1975)
  ///
  /// 되돌릴 수 없으므로 **확인창을 먼저 거친다.** 문구는 무엇이 사라지고 무엇이
  /// 남는지 말한다 — 회원이 쓴 말까지 지워지는 줄 알면 누르지 못한다.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.aicInsightDelete,
      message: l.aicInsightDeleteConfirm,
      confirmLabel: l.aicInsightDelete,
      cancelLabel: l.myCancel,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(aiCoachRepositoryProvider).dismissInsight(record.messageId);
    } on Object {
      toast.show(l.aicInsightDeleteFailed, type: AppToastType.error);
      return;
    }
    ref.invalidate(aiCoachInsightsProvider);
    // 담당이 없는 회원의 AI 추천은 이 감지로 좁혀져 있다(#2016). 이 창은 운동
    // 탭의 추천 칸에서도 열린다 — 탭을 옮기지 않으니 목록을 여기서 다시 받아야
    // 치운 감지로 뺐던 운동이 그 자리에서 돌아온다.
    ref.invalidate(coachRoutinesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String date = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(record.createdAt);
    return Padding(
      key: ValueKey<String>('aiCoachInsightRow-${record.messageId}'),
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(
                label: insightLabel(l, record.insight),
                // 말풍선 아래 배지와 같은 것을 가리킨다 — 톤도 같다(#1975).
                tone: AppTagTone.danger,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  date,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
              // 잘못 잡힌 감지를 치우는 자리(#1975). 줄의 오른쪽 끝에 둔다 —
              // 어느 줄을 지우는지는 같은 줄에 있어야 분명하다.
              AppButton(
                key: ValueKey<String>(
                  'aiCoachInsightDelete-${record.messageId}',
                ),
                label: l.aicInsightDelete,
                variant: AppButtonVariant.destructiveText,
                size: OnCareButtonSize.small,
                onPressed: () => _confirmDelete(context, ref),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            record.text,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
