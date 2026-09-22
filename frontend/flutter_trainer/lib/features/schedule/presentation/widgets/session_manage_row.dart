import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 세션 하나에 할 수 있는 일들. (#871, #1011, #1012, #2178)
///
/// 일곱 개가 같은 크기·같은 모양으로 늘어서 있었다. 버튼이 많아 보이는 것이
/// 아니라 실제로 많았고, 되돌릴 수 없는 `삭제` 가 자주 쓰는 `채팅` 과 나란히
/// 서 있었다.
///
/// 지금은 두 갈래로 나눈다.
///
///  * **이 약속이 어떻게 끝났나** — `완료`·`취소 처리` 는 매 세션마다 누르는
///    동작이라 카드에 글씨 버튼으로 둔다(#2176). 노쇼는 `취소 처리` 창의
///    선택지다(#2175).
///  * **일정을 손본다** — 일정 수정·프로그램 수정·메모·삭제는 오른쪽 끝의 연필
///    버튼 하나로 묶고, 누르면 펼쳐지는 메뉴에서 고른다(#2178). 아이콘 넷이
///    한 줄로 늘어서 있으면 무엇이 무엇인지 툴팁을 띄워 봐야 알았다 — 메뉴는
///    항목마다 글씨가 있다.
///
/// `채팅` 은 이 줄에서 뺐다(#2179) — 회원과의 대화는 메시지 화면이 맡는다.
///
/// `삭제` 는 메뉴 마지막 자리에 빨간 글씨로 둔다. 되돌릴 수 없는 동작을 다른
/// 것들과 같은 무게로 세우지 않는다.
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
    required this.onComplete,
    this.onCancel,
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
  final VoidCallback? onComplete;

  /// 예정 세션만 — 진행되지 않은 약속을 `취소`·`노쇼` 기록으로 남긴다(#871).
  /// 노쇼는 따로 버튼을 두지 않고 이 창의 선택지로 고른다(#2175).
  final VoidCallback? onCancel;

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
      // `완료` 와 같은 모양으로 선다(#2176) — 아이콘만 두었더니 같은 갈래의
      // 두 동작이 서로 다른 무게로 읽혔다.
      if (onCancel != null)
        AppButton(
          key: const ValueKey<String>('session-cancel-chip'),
          leadingIcon: Icons.event_busy_rounded,
          label: l.schedCancel,
          variant: AppButtonVariant.secondary,
          size: OnCareButtonSize.small,
          onPressed: onCancel,
        ),
    ];

    // 항목 키는 버튼 줄이던 때의 키를 그대로 잇는다 — 그 동작을 찾던 테스트가
    // 메뉴를 연 뒤 같은 키로 찾는다(#2178).
    final edits = <AppMenuItem>[
      AppMenuItem(
        key: const ValueKey<String>('session-edit-schedule-chip'),
        icon: Icons.edit_calendar_rounded,
        label: l.schedEditTitle,
        onSelected: onEditSchedule,
      ),
      if (hasProgram && showEditProgram)
        AppMenuItem(
          key: const ValueKey<String>('session-edit-program-chip'),
          icon: Icons.fitness_center_rounded,
          label: l.progEditTitle,
          onSelected: onEditProgram,
        ),
      if (showEditNote)
        AppMenuItem(
          key: const ValueKey<String>('session-edit-note-chip'),
          icon: hasNote ? Icons.edit_note_rounded : Icons.note_add_rounded,
          label: hasNote ? l.schedEditNote : l.schedAddNote,
          onSelected: onEditNote,
        ),
      // 되돌릴 수 없는 동작이라 마지막 자리에 빨간 글씨로 둔다. 누르면
      // 확인창이 먼저 뜬다.
      AppMenuItem(
        key: const ValueKey<String>('session-delete-chip'),
        icon: Icons.delete_outline_rounded,
        label: l.actionDelete,
        destructive: true,
        onSelected: onDelete,
      ),
    ];

    // 손보는 동작은 오른쪽 끝에 붙여, 약속의 결말을 남기는 버튼들과 확실히
    // 갈라 놓는다(#1012).
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: OnCareSpacing.s4,
            runSpacing: OnCareSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: ended,
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        AppMenu(
          items: edits,
          triggerBuilder: (context, toggle) => AppIconButton(
            key: const ValueKey<String>('session-edit-menu'),
            icon: Icons.edit_rounded,
            tooltip: l.actionEdit,
            color: OnCareColors.textSecondary,
            onPressed: toggle,
          ),
        ),
      ],
    );
  }
}
