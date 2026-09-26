import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_chips.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_ended_box.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_manage_row.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_note_box.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel, findClientIdentity;
import 'package:oncare_ui/oncare_ui.dart';

/// 상세 패널의 세션 한 건 — 시간·상태·누구인가와 그날 할 일.
///
/// 완료된 세션은 프로그램과 메모를 보여 주고 고객에게 보낼 수 있다. 예정된
/// 세션은 계획(없으면 [SessionNoPlanBox])과 수정·삭제 동선을 연다.
/// 취소·노쇼로 끝난 세션은 [SessionEndedBox] 로 그 기록을 남긴다.
///
/// 카드는 **늘 펼친 상태**다(#1012). 접었다 펴는 손잡이가 머리글에 있었지만,
/// 이 카드가 서는 자리는 이미 한 세션만 골라 보여 주는 상세 패널이라 접을
/// 것이 없었다 — 눌러도 아무 일도 일어나지 않는 화살표였다.
class SessionCard extends ConsumerWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.onEditSchedule,
    required this.onEditProgram,
    required this.onGoToProgram,
    required this.onEditNote,
    required this.onDelete,
    required this.onComplete,
    this.onCancel,
    required this.programDateLabel,
    required this.sendingProgram,
    required this.onSendProgram,
    this.personalRoutines,
    this.hasUnsentRoutines = false,
    this.onSendRoutines,
    this.onSkipRoutines,
    this.onEditRoutines,
  });

  /// 이 PT 에 붙은 개인운동 덩어리. (#2224)
  ///
  /// PT 프로그램과 **나란히** 선다 — 같은 PT 를 두고 "회원이 여기서 할 것" 과
  /// "회원이 혼자 할 것" 이 갈리므로, 한 카드 안에서 두 갈래로 읽혀야 한다.
  final Widget? personalRoutines;

  /// 아직 회원에게 가지 않은 개인운동이 붙어 있는가. (#2224)
  final bool hasUnsentRoutines;

  /// 취소·노쇼로 끝나 보낼 프로그램이 없을 때, 그 자리를 대신하는 전송.
  final VoidCallback? onSendRoutines;
  final VoidCallback? onSkipRoutines;

  /// 연필 메뉴의 `개인운동 수정` — 아직 보내지 않았을 때만 선다. (#2224)
  final VoidCallback? onEditRoutines;

  final ScheduleSession session;
  final VoidCallback onEditSchedule;
  final VoidCallback onEditProgram;

  /// 프로그램이 아직 없는 세션에서 그 고객의 코칭 탭으로 이동한다 — 이
  /// 카드 안에서 프로그램을 짓지 않는다(#1247).
  final VoidCallback onGoToProgram;

  /// 운동 목록 없이 메모만 여는 자리. 세션 종류와 상관없이 있다(#1011).
  final VoidCallback onEditNote;

  final VoidCallback onDelete;

  /// 예정 세션의 `취소`·`노쇼` 기록 처리 — 노쇼도 이 창에서 고른다(#2175).
  /// 대상이 아니면 null 이라 화면에 나오지 않는다 — 서버가 409 로 막을 동작을
  /// 아예 내놓지 않는다(#871).
  final VoidCallback? onCancel;
  final String programDateLabel;

  /// 이 세션의 프로그램 전송이 진행 중인가. (#822)
  final bool sendingProgram;

  /// 완료한 세션의 프로그램을 회원에게 보낸다.
  final VoidCallback onSendProgram;

  /// 예정 sessions only — flips to 완료 and logs the 운동기록.
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final s = session;
    final roster =
        ref.watch(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    // 상담은 운동 프로그램을 짜는 자리가 아니다 — 무슨 이야기를 나눴는지를 적는
    // 자리다. 그래서 프로그램 목록도, "아직 계획된 프로그램이 없어요" 안내도,
    // 회원에게 보내는 버튼도 두지 않는다. 남는 것은 메모뿐이다(#988).
    final noteOnly = s.type == SessionType.consultation;
    // `PT 프로그램 전송` 자리가 서는가 — 개인운동은 그 전송에 실려 나가므로
    // 이 값이 개인운동을 어느 자리에서 보낼지까지 가른다(#2224).
    final bool programSendStands =
        !noteOnly && s.isDone && s.program.isNotEmpty;
    // 머리글의 연필과 아래 결말 버튼이 **같은 항목 목록**을 쓴다 — 한쪽만
    // 고치면 같은 동작이 두 자리에서 달라진다(#2224).
    final SessionManageRow manageRow = SessionManageRow(
      onEditSchedule: onEditSchedule,
      onEditProgram: onEditProgram,
      onEditNote: onEditNote,
      hasNote: s.note.trim().isNotEmpty,
      hasProgram: !noteOnly,
      // 상담이면서 아직 메모가 없으면 `메모 추가` 는 위
      // `SessionNoNoteBox` 안으로 옮겨 갔다(#1012).
      showEditNote: !(noteOnly && s.note.trim().isEmpty),
      // 프로그램이 비어 있으면 `SessionNoPlanBox` 가 코칭 탭
      // 바로가기를 대신 보여 준다(#1236). 이미 회원에게 보낸
      // 프로그램은 더 손댈 수 없어야 하므로도 세우지 않는다
      // (#1247).
      showEditProgram: s.program.isNotEmpty && !s.programSent,
      // 아직 보내지 않은 개인운동이 붙어 있을 때만 — 보낸 뒤에 바뀌면 회원이
      // 어제 본 목록과 오늘 본 목록이 말없이 달라진다(#2224).
      onEditRoutines: hasUnsentRoutines ? onEditRoutines : null,
      onDelete: onDelete,
      onCancel: onCancel,
      onComplete: onComplete,
    );
    final client = findClientIdentity(
      roster,
      clientId: session.clientId,
      clientName: session.clientName,
    );
    final TextStyle nameStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.body))
        .copyWith(color: OnCareColors.textPrimary);
    // 안쪽 여백은 AppCard 기본값(OnCareSpacing.cardPadding)이다.
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 머리글은 **무엇이 어떻게 됐나 → 누구인가** 순서다. (#1012)
          //
          //   [완료]  12:00–12:50 (50분)
          //   [프로필]  이지수  여성 · 32세          [1:1 PT]
          //             체지방 감량
          //
          // 첫 줄은 약속에 관한 값만 담는다. 아바타를 그 줄에 세우면 사람이
          // 먼저 눈에 들어와, 상태·시각을 먼저 찾는 훑기와 어긋난다.
          // 소요 시간은 시각 옆 괄호에 둔다 — 종류와 묶어 `1:1 PT · 50분`
          // 으로 두었더니 서로 다른 두 값이 한 덩어리로 읽혔다.
          //
          // 종류 알약은 둘째 줄 오른쪽 끝이다. 시각 옆에 두었을 때는 그
          // 줄이 세 값으로 빽빽한데 프로필 줄 오른쪽은 통째로 비어 있었다.
          Row(
            children: <Widget>[
              SessionStatusChip(status: s.status),
              const SizedBox(width: OnCareSpacing.s8),
              // 시각은 잘리면 안 되는 값이라 글자를 자르는 대신 통째로
              // 작게 그린다 — 폭 340 패널에 큰 글자 배율이 겹치면 이
              // 줄이 먼저 넘친다.
              // `Expanded` 라야 남은 폭을 시각이 모두 차지해 연필이 줄 끝에
              // 선다 — `Flexible` 은 제 폭만 쓰고 멈춰, 연필이 시각 바로
              // 옆에 붙었다(#2224).
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // 소요 시간(`(50분)`)은 적지 않는다 — 시작·끝 시각이
                    // 이미 그 값을 말하고 있어, 옆에 다시 적으면 같은
                    // 사실을 두 번 읽게 된다.
                    timeRangeLabel(l, s),
                    maxLines: 1,
                    // 시각은 이 카드에서 가장 먼저 읽는 값이다 — 카드 제목
                    // 자리다(#1012).
                    style:
                        OnCareTypography.numeric(
                          tokens.text(OnCareTypography.titleSmall),
                        ).copyWith(
                          color: s.isFinished
                              ? OnCareColors.textDisabled
                              : OnCareColors.textPrimary,
                        ),
                  ),
                ),
              ),
              // 손보는 연필은 머리글 **오른쪽 끝**이다(#2224) — 카드가 길어져도
              // 늘 같은 자리에 있고, 약속의 결말을 남기는 `완료`·`취소 처리`
              // 와 무게가 갈린다.
              //
              // 글리프를 다른 요소의 오른쪽 끝에 맞추려고 바깥으로 당겼더니
              // 누르는 자리(박스 44)가 카드 가장자리에 붙어 답답했다. 버튼은
              // 제 여백을 그대로 쓰게 두고, 글리프가 조금 안쪽에 서는 편을
              // 고른다 — 글자끼리의 정렬보다 누를 자리의 숨통이 먼저다.
              SessionEditMenu(items: manageRow.editItems(l)),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Row(
            // 프로필(아바타)과 이름을 세로 가운데로 맞춘다 — `Row` 의 기본값이
            // 가운데라 값을 명시하지 않는다.
            children: <Widget>[
              AppAvatar(name: s.clientName),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (client == null)
                      // 로스터에 없는 고객(상담으로 잡힌 가망 고객)은
                      // 이름만 부른다. 뒤에 `(신규)` 를 달아 두었더니
                      // 네 글자 이름이 그 표에 밀려 잘렸다 — 신규라는
                      // 사실은 종류 알약(`상담`)이 이미 말한다(#1012).
                      Text(
                        s.clientName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      )
                    else ...<Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              client.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                          ),
                          const SizedBox(width: OnCareSpacing.s4),
                          Flexible(
                            child: Text(
                              clientDemographicsLabel(context, client),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(OnCareTypography.caption)
                                  .copyWith(color: OnCareColors.textTertiary),
                            ),
                          ),
                        ],
                      ),
                      // 오늘 만날 회원이 무엇을 목표로 하는 사람인지는
                      // 세션 종류만큼 자리에서 필요하다(#898). 목표가 비면
                      // 빈 줄로 행 높이를 먹지 않는다.
                      if (client.goal.trim().isNotEmpty)
                        Text(
                          healthFocusGoalLabel(
                            AppLocalizations.of(context),
                            client.goal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens
                              .text(OnCareTypography.caption)
                              .copyWith(color: OnCareColors.textTertiary),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 종류는 흐린 글씨가 아니라 알약으로 둔다 — 회원의 부가
              // 정보가 아니라 이 약속이 무엇인가를 말하는 값이다(#938).
              // 상태는 첫 줄의 SessionStatusChip 이 이미 말하므로 여기서
              // 되풀이하지 않는다. 소요 시간도 위 시각 줄이 이미 말해
              // 다시 붙이지 않는다(#1012).
              SessionTypeChip(
                label: sessionTypeLabel(l, s.type),
                muted: s.isDone,
                prominent: true,
                // 시간표 블록과 같은 표현 — 상담은 비운다(#1013).
                outlined: noteOnly,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          if (!noteOnly)
            if (s.program.isNotEmpty) ...<Widget>[
              _GroupLabel(label: l.schedGroupProgram),
              const SizedBox(height: OnCareSpacing.s8),
              for (var i = 0; i < s.program.length; i++) ...<Widget>[
                SessionProgramRow(index: i + 1, item: s.program[i]),
                const SizedBox(height: OnCareSpacing.s8),
              ],
            ] else if (s.isUpcoming) ...<Widget>[
              // 예정 session without a plan yet.
              SessionNoPlanBox(onGoToProgram: onGoToProgram),
              const SizedBox(height: OnCareSpacing.s12),
            ],
          // PT 에서 할 것과 회원이 혼자 할 것을 한 카드에서 갈라 보여 준다
          // (#2224) — 완료하면 이 개인운동이 함께 나간다.
          if (!noteOnly && personalRoutines != null) personalRoutines!,
          if (s.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            SessionNoteBox(note: s.note),
            const SizedBox(height: OnCareSpacing.s12),
          ] else if (noteOnly) ...<Widget>[
            SessionNoNoteBox(onAdd: onEditNote),
            const SizedBox(height: OnCareSpacing.s12),
          ],
          // 취소는 삭제와 달리 기록이라, 그 기록을 볼 수 있어야
          // 만든 의미가 있다(#871).
          if (s.isCancelled || s.isNoShow) ...<Widget>[
            SessionEndedBox(session: s),
            const SizedBox(height: OnCareSpacing.s12),
          ],
          manageRow,
          // 개인운동은 PT 프로그램 전송에 실려 나간다(#2224). 그 자리가 서지
          // 않는 끝난 PT 에서는 같은 자리가 `개인운동 보내기` 가 된다 —
          // 버튼을 새로 만들지 않는다: 개인운동은 늘 이 한 자리에서 나간다.
          //
          // 취소·노쇼뿐 아니라 **프로그램 없이 완료된 PT** 도 여기 걸린다.
          // 스케줄에서 바로 잡아 프로그램 없이 마친 PT 에 개인운동만 붙어
          // 있으면, 예전에는 어느 조건에도 걸리지 않아 보낼 길이 아예 막혔다.
          //
          // **끝난 PT 만이다.** 예정인 PT 의 개인운동은 아직 보낼 때가
          // 아니다 — 프로그램을 보낼 때 함께 간다.
          if (!noteOnly &&
              hasUnsentRoutines &&
              !programSendStands &&
              (s.isDone || s.isCancelled || s.isNoShow)) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            AppButtonPair(
              cancelKey: const ValueKey<String>('session-routines-skip'),
              cancelLabel: l.schedRoutinesSkip,
              onCancel: onSkipRoutines,
              confirmKey: const ValueKey<String>('session-routines-send'),
              confirmLabel: l.schedRoutinesSend,
              onConfirm: onSendRoutines,
            ),
          ],
          if (programSendStands) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            // 이미 보냈으면 같은 자리에서 그 사실을 말하고 누를 수 없다 —
            // 다시 누를 수 있게 두면 트레이너가 두 번 보냈는지 알 수 없다.
            AppButton(
              key: const ValueKey<String>('schedule-send-program'),
              // 개인운동이 함께 실린다(#2224) — 버튼이 그 사실을 말한다.
              //
              // 누구에게 가는지는 바로 위 카드 머리글이 이미 말하므로 버튼에는
              // 이름을 넣지 않는다 — 버튼은 높이가 묶여 있어 한 줄뿐이라,
              // 이름까지 넣으면 정작 무엇을 보내는지가 잘린다.
              label: s.programSent
                  ? l.schedSentTo(s.clientName)
                  : hasUnsentRoutines
                  ? l.schedSendProgramWithRoutines(programDateLabel)
                  : l.schedSentProgramTo(programDateLabel),
              leadingIcon: s.programSent
                  ? Icons.check_circle_outline_rounded
                  : Icons.send_rounded,
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              // 무엇을 보내는지가 이 버튼의 전부다 — 좁은 카드에서 말줄임으로
              // 끝나면 `개인운동도 함께 간다` 는 사실이 통째로 잘린다(#2224).
              shrinkLabel: true,
              loading: sendingProgram,
              onPressed: (s.programSent || sendingProgram)
                  ? null
                  : onSendProgram,
            ),
          ],
        ],
      ),
    );
  }
}

/// 카드 안에서 갈래를 가르는 작은 제목 — `PT 프로그램` / `개인운동`. (#2224)
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: context.oncare
          .text(OnCareTypography.strong(OnCareTypography.caption))
          .copyWith(color: OnCareColors.textSecondary),
    ),
  );
}
