import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_day_record_tile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 운동 — 기록 확인 중심 화면. 얼마나 했나(운동 현황) → 무엇을 했나(운동
/// 기록) 순서로 답한다(#1025).
///
/// 루틴을 **짜고 배정하는** 일은 프로그램 탭의 몫이다. 배정된 루틴 목록과 PT
/// 프로그램 이력을 여기서 한 번 더 늘어놓지 않는 이유다(#1025).
///
/// 다만 **아직 하지 않은 개인 운동을 물리는 것**은 여기 남는다. 고객의 운동을
/// 보다가 잘못 보낸 것을 발견하는 자리가 여기이고, 그때 프로그램 탭으로
/// 건너가야 하면 보던 맥락을 잃는다(#1020).
class WorkoutView extends ConsumerStatefulWidget {
  /// Creates the workout view for [client].
  const WorkoutView({super.key, required this.client, this.embedded = false});

  /// The client whose routines, sessions and history are shown.
  final TrainerClient client;

  /// When true, lets the member detail own the single page scroll.
  final bool embedded;

  @override
  ConsumerState<WorkoutView> createState() => _WorkoutViewState();
}

class _WorkoutViewState extends ConsumerState<WorkoutView> {
  /// 기본은 **오늘** — 식단 탭과 첫 화면의 기준을 맞춘다.
  ClientPeriod _period = ClientPeriod.today;

  @override
  Widget build(BuildContext context) {
    final TrainerClient client = widget.client;
    final bool embedded = widget.embedded;
    final AppLocalizations l = AppLocalizations.of(context);

    // 운동현황이 화면 맨 위다 — "얼마나 했나" 가 "무엇을 했나" 보다 먼저
    // 답해야 할 질문이다(#1025). 기록 목록은 자기 async 상태를 따로 들고
    // 있어, /history 가 실패해도 운동현황은 그대로 보인다.
    final children = <Widget>[
      ClientPeriodSection(
        // 회원 앱 `운동 현황` 제목이 쓰는 것과 같은 아이콘이다 (회원 앱 #1126)
        // — 같은 섹션을 두 화면이 다른 그림으로 가리키면 안 된다.
        icon: Icons.fitness_center_rounded,
        title: l.clientTrendTitle,
        period: _period,
        onChanged: (ClientPeriod p) => setState(() => _period = p),
        child: ClientExerciseStatusCard(clientId: client.id, period: _period),
      ),
      // 아직 하지 않은 개인 운동. 지난 기록보다 먼저 온다 — 앞으로 할 일이
      // 지나간 일보다 급하고, 잘못 보낸 배정을 여기서 바로 물릴 수 있어야
      // 한다(#1020). 물릴 것이 없으면 이 자리는 통째로 비어 있다.
      //
      // `오늘` 에만 둔다. 이번 주·전체는 지나간 기록을 되짚는 화면이라, 기간과
      // 무관한 '앞으로 할 일' 이 거기 계속 붙어 있으면 두 성격이 섞인다 —
      // 기간 토글이 목록을 지배한다는 이 화면의 규칙과도 어긋난다.
      if (_period == ClientPeriod.today) _PendingRoutines(clientId: client.id),
      // 운동 탭에는 AI 분석 카드를 두지 않는다(#2329) — 현황과 날짜별 기록이
      // 이미 같은 기간을 말하고 있어, 한 문장 해석이 기록을 밀어내기만 했다.
      const SizedBox(height: OnCareSpacing.s12),
      // 기록은 이 목록 하나다. 예전에는 날짜별 목록 아래에 `운동 기록` 카드
      // 목록이 또 있어, 이번 주·전체에서 같은 날의 같은 운동이 두 벌로
      // 나왔다(#1025). 미션 카드는 버리지 않고 이 목록의 펼친 자리로 들어왔다.
      AppSectionHeader(title: l.workoutRecords),
      const SizedBox(height: OnCareSpacing.s8),
      _DailyExerciseRecords(clientId: client.id, period: _period),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(OnCareSpacing.s16),
      children: children,
    );
  }
}

/// 운동 기록 한 건 — 종류와 운동 줄(걸른 것은 취소선)만 말한다.
///
/// 완료 배지(`100%`·트로피)와 `4/4`, 회원 피드백·트레이너 메모 상자는
/// 걷어냈다(#2329). 몇 개를 했는지는 줄마다 붙은 체크와 취소선이 이미 말하고,
/// 피드백은 기록 카드가 아니라 채팅·메모에서 모은다.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final RoutineHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 날짜는 적지 않는다 — 이 판을 펼친 줄이 바로 위에서 이미 그 날을
          // 말하고 있다(#1025).
          AppTag(
            label: routineKindLabel(l, entry.label, kind: entry.kind),
            tone: AppTagTone.brand,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          for (final (int i, ClientExerciseItem item)
              in entry.exercises.indexed)
            _ExerciseLine(
              key: ValueKey<String>('workout-exercise-line-${entry.id}-$i'),
              line: clientExerciseLine(l, item),
              done: item.done,
            ),
        ],
      ),
    );
  }
}

