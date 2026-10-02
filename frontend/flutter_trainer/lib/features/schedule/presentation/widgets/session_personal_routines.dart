import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 일정에 붙은 개인운동을 다시 읽게 하는 판번호. (#2280)
///
/// 개인운동을 처음 붙이는 자리는 코칭 탭이다 — 스케줄 화면은 그동안 떠 있지
/// 않아 무엇이 바뀌었는지 모른다. 붙인 쪽이 이 값을 올리면 일정 상세의
/// 개인운동 갈래가 새로 서면서 서버에서 다시 읽는다.
final scheduledRoutinesRevisionProvider = StateProvider<int>((ref) => 0);

/// 개인운동이 없을 때 처음 붙일 수 있는 PT 인가. (#2280)
///
/// `직접 만들기`·저장한 프로그램 적용으로 짠 PT 는 개인운동 단계를 지나지 않아
/// 개인운동 없이 스케줄에 선다. 일정 상세가 그 PT 를 구제하는 자리다. 서버
/// (`_ensure_routine_attachable`)와 같은 규칙이다 — 붙인 개인운동은 PT 프로그램
/// 전송에 실려 나가므로, 그 전송을 아직 기다리는 PT 에만 붙인다.
///
/// * 상담·담당 해제 회원의 일정은 아니다.
/// * PT 프로그램이 있어야 한다 — 없으면 나중에 프로그램 만들기로 실을 때
///   붙은 줄을 갈아 끼워, 여기서 붙인 것이 사라진다.
/// * 이미 보낸 PT 는 아니다 — 보낸 뒤에 붙으면 회원이 본 목록이 말없이
///   달라진다.
/// * 취소·노쇼는 아니다 — 열리지 않은 PT 다음에 할 운동을 새로 짜는 자리가
///   아니다.
bool acceptsFirstPersonalRoutines(ScheduleSession s) =>
    s.type != SessionType.consultation &&
    !s.memberDetached &&
    s.program.isNotEmpty &&
    !s.programSent &&
    !s.isCancelled &&
    !s.isNoShow;

/// 일정 상세 카드의 `개인운동` 갈래. (#2224)
///
/// PT 프로그램과 나란히 서서 "회원이 여기서 할 것" 과 "회원이 혼자 할 것" 을
/// 가른다. 예정인 PT 는 **무엇이 함께 갈지** 보여 주기만 한다 — 완료할 때
/// 나가므로 여기서 보낼 것이 없다.
///
/// **보낸 뒤에도 사라지지 않는다** — 줄마다 `전송됨` 이 붙을 뿐이다. 트레이너가
/// 나중에 그 PT 를 열어 "이 회원에게 무엇을 딸려 보냈나" 를 볼 데가 여기뿐이라,
/// 보내자마자 갈래째 비면 보낸 기록을 어디서도 확인할 수 없다.
///
/// 마무리된 PT([finished]) 라면 갈 곳을 잃은 개인운동이라 보낼지 정한다.
/// 취소·노쇼 때 **저절로 가지 않는다** — 아파서 쉬는 회원에게 운동이 자동으로
/// 가면 안 된다. 취소하는 순간에 묻지 않는 까닭은 그때가 경황이 없을 때라,
/// 그 순간에 운동 구성을 고치라고 들이미는 것이 무리이기 때문이다.
class SessionPersonalRoutines extends ConsumerStatefulWidget {
  const SessionPersonalRoutines({
    required this.sessionId,
    required this.finished,
    this.onChanged,
    this.showEmpty = false,
    this.onAdd,
    super.key,
  });

  /// `개인운동 없음` 의 추가 버튼 — 코칭 탭의 개인운동 단계로 간다. (#2280)
  ///
  /// 스케줄에서 짜지 않는다: 개인운동은 AI 제안을 받아 짜는 것이라, 빈 줄에서
  /// 시작하는 창을 여기 두면 그 제안을 못 본다. PT 프로그램이 없을 때
  /// `SessionNoPlanBox` 가 코칭 탭으로 보내는 것과 같다(#1247).
  final VoidCallback? onAdd;

  /// 목록이 바뀔 때마다 부른다 — 카드 아래 전송 버튼이 무엇을 보낼지
  /// 이 값으로 정한다(#2224). 읽지 못했으면 null 이다 — 없는지 모르는 것을
  /// 없다고 말하지 않는다(#2280).
  final ValueChanged<List<RoutineExercise>?>? onChanged;

  /// 하나도 없을 때 `개인운동 없음` 을 세우는가. (#2280)
  ///
  /// 처음 붙일 수 있는 PT([acceptsFirstPersonalRoutines])에서만 참이다 —
  /// 붙일 수 없는 자리에서 없다고 말하면 트레이너가 할 수 있는 일이 없다.
  final bool showEmpty;

  final String sessionId;

  /// 완료·취소·노쇼로 끝난 PT 인가 — 그때만 보내기/보내지 않음이 선다.
  final bool finished;

  @override
  ConsumerState<SessionPersonalRoutines> createState() =>
      _SessionPersonalRoutinesState();
}

class _SessionPersonalRoutinesState
    extends ConsumerState<SessionPersonalRoutines> {
  List<SessionRoutine> _routines = const <SessionRoutine>[];

  /// 서버에서 읽어 왔는가 — 읽기 전·실패한 뒤에는 `개인운동 없음` 을 세우지
  /// 않는다(#2280).
  bool _loaded = false;

  /// 마지막 조회가 실패했는가 — 숨기지 않고 실패 안내와 재시도를 세운다
  /// (#2891). 마무리된 PT 에 보내지 않은 개인운동이 남아 있어도 조회가 한 번
  /// 실패해 갈래째 사라지면, 트레이너는 보낼 것이 없다고 읽어 회원에게
  /// 루틴이 영영 가지 않을 수 있다.
  bool _failed = false;

  /// 다시 읽는 중인가 — 재시도 버튼을 거듭 누르지 않게 잠근다.
  bool _loading = false;

  /// 아직 보내지 않은 것만 — 전송 버튼이 실을 것이다.
  List<RoutineExercise> get _unsent => <RoutineExercise>[
    for (final SessionRoutine r in _routines)
      if (!r.sent) r.exercise,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SessionPersonalRoutines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await ref
          .read(scheduleRepositoryProvider)
          .fetchScheduledRoutines(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _routines = rows;
        _loaded = true;
        _failed = false;
        _loading = false;
      });
      widget.onChanged?.call(_unsent);
    } catch (_) {
      // 없는 것을 있다고 말하지 않되, 못 읽은 것을 없다고도 말하지 않는다 —
      // 목록 대신 실패 안내와 재시도를 세운다(#2891).
      if (!mounted) return;
      setState(() {
        _routines = const <SessionRoutine>[];
        _loaded = false;
        _failed = true;
        _loading = false;
      });
      widget.onChanged?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return PersonalRoutinesLoadError(
        key: const ValueKey<String>('session-personal-routines-error'),
        retryKey: const ValueKey<String>('session-personal-routines-retry'),
        onRetry: _loading ? null : () => unawaited(_load()),
      );
    }
    if (_routines.isEmpty) {
      return _loaded && widget.showEmpty
          ? _NoPersonalRoutines(onAdd: widget.onAdd)
          : const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return Column(
      key: const ValueKey<String>('session-personal-routines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // `미전송` 태그는 두지 않는다 — 마무리된 PT 에 개인운동이 아직
        // 남아 있다는 사실은 아래 `보내지 않음`·`개인운동 보내기` 가 이미
        // 말하고 있다. 같은 말을 두 번 적지 않는다.
        Text(
          l.schedGroupPersonal,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        for (final SessionRoutine row in _routines)
          Padding(
            padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
            child: AppTile(
              tone: AppTileTone.neutral,
              child: Row(
                children: <Widget>[
                  const AppIcon(
                    AppIcons.personalRoutine,
                    size: OnCareSize.iconSmall,
                    color: OnCareColors.textTertiary,
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: Text(
                      personalRoutineLabel(l, row.exercise),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                  // 보낸 줄에만 표를 단다 — 아직 보낼 것이 남은 줄은 아래
                  // 안내 문구가 이미 말하고 있다.
                  if (row.sent) ...<Widget>[
                    const SizedBox(width: OnCareSpacing.s8),
                    Text(
                      l.schedRoutineSent,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // 보내는 자리는 이 덩어리가 아니라 카드 아래 **전송 버튼 하나**다
        // (#2224) — 개인운동은 PT 프로그램과 함께 나가므로 버튼을 따로 두면
        // 같은 전송이 두 자리에 있는 것처럼 읽힌다. 취소·노쇼면 보낼
        // 프로그램이 없어 그 버튼이 `개인운동 보내기` 로 바뀐다.
        // 보낼 것이 하나도 남지 않았으면 안내 문구를 두지 않는다 — 줄마다
        // 붙은 `전송됨` 이 이미 상태를 말한다.
        if (_unsent.isNotEmpty)
          Text(
            widget.finished
                ? l.schedRoutinesNotSentYet
                : l.schedRoutinesGoesOnComplete,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        const SizedBox(height: OnCareSpacing.s12),
      ],
    );
  }
}

/// 개인운동을 읽지 못했을 때의 `개인운동` 갈래. (#2891)
///
/// "없음" 과 구분되는 한 줄 — 불러오지 못했다는 사실과 다시 시도를 함께
/// 둔다. 일정 상세와 코칭 탭의 미전송 안내가 같은 모양을 쓴다.
class PersonalRoutinesLoadError extends StatelessWidget {
  const PersonalRoutinesLoadError({
    required this.onRetry,
    this.retryKey,
    this.showLabel = true,
    super.key,
  });

  /// 다시 읽는다. 읽는 중이면 null 로 잠근다.
  final VoidCallback? onRetry;

  final Key? retryKey;

  /// 위에 `개인운동` 갈래 이름을 붙이는가 — 일정 상세처럼 다른 갈래와 나란한
  /// 자리에서만 붙인다.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showLabel) ...<Widget>[
          Text(
            l.schedGroupPersonal,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        AppTile(
          tone: AppTileTone.neutral,
          child: Row(
            children: <Widget>[
              const AppIcon(
                AppIcons.error,
                size: OnCareSize.iconSmall,
                color: OnCareColors.danger,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.schedRoutinesLoadFailed,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppButton(
                key: retryKey,
                label: l.actionRetry,
                leadingIcon: AppIcons.refresh,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
        if (showLabel) const SizedBox(height: OnCareSpacing.s12),
      ],
    );
  }
}

/// 개인운동이 하나도 없는 PT 의 `개인운동` 갈래. (#2280)
///
/// 갈래를 통째로 비우면 트레이너는 이 PT 에 개인운동이 빠졌다는 것을 보내는
/// 순간에야 안다. 보내기 전에 눈에 띄도록 갈래 자리에 빈 상태를 세운다.
///
/// 붙이는 버튼은 **이 박스 안**에 둔다 — 이 카드는 없는 것은 빈 상태 박스
/// 안에서 추가하고(`SessionNoPlanBox`·`SessionNoNoteBox`), 있는 것은 연필
/// 메뉴에서 고친다. 연필 메뉴에 두면 문제를 보는 자리와 푸는 자리가 떨어져,
/// 버튼 위치를 설명하는 문구가 따로 필요했다.
class _NoPersonalRoutines extends StatelessWidget {
  const _NoPersonalRoutines({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return Column(
      key: const ValueKey<String>('session-no-personal-routines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.schedGroupPersonal,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppTile(
          tone: AppTileTone.neutral,
          child: Row(
            children: <Widget>[
              const AppIcon(
                AppIcons.personalRoutine,
                size: OnCareSize.iconSmall,
                color: OnCareColors.textTertiary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.schedNoRoutines,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
              if (onAdd != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                // 코칭 탭으로 나가는 바로가기. 공용 아이콘 버튼의 기본(배경
                // 없음)을 쓴다 — 회색 박스 안에서 채움이 겹쳐 보이지 않게.
                AppIconButton(
                  key: const ValueKey<String>('session-add-routines'),
                  icon: AppIcons.add,
                  tooltip: l.schedAddRoutines,
                  onPressed: onAdd,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
      ],
    );
  }
}

/// 개인운동 없이 넘어가려 할 때 트레이너의 답. (#2280)
enum NoPersonalRoutineChoice {
  /// 그 자리에서 개인운동을 붙이고 이어서 간다.
  add,

  /// 개인운동 없이 그대로 간다.
  skip,
}

/// 개인운동이 없는 PT 를 넘기기 직전에 한 번 붙잡는다. (#2280)
///
/// `PT 마다 개인운동 최소 한 개`(#2223)를 **막지 않는다** — 부상 회복 중인
/// 회원·마지막 PT 처럼 개인운동을 줄 수 없는 날이 있고, 막으면 형식적인
/// 개인운동으로 채우게 된다. 대신 무심코 PT 만 넘기지 않도록 강조 버튼을
/// `개인운동 추가` 로 두고, 없이 가려면 한 번 더 고르게 한다.
///
/// 창을 닫으면 null — 아무것도 하지 않는다.
Future<NoPersonalRoutineChoice?> showNoPersonalRoutineDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String skipLabel,
}) {
  final l = AppLocalizations.of(context);
  return showAppDialog<NoPersonalRoutineChoice>(
    context: context,
    builder: (dialogContext) => AppDialog(
      key: const ValueKey<String>('no-personal-routine-dialog'),
      title: title,
      showClose: false,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('no-personal-routine-skip'),
        cancelLabel: skipLabel,
        onCancel: () =>
            Navigator.of(dialogContext).pop(NoPersonalRoutineChoice.skip),
        confirmKey: const ValueKey<String>('no-personal-routine-add'),
        confirmLabel: l.schedAddRoutines,
        onConfirm: () =>
            Navigator.of(dialogContext).pop(NoPersonalRoutineChoice.add),
      ),
      child: Text(
        body,
        style: context.oncare
            .text(OnCareTypography.bodySmall)
            .copyWith(color: OnCareColors.textSecondary),
      ),
    ),
  );
}

/// 보내기 전에 구성을 고치는 창. (#2224)
///
/// 개인운동은 "이 PT 다음에 할 것" 으로 짜였다. PT 가 열리지 않았으면 전제가
/// 깨지므로 그대로 보내기 어렵다. 취소된 PT 에는 프로그램 만들기로 다시 붙일
/// 수 없어(`예정` 세션만 찾는다) 고치는 자리가 여기뿐이다.
///
/// **고치는 창이다** — 처음 짜는 것은 코칭 탭의 개인운동 단계(AI 제안)가
/// 한다(#2280). 프로그램도 AI 로 한 번 짜고 고치는 것은 부분 창에서 한다.
/// 코칭 탭 편집기 아래 개인운동 박스의 `개인운동 수정` 도 이 창을 쓴다:
/// 개인운동을 고치는 창이 스케줄과 코칭에서 같아야 트레이너가 헷갈리지 않는다.
class SendPersonalRoutinesDialog extends StatefulWidget {
  const SendPersonalRoutinesDialog({
    required this.routines,
    this.editOnly = false,
    this.goal = '',
    super.key,
  });

  final List<RoutineExercise> routines;

  /// 회원 건강 목표(` · ` 로 이은 값) — 효과 칸의 자동 문구를 정한다(#2570).
  final String goal;

  /// 보내지 않고 **고치기만** 하는가 — 일정 상세의 `개인운동 수정` 이 이 길로
  /// 연다(#2224). 아직 보내지 않은 개인운동은 PT 직전까지 손볼 수 있어야
  /// 한다: 회원 상태를 보고 운동 하나를 빼거나 시간을 줄이려고 프로그램
  /// 만들기까지 돌아갈 일은 아니다.
  final bool editOnly;

  @override
  State<SendPersonalRoutinesDialog> createState() =>
      _SendPersonalRoutinesDialogState();
}

class _SendPersonalRoutinesDialogState
    extends State<SendPersonalRoutinesDialog> {
  // 서버는 비어 온 효과를 문구표로 채워 저장한다(#2570). 그 값이 지금 자동
  // 문구와 같으면 트레이너가 적은 것이 아니므로 비워 둔다 — 그래야 유형을
  // 바꿨을 때 placeholder 가 새 유형을 따라간다.
  late final List<RoutineExercise> _draft = <RoutineExercise>[
    for (final RoutineExercise r in widget.routines)
      r.effect == autoRoutineEffect(r.type, widget.goal)
          ? r.copyWith(effect: '')
          : r,
  ];
  late final List<TextEditingController> _names = <TextEditingController>[
    for (final RoutineExercise r in widget.routines)
      TextEditingController(text: r.name),
  ];

  static const RoutineExercise _blankRoutine = RoutineExercise(
    name: '',
    minutes: 30,
    type: '유산소',
  );

  /// 저장할 목록 — 손댄 줄은 트레이너 것이 된다(#2223).
  ///
  /// 서버도 같은 규칙으로 출처를 고치지만, 코칭 탭은 이 목록을 그대로 들고
  /// 있다가 `일정 추가` 로 보낸다. 여기서 맞춰 두어야 편집기 박스의 태그가
  /// 사실과 같다.
  List<RoutineExercise> get _result => <RoutineExercise>[
    for (var i = 0; i < _draft.length; i++)
      if (i < widget.routines.length &&
          samePersonalRoutine(widget.routines[i], _draft[i]))
        _draft[i]
      else
        _draft[i].copyWith(source: 'trainer'),
  ];

  @override
  void dispose() {
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeAt(int index) {
    setState(() {
      _draft.removeAt(index);
      _names.removeAt(index).dispose();
    });
  }

  /// 빈 줄 하나를 더한다 — 상한은 프로그램 세션과 같은 [kProgramMaxSessions] 다.
  ///
  /// 이름이 빈 채로 저장되면 회원이 이름 없는 운동을 받는다. 이름 칸이 비어
  /// 있는 동안에는 저장을 막는다([_canSave]).
  void _add() {
    setState(() {
      _draft.add(_blankRoutine);
      _names.add(TextEditingController());
    });
  }

  /// 이름이 빈 줄이 하나도 없고, 적어도 한 줄은 남아 있는가.
  ///
  /// 서버도 같은 두 가지를 본다 — 비우면 400, 이름은 필수다. 여기서 막아야
  /// 트레이너가 저장을 눌러 보고서야 실패를 안다.
  bool get _canSave =>
      _draft.isNotEmpty && _draft.every((e) => e.name.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppDialog(
      key: const ValueKey<String>('session-routines-send-dialog'),
      title: widget.editOnly
          ? l.schedEditRoutinesTitle
          : l.schedRoutinesSendTitle,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('session-routines-send-confirm'),
        confirmLabel: widget.editOnly ? l.actionSave : l.actionSend,
        onConfirm: _canSave ? () => Navigator.of(context).pop(_result) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.editOnly ? l.schedEditRoutinesBody : l.schedRoutinesSendBody,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          for (var index = 0; index < _draft.length; index++) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            _RoutineRow(
              key: ValueKey<String>('session-routine-edit-$index'),
              index: index,
              exercise: _draft[index],
              controller: _names[index],
              goal: widget.goal,
              onChanged: (value) => setState(() => _draft[index] = value),
              onRemove: _draft.length > 1 ? () => _removeAt(index) : null,
            ),
          ],
          // 목록을 늘리는 `+ 운동 추가` 는 목록 끝 가운데 글자 버튼이다 — 새 줄이
          // 생기는 바로 그 자리라, 누른 뒤 스크롤해 내려가 찾지 않아도 된다. 창
          // 제목 오른쪽에 두었더니 새 줄은 목록 맨 아래에 생겨, 목록이 길면 누른
          // 결과가 보이지 않았다(#2476).
          // 덜어내기만 되고 더하기가 없으면, 운동 하나를 보태려고 프로그램
          // 만들기까지 돌아가야 한다 — 고치는 자리가 반쪽이 된다(#2224).
          if (_draft.length < kProgramMaxSessions) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              child: AppButton(
                key: const ValueKey<String>('session-routine-add'),
                label: l.progAddExercise,
                leadingIcon: AppIcons.add,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
                onPressed: _add,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.index,
    required this.exercise,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
    this.goal = '',
    super.key,
  });

  final int index;
  final RoutineExercise exercise;
  final TextEditingController controller;
  final String goal;
  final ValueChanged<RoutineExercise> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: RoutineCategoryChips(
                keyPrefix: 'session-routine-category-$index',
                value: exercise.type,
                onChanged: (type) => onChanged(exercise.copyWith(type: type)),
              ),
            ),
            if (onRemove != null)
              AppIconButton(
                key: ValueKey<String>('session-routine-remove-$index'),
                icon: AppIcons.delete,
                tooltip: AppLocalizations.of(context).actionDelete,
                color: OnCareColors.textTertiary,
                onPressed: onRemove,
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        RoutineNameField(
          keyPrefix: 'session-routine-name-$index',
          controller: controller,
          onChanged: (name) => onChanged(exercise.copyWith(name: name)),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        RoutineEffectField(
          keyPrefix: 'session-routine-effect-$index',
          value: exercise.effect,
          autoEffect: autoRoutineEffect(exercise.type, goal),
          onChanged: (effect) => onChanged(exercise.copyWith(effect: effect)),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 근력은 세트·횟수로 재므로 시간 칸을 쓰지 않는다(#1310) — 여기서는
        // 구성을 덜어내거나 이름·유형을 바꾸는 정도만 하고, 세트까지 다시
        // 짜려면 프로그램 만들기로 간다.
        if (exercise.type != '근력')
          RoutineDurationField(
            keyPrefix: 'session-routine-duration-$index',
            seconds: exercise.seconds > 0 ? exercise.seconds : 30 * 60,
            onChanged: (seconds) =>
                onChanged(exercise.copyWith(durationSeconds: seconds)),
          ),
      ],
    );
  }
}
