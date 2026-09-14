import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 오늘 처리해야 할 후속 관리 — 트레이너가 직접 남긴 업무 큐. (#869)
///
/// 옆의 `오늘 할 일` 카드와 나누어 둔다. 그쪽은 데이터에서 **파생된** 신호(답장
/// 대기·나트륨 초과)라 처리한다고 사라지지 않지만, 여기 있는 줄은 트레이너가
/// 직접 남기고 직접 닫는 기록이다. 한 카드에 섞으면 완료 버튼이 어떤 줄에는
/// 있고 어떤 줄에는 없는 목록이 된다.
///
/// 기한이 지난 항목도 함께 온다(서버 `scope=due`). 하루 지났다고 조용해지면
/// 놓치지 않으려고 만든 기능이 놓치는 경로가 된다.
class FollowUpCard extends ConsumerStatefulWidget {
  const FollowUpCard({super.key, this.maxRows = 5});

  /// 몇 줄까지 보여 줄지. 넘치는 만큼은 남은 건수로만 알린다.
  final int maxRows;

  @override
  ConsumerState<FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends ConsumerState<FollowUpCard> {
  /// 완료 처리 중인 할 일. 같은 줄을 두 번 눌러도 요청이 두 번 나가지 않는다.
  String? _completing;

  Future<void> _complete(FollowUpTask task) async {
    if (_completing != null) return;
    final l = AppLocalizations.of(context);
    setState(() => _completing = task.id);
    try {
      await ref.read(followUpTaskRepositoryProvider).complete(task.id);
      // 고객 상세의 남은 목록도 같은 데이터를 읽는다 — 한쪽만 갱신하면 이미 닫은
      // 할 일이 다른 화면에 남는다.
      ref
        ..invalidate(dueFollowUpsProvider)
        ..invalidate(clientFollowUpsProvider(task.memberId));
    } on AppError catch (error) {
      if (mounted) {
        _toast(serverDetailOr(l, error.message, l.followUpCompleteFailed));
      }
    } on Object {
      if (mounted) _toast(l.followUpCompleteFailed);
    } finally {
      if (mounted) setState(() => _completing = null);
    }
  }

  void _toast(String message) {
    showAppToast(context, message, type: AppToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final tasks = ref.watch(dueFollowUpsProvider);
    final List<FollowUpTask>? loaded = tasks.valueOrNull;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(
                  title: l.followUp,
                  icon: Icons.event_available_rounded,
                ),
              ),
              if (loaded != null && loaded.isNotEmpty)
                Text(
                  l.followUpCount(loaded.length),
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: tokens.brand.primary),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          tasks.when(
            loading: () => const AppLoading(placement: AppStatePlacement.card),
            // 후속 관리 조회가 실패해도 대시보드의 다른 카드는 그대로 산다 — 이
            // 카드 안에서만 다시 시도한다.
            error: (error, _) => AppErrorState(
              title: error is AppError
                  ? serverDetailOr(l, error.message, l.followUpLoadFailed)
                  : l.followUpLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(dueFollowUpsProvider),
              placement: AppStatePlacement.card,
            ),
            data: (list) => list.isEmpty
                ? AppEmptyState(
                    title: l.followUpDashboardEmpty,
                    icon: Icons.check_circle_rounded,
                    placement: AppStatePlacement.card,
                  )
                : Column(
                    children: <Widget>[
                      for (final task in list.take(widget.maxRows))
                        FollowUpRow(
                          key: ValueKey<String>(
                            'dashboard-follow-up-${task.id}',
                          ),
                          task: task,
                          showMemberName: true,
                          busy: _completing == task.id,
                          onComplete: () => _complete(task),
                          onTap: () => context.go(
                            AppRoutes.followUpTarget(
                              task.memberId,
                              task.context.wire,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 할 일 한 줄 — 예정일, (선택) 고객 이름, 내용, 완료 버튼.
///
/// 대시보드와 고객 상세가 같은 줄을 쓴다. 두 화면에서 모양이 갈리면 "완료"가
/// 어느 쪽에서 무엇을 뜻하는지 다시 배워야 한다.
class FollowUpRow extends StatelessWidget {
  const FollowUpRow({
    super.key,
    required this.task,
    required this.onComplete,
    this.onTap,
    this.showMemberName = false,
    this.busy = false,
  });

  final FollowUpTask task;
  final VoidCallback onComplete;
  final VoidCallback? onTap;

  /// 고객 이름을 함께 그릴지. 고객 상세는 이미 누구인지 아는 화면이라 끈다.
  final bool showMemberName;

  /// 이 줄의 완료 요청이 나가 있는 동안. 중복 클릭을 막는다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool overdue = task.isOverdue(todayKst());
    return AppListRow(
      title: task.title,
      subtitle: showMemberName && task.memberName.isNotEmpty
          ? task.memberName
          : null,
      leading: AppTag(
        // 지난 항목은 날짜 대신 그 사실을 말한다 — 목록에서 먼저 눈에 띄어야
        // 하는 정보가 "며칠인가"가 아니라 "늦었다"다.
        label: overdue ? l.followUpOverdue : ymd(task.dueDate),
        tone: overdue ? AppTagTone.danger : AppTagTone.brand,
      ),
      trailing: AppButton(
        key: ValueKey<String>('follow-up-complete-${task.id}'),
        label: l.followUpComplete,
        onPressed: busy ? null : onComplete,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
      ),
      onTap: onTap,
    );
  }
}
