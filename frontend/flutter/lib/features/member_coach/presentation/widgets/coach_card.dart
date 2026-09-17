import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart'
    show exerciseTypeFromLabel;
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart'
    show exerciseAmountLabelOf, exerciseWeightLabel;
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/my_health/presentation/points_reward.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
// 토스트는 아직 앱의 AppToastHost 를 쓴다 — 패키지 쪽 같은 이름은 가린다.
import 'package:oncare_ui/oncare_ui.dart';

/// 담당 트레이너 관계와 소통만 담는다 — 이름·전문 분야·프로필 이동·채팅.
///
/// 추천 개인운동은 여기 있지 않다. 트레이너 추천이든 AI 추천이든 회원에게는
/// "지금 무엇을 하면 되는가" 라는 한 가지 질문이라, [AiCoachingCard] 의
/// `추천 개인운동` 한 곳에 모았다(#782). 예전에는 이 카드와 AI 카드가 화면
/// 두 곳에 나뉘어 있어 둘의 관계와 우선순위를 회원이 다시 해석해야 했다.
class CoachCard extends ConsumerWidget {
  const CoachCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final coachAsync = ref.watch(memberCoachProvider);
    final coach = coachAsync.valueOrNull;
    if (coach == null) return const SizedBox.shrink();
    // 트레이너 상세는 이제 트레이너 id 로 라우팅한다 — 한 헬스장에
    // 여러 명이 있으므로 헬스장 id 로는 한 명을 특정할 수 없다.
    final assignedTrainer = ref.watch(myTrainerProvider).valueOrNull;

    final unread = ref.watch(coachUnreadProvider).valueOrNull ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s24,
        0,
        OnCareSpacing.s24,
        OnCareSpacing.s20,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('assignedTrainerProfile'),
                onTap: assignedTrainer == null
                    ? null
                    : () => context.push(
                        AppRoutes.trainerDetailPath(assignedTrainer.id),
                      ),
                borderRadius: OnCareRadius.mdAll,
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: OnCareSize.avatarMedium,
                      height: OnCareSize.avatarMedium,
                      child: AppIcon(
                        AppIcons.person,
                        color: tokens.brand.primary,
                        size: OnCareSize.iconMedium,
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l.coachAssignedTrainer,
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.caption,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textTertiary),
                          ),
                          Text(
                            '${coach.name} · ${coach.specialty}',
                            style: tokens
                                .text(OnCareTypography.titleSmall)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    // 화살표는 '누르면 간다'는 신호다. 트레이너 상세로 갈 수
                    // 없을 때(myTrainerProvider 가 아직 없거나 연결이 끊긴
                    // 경우)는 지운다 — 예전에는 화살표만 남아 눌러도 아무 일이
                    // 없었다(#786).
                    if (assignedTrainer != null)
                      const AppIcon(
                        AppIcons.chevronRight,
                        size: OnCareSize.iconMedium,
                        color: OnCareColors.textTertiary,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            _ChatButton(
              unread: unread,
              onTap: () =>
                  openTrainerChatPage(context, trainerName: coach.name),
            ),
          ],
        ),
      ),
    );
  }
}

/// 운동 탭의 `AI 코칭` — 코칭 포인트와 추천 개인운동을 한 흐름으로 보여준다.
///
/// 예전에는 `AI 맞춤 조언`(텍스트)과 `AI 맞춤 운동`(카드)이 화면 위아래로 멀리
/// 떨어져 있고 그 사이에 운동 현황·트레이너 카드가 끼어 있었다. 둘은 같은
/// 기록에서 나온 같은 판단인데, 회원은 "왜 이 운동인지" 를 다시 이어 붙여야
/// 했다(#782).
///
/// 추천 개인운동은 `추가 운동` 이 아니라 **PT 와 다음 PT 사이에 스스로 하는
/// 운동**이다. 그래서 추천할 것이 없는 날은 빈 카드를 만들지 않고 코칭 포인트만
/// 남긴다 — AI 가 매번 운동을 억지로 만들어 낼 이유가 없다.
class AiCoachingCard extends ConsumerWidget {
  const AiCoachingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 트레이너 추천과 AI 추천을 한 목록으로 합친다. 회원에게는 "지금 무엇을
    // 하면 되는가" 라는 한 가지 질문이고, 누가 정했는지는 각 줄의 출처가 말한다.
    final List<CoachRoutine> routines =
        ref.watch(coachRoutinesProvider).valueOrNull ?? const <CoachRoutine>[];
    final MemberCoach? coach = ref.watch(memberCoachProvider).valueOrNull;

