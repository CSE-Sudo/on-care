import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 세션 하나에 할 수 있는 일들. (#871, #1011, #1012)
///
/// 일곱 개가 같은 크기·같은 모양으로 늘어서 있었다. 버튼이 많아 보이는 것이
/// 아니라 실제로 많았고, 되돌릴 수 없는 `삭제` 가 자주 쓰는 `채팅` 과 나란히
/// 서 있었다.
///
/// 지금은 두 가지로 정리한다.
///
///  * **갈래로 묶는다.** "이 약속이 어떻게 끝났나"(완료·취소·노쇼) / "일정을
///    손본다"(수정·삭제) / "고객에게 간다"(채팅) 를 구분선으로 가른다.
///  * **자주 쓰는 것만 글씨로 남긴다.** 매 세션마다 누르는 `완료`·`채팅` 은
///    글씨를 지키고, 나머지는 아이콘으로 줄인다. 아이콘만으로는 무엇인지 말하지
///    못하므로 툴팁(= 시맨틱 라벨)을 반드시 함께 단다.
///
/// `삭제` 는 마지막 자리에 채우지 않은 빨간 아이콘으로 둔다. 되돌릴 수 없는
/// 동작을 다른 것들과 같은 무게로 세우지 않는다.
class SessionManageRow extends StatelessWidget {
  const SessionManageRow({
    super.key,
    required this.onEditSchedule,
    required this.onEditProgram,
    required this.onEditNote,
    required this.hasNote,
    required this.hasProgram,
    this.showEditNote = true,
    this.showEditProgram = true,
    required this.onDelete,
    required this.onChat,
    required this.onComplete,
    this.onCancel,
    this.onNoShow,
  });

  final VoidCallback onEditSchedule;
  final VoidCallback onEditProgram;

  /// 운동 목록 없이 메모만 여는 자리. 세션 종류와 상관없이 있다(#1011).
  final VoidCallback onEditNote;

  /// 이미 남긴 메모가 있는가. (#1011)
  ///
  /// 자리는 하나지만 **하는 일이 둘**이다 — 빈 세션에서는 처음 적는 것이고,
  /// 적어 둔 세션에서는 고치는 것이다. 아무것도 적지 않았는데 `메모 수정` 이라고
  /// 부르면, 어딘가에 이미 메모가 있는데 못 찾고 있는 것처럼 읽힌다. 글자와
  /// 아이콘이 함께 갈린다 — `메모 추가`(＋)와 `메모 수정`(연필).
  final bool hasNote;

  /// 프로그램을 짜는 세션인가. 상담은 아니므로 `프로그램 수정` 이 서지 않는다 —
  /// 누를 이유가 없는 버튼으로 읽힌다(#988).
  final bool hasProgram;

  /// `메모 추가`·`메모 수정` 을 이 줄에 세우는가. 상담이면서 아직 메모가
  /// 없으면 그 자리는 [SessionNoNoteBox] 안으로 옮겨 갔다 — 이 줄에 또
  /// 세우면 같은 동작이 두 자리에서 보인다.
  final bool showEditNote;

  /// `프로그램 수정` 을 이 줄에 세우는가. 프로그램이 아직 비어 있으면 코칭
  /// 탭으로 가는 자리가 [SessionNoPlanBox] 안에 따로 있다(#1236) — 이
  /// 줄에는 세울 것이 없다. 이미 회원에게 보낸 프로그램도 더 손댈 수 없어야
  /// 하므로 세우지 않는다(#1247).
  final bool showEditProgram;

  final VoidCallback onDelete;
  final VoidCallback onChat;
  final VoidCallback? onComplete;

  /// 예정 세션만 — 진행되지 않은 약속을 `취소` 기록으로 남긴다(#871).
  final VoidCallback? onCancel;

  /// 예정이면서 지나간 세션만 — 회원이 오지 않았다는 기록.
  final VoidCallback? onNoShow;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ended = <Widget>[
      if (onComplete != null)
        AppButton(
          // Keyed: l.legendDone is also a status word elsewhere on this row,
          // so text alone no longer identifies the action.
          key: const ValueKey<String>('session-complete-chip'),
          leadingIcon: Icons.check_rounded,
          label: l.legendDone,
          variant: AppButtonVariant.secondary,
          size: OnCareButtonSize.small,
          onPressed: onComplete,
        ),
      if (onCancel != null)
        AppIconButton(
          key: const ValueKey<String>('session-cancel-chip'),
          icon: Icons.event_busy_rounded,
          tooltip: l.schedCancel,
          color: OnCareColors.textSecondary,
          onPressed: onCancel,
        ),
      if (onNoShow != null)
        AppIconButton(
          key: const ValueKey<String>('session-no-show-chip'),
          icon: Icons.person_off_rounded,
          tooltip: l.schedNoShow,
          color: OnCareColors.textSecondary,
          onPressed: onNoShow,
        ),
    ];

    final edits = <Widget>[
      AppIconButton(
        key: const ValueKey<String>('session-edit-schedule-chip'),
        icon: Icons.edit_calendar_rounded,
        tooltip: l.schedEditTitle,
        color: OnCareColors.textSecondary,
        onPressed: onEditSchedule,
      ),
      if (hasProgram && showEditProgram)
        AppIconButton(
          key: const ValueKey<String>('session-edit-program-chip'),
          icon: Icons.fitness_center_rounded,
          tooltip: l.progEditTitle,
          color: OnCareColors.textSecondary,
          onPressed: onEditProgram,
        ),
      if (showEditNote)
        AppIconButton(
          key: const ValueKey<String>('session-edit-note-chip'),
          // 아이콘도 함께 갈린다 — 글자 없이 아이콘만 그리는 자리라, 글자만
          // 바꾸면 툴팁을 띄우기 전에는 무엇이 달라졌는지 보이지 않는다.
          icon: hasNote ? Icons.edit_note_rounded : Icons.note_add_rounded,
          tooltip: hasNote ? l.schedEditNote : l.schedAddNote,
          color: OnCareColors.textSecondary,
          onPressed: onEditNote,
        ),
    ];

    // 갈래를 띄울 거라면 끝까지 띄운다 — `채팅`·`삭제` 는 오른쪽 끝에 붙여
    // 세션을 손보는 동작들과 확실히 갈라 놓는다(#1012).
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: OnCareSpacing.s4,
            runSpacing: OnCareSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ...ended,
              if (ended.isNotEmpty) const _GroupDivider(),
              ...edits,
            ],
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        AppButton(
          key: const ValueKey<String>('session-chat-chip'),
          leadingIcon: Icons.chat_bubble_outline_rounded,
          label: l.clientChat,
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
          onPressed: onChat,
        ),
        const SizedBox(width: OnCareSpacing.s4),
        // 되돌릴 수 없는 동작이라 마지막 자리에, 채우지 않은 빨간 아이콘으로
        // 둔다. 누르면 확인창이 먼저 뜬다. 글씨를 달면 이 줄의 글씨 버튼이
        // 셋이 되어(`완료`·`채팅`·`삭제`) 다시 "버튼이 많은 줄" 이 된다.
        AppIconButton(
          key: const ValueKey<String>('session-delete-chip'),
          icon: Icons.delete_outline_rounded,
          tooltip: l.actionDelete,
          color: OnCareColors.danger,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// 갈래 사이의 얇은 세로 선. 간격만으로는 묶음이 보이지 않는다.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnCareSize.hairline,
      height: OnCareSize.iconSmall,
      margin: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s4),
      color: OnCareColors.lineSubtle,
    );
  }
}
