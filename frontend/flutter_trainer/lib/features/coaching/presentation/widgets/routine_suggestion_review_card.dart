import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_suggestion_edit_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The AI personal-exercise review area of the program tab (#790).
///
/// 정규 프로그램 편집기 **위**에 두고 시각적으로 갈라 둔다. 둘의 목적이 다르기
/// 때문이다 — 정규 프로그램은 일정 기간의 전체 계획이고, 개인운동은 PT 와 다음
/// PT 사이에 하는 짧은 보완·회복 운동이다. 그래서 편집기 안에 섞지 않고 여기서
/// `판단`만 한다: 그대로 추천 / 추천 안 함. 내용을 손보는 것은 판단이 아니라
/// 보조 동작이라, 카드 오른쪽 위의 연필로 뺐다(#939).
///
/// 승인은 새 배정을 만드는 것이 아니라 **이 제안을 배정으로 바꾸는 것**이다.
/// 회원 알림도 그 시점에 서버가 보낸다. 승인 전 후보는 회원에게 보이지 않는다.
class RoutineSuggestionReviewCard extends ConsumerStatefulWidget {
  /// Creates the review area for [clientId].
  const RoutineSuggestionReviewCard({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  /// Member whose suggestions are reviewed. 회원이 바뀌면 그 회원의 목록으로
  /// 갱신된다 — provider 가 회원별로 갈라져 있다.
  final String clientId;

  /// Member's display name, used in the intro line and the SnackBar.
  final String clientName;

  @override
  ConsumerState<RoutineSuggestionReviewCard> createState() =>
      _RoutineSuggestionReviewCardState();
}

class _RoutineSuggestionReviewCardState
    extends ConsumerState<RoutineSuggestionReviewCard> {
  /// 처리 중인 제안 id.
  ///
  /// 카드별로 담는 이유: 하나를 승인하는 동안 다른 제안은 계속 판단할 수 있어야
  /// 하지만, **같은 제안**의 두 번째 클릭은 막아야 한다. 서버가 409 로 다시
  /// 막아 주긴 하지만, 그 왕복 동안 트레이너는 아무 반응 없는 버튼을 두 번
  /// 누른 상태다.
  final Set<String> _busy = <String>{};

  /// 검토 없이 곧바로 나가던 승인 앞에 **최종 검토**를 세운다 (#1028).
  ///
  /// 여기서 승인은 곧 전송이다 — 서버가 이 제안을 배정으로 바꾸고 회원 알림도
  /// 그 시점에 나간다. 그런데 예전에는 목록의 `고객에게 추천` 한 번이 곧바로
  /// mutation 이었다: 옆 카드를 누르려다 손이 미끄러지면 회원에게 이미 가 있다.
  ///
  /// 그렇다고 이 제안을 프로그램 편집기의 최종 검토로 보내지는 **않았다**.
  /// 개인운동 제안은 기간 프로그램과 다른 물건이고(PT 사이를 메우는 짧은 운동),
  /// 서버가 승인/거절 수명주기를 따로 들고 있다(`approve`/`dismiss`, 이미 처리된
  /// 제안은 409). 프로그램 초안으로 옮겨 담으면 그 수명주기를 잃고 두 개념이
  /// 섞인다. 그래서 **이 제안만의 최종 검토**를 둔다 — 나갈 값(이름·시간·유형·
  /// 메모)을 그대로 보여 주고 확인을 받은 뒤에만 mutation 이 일어난다.
  Future<void> _confirmThenApprove(RoutineSuggestion suggestion) async {
    if (_busy.contains(suggestion.id)) return;
    final confirmed = await showRoutineSuggestionConfirmDialog(
      context,
      suggestion: suggestion,
      clientName: widget.clientName,
    );
    if (confirmed != true || !mounted) return;
    await _approve(suggestion);
  }

  Future<void> _approve(
    RoutineSuggestion suggestion, {
    RoutineSuggestionEdit? edit,
  }) async {
    final AppLocalizations l = AppLocalizations.of(context);
    await _review(
      suggestion,
      () => ref
          .read(trainerRoutineSuggestionRepositoryProvider)
          .approve(
            suggestion.id,
            name: edit?.name,
            minutes: edit?.minutes,
            type: edit?.type,
            // 근력이면 수정 창이 채운 세 값이 함께 간다. 그대로 승인(edit 이
            // null)이면 아무것도 보내지 않고, 서버가 제안 행에 이미 들고 있는
            // 값을 그대로 배정으로 옮긴다. (#1321)
            sets: edit?.sets,
            reps: edit?.reps,
            weight: edit?.weight,
            reason: edit?.reason,
          ),
      l.suggestionApproved(edit?.name ?? suggestion.name, widget.clientName),
    );
  }

  Future<void> _dismiss(RoutineSuggestion suggestion) async {
    final AppLocalizations l = AppLocalizations.of(context);
    await _review(
      suggestion,
      () => ref
          .read(trainerRoutineSuggestionRepositoryProvider)
          .dismiss(suggestion.id),
      l.suggestionDismissed(suggestion.name),
    );
  }

  Future<void> _editThenApprove(RoutineSuggestion suggestion) async {
    if (_busy.contains(suggestion.id)) return;
    final edit = await showRoutineSuggestionEditDialog(context, suggestion);
    if (edit == null || !mounted) return;
    await _approve(suggestion, edit: edit);
  }

  /// 검토 한 건을 실행하고 목록을 다시 읽는다.
  ///
  /// 성공하면 provider 를 invalidate 한다 — 카드를 화면에서만 지우면, 다른 창의
  /// 판단이나 서버가 이미 처리한 상태와 화면이 어긋난다. 목록을 다시 읽는 쪽이
  /// 언제나 서버의 사실과 같다.
  Future<void> _review(
    RoutineSuggestion suggestion,
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy.contains(suggestion.id)) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final reviewedFor = widget.clientId;
    setState(() => _busy.add(suggestion.id));
    try {
      await action();
      ref.invalidate(routineSuggestionsProvider(reviewedFor));
      if (!mounted) return;
      showAppToast(context, success, type: AppToastType.success);
    } on RoutineSuggestionAlreadyReviewed {
      // 두 번 눌렀거나 다른 창에서 이미 처리했다. 실패로 말하면 트레이너는 자기
      // 판단이 반영되지 않았다고 읽는다 — 실제로는 반영돼 있다.
      ref.invalidate(routineSuggestionsProvider(reviewedFor));
      if (!mounted) return;
      showAppToast(context, l.suggestionAlreadyReviewed);
    } on AppError catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.suggestionActionFailed),
        type: AppToastType.error,
      );
    } on Object {
      if (!mounted) return;
      showAppToast(context, l.suggestionActionFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _busy.remove(suggestion.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final pending = ref.watch(routineSuggestionsProvider(widget.clientId));
    final rows = pending.valueOrNull ?? const <RoutineSuggestion>[];
    final TextStyle quietStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textTertiary);

    return AppCard(
      key: const ValueKey<String>('routine-suggestion-review-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(
                  title: l.suggestionReviewTitle,
                  // 정규 프로그램 카드들과 한눈에 갈라지는 표시 — 여기는 AI 가
                  // 준비한 것을 판단하는 자리다.
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
              if (rows.isNotEmpty)
                AppTag(
                  key: const ValueKey<String>('routine-suggestion-badge'),
                  label: l.suggestionReviewBadge(rows.length),
                  tone: AppTagTone.brand,
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          switch (pending) {
            AsyncError() => Text(
              l.suggestionReviewLoadFailed,
              key: const ValueKey<String>('routine-suggestion-error'),
              style: quietStyle,
            ),
            // 목록이 비었을 때 큰 empty card 를 만들지 않는다 — 검토할 것이
            // 없는 날에도 프로그램 탭의 절반을 차지하면 안 된다.
            AsyncData(:final value) when value.isEmpty => Text(
              l.suggestionReviewEmpty,
              key: const ValueKey<String>('routine-suggestion-empty'),
              style: quietStyle,
            ),
            AsyncLoading() when rows.isEmpty => const Padding(
              padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
              child: Center(child: AppLoading.inline()),
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l.suggestionReviewIntro(widget.clientName),
                  // 카드 안의 근거 문구(`suggestion.reason`)와 같은 굵기다 — 이
                  // 줄만 진하면 안내문이 판단거리처럼 강조돼 보였다.
                  style: quietStyle,
                ),
                const SizedBox(height: OnCareSpacing.s12),
                for (final suggestion in rows) ...<Widget>[
                  _SuggestionCard(
                    key: ValueKey<String>(
                      'routine-suggestion-${suggestion.id}',
                    ),
                    suggestion: suggestion,
                    busy: _busy.contains(suggestion.id),
                    onApprove: () => _confirmThenApprove(suggestion),
                    onEdit: () => _editThenApprove(suggestion),
                    onDismiss: () => _dismiss(suggestion),
                  ),
                  if (suggestion != rows.last)
                    const SizedBox(height: OnCareSpacing.s8),
                ],
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// One suggestion: what it is, why, and the three judgements.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.suggestion,
    required this.busy,
    required this.onApprove,
    required this.onEdit,
    required this.onDismiss,
  });

  final RoutineSuggestion suggestion;

  /// 이 제안의 검토가 진행 중이다 — 세 버튼 모두 잠긴다.
  final bool busy;

  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle metaStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    final TextStyle metaStrongStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textTertiary);
    return Container(
      key: ValueKey<String>('routine-suggestion-surface-${suggestion.id}'),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
      ),
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                // 이름 - 종류 - 시간/분/회 를 한 줄에 둔다. 이름/종류/설명처럼
                // 줄을 나누면 셋을 훑는 데 시선이 세 번 움직였다.
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: suggestion.name,
                        style: tokens
                            .text(
                              OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              ),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      TextSpan(text: ' · ', style: metaStyle),
                      TextSpan(
                        text: routineTypeLabel(l, suggestion.type),
                        style: metaStrongStyle,
                      ),
                      TextSpan(text: ' · ', style: metaStyle),
                      TextSpan(
                        // 근력은 시간이 아니라 세트·횟수·중량으로 적는다 — 최종
                        // 검토 dialog·수정 창과 같은 함수를 쓴다. (#1321)
                        //
                        // 종류(`routineTypeLabel`)와 같은 크기·색이다 — 강조색을
                        // 쓰면 이 값만 판단거리처럼 튀어 보였다.
                        text: routineSuggestionAmountLabel(l, suggestion),
                        style: metaStrongStyle,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // `수정`·`거절` 은 판단이 아니라 **보조 동작**이다(#939). 아래
              // 줄에 세워 두면 `고객에게 추천` 과 함께 판단처럼 읽혔다. 손볼
              // 대상(운동 이름·시간) 옆에 연필·휴지통으로 둔다.
              const SizedBox(width: OnCareSpacing.s4),
              AppIconButton(
                key: ValueKey<String>(
                  'routine-suggestion-edit-${suggestion.id}',
                ),
                icon: Icons.edit_rounded,
                tooltip: l.actionEdit,
                color: tokens.brand.primary,
                onPressed: busy ? null : onEdit,
              ),
              AppIconButton(
                key: ValueKey<String>(
                  'routine-suggestion-dismiss-${suggestion.id}',
                ),
                icon: Icons.delete_outline_rounded,
                tooltip: l.suggestionDismiss,
                color: OnCareColors.textSecondary,
                onPressed: busy ? null : onDismiss,
              ),
            ],
          ),
          if (suggestion.reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Text(
              suggestion.reason,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ],
          if (suggestion.evidence.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // 근거는 서버가 만든 짧은 표시다 — AI 내부 분석을 길게 노출하지 않고
            // 트레이너가 승인 판단에 쓸 재료만 보여 준다.
            Wrap(
              spacing: OnCareSpacing.s4,
              runSpacing: OnCareSpacing.s4,
              children: <Widget>[
                for (final item in suggestion.evidence)
                  AppTag(label: item, tone: AppTagTone.brand),
              ],
            ),
          ],
          const SizedBox(height: OnCareSpacing.s12),
          // 아래 줄에는 **결정 하나**만 남는다 — 이 제안을 고객에게 줄 것인가.
          // 거절은 판단이 아니라 위의 휴지통으로 옮겼다(#939 후속).
          Align(
            alignment: Alignment.centerRight,
            // 진행 표시와 추천은 한 덩어리다 — 흘러넘쳐도 서로 떨어지지
            // 않아야 "무엇이 도는 중인지" 가 읽힌다.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy) ...<Widget>[
                  const AppLoading.inline(),
                  const SizedBox(width: OnCareSpacing.s8),
                ],
                AppButton(
                  key: ValueKey<String>(
                    'routine-suggestion-approve-${suggestion.id}',
                  ),
                  label: l.suggestionApprove,
                  size: OnCareButtonSize.small,
                  onPressed: busy ? null : onApprove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