    // 추천이 없으면 카드 자체를 그리지 않는다. 빈 카드는 자리만 차지하고
    // 아무것도 알려 주지 않는다.
    //
    // 예전에는 이 카드가 `이번 코칭 포인트` 도 함께 말했다. 지금은 화면 위쪽의
    // AI 맞춤 조언 카드가 그 말을 하므로 여기서는 뺐다 — 같은 말이 한 화면에
    // 두 번 있으면 안 된다. (#1021)
    if (routines.isEmpty) return const SizedBox.shrink();

    return AppCard(
      key: const Key('aiCoachingCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 카드가 말하는 것은 `AI 코칭` 이 아니라 **추천 개인운동**이다
          // (#1130). 제목이 곧 내용이라 아이콘도 운동 쪽으로 바꿨다. 큰 글자
          // 배율에서는 제목이 줄을 바꿔 카드 안에 머문다(#766).
          AppSectionHeader(title: l.coachRoutineTitle, icon: AppIcons.running),
          // 카드 제목이 이미 `추천 개인운동` 이라 안에 같은 말을 또 두지
          // 않는다. `PT 와 다음 PT 사이…` 안내도 뺐다 (#1130).
          const SizedBox(height: OnCareSpacing.s12),
          for (final (int index, CoachRoutine routine)
              in routines.indexed) ...<Widget>[
            // 여러 세션짜리 프로그램은 첫 세션 위에 프로그램 이름을 한 번
            // 얹는다 — 세션 카드가 어디에 묶이는지 보이지 않으면 그냥 낱개
            // 루틴 여러 개로 읽힌다(#709).
            if (routine.programName.isNotEmpty &&
                (index == 0 ||
                    routines[index - 1].programName != routine.programName))
              Padding(
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                child: Row(
                  children: <Widget>[
                    AppIcon(
                      AppIcons.routine,
                      size: OnCareSize.iconSmall,
                      color: tokens.brand.primary,
                    ),
                    const SizedBox(width: OnCareSpacing.s4),
                    Expanded(
                      child: Text(
                        routine.programName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            _RecommendedExerciseRow(
              routine: routine,
              sourceLabel: routineSourceLabel(l, routine, coach),
              // 담당이 배정한 것을 회원이 조용히 없애면 다음 상담에서 둘이
              // 서로 다른 기록을 본다. 담당이 없을 때만 스스로 물린다. (#1020)
              cancellable: coach == null,
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
        ],
      ),
    );
  }
}

/// 추천 운동을 했는지 표시하는 체크 박스. (#1021)
///
/// 체크한 것을 다시 누르면 **묻고 나서** 되돌린다 (#1131). 수행은 기록으로 남아
/// 주간 시간·칼로리에 더해지고 트레이너에게도 보이므로, 조용히 지워지면 안 되지만
/// 잘못 누른 체크를 풀 방법이 아예 없어도 안 된다.
class _RoutineCheckbox extends StatelessWidget {
  const _RoutineCheckbox({
    super.key,
    required this.done,
    required this.saving,
    required this.onCheck,
  });

  final bool done;
  final bool saving;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 저장 중 스피너와 체크 박스가 같은 최소 터치 크기 칸을 차지해 줄이 들썩이지
    // 않는다. 모양은 테마의 체크 박스 규격을 그대로 따른다.
    return SizedBox.square(
      dimension: context.oncare.density.minTouchTarget,
      child: Center(
        child: saving
            ? const AppLoading.inline()
            : Semantics(
                checked: done,
                label: l.coachRoutineDone,
                child: Checkbox(
                  value: done,
                  onChanged: (bool? _) => onCheck(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
      ),
    );
  }
}

/// 회원이 읽을 수 있는 추천 출처 문구.
///
/// 내부 `source` 값을 그대로 보여 주지 않는다. 회원이 알아야 할 것은 "누가
/// 확인했는가" 다 — 트레이너가 본 추천과 AI 가 혼자 낸 추천은 무게가 다르다.
///
/// 담당 트레이너가 있으면 AI 추천은 승인된 것만 내려온다(#790). 그래서 여기
/// 도착한 AI 추천에 `트레이너 확인` 을 붙이는 것이 사실이다.
String routineSourceLabel(
  AppLocalizations l,
  CoachRoutine routine,
  MemberCoach? coach,
) {
  if (routine.isTrainerRecommended) return l.coachRoutineByTrainer;
  if (coach != null) return l.coachRoutineAiChecked(coach.name);
  return l.coachRoutineAiAuto;
}

class _RecommendedExerciseRow extends ConsumerStatefulWidget {
  const _RecommendedExerciseRow({
    required this.routine,
    required this.sourceLabel,
    required this.cancellable,
  });

  /// 회원이 읽는 출처 한 줄 — `AI 추천 · 김트레이너 확인` 처럼.
  final String sourceLabel;

  final CoachRoutine routine;

  /// 회원이 스스로 물릴 수 있는가 — 담당 트레이너가 없을 때만 참이다. (#1020)
  final bool cancellable;

  @override
  ConsumerState<_RecommendedExerciseRow> createState() =>
      _RecommendedExerciseRowState();
}

class _RecommendedExerciseRowState
    extends ConsumerState<_RecommendedExerciseRow> {
  bool _saving = false;

  /// 개인 운동 취소. 담당 트레이너가 없을 때만 화면에 나타난다 — 담당이 있으면
  /// 취소는 트레이너의 일이라 서버도 403 으로 막는다. (#1020)
  Future<void> _cancel() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final CoachRoutine routine = widget.routine;
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.coachCardRoutineCancelTitle,
      message: l.coachRoutineCancelConfirm(routine.name),
      confirmLabel: l.coachRoutineCancel,
      // 확정 버튼에 이미 '취소' 가 들어 있다 — 왼쪽까지 `취소` 면 어느 쪽이
      // 물리는 버튼인지 헷갈린다(#1782).
      cancelLabel: l.coachRoutineKeep,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(memberCoachRepositoryProvider).deleteRoutine(routine.id);
      ref.invalidate(coachRoutinesProvider);
      if (mounted) {
        showAppToast(
          context,
          l.coachRoutineCancelled,
          type: AppToastType.success,
        );
      }
    } on Object {
      if (mounted) {
        showAppToast(
          context,
          l.coachRoutineCancelFailed,
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 체크를 되돌린다 — 묻고 나서 (#1131).
  ///
  /// 완료는 기록으로 남아 주간 시간·칼로리에 더해지고 트레이너에게도 보인다.
  /// 잘못 누른 체크를 풀 방법이 없으면 하지 않은 운동이 그 숫자에 영원히 남아,
  /// 회원과 트레이너가 서로 다른 기록을 보게 된다.
  Future<void> _undoComplete() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final CoachRoutine routine = widget.routine;
    // 기록에서 빼는 동작이라 확정 버튼은 위험 동작 색이다.
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.coachCardRoutineUndoTitle,
      message: l.coachRoutineUndoConfirm(routine.name),
      confirmLabel: l.coachRoutineUndo,
      // 확정 버튼 `완료 취소` 와 둘 다 '취소' 가 되지 않게 왼쪽은 `유지` 다(#1782).
      cancelLabel: l.coachRoutineKeep,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(memberCoachRepositoryProvider)
          .uncompleteRoutine(routine.id);
      ref.invalidate(coachRoutinesProvider);
      ref.invalidate(exerciseWeekProvider);
      // 되돌린 완료의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      if (mounted) {
        showAppToast(context, l.coachRoutineUndone, type: AppToastType.success);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('uncompleteRoutine failed: $error\n$stackTrace');
      if (mounted) {
        showAppToast(
          context,
          l.coachRoutineUndoFailed,
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _complete() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final CoachRoutine routine = widget.routine;
    // 강도·피드백을 받는 입력이라 모바일 규격대로 바텀시트다. 탭 페이지의
    // Navigator 가 아니라 루트에서 띄워 하단 바 위를 덮는다 — 예전 다이얼로그와
    // 같은 층이다.
    final _RoutineCompletionInput? input =
        await showAppSheet<_RoutineCompletionInput>(
          context: Navigator.of(context, rootNavigator: true).context,
          builder: (_) => const _RoutineCompletionSheet(),
        );
    if (input == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final CoachRoutine done = await ref
          .read(memberCoachRepositoryProvider)
          .completeRoutine(
            routine.id,
            // 시간은 **배정된 값 그대로** 간다 (#1360). 운동의 세부 내용은
            // 추천이 정하는 것이라 회원이 고쳐 넣을 자리가 아니다. 계획 시간이
            // 비어 있는 배정만 1분으로 받는다 — 0분짜리 기록은 주간 집계에서
            // 한 적 없는 운동과 구분되지 않는다.
            minutes: routine.minutes > 0 ? routine.minutes : 1,
            intensity: input.intensity,
          );
      ref.invalidate(coachRoutinesProvider);
      ref.invalidate(exerciseWeekProvider);
      // 추천·배정 운동 완료는 포인트를 받는다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      if (mounted) {
        showAppToast(
          context,
          l.coachRoutineLogged,
          type: AppToastType.success,
          // 받은 포인트가 있으면 ★ +50P. 하루 한도를 넘었으면 저장 알림만.
          rewardLabel: pointsRewardLabel(l, done.pointsAward),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('completeRoutine failed: $error\n$stackTrace');
      if (mounted) {
        if (error is NotFoundError) {
          ref.invalidate(coachRoutinesProvider);
        }
        final String message = switch (error) {
          NotFoundError() => l.coachRoutineGone,
          NetworkError() => l.coachRoutineNetworkError,
          _ => l.coachRoutineLogFailed,
        };
        showAppToast(context, message, type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final CoachRoutine routine = widget.routine;
    // 이미 한 운동은 글자를 한 단계 낮춘다 (#1196). 체크 박스 하나만으로는
    // 여러 줄짜리 목록에서 어디까지 했는지 한눈에 갈리지 않는다 — 남은 줄이
    // 검정으로 남아 있어야 다음에 할 것이 먼저 읽힌다.
    final Color titleColor = routine.completed
        ? OnCareColors.textTertiary
        : OnCareColors.textPrimary;
    final Color detailColor = routine.completed
        ? OnCareColors.textTertiary
        : OnCareColors.textSecondary;
    final TextStyle detailStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: detailColor);
    // 안쪽 칸은 중립 바탕이다 — 트레이너 피드백 상자가 브랜드 옅은 바탕이라
    // 칸까지 같은 색이면 그 상자가 사라진다.
    return Container(
      padding: const EdgeInsets.fromLTRB(
        0,
        OnCareSpacing.s4,
        OnCareSpacing.tilePadding,
        OnCareSpacing.tilePadding,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.surfacePage,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 했는지 안 했는지는 체크 박스로 말한다 (#1021). 예전에는 오른쪽
              // 아래에 `수행 완료` 버튼이 있었는데, 시간·유형 아래에 붙어 있어
              // 무엇에 대한 버튼인지 한눈에 붙지 않았다. 체크 박스를 줄 맨
              // 앞에 두면 "이 운동을 했다" 가 그 줄에서 바로 읽힌다.
              _RoutineCheckbox(
                key: Key('completeRoutine-${routine.id}'),
                done: routine.completed,
                saving: _saving,
                onCheck: routine.completed ? _undoComplete : _complete,
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(top: OnCareSpacing.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        routine.isProgramSession
                            ? routine.sessionName
                            : routine.name,
                        style: tokens
                            .text(
                              OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              ),
                            )
                            .copyWith(color: titleColor),
                      ),
                      // 운동 구성이 오면 그것을 보여 준다 — 이름만 이어 붙인
                      // reason 보다 정확하다(세트·횟수·중량까지 온다, #709).
                      if (routine.exercises.isNotEmpty)
                        for (final CoachRoutineExercise exercise
                            in routine.exercises) ...<Widget>[
                          const SizedBox(height: OnCareSpacing.s2),
                          Text(
                            _routineExerciseLine(l, exercise),
                            style: detailStyle,
                          ),
                        ]
                      else if (routine.reason.isNotEmpty) ...<Widget>[
                        const SizedBox(height: OnCareSpacing.s2),
                        Text(routine.reason, style: detailStyle),
                      ],
                      // 누가 이 운동을 정했는지. 트레이너가 본 추천과 AI 가 혼자
                      // 낸 추천은 회원에게 무게가 다르다(#782).
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        widget.sourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(
                              // 누가 정한 운동인지는 보조 설명이 아니다 — 회색이면
                              // 옆의 부연과 무게가 같다(#1457). 완료한 줄에서는
                              // 본문이 흐려지므로 같은 파랑을 한 단계 옅게 둔다.
                              color: routine.completed
                                  ? tokens.brand.border
                                  : tokens.brand.primary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 오른쪽 묶음은 **제 몫을 다 차지한다** (#1153). `Flexible` 은
              // 내용 크기로 줄어들어, 남은 자리가 그 오른쪽에 빈 칸으로 남았고
              // 값이 카드 가운데에서 끝난 것처럼 보였다. 폭을 받아 두고 안에서
              // 오른쪽 정렬하면 값이 카드 끝에 붙는다. 글자 배율이 커지면
              // 아래 FittedBox 가 값부터 줄인다(#766).
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(top: OnCareSpacing.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      // 카드 오른쪽 끝에 한 줄로 붙인다 (#1130). 두 줄로
                      // 접히면 첫 줄이 카드 가운데에서 끝나 어디에 걸린 값인지
                      // 애매해진다.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${routine.type} · ${_routineAmountLabel(l, routine)}',
                          maxLines: 1,
                          textAlign: TextAlign.end,
                          style: tokens
                              .text(
                                OnCareTypography.strong(
                                  OnCareTypography.caption,
                                ),
                              )
                              .copyWith(color: tokens.brand.primary),
                        ),
                      ),
                      // 아직 하지 않은 것만 물릴 수 있다 — 이미 한 운동을 목록에서
                      // 지우면 기록과 화면이 갈린다. 목록에서 지우는 동작이라
                      // 화면 안의 트리거는 위험 글자 버튼이다.
                      if (widget.cancellable && !routine.completed)
                        AppButton(
                          key: Key('cancelRoutine-${routine.id}'),
                          label: l.coachRoutineCancel,
                          variant: AppButtonVariant.destructiveText,
                          size: OnCareButtonSize.small,
                          onPressed: _saving ? null : _cancel,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (routine.trainerFeedback.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Container(
              key: Key('routineFeedback-${routine.id}'),
              width: double.infinity,
              margin: const EdgeInsets.only(left: OnCareSpacing.tilePadding),
              padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
              decoration: BoxDecoration(
                color: tokens.brand.surface,
                borderRadius: OnCareRadius.mdAll,
              ),
              child: Text(
                l.coachRoutineTrainerFeedback(routine.trainerFeedback),
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutineCompletionInput {
  const _RoutineCompletionInput({required this.intensity});

  final String intensity;
}

/// 체크했을 때 뜨는 완료 입력. 회원이 정하는 것은 **얼마나 힘들었는지와
/// 피드백** 뿐이다 (#1360) — 시간·구성 같은 운동의 세부 내용은 추천이 든 값을
/// 그대로 쓴다.
class _RoutineCompletionSheet extends StatefulWidget {
  const _RoutineCompletionSheet();

  @override
  State<_RoutineCompletionSheet> createState() =>
      _RoutineCompletionSheetState();
}

class _RoutineCompletionSheetState extends State<_RoutineCompletionSheet> {
  /// 피드백 길이 상한. 카드에 그대로 펼쳐 보여 주는 글이라 몇 줄 안에서
  /// 끝나야 한다 (#1360).

  String _intensity = 'moderate';

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppSheet(
      title: l.coachRoutineCompleteTitle,
      // [AppButtonPair] 와 같은 배치(취소 왼쪽 보조, 확정 오른쪽 주요)다. 확정
      // 버튼에 테스트·자동화가 잡는 키가 있어 두 버튼을 직접 놓는다.
      footer: Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: l.actionCancel,
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: OnCareSpacing.buttonGap),
          Expanded(
            child: AppButton(
              key: const Key('confirmRoutineCompletion'),
              label: l.coachRoutineSubmit,
              fullWidth: true,
              onPressed: () => Navigator.of(
                context,
              ).pop(_RoutineCompletionInput(intensity: _intensity)),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.coachRoutineIntensity,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 운동 직접 추가 화면과 같은 분리형 칩이다(#1457). 셋이 하나의
          // 타원으로 이어진 `SegmentedButton` 은 같은 3단계 강도를 다른
          // UI 로 보이게 했다. value 는 서버로 나가는 계약이라 그대로 두고,
          // 라벨만 로케일을 따른다(#847).
          Row(
            key: const Key('routineCompletionIntensity'),
            children: <Widget>[
              for (final ({String value, String label}) option
                  in <({String value, String label})>[
                    (value: 'light', label: l.coachIntensityLight),
                    (value: 'moderate', label: l.coachIntensityModerate),
                    (value: 'high', label: l.coachIntensityHigh),
                  ]) ...<Widget>[
                if (option.value != 'light')
                  const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: AppChoiceChip(
                    key: Key('routineIntensity-${option.value}'),
                    label: option.label,
                    selected: _intensity == option.value,
                    onSelected: (bool _) =>
                        setState(() => _intensity = option.value),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;

    // 안 읽은 개수 배지를 라벨 옆에 붙여야 해서 [AppButton] 대신 같은 높이·반경의
    // 옅은 브랜드 칸을 직접 놓는다.
    return Material(
      color: tokens.brand.surface,
      borderRadius: OnCareRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: OnCareRadius.mdAll,
        child: Container(
          height: tokens.density.buttonMedium,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AppIcon(
                AppIcons.chat,
                size: OnCareSize.iconSmall,
                color: tokens.brand.primary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 큰 글자 배율에서 라벨이 버튼을 넘겼다. 안 읽은 개수 배지는
              // 접지 않는다 — 몇 건인지가 이 버튼을 누를 이유다(#766).
              Flexible(
                // 줄임표 대신 축소다 — `Chat with train…` 이 되면 버튼이 무슨
                // 버튼인지 사라진다. (#1004)
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l.coachChatWithTrainer,
                    maxLines: 1,
                    style: tokens
                        .text(OnCareTypography.buttonMedium)
                        .copyWith(color: tokens.brand.primary),
                  ),
                ),
              ),
              if (unread > 0) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                // 한 자리 수는 정원, 두 자리 이상은 같은 높이의 알약이다 —
                // 두 앱 공용 배지 규격(#1418, #1695). 버튼 높이를 그대로 받으면
                // 배지가 세로로 늘어나므로 제 크기로 풀어 둔다.
                UnconstrainedBox(child: AppCountBadge(count: unread)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 배정 세션의 운동 한 줄 — `레그프레스 · 4세트 · 12회 · 60kg`. (#1904)
///
/// 단위와 구분자는 문구다. 예전에는 엔티티의 `detail` 이 `세트`·`분`·`휴식 초`
/// 를 Dart 문자열에 박아 두어 영어에서도 한국어가 나왔고, 세트와 횟수 사이만
/// `×` 를 써 앱의 나머지 표기(` · `)와 갈렸다.
///
/// 비어 있는 값은 건너뛴다 — 적히지 않은 칸에 0 이 뜨면 트레이너가 정한 값처럼
/// 읽힌다.
String _routineExerciseLine(AppLocalizations l, CoachRoutineExercise exercise) {
  final int? sets = exercise.sets;
  final int? reps = exercise.reps;
  final double? weight = exercise.weight;
  final int? duration = exercise.duration;
  final int? rest = exercise.rest;
  final List<String> parts = <String>[
    exercise.name,
    if (sets != null && sets > 0) l.exSetsCount(sets),
    if (reps != null && reps > 0) l.exRepsCount(reps),
    if (weight != null && weight > 0) exerciseWeightLabel(l, weight),
    if (duration != null && duration > 0) l.exDurationMinutes(duration),
    if (rest != null && rest > 0) l.exRestSeconds(rest),
  ];
  return parts.join(' · ');
}

/// 루틴 한 줄이 말하는 **양**. 근력은 세트·횟수(·중량)로, 나머지는 분으로
/// 읽는다 — 회원이 직접 적은 기록과 **같은 규칙**(`exerciseAmountLabelOf`)이다.
///
/// 예전에는 유형과 상관없이 분만 적었다. 그래서 세트를 들고 온 근력 루틴이
/// `근력 · 10분` 으로 보였고, 같은 루틴을 세트로 세는 운동 현황 링·주간 목표와
/// 수가 갈렸다(#1262, #1901).
///
/// 회원이 실제로 한 시간(`completedMinutes`)이 있으면 그것을 쓴다. 세트·횟수·
/// 중량은 트레이너가 정한 배정 값이라 완료해도 바뀌지 않는다 — 완료 시트가
/// 묻는 것은 강도와 피드백뿐이다(#1360).
///
/// 세트를 들지 않은 루틴은 분으로 둔다. 기록은 분에서 세트를 되짚지만(#1262)
/// 배정은 적힌 수가 곧 값이라, 없는 세트를 지어내 적지 않는다.
String _routineAmountLabel(AppLocalizations l, CoachRoutine routine) =>
    exerciseAmountLabelOf(
      l,
      type: exerciseTypeFromLabel(routine.type),
      minutes: routine.completedMinutes ?? routine.minutes,
      sets: routine.sets,
      reps: routine.reps,
      weight: routine.weight,
      setsFromMinutesWhenUnknown: false,
    );