/// 기록된 운동 한 줄 — 이름과 수행 여부.
///
/// 저장된 문자열은 끝에 '✓' / '✗' 로 결과를 표시한다. 그 글자는 **저장 규칙**
/// 이지 화면에 찍을 것이 아니다: Flutter web 의 폰트 스택에 글리프가 없어
/// 두부 상자로 그려진다. 표시를 읽어 아이콘과 취소선으로 바꿔 그린다.
class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({super.key, required this.line, this.done = true});

  /// 이미 조립된 한 줄 — `벤치프레스 · 4세트 · 10회 · 40kg`.
  final String line;

  /// 실제로 했는가. 예전에는 줄 끝의 `✓`/`✗` 로 알았는데, 이제 값이 따로 온다
  /// (#1902).
  final bool done;

  @override
  Widget build(BuildContext context) {
    final bool skipped = !done;
    final String text = line;
    final Color color = skipped
        ? OnCareColors.textDisabled
        : OnCareColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 아이콘을 첫 줄 높이에 맞춘다 — 위쪽에 붙이면 한글 글자의 시각적
          // 중심보다 높이 떠 보인다.
          Padding(
            padding: const EdgeInsets.only(top: OnCareSpacing.s2),
            child: Icon(
              skipped ? Icons.close_rounded : Icons.check_rounded,
              size: OnCareSize.iconSmall,
              color: skipped ? OnCareColors.textDisabled : OnCareColors.success,
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Expanded(
            child: Text(
              text,
              style: context.oncare
                  .text(OnCareTypography.bodySmall)
                  .copyWith(
                    color: color,
                    decoration: skipped ? TextDecoration.lineThrough : null,
                    decorationColor: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 기간의 날짜별 운동 기록 — 눌러서 펼친다. (#1025)
///
/// 식단과 같은 줄([ClientDayRecordTile])을 쓴다. 위 [ClientExerciseStatusCard]
/// 가 이미 읽어 둔 같은 기간 데이터를 다시 구독하므로 요청이 더 나가지 않는다.
class _DailyExerciseRecords extends ConsumerStatefulWidget {
  const _DailyExerciseRecords({required this.clientId, required this.period});

  final String clientId;
  final ClientPeriod period;

  @override
  ConsumerState<_DailyExerciseRecords> createState() =>
      _DailyExerciseRecordsState();
}

class _DailyExerciseRecordsState extends ConsumerState<_DailyExerciseRecords> {
  /// 펼쳐 둔 날. 하나만 연다 — 식단과 같은 규칙이다.
  ///
  /// 오늘은 처음부터 펼쳐 둔다. 이 목록이 예전의 `운동 기록` 카드 목록을
  /// 대신하므로(#1025), 오늘 것까지 눌러야 보이면 지금까지 바로 보이던 것이
  /// 한 번 더 손이 가게 된다.
  late String? _openDay = ymd(nowKst());

  @override
  void didUpdateWidget(_DailyExerciseRecords old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period || old.clientId != widget.clientId) {
      _openDay = ymd(nowKst());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ClientPeriodKey key = clientPeriodKeyNow(
      widget.clientId,
      widget.period,
    );
    final AsyncValue<ClientExercisePeriod> async = ref.watch(
      clientExercisePeriodProvider(key),
    );
    // 이력은 고객 단위로 한 번 읽어 날짜별로 나눠 둔다 — 펼칠 때마다 다시
    // 읽으면 같은 목록을 날 수만큼 되읽는다.
    final AsyncValue<List<RoutineHistoryEntry>> history = ref.watch(
      clientHistoryProvider(widget.clientId),
    );
    final Map<String, List<RoutineHistoryEntry>> byDate =
        <String, List<RoutineHistoryEntry>>{};
    final List<RoutineHistoryEntry> undated = <RoutineHistoryEntry>[];
    for (final RoutineHistoryEntry entry
        in history.valueOrNull ?? const <RoutineHistoryEntry>[]) {
      final DateTime? when = entry.completedAt;
      // 날짜를 모르는 기록은 버리지 않고 따로 모은다. 어느 날 줄에도 붙일 수
      // 없지만, 모른다고 숨기면 트레이너 눈에는 기록이 사라진 것으로
      // 보인다(#1114 가 목록에서 지킨 규칙이다).
      if (when == null) {
        undated.add(entry);
        continue;
      }
      (byDate[ymd(when)] ??= <RoutineHistoryEntry>[]).add(entry);
    }
    // 이력이 실패하면 그 자리에서 말하고 다시 시도할 수 있어야 한다. 조용히
    // 비워 두면 "그날 아무것도 안 했다" 와 구분되지 않는다 — 위 그래프는 다른
    // provider 라 그대로 보인다.
    if (history.hasError) {
      return AppErrorState(
        key: ValueKey<String>('workout-history-retry-${widget.clientId}'),
        title: l.workoutLoadFailed,
        retryLabel: l.actionRetry,
        onRetry: history.isLoading
            ? null
            : () => ref.invalidate(clientHistoryProvider(widget.clientId)),
        placement: AppStatePlacement.card,
      );
    }
    Widget withUndated(Widget days) {
      // 평소에는 비어 있다 — 시딩도 실 API 도 완료 날짜를 채운다. 옛 행이나
      // 날짜를 잃은 기록이 있을 때만 이 자리가 생긴다.
      if (undated.isEmpty) return days;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          days,
          const SizedBox(height: OnCareSpacing.s16),
          AppSectionHeader(title: l.workoutUndatedTitle),
          const SizedBox(height: OnCareSpacing.s8),
          for (final RoutineHistoryEntry entry in undated) ...<Widget>[
            _HistoryCard(entry: entry),
            const SizedBox(height: OnCareSpacing.s8),
          ],
        ],
      );
    }

    return async.maybeWhen(
      data: (ClientExercisePeriod period) => withUndated(
        ClientDayRecordCard(
          key: const ValueKey<String>('exercise-daily-records'),
          children: <Widget>[
            for (final ClientExerciseDay day in period.days.reversed)
              () {
                final List<RoutineHistoryEntry> dayEntries =
                    byDate[ymd(day.date)] ?? const <RoutineHistoryEntry>[];
                // 집계는 0 인데 이력은 있는 날이 있다 — 스케줄에서 세션을 완료
                // 처리하면 이력이 먼저 생기고 하루 집계는 아직 0 이다. 시간만
                // 보고 접어 두면 방금 남긴 기록이 갈 곳을 잃는다(#1025).
                final bool logged = day.minutes > 0 || dayEntries.isNotEmpty;
                final bool today = widget.period == ClientPeriod.today;
                return ClientDayRecordTile(
                  date: day.date,
                  logged: logged,
                  expanded: today || _openDay == ymd(day.date),
                  toggleable: !today,
                  onToggle: () => setState(() {
                    _openDay = _openDay == ymd(day.date) ? null : ymd(day.date);
                  }),
                  emptyLabel: l.dietDayEmpty,
                  // 그날의 기록 카드가 펼친 자리로 들어온다 — 종류와 운동
                  // 줄이다(완료 배지·피드백·메모는 #2329 에서 걷어냈다).
                  // 이력이 없는 날에는 지표에 남은 운동 이름만 보여 준다.
                  extra: (today || _openDay == ymd(day.date)) && logged
                      ? _DayDetail(
                          clientId: widget.clientId,
                          date: day.date,
                          entries: dayEntries,
                        )
                      : null,
                  details: <({String label, String value})>[
                    (
                      label: l.clientTrendWorkoutMinutes,
                      value: '${day.minutes}${l.unitMinutes}',
                    ),
                    (
                      // 섭취 칼로리와 같은 말로 부르지 않는다(#1465).
                      label: l.clientTrendCaloriesBurned,
                      value: '${formatNumber(day.calories)} ${l.unitKcal}',
                    ),
                    if (day.cardioMinutes > 0)
                      (
                        label: l.routineTypeCardio,
                        value: '${day.cardioMinutes}${l.unitMinutes}',
                      ),
                    // 근력은 **세트**로 읽는다 (#1170). 같은 40분이라도 12세트를
                    // 한 날과 6세트를 하고 절반을 쉰 날이 같은 값이 되면, 분은
                    // 근력이 얼마나였는지를 말해 주지 못한다 — 회원 앱도 근력만
                    // 세트로 잰다(`ExerciseLoadKind.strength`).
                    if (day.strengthSets > 0)
                      (
                        label: l.routineTypeStrength,
                        value: l.progSetsValue(day.strengthSets),
                      ),
                    if (day.stretchingMinutes > 0)
                      (
                        label: l.routineTypeFlexibility,
                        value: '${day.stretchingMinutes}${l.unitMinutes}',
                      ),
                    if (day.otherMinutes > 0)
                      (
                        label: l.routineTypeOther,
                        value: '${day.otherMinutes}${l.unitMinutes}',
                      ),
                  ],
                );
              }(),
          ],
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 펼친 날에 실제로 한 운동. (#1025)
///
/// 위 알약들은 "얼마나" 를 말한다(시간·칼로리·유형별 분). 그 숫자가 **무엇으로**
/// 채워졌는지는 이름이 말한다 — 식단에서 하루 합계 아래 끼니를 펴는 것과 같은
/// 자리다.
///
/// 줄은 아래 운동 기록 카드와 같은 [_ExerciseLine] 이다. 걸른 운동에 취소선이
/// 그어지는 규칙도 그대로라, 한 화면에서 같은 표시가 다른 뜻으로 읽히지 않는다.
class _DayDetail extends ConsumerWidget {
  const _DayDetail({
    required this.clientId,
    required this.date,
    required this.entries,
  });

  final String clientId;
  final DateTime date;

  /// 그날의 미션 카드들. 비어 있으면 지표에 남은 운동 이름만 보여 준다.
  final List<RoutineHistoryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: OnCareSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final RoutineHistoryEntry entry in entries) ...<Widget>[
              _HistoryCard(entry: entry),
              const SizedBox(height: OnCareSpacing.s8),
            ],
          ],
        ),
      );
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<ClientExerciseItem>> async = ref.watch(
      clientExercisesOnProvider((clientId: clientId, date: date)),
    );
    return async.maybeWhen(
      data: (List<ClientExerciseItem> items) {
        // 분 수는 있는데 이름이 없는 날이 있다 — 합계만 들어온 기록이다.
        // 그럴 때는 아무 말도 하지 않는다: 위 알약이 이미 그날을 말했다.
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: OnCareSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (int i, ClientExerciseItem item) in items.indexed)
                _ExerciseLine(
                  key: ValueKey<String>(
                    'workout-exercise-line-${ymd(date)}-$i',
                  ),
                  line: clientExerciseLine(l, item),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 회원이 매일 하는 개인 운동과 그 취소. (#1020, #2161)
///
/// 배정된 루틴 **이력**을 되살리는 것이 아니다. 지난 배정·PT 이력은 프로그램
/// 탭이 맡고, 여기에는 지금 회원 목록에 걸려 있는 것이 온다.
///
/// 개인 운동은 매일 새로 체크하는 목록이라(#2161), 오늘 이미 한 운동도 내일
/// 다시 걸린다. 그래서 오늘 한 것도 여기 남기고 `오늘 완료` 로 표시한다. 취소는
/// 목록에서 내릴 뿐 이미 한 기록을 지우지 않는다 — 서버가 행을 남기고 그날부터
/// 목록에서 뺀다.
class _PendingRoutines extends ConsumerWidget {
  const _PendingRoutines({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<AssignedRoutine> pending =
        ref.watch(assignedRoutinesProvider(clientId)).valueOrNull ??
        const <AssignedRoutine>[];
    // 물릴 것이 없으면 제목도 두지 않는다 — 늘 있는 빈 카드는 자리만 먹는다.
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey<String>('workout-pending-routines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: OnCareSpacing.s16),
        AppSectionHeader(title: l.workoutPendingTitle),
        const SizedBox(height: OnCareSpacing.s8),
        for (final AssignedRoutine routine in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
            child: _PendingRoutineRow(clientId: clientId, routine: routine),
          ),
      ],
    );
  }
}

/// 배정 한 줄이 말하는 **양**. 근력은 세트·횟수·중량, 나머지는 시간이다.
///
/// 프로그램 탭 AI 개인 운동 제안 카드의 [routineSuggestionAmountLabel] 과 같은
/// 규칙이다 — 다만 이 목록은 [RoutineSuggestion] 이 아니라 이미 배정된
/// [AssignedRoutine] 을 다룬다.
///
/// 맨몸 운동의 중량은 `0kg` 이다 — 중량 칸은 비울 수 없고(최솟값 0) 근력을
/// 고르면 언제나 값을 하나 든다. 값이 아예 없는 것은 규칙이 서기 전에 저장된
/// 행뿐이라, 그때만 자리를 비운다.
String _pendingRoutineAmountLabel(AppLocalizations l, AssignedRoutine routine) {
  if (routine.type != '근력') return l.minutesShort(routine.minutes);
  final List<String> parts = <String>[
    if (routine.sets != null) l.progSetsValue(routine.sets!),
    // 버티는 운동은 회가 아니라 초로 읽는다 — 둘은 배타다(#1969).
    if (routine.holdSeconds != null)
      l.progHoldValue(routine.holdSeconds!)
    else if (routine.reps != null)
      l.progRepsValue(routine.reps!),
    if (routine.weight != null)
      '${_trimZero(routine.weight!)}${l.routineUnitKg}',
  ];
  return parts.isEmpty ? l.minutesShort(routine.minutes) : parts.join(' · ');
}

/// 20.0 → `20`, 62.5 → `62.5`.
String _trimZero(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// 물릴 수 있는 개인 운동 한 줄 — 이름·시간과 취소.
class _PendingRoutineRow extends ConsumerStatefulWidget {
  const _PendingRoutineRow({required this.clientId, required this.routine});

  final String clientId;
  final AssignedRoutine routine;

  @override
  ConsumerState<_PendingRoutineRow> createState() => _PendingRoutineRowState();
}

class _PendingRoutineRowState extends ConsumerState<_PendingRoutineRow> {
  bool _busy = false;

  Future<void> _cancel() async {
    final AppLocalizations l = AppLocalizations.of(context);
    // 되돌릴 수 없는 일이라 한 번 묻는다 — 프로그램 탭의 취소와 같은 문구다.
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.routineDeleteTitle,
      message: l.routineDeleteBody(widget.routine.name),
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      // 프로그램 탭이 쓰는 것과 **같은** mutation 이다(#504, #1020).
      await ref
          .read(trainerRoutineRepositoryProvider)
          .deleteRoutine(widget.clientId, widget.routine.id);
      if (!mounted) return;
      showAppToast(context, l.routineDeleted, type: AppToastType.success);
    } on StateError {
      // 404 — 이미 없는 것을 지우려 했다. 목적은 이뤄진 셈이라 목록만 다시 읽고
      // 그 줄을 화면에서 걷어낸다.
      if (!mounted) return;
      showAppToast(context, l.routineAlreadyGone);
    } on Object {
      if (!mounted) return;
      showAppToast(context, l.routineDeleteFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(assignedRoutinesProvider(widget.clientId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AssignedRoutine routine = widget.routine;
    final TextStyle separator = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return AppCard(
      padding: AppCard.compactPadding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 이름 - 종류 - 시간/세트/횟수 를 한 줄에 둔다 — 프로그램 탭
                // AI 개인 운동 제안 카드와 같은 구성이다.
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: routine.name,
                        style: tokens
                            .text(
                              OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              ),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      TextSpan(text: ' · ', style: separator),
                      TextSpan(
                        text: routineTypeLabel(l, routine.type),
                        style: tokens
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                      TextSpan(text: ' · ', style: separator),
                      TextSpan(
                        text: _pendingRoutineAmountLabel(l, routine),
                        style: OnCareTypography.numeric(
                          tokens.text(
                            OnCareTypography.strong(OnCareTypography.caption),
                          ),
                        ).copyWith(color: tokens.brand.primary),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (routine.reason.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s2),
                  Text(
                    routine.reason,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // 오늘 이미 했는가 — 매일 새로 체크하는 목록이라 완료는 오늘 기준이다
          // (#2161).
          if (routine.completed) ...<Widget>[
            AppTag(
              key: ValueKey<String>('workout-routine-done-${routine.id}'),
              label: l.workoutRoutineDoneToday,
              icon: Icons.check_rounded,
              tone: AppTagTone.success,
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          // 누가 보낸 것인지 — AI 추천과 트레이너 배정은 물릴 때의 무게가 다르다.
          routine.source == 'ai'
              ? AppTag(
                  label: l.clientWorkoutSourceAi,
                  icon: Icons.auto_awesome_rounded,
                  tone: AppTagTone.brand,
                )
              : AppTag(
                  label: l.coachTrainer,
                  icon: Icons.badge_rounded,
                  tone: AppTagTone.brand,
                ),
          const SizedBox(width: OnCareSpacing.s4),
          if (_busy)
            const AppLoading.inline()
          else
            AppIconButton(
              key: ValueKey<String>('workout-cancel-routine-${routine.id}'),
              onPressed: _cancel,
              icon: Icons.close_rounded,
              color: OnCareColors.textSecondary,
              tooltip: l.workoutPendingCancel,
            ),
        ],
      ),
    );
  }
}

/// 고객이 그날 한 운동 한 줄 — `벤치프레스 · 4세트 · 10회 · 40kg`. (#1902)
///
/// 단위는 로케일을 타는 문구라 여기서 붙인다. 예전에는 이 수가 이름 문자열
/// 안에 있어서(`레그프레스 70kg · 4세트`), 값을 필드로 옮기면 화면에서 사라졌다.
///
/// 근력은 세트·횟수·중량으로, 나머지는 분으로 읽는다 — 회원 앱과 같은 규칙이다
/// (#1262). 적히지 않은 칸은 건너뛴다.
String clientExerciseLine(AppLocalizations l, ClientExerciseItem item) {
  final int? sets = item.sets;
  final int? reps = item.reps;
  final int? holdSeconds = item.holdSeconds;
  final double? weight = item.weight;
  final List<String> parts = <String>[
    item.name,
    if (sets != null && sets > 0) l.progSetsValue(sets),
    // 버티는 운동은 `3세트 · 60초` 로 읽는다 — 한 세트를 두 단위로 적지
    // 않으므로 회와 함께 서지 않는다(#1969).
    if (holdSeconds != null && holdSeconds > 0)
      l.progHoldValue(holdSeconds)
    else if (reps != null && reps > 0)
      l.progRepsValue(reps),
    if (weight != null && weight > 0)
      '${_trimZeroKg(weight)}${l.routineUnitKg}',
    if (sets == null && item.minutes > 0) l.minutesShort(item.minutes),
    // 강도는 계약값(`moderate`)으로 온다 — 예전 서버 문장은 그 코드를 그대로
    // 적어 한국어 화면에도 `moderate` 가 나왔다(#2300).
    ?_intensityLabel(l, item.intensity),
  ];
  return parts.join(' · ');
}

/// 강도 계약값 → 화면 문구. 모르는 값·빈 값은 적지 않는다.
String? _intensityLabel(AppLocalizations l, String? intensity) =>
    switch (intensity) {
      'light' => l.intensityLight,
      'moderate' => l.intensityModerate,
      'high' => l.intensityHigh,
      _ => null,
    };

/// 20.0 → `20`, 62.5 → `62.5`. 정수 무게에 소수점이 붙으면 원판 단위가 아닌
/// 값을 적은 것처럼 읽힌다.
String _trimZeroKg(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
