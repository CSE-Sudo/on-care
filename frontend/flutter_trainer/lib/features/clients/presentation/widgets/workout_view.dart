import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/data/repositories/routine_days_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_day_record_tile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_routine_status.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/exercise_memo.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/presentation/routine_effect_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_duration.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/exercise_weight_label.dart';
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
        icon: AppIcons.exercise,
        title: l.clientTrendTitle,
        period: _period,
        onChanged: (ClientPeriod p) => setState(() => _period = p),
        child: ClientExerciseStatusCard(clientId: client.id, period: _period),
      ),
      // 운동 탭에는 AI 분석 카드를 두지 않는다(#2329) — 현황과 날짜별 기록이
      // 이미 같은 기간을 말하고 있어, 한 문장 해석이 기록을 밀어내기만 했다.
      const SizedBox(height: OnCareSpacing.s16),
      // 기록은 이 목록 하나다. 예전에는 날짜별 목록 아래에 `운동 기록` 카드
      // 목록이 또 있어, 이번 주·전체에서 같은 날의 같은 운동이 두 벌로
      // 나왔다(#1025). 미션 카드는 버리지 않고 이 목록의 펼친 자리로 들어왔다.
      // 제목은 두지 않는다 — 식단 탭처럼 현황 바로 아래가 기록이다.
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
  const _HistoryCard({required this.clientId, required this.entry});

  final String clientId;
  final RoutineHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHead(
            // 날짜는 적지 않는다 — 이 판을 펼친 줄이 바로 위에서 이미 그 날을
            // 말하고 있다(#1025).
            tag: AppTag(
              label: routineKindLabel(l, entry.label, kind: entry.kind),
              tone: AppTagTone.brand,
            ),
            // 한 건에 메모 하나다(#2332). id 를 잃은 옛 기록은 가리킬 수 없어
            // 메모 자리를 두지 않는다.
            memo: entry.id.isEmpty
                ? null
                : ExerciseMemoButton(
                    clientId: clientId,
                    memoRef: memoRefForHistory(entry),
                  ),
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

/// 운동 기록 카드의 머리 줄 — 왼쪽에 종류 태그, 오른쪽 끝에 메모 자리(#2332).
///
/// 메모 버튼이 태그보다 커서 줄이 높아지지 않게 가운데로 맞춘다. 메모 자리가
/// 없으면 태그만 남아 예전 모양 그대로다.
class _CardHead extends StatelessWidget {
  const _CardHead({required this.tag, this.memo});

  final Widget tag;
  final Widget? memo;

  @override
  Widget build(BuildContext context) {
    final Widget? memo = this.memo;
    if (memo == null) return tag;
    // `Flexible` 과 `Spacer` 를 함께 두면 남는 폭을 반씩 나눠 가져 메모 자리가
    // 카드 가운데쯤에 멈춘다 — 양 끝으로 벌린다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(child: tag),
        memo,
      ],
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
            child: AppIcon(
              skipped ? AppIcons.close : AppIcons.check,
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
    // 지금 걸린 개인운동 — `오늘` 맨 위 상자가 그린다.
    final List<AssignedRoutine> routines =
        ref.watch(assignedRoutinesProvider(widget.clientId)).valueOrNull ??
        const <AssignedRoutine>[];
    final Map<String, List<RoutineHistoryEntry>> byDate =
        <String, List<RoutineHistoryEntry>>{};
    final List<RoutineHistoryEntry> undated = <RoutineHistoryEntry>[];
    for (final RoutineHistoryEntry entry
        in history.valueOrNull ?? const <RoutineHistoryEntry>[]) {
      // 운동한 날(서버 `date`, 없으면 KST 로 옮긴 완료 시각)로 묶는다(#2748).
      // 예전에는 UTC 완료 시각의 날짜로 묶어, KST 오전 9시 전 운동은 전날에,
      // 지난 날짜로 소급 체크한 운동은 체크한 오늘 줄에 붙었다.
      final DateTime? when = historyDayOf(entry);
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
            _HistoryCard(clientId: widget.clientId, entry: entry),
            const SizedBox(height: OnCareSpacing.s8),
          ],
        ],
      );
    }

    return async.maybeWhen(
      data: (ClientExercisePeriod period) {
        // `오늘` 은 날짜 줄 없이 그날 내용만 카드에 담는다 — 식단 `오늘` 처럼.
        // 기간 제목이 이미 오늘이라 날짜 줄은 같은 말을 한 번 더 한다.
        if (widget.period == ClientPeriod.today) {
          final ClientExerciseDay? day = period.days
              .where((ClientExerciseDay d) => ymd(d.date) == ymd(todayKst()))
              .firstOrNull;
          if (day == null) return const SizedBox.shrink();
          final List<RoutineHistoryEntry> dayEntries =
              byDate[ymd(day.date)] ?? const <RoutineHistoryEntry>[];
          final bool logged = day.minutes > 0 || dayEntries.isNotEmpty;
          if (!logged && routines.isEmpty) {
            return withUndated(
              AppCard(
                key: const ValueKey<String>('exercise-daily-records'),
                child: Text(
                  l.dietDayEmpty,
                  style: context.oncare
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            );
          }
          // 식단 `오늘` 처럼 출처마다 상자 한 장 — 개인운동 · 회원 추가 · PT.
          // 오늘 걸린 개인운동은 맨 위 상자 하나다(#2508) — 해야 할 목록과 한
          // 것을 두 자리에 나눠 같은 운동을 두 번 보이지 않는다. 메모는 상자마다
          // 머리 오른쪽에 둔다 — 개인운동·회원 추가·PT 를 따로 적는다.
          return withUndated(
            KeyedSubtree(
              key: const ValueKey<String>('exercise-daily-records'),
              child: _DayDetail(
                clientId: widget.clientId,
                day: day,
                entries: dayEntries,
                asCards: true,
                routines: routines,
              ),
            ),
          );
        }
        return withUndated(
          ClientDayRecordCard(
            key: const ValueKey<String>('exercise-daily-records'),
            children: <Widget>[
              // 오지 않은 날은 그리지 않는다(#2512) — `기록 없음` 이 아니라 아직
              // 기록할 수 없는 날이다.
              for (final ClientExerciseDay day in period.days.reversed.where(
                (ClientExerciseDay d) => !d.date.isAfter(todayKst()),
              ))
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
                      _openDay = _openDay == ymd(day.date)
                          ? null
                          : ymd(day.date);
                    }),
                    emptyLabel: l.dietDayEmpty,
                    // 식단 펼친 날과 같은 모양이다 — 맨 위 `하루 합계` 줄, 그 아래
                    // PT·개인운동·직접 기록 줄(#2508). 하루 합계가 알약이던 동안에는
                    // 식단과 말투가 달랐다.
                    extra: (today || _openDay == ymd(day.date)) && logged
                        ? _DayDetail(
                            clientId: widget.clientId,
                            day: day,
                            entries: dayEntries,
                          )
                        : null,
                    details: const <({String label, String value})>[],
                  );
                }(),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 펼친 날 — 식단 펼친 날과 같은 줄 모양이다. (#1025, #2508)
///
/// 맨 위 `하루 합계` 줄이 "얼마나"(운동 시간·유형별·총 소모 kcal)를 말하고, 그
/// 아래 줄들이 **무엇으로** 채워졌는지를 출처별로 말한다 — 개인운동 · 회원 추가
/// · PT. 식단이 하루 합계 아래 끼니를 펴는 것과 같은 자리다.
///
/// 출처 안에서는 운동을 유형별로 묶어 옅은 유형 이름 아래 들여 쓴다. 개인운동
/// 줄은 왼쪽 세로 막대가 한 것(색)과 안 한 것(회색)을 가른다. 메모는 출처마다
/// 알약 줄 오른쪽 끝에 선다 — `오늘` 상자와 같다.
class _DayDetail extends ConsumerWidget {
  const _DayDetail({
    required this.clientId,
    required this.day,
    required this.entries,
    this.asCards = false,
    this.routines = const <AssignedRoutine>[],
  });

  /// `오늘` — 하루 합계 줄 없이 출처마다 상자 한 장으로 그린다(식단 `오늘`).
  final bool asCards;

  final String clientId;
  final ClientExerciseDay day;

  /// 그날의 이력 — PT 세션과 하루치 개인운동 카드.
  final List<RoutineHistoryEntry> entries;

  /// `오늘` 걸린 개인운동 — 있으면 개인운동 상자가 이력 대신 이것을 그린다.
  final List<AssignedRoutine> routines;

  DateTime get date => day.date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ClientExerciseItem> items =
        ref
            .watch(clientExercisesOnProvider((clientId: clientId, date: date)))
            .valueOrNull ??
        const <ClientExerciseItem>[];
    // 회원이 직접 적은 기록만 따로 한 줄로 둔다(#2534) — PT 완료·개인운동
    // 완료 행은 그 출처가 말한다. 이력이 없는 날은 출처를 모르는 행도 여기
    // 선다(옛 응답).
    final List<ClientExerciseItem> own = entries.isEmpty
        ? <ClientExerciseItem>[
            for (final ClientExerciseItem item in items)
              if (!_isAssignedRow(item) && item.source != 'trainer_pt') item,
          ]
        : _memberLogs(items);
    // 트레이너가 살필 순서 — 개인운동 → 회원 추가 → PT. PT 는 트레이너가 함께
    // 한 운동이라 맨 아래로 둔다.
    final List<RoutineHistoryEntry> personal = <RoutineHistoryEntry>[
      for (final RoutineHistoryEntry entry in entries)
        if (!_isPtEntry(entry)) entry,
    ];
    final List<RoutineHistoryEntry> pt = <RoutineHistoryEntry>[
      for (final RoutineHistoryEntry entry in entries)
        if (_isPtEntry(entry)) entry,
    ];
    final List<_Line> ownLines = <_Line>[
      for (final (int i, ClientExerciseItem item) in own.indexed)
        _Line(
          key: ValueKey<String>(
            entries.isEmpty
                ? 'workout-exercise-line-${ymd(date)}-$i'
                : 'workout-member-log-line-${ymd(date)}-$i',
          ),
          type: item.type,
          item: item,
          calories: item.calories,
        ),
    ];
    if (asCards) {
      final List<Widget> cards = <Widget>[
        // 걸린 개인운동이 있으면 그 상자가 하루치 `개인운동` 카드를 대신한다 —
        // 같은 운동을 두 번 보이지 않는다. 다른 개인운동 이력(옛 AI 개인운동
        // 등)은 그대로 상자로 선다.
        if (routines.isNotEmpty)
          _PersonalTodayCard(
            clientId: clientId,
            date: date,
            routines: routines,
            entry: personal.where(_isPersonalDay).firstOrNull,
          ),
        for (final RoutineHistoryEntry entry in personal)
          if (routines.isEmpty || !_isPersonalDay(entry))
            _TodayCard.entry(clientId: clientId, entry: entry, dayItems: items),
        if (own.isNotEmpty)
          _TodayCard(
            key: ValueKey<String>('workout-member-log-${ymd(date)}'),
            tag: AppTag(label: l.workoutMemberLogTitle),
            lines: ownLines,
            done: own,
            memo: ExerciseMemoButton(
              clientId: clientId,
              memoRef: TrainerMemoRef(
                kind: TrainerMemoRefKind.memberLog,
                day: ymd(date),
              ),
            ),
          ),
        for (final RoutineHistoryEntry entry in pt)
          _TodayCard.entry(clientId: clientId, entry: entry, dayItems: items),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (int i, Widget card) in cards.indexed) ...<Widget>[
            if (i > 0) const SizedBox(height: OnCareSpacing.s12),
            card,
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WorkoutDayRow(
          key: ValueKey<String>('workout-day-total-${ymd(date)}'),
          // 날짜 줄 바로 아래라 선을 긋지 않는다 — 식단 펼친 날과 같다. 선은
          // 줄과 줄 사이에만.
          divider: false,
          label: Text(
            l.clientDietDayTotal,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          lines: <Widget>[
            Text(
              _totalLine(l),
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ],
          trailing: Text(
            l.workoutTotalBurned(formatNumber(day.calories)),
            maxLines: 1,
            softWrap: false,
            style: OnCareTypography.numeric(
              context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: context.oncare.brand.primary),
            ),
          ),
        ),
        for (final RoutineHistoryEntry entry in personal)
          _EntryRow(clientId: clientId, entry: entry, dayItems: items),
        if (own.isNotEmpty)
          _SourceSection(
            key: ValueKey<String>('workout-member-log-${ymd(date)}'),
            tag: AppTag(label: l.workoutMemberLogTitle),
            lines: ownLines,
            memo: ExerciseMemoButton(
              clientId: clientId,
              memoRef: TrainerMemoRef(
                kind: TrainerMemoRefKind.memberLog,
                day: ymd(date),
              ),
            ),
          ),
        for (final RoutineHistoryEntry entry in pt)
          _EntryRow(clientId: clientId, entry: entry, dayItems: items),
      ],
    );
  }

  /// `운동 시간 43분 · 유산소 25분 · 근력 6세트` — 근력은 세트로 읽는다(#1170).
  String _totalLine(AppLocalizations l) => <String>[
    '${l.clientTrendWorkoutMinutes} ${day.minutes}${l.unitMinutes}',
    if (day.cardioMinutes > 0)
      '${l.routineTypeCardio} ${day.cardioMinutes}${l.unitMinutes}',
    if (day.strengthSets > 0)
      '${l.routineTypeStrength} ${l.progSetsValue(day.strengthSets)}',
    if (day.stretchingMinutes > 0)
      '${l.routineTypeFlexibility} ${day.stretchingMinutes}${l.unitMinutes}',
    if (day.otherMinutes > 0)
      '${l.routineTypeOther} ${day.otherMinutes}${l.unitMinutes}',
  ].join(' · ');

  /// 그날 운동 행 중 이력이 말하지 않는 것 — 회원이 직접 적은 기록. (#2534)
  ///
  /// PT 완료·배정 운동 완료로 생긴 행은 출처로 거른다([ClientExerciseItem.isMemberLog]).
  /// 이름으로도 한 번 더 거른다: 시드의 개인운동 이력처럼 같은 운동이 이력과
  /// `member` 행에 함께 적힌 날이 있다. 같은 이름을 두 번 보여 주지 않는다.
  List<ClientExerciseItem> _memberLogs(List<ClientExerciseItem> items) {
    final Set<String> inHistory = <String>{
      for (final RoutineHistoryEntry entry in entries)
        for (final ClientExerciseItem item in entry.exercises) item.name.trim(),
    };
    return <ClientExerciseItem>[
      for (final ClientExerciseItem item in items)
        if (item.isMemberLog && !inHistory.contains(item.name.trim())) item,
    ];
  }
}

/// PT 세션 이력인가 — 나머지는 개인운동(하루치 카드·옛 AI 개인운동)이다.
bool _isPtEntry(RoutineHistoryEntry entry) =>
    routineKindCode(entry.label, kind: entry.kind) == 'pt_session';

/// 하루치 `개인운동` 카드인가(#2510) — 그날 걸린 개인운동과 한 것.
bool _isPersonalDay(RoutineHistoryEntry entry) =>
    routineKindCode(entry.label, kind: entry.kind) == 'personal_routine';

/// 개인운동 완료로 생긴 운동 행인가.
bool _isAssignedRow(ClientExerciseItem item) =>
    item.source == 'assigned_routine' || item.assignedRoutineId != null;

/// 운동 줄들의 시간 합(초). 근력은 세트로 재므로 시간이 없다.
int _secondsOf(Iterable<ClientExerciseItem> items) => items.fold<int>(
  0,
  (int sum, ClientExerciseItem item) =>
      sum + (item.sets == null && item.done ? item.seconds : 0),
);

/// 운동 줄들의 소모 kcal 합. 값이 실리지 않은 줄뿐이면 null.
int? _caloriesOf(Iterable<ClientExerciseItem> items) {
  int? sum;
  for (final ClientExerciseItem item in items) {
    final int? kcal = item.calories;
    if (kcal != null) sum = (sum ?? 0) + kcal;
  }
  return sum;
}

/// 줄 오른쪽 끝의 소모 kcal — 식단 줄처럼 알약·첫 운동 줄과 한 줄에 선다.
/// 시간·완료 수는 적지 않는다: 하루 합계가 총 시간을 말한다.
class _RowTotals extends StatelessWidget {
  const _RowTotals({this.calories, this.strong = true, this.estimated = false});

  final int? calories;
  final bool strong;

  /// 아직 안 한 운동의 예상값 — `예상 소모 N kcal` 을 옅게.
  final bool estimated;

  /// `예상 소모 1,234 kcal` 이 들어가는 폭 — 줄마다 kcal 끝이 맞는다.
  static const double width = 128;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int? kcal = calories;
    final TextStyle base = context.oncare.text(
      strong
          ? OnCareTypography.strong(OnCareTypography.bodySmall)
          : OnCareTypography.bodySmall,
    );
    return SizedBox(
      width: width,
      child: kcal == null
          ? null
          : Text(
              // 무엇의 kcal 인지 줄마다 말한다 — 식단 탭의 kcal(먹은 양)과
              // 같은 숫자 모양이라 `소모` 를 붙인다.
              estimated
                  ? l.workoutLineEstimated(formatNumber(kcal))
                  : l.workoutLineBurned(formatNumber(kcal)),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.end,
              style: OnCareTypography.numeric(base).copyWith(
                color: estimated
                    ? OnCareColors.textTertiary
                    : OnCareColors.textPrimary,
              ),
            ),
    );
  }
}

/// 이력 한 건 → 펼친 날의 출처 한 덩어리. PT 는 `PT`, 하루치 개인운동은 `개인운동`.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.clientId,
    required this.entry,
    this.dayItems = const <ClientExerciseItem>[],
  });

  final String clientId;
  final RoutineHistoryEntry entry;

  /// 그날 운동 기록 행 — 이 줄의 소모 kcal 을 여기서 센다. 이력 줄에는 kcal
  /// 이 없다.
  final List<ClientExerciseItem> dayItems;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? code = routineKindCode(entry.label, kind: entry.kind);
    final bool personal = code == 'ai_personal' || code == 'personal_routine';
    final ClientExerciseItem? Function(ClientExerciseItem) rowOf = _rowMatcher(
      _dayRowsOf(entry, dayItems, personal: personal),
    );
    return _SourceSection(
      key: ValueKey<String>('workout-entry-${entry.id}'),
      tag: AppTag(
        label: code == 'pt_session'
            ? l.workoutDaySourcePt
            : routineKindLabel(l, entry.label, kind: entry.kind),
        tone: AppTagTone.brand,
      ),
      // 이 기록에 다는 메모 — id 를 잃은 옛 기록은 가리킬 수 없어 두지 않는다.
      memo: entry.id.isEmpty
          ? null
          : ExerciseMemoButton(
              clientId: clientId,
              memoRef: memoRefForHistory(entry),
            ),
      // 줄마다 그 운동의 소모 kcal — 오늘 상자와 같다.
      lines: <_Line>[
        for (final (int i, ClientExerciseItem item) in entry.exercises.indexed)
          () {
            final ClientExerciseItem? row = rowOf(item);
            return _Line(
              key: ValueKey<String>('workout-exercise-line-${entry.id}-$i'),
              type: item.type,
              item: item,
              calories: row?.calories,
              intensity: item.intensity ?? row?.intensity,
              planned: item.prescribedIntensity,
              // 지난 날의 개인운동은 한 것과 안 한 것이다.
              mark: !personal
                  ? _LineMark.none
                  : item.done
                  ? _LineMark.done
                  : _LineMark.missed,
            );
          }(),
      ],
    );
  }
}

/// 펼친 날의 출처 한 덩어리 — `오늘` 상자와 같은 모양을 상자 없이 그린다.
///
/// 머리 줄은 왼쪽 출처 알약, 오른쪽 끝 메모. 그 아래 유형별로 묶은 운동 줄을
/// 알약 글씨가 시작하는 자리에 맞춰 들여 쓴다. 덩어리 사이는 선으로 가른다.
class _SourceSection extends StatelessWidget {
  const _SourceSection({
    super.key,
    required this.tag,
    required this.lines,
    this.memo,
  });

  final Widget tag;
  final List<_Line> lines;
  final Widget? memo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardTop(tag: tag, memo: memo),
          const SizedBox(height: OnCareSpacing.s8),
          Padding(
            padding: const EdgeInsets.only(left: _tagInset),
            child: _GroupedLines(lines: lines, showCalories: true),
          ),
        ],
      ),
    );
  }
}

/// 이력 줄 → 그날 운동 행. 이름으로 하나씩 짝짓는다 — 이력 줄에는 소모
/// kcal·강도가 없고 운동 행에 있다. 안 한 줄은 짝이 없다.
ClientExerciseItem? Function(ClientExerciseItem) _rowMatcher(
  List<ClientExerciseItem> rows,
) {
  final List<ClientExerciseItem> pool = <ClientExerciseItem>[...rows];
  return (ClientExerciseItem item) {
    if (!item.done) return null;
    final int at = pool.indexWhere(
      (ClientExerciseItem row) => row.name.trim() == item.name.trim(),
    );
    if (at < 0) return null;
    return pool.removeAt(at);
  };
}

/// 이 이력에 해당하는 그날 운동 행. 출처(PT 완료·개인운동 완료)로 고르고,
/// 출처가 없는 데모·옛 응답은 이름으로 잇는다.
List<ClientExerciseItem> _dayRowsOf(
  RoutineHistoryEntry entry,
  List<ClientExerciseItem> dayItems, {
  required bool personal,
}) {
  final List<ClientExerciseItem> bySource = <ClientExerciseItem>[
    for (final ClientExerciseItem item in dayItems)
      if (personal ? _isAssignedRow(item) : item.source == 'trainer_pt') item,
  ];
  if (bySource.isNotEmpty) return bySource;
  final Set<String> names = <String>{
    for (final ClientExerciseItem item in entry.exercises)
      if (item.done) item.name.trim(),
  };
  return <ClientExerciseItem>[
    for (final ClientExerciseItem item in dayItems)
      if (names.contains(item.name.trim())) item,
  ];
}

/// 줄 앞 표시. 개인운동만 막대를 단다 — PT·회원 추가는 한 것만 적힌다.
enum _LineMark {
  /// 막대 없이 자리만 맞춘다.
  none,

  /// 한 것 — 색 막대.
  done,

  /// 오늘 아직 — 회색 막대, 글씨 옅게.
  pending,

  /// 지난 날 안 한 것 — 회색 막대, 글씨 더 옅게.
  missed,
}

/// 운동 한 줄의 내용.
class _Line {
  const _Line({
    required this.key,
    required this.type,
    this.name,
    this.detail,
    this.item,
    this.effect,
    this.mark = _LineMark.none,
    this.calories,
    this.intensity,
    this.planned,
    this.estimated = false,
  });

  final Key key;

  /// 유형 — 계약값(`cardio`)이나 배정 유형(`유산소`). 비면 묶음 이름 없이 선다.
  final String type;

  /// 운동 이름(`스쿼트`)과 세부(`3세트 · 12회`). 비면 [item] 에서 만든다.
  final String? name;
  final String? detail;

  /// 이 줄의 운동 행 — [name] 이 없을 때 이름과 세부를 만든다.
  final ClientExerciseItem? item;

  /// 이름 뒤 옅은 효과 한 줄(개인운동).
  final String? effect;
  final _LineMark mark;

  /// 이 운동의 소모 kcal — 안 한 줄이나 값을 모르면 비운다.
  final int? calories;

  /// 강도 계약값(`moderate`) — 운동 글 바로 뒤 작은 태그. 비면 [item] 의 강도,
  /// 그것도 없으면 태그를 두지 않는다.
  final String? intensity;

  /// 트레이너가 처방한 강도 — 한 개인운동에서 [intensity](회원이 고른 강도)와
  /// 다르면 처방을 회색으로 두고 그 옆에 파랑 `수행 …` 을 붙인다(#2508).
  final String? planned;

  /// [calories] 가 아직 안 한 운동의 예상값인가 — `예상 소모` 로 옅게 적는다.
  final bool estimated;
}

/// 유형 순서와 묶음 이름. 계약값과 배정 유형(한국어)을 함께 받는다.
const List<String> _typeOrder = <String>[
  'cardio',
  'strength',
  'stretching',
  'other',
  '',
];

String _typeCode(String type) => switch (type.trim()) {
  'cardio' || '유산소' || '걷기' => 'cardio',
  'strength' || '근력' => 'strength',
  'stretching' || 'flexibility' || '스트레칭' || '요가' || '유연성' => 'stretching',
  '' => '',
  _ => 'other',
};

String? _typeCaption(AppLocalizations l, String code) => switch (code) {
  'cardio' => l.routineTypeCardio,
  'strength' => l.routineTypeStrength,
  'stretching' => l.routineTypeFlexibility,
  'other' => l.routineTypeOther,
  _ => null,
};

/// 운동 줄을 유형별로 묶어 그린다 — 옅은 유형 이름 아래 들여 쓴 줄. (#2508)
///
/// 줄마다 유형 칩을 달면 태그가 줄 수만큼 늘어 출처 알약이 묻힌다. 묶음 안
/// 순서는 들어온 순서 그대로다.
class _GroupedLines extends StatelessWidget {
  const _GroupedLines({
    super.key,
    required this.lines,
    this.showCalories = false,
  });

  final List<_Line> lines;

  /// 줄마다 오른쪽 kcal 을 적는가(`오늘` 상자).
  final bool showCalories;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Map<String, List<_Line>> groups = <String, List<_Line>>{};
    for (final _Line line in lines) {
      (groups[_typeCode(line.type)] ??= <_Line>[]).add(line);
    }
    final List<Widget> children = <Widget>[];
    for (final String code in _typeOrder) {
      final List<_Line>? group = groups[code];
      if (group == null) continue;
      final String? caption = _typeCaption(l, code);
      if (caption != null) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : OnCareSpacing.s8,
              bottom: OnCareSpacing.s2,
            ),
            child: Text(
              caption,
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
        );
      }
      for (final _Line line in group) {
        children.add(_LineRow(line: line, showCalories: showCalories));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// 들여 쓴 운동 한 줄 — 왼쪽 막대, 이름·양(과 효과), 오른쪽 kcal.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, this.showCalories = false});

  final _Line line;
  final bool showCalories;

  /// 막대 굵기와 막대~글씨 사이.
  static const double _barWidth = 3;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final ClientExerciseItem item =
        line.item ?? const ClientExerciseItem(name: '');
    final String name = line.name ?? item.name;
    // 세부는 이름을 뺀 나머지 — `벤치프레스 · 4세트 · 10회` 에서 `4세트 · 10회`.
    // 강도는 글 대신 오른쪽 태그로 둔다(회원 앱 운동 탭과 같다).
    final String detail =
        line.detail ??
        () {
          final String full = clientExerciseLine(
            l,
            ClientExerciseItem.fromJson(<String, Object?>{
              ...item.toJson(),
              'intensity': null,
            }),
          );
          final String head = '${item.name} · ';
          return full.startsWith(head) ? full.substring(head.length) : '';
        }();
    final String? intensityCode = line.intensity ?? item.intensity;
    final String? plannedCode = line.planned;
    // 처방과 다르게 한 개인운동 — 트레이너는 처방을 직접 보냈으니 처방을 기준
    // 자리에 회색으로 두고, 회원이 한 강도를 `수행 …` 으로 덧붙인다.
    final bool deviated =
        line.mark == _LineMark.done &&
        plannedCode != null &&
        intensityCode != null &&
        plannedCode != intensityCode;
    final String? intensity = _intensityLabel(
      l,
      deviated ? plannedCode : intensityCode,
    );
    final String? performed = deviated
        ? _intensityLabel(l, intensityCode)
        : null;
    final Color bar = switch (line.mark) {
      _LineMark.done => OnCareColors.success,
      _LineMark.pending || _LineMark.missed => OnCareColors.lineStrong,
      _LineMark.none => Colors.transparent,
    };
    // 이름은 진하게, 세부는 한 단계 옅게 — 둘이 같은 글씨면 무엇을 했는지와
    // 얼마나 했는지가 한 덩어리로 읽힌다.
    final Color ink = switch (line.mark) {
      _LineMark.done || _LineMark.none => OnCareColors.textPrimary,
      _LineMark.pending => OnCareColors.textSecondary,
      _LineMark.missed => OnCareColors.textTertiary,
    };
    final Color sub = switch (line.mark) {
      _LineMark.done || _LineMark.none => OnCareColors.textSecondary,
      _LineMark.pending => OnCareColors.textTertiary,
      _LineMark.missed => OnCareColors.textDisabled,
    };
    final String? effect = line.effect;
    return Padding(
      key: line.key,
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Container(
        padding: const EdgeInsets.only(left: OnCareSpacing.s8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: bar, width: _barWidth),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: name,
                      style: tokens
                          .text(
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                          )
                          .copyWith(color: ink),
                    ),
                    if (detail.isNotEmpty) ...<InlineSpan>[
                      TextSpan(
                        text: ' · ',
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                      TextSpan(
                        text: detail,
                        style: OnCareTypography.numeric(
                          tokens.text(OnCareTypography.bodySmall),
                        ).copyWith(color: sub),
                      ),
                    ],
                    // 강도는 운동 글 바로 뒤 — 무엇을 얼마나 어떤 강도로 했는지가
                    // 한 덩어리로 읽힌다. 트레이너가 정한 강도는 아직 안 한 동안
                    // 회색, 회원이 하면 파랑으로 확정된다. 기록(PT·회원 추가)의
                    // 강도는 한 강도다.
                    if (intensity != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: OnCareSpacing.s8,
                          ),
                          child: AppTag(
                            label: intensity,
                            tone:
                                deviated ||
                                    line.mark == _LineMark.pending ||
                                    line.mark == _LineMark.missed
                                ? AppTagTone.neutral
                                : AppTagTone.brand,
                          ),
                        ),
                      ),
                    // 회원이 처방과 다르게 한 강도 — 트레이너가 강도를 고칠
                    // 근거가 이 차이다.
                    if (performed != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: OnCareSpacing.s4,
                          ),
                          child: AppTag(
                            label: l.workoutIntensityPerformed(performed),
                            tone: AppTagTone.brand,
                          ),
                        ),
                      ),
                    // 효과는 같은 줄 끝에 옅게 — 앞에 중간 점을 두지 않는다
                    // (#2951). 세부와 같은 말로 읽히지 않게 간격과 색으로만
                    // 가른다.
                    if (effect != null && effect.isNotEmpty) ...<InlineSpan>[
                      const WidgetSpan(
                        child: SizedBox(width: OnCareSpacing.s8),
                      ),
                      TextSpan(
                        text: effect,
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showCalories) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s12),
              _RowTotals(
                calories: line.calories,
                strong: false,
                estimated: line.estimated,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `오늘` 의 출처 상자 한 장 — 식단 `오늘` 끼니 카드와 같은 틀이다(#2508).
///
/// 맨 위 알약(회원 추가 · PT), 유형별로 묶은 운동 줄과 줄마다 오른쪽 kcal, 선
/// 아래 요약(운동 시간 · 근력 세트)과 `총 N kcal`.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    super.key,
    required this.tag,
    required this.lines,
    this.done,
    this.memo,
  });

  /// 이력 한 건(PT 세션·하루치 개인운동) → 상자.
  factory _TodayCard.entry({
    required String clientId,
    required RoutineHistoryEntry entry,
    required List<ClientExerciseItem> dayItems,
  }) {
    final String? code = routineKindCode(entry.label, kind: entry.kind);
    final bool personal = code == 'ai_personal' || code == 'personal_routine';
    final ClientExerciseItem? Function(ClientExerciseItem) rowOf = _rowMatcher(
      _dayRowsOf(entry, dayItems, personal: personal),
    );

    return _TodayCard(
      key: ValueKey<String>('workout-entry-${entry.id}'),
      tag: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l = AppLocalizations.of(context);
          return AppTag(
            label: code == 'pt_session'
                ? l.workoutDaySourcePt
                : routineKindLabel(l, entry.label, kind: entry.kind),
            tone: AppTagTone.brand,
          );
        },
      ),
      done: <ClientExerciseItem>[
        for (final ClientExerciseItem item in entry.exercises)
          if (item.done) item,
      ],
      lines: <_Line>[
        for (final (int i, ClientExerciseItem item) in entry.exercises.indexed)
          () {
            final ClientExerciseItem? row = rowOf(item);
            return _Line(
              key: ValueKey<String>('workout-exercise-line-${entry.id}-$i'),
              type: item.type,
              item: item,
              calories: row?.calories,
              intensity: item.intensity ?? row?.intensity,
              planned: item.prescribedIntensity,
              mark: !personal
                  ? _LineMark.none
                  : item.done
                  ? _LineMark.done
                  : _LineMark.pending,
            );
          }(),
      ],
      // 이 기록에 다는 메모 — id 를 잃은 옛 기록은 가리킬 수 없어 두지 않는다.
      memo: entry.id.isEmpty
          ? null
          : ExerciseMemoButton(
              clientId: clientId,
              memoRef: memoRefForHistory(entry),
            ),
    );
  }

  final Widget tag;
  final List<_Line> lines;

  /// 머리 오른쪽 메모 자리 — 이 상자(기록)에 남긴 메모.
  final Widget? memo;

  /// 한 운동 — 요약(운동 시간·근력 세트)을 센다. 없으면 줄 수만큼 모두 한 것.
  final List<ClientExerciseItem>? done;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardTop(tag: tag, memo: memo),
          const SizedBox(height: OnCareSpacing.s8),
          // 알약 글씨가 시작하는 자리에 내용을 맞춘다 — 알약 배경 끝이 아니라.
          Padding(
            padding: const EdgeInsets.only(left: _tagInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _GroupedLines(lines: lines, showCalories: true),
                _CardFooter(
                  done: done ?? const <ClientExerciseItem>[],
                  calories: _caloriesOf(<ClientExerciseItem>[
                    for (final _Line line in lines)
                      if (line.calories != null)
                        ClientExerciseItem(name: '', calories: line.calories),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `오늘` 상자 내용이 들여 쓰는 폭 — 출처 알약 안쪽 여백과 같아, 유형 이름과
/// 운동 줄이 알약 글씨와 한 세로줄에 선다.
const double _tagInset = OnCareSpacing.s8;

/// `오늘` 상자 머리 — 왼쪽 알약(과 덧붙일 말), 오른쪽 끝 메모.
class _CardTop extends StatelessWidget {
  const _CardTop({required this.tag, this.note, this.memo});

  final Widget tag;
  final Widget? note;
  final Widget? memo;

  @override
  Widget build(BuildContext context) {
    final Widget? note = this.note;
    return Row(
      children: <Widget>[
        tag,
        // 덧붙일 말이 남는 폭을 다 가져 메모를 오른쪽 끝으로 민다 — `Flexible`
        // 과 `Spacer` 를 함께 두면 폭을 반씩 나눠 메모가 가운데쯤에 멈춘다.
        if (note != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(child: note),
        ] else
          const Spacer(),
        ?memo,
      ],
    );
  }
}

/// `오늘` 상자 아래 — 선, 요약(운동 시간 · 근력 세트)과 `총 소모 N kcal`.
class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.done, this.calories});

  /// 한 운동 줄.
  final List<ClientExerciseItem> done;
  final int? calories;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int seconds = _secondsOf(done);
    final int sets = done.fold<int>(
      0,
      (int sum, ClientExerciseItem item) => sum + (item.sets ?? 0),
    );
    final int? total = calories;
    final String summary = <String>[
      if (seconds > 0)
        '${l.clientTrendWorkoutMinutes} ${formatExerciseDuration(l, seconds)}',
      if (sets > 0) '${l.routineTypeStrength} ${l.progSetsValue(sets)}',
    ].join(' · ');
    if (summary.isEmpty && total == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  summary,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
              if (total != null)
                // 식단의 `총 N kcal`(먹은 양)과 헷갈리지 않게 `소모` 를 붙인다.
                Text(
                  l.workoutTotalBurned(formatNumber(total)),
                  style: OnCareTypography.numeric(
                    tokens
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
                        .copyWith(color: tokens.brand.primary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `오늘` 맨 위 개인운동 상자 — 지금 걸린 개인운동과 오늘 했는지. (#2508)
///
/// 머리 줄은 다른 상자와 같다: 왼쪽 `개인운동` 알약, 한 수(`2/4`)와 보낸 날·
/// 끝나는 날. 줄은 유형별로 묶어 `운동명 · 세부 효과` 이고, 왼쪽 막대가 한 것
/// (색)과 아직(회색)을 가른다. 묶음 안에서는 아직 → 한 것 순서다. 아래는 한
/// 것의 요약과 `총 N kcal`.
///
/// 내리기(X)는 두지 않는다 — 바꾸는 길은 새로 보내기 하나다(#2511).
class _PersonalTodayCard extends ConsumerWidget {
  const _PersonalTodayCard({
    required this.clientId,
    required this.date,
    required this.routines,
    this.entry,
  });

  final String clientId;
  final DateTime date;
  final List<AssignedRoutine> routines;

  /// 오늘 한 개인운동 이력(하루치 카드) — 없으면 아직 아무것도 안 한 날이다.
  final RoutineHistoryEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RoutineDaysKey key = routineDaysKeyNow(clientId);
    // 날짜별 조회가 실패해도 목록은 그대로 보인다 — 한 것 표시만 배정의
    // `completed` 로 떨어진다.
    final RoutineDays days =
        ref.watch(clientRoutineDaysProvider(key)).valueOrNull ??
        RoutineDays.empty;
    final List<ClientExerciseItem> items =
        ref
            .watch(clientExercisesOnProvider((clientId: clientId, date: date)))
            .valueOrNull ??
        const <ClientExerciseItem>[];
    final RoutineHistoryEntry? entry = this.entry;
    final List<ClientExerciseItem> rows = entry == null
        ? <ClientExerciseItem>[
            for (final ClientExerciseItem item in items)
              if (_isAssignedRow(item)) item,
          ]
        : _dayRowsOf(entry, items, personal: true);
    // 줄마다의 운동 행(kcal·회원이 고른 강도) — 그날 개인운동 행에서 이름으로
    // 하나씩 짝짓는다.
    final List<ClientExerciseItem> pool = <ClientExerciseItem>[...rows];
    ClientExerciseItem? rowOf(AssignedRoutine routine) {
      final int at = pool.indexWhere(
        (ClientExerciseItem row) =>
            row.assignedRoutineId == routine.id ||
            row.name.trim() == routine.name.trim(),
      );
      if (at < 0) return null;
      return pool.removeAt(at);
    }

    bool doneToday(AssignedRoutine routine) =>
        days.dayOf(key.day)?.itemFor(routine.id)?.status.completed ??
        routine.completed;
    final List<AssignedRoutine> ordered = <AssignedRoutine>[
      for (final AssignedRoutine r in routines)
        if (!doneToday(r)) r,
      for (final AssignedRoutine r in routines)
        if (doneToday(r)) r,
    ];
    final int doneCount = routines.where(doneToday).length;
    final String? sent = _todayWindow(l, days, key.day);
    return AppCard(
      key: const ValueKey<String>('workout-pending-routines'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardTop(
            tag: AppTag(label: l.workoutKindPersonal, tone: AppTagTone.brand),
            note: Text.rich(
              key: const ValueKey<String>('workout-pending-window'),
              TextSpan(
                children: <InlineSpan>[
                  // `3/6` 은 날짜처럼 읽혀 문장으로 적는다.
                  TextSpan(
                    text: l.workoutRoutineDoneOf(doneCount, routines.length),
                    style: context.oncare
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                  if (sent != null) TextSpan(text: '   $sent'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
            // 그날 개인운동 상자에 다는 메모.
            memo: ExerciseMemoButton(
              clientId: clientId,
              memoRef: TrainerMemoRef(
                kind: TrainerMemoRefKind.personal,
                day: ymd(date),
              ),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 알약 글씨가 시작하는 자리에 내용을 맞춘다 — 알약 배경 끝이 아니라.
          Padding(
            padding: const EdgeInsets.only(left: _tagInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _GroupedLines(
                  key: const ValueKey<String>('workout-pending-list'),
                  showCalories: true,
                  lines: <_Line>[
                    for (final AssignedRoutine routine in ordered)
                      () {
                        final bool done = doneToday(routine);
                        final ClientExerciseItem? row = done
                            ? rowOf(routine)
                            : null;
                        return _Line(
                          key: ValueKey<String>(
                            done
                                ? 'workout-routine-done-${routine.id}'
                                : 'workout-routine-pending-${routine.id}',
                          ),
                          type: routine.type,
                          name: routine.name,
                          detail: _pendingRoutineAmountLabel(l, routine),
                          // 한 운동은 회원이 고른 강도, 아직은 처방 강도다.
                          intensity: row?.intensity ?? routine.intensity,
                          planned: done ? routine.intensity : null,
                          effect: _effectOf(l, routine),
                          mark: done ? _LineMark.done : _LineMark.pending,
                          // 안 한 운동은 유형·시간·강도로 어림한 예상값을 옅게 —
                          // 프로그램 화면이 보낼 때 보여 준 값과 같은 식이다.
                          calories: done ? row?.calories : _estimateOf(routine),
                          estimated: !done,
                        );
                      }(),
                  ],
                ),
                _CardFooter(
                  done: <ClientExerciseItem>[
                    for (final ClientExerciseItem item in rows)
                      if (item.done) item,
                  ],
                  calories: _caloriesOf(rows),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 아직 안 한 개인운동의 예상 소모 kcal — 근력은 세트를 분으로 바꿔 센다.
  static int? _estimateOf(AssignedRoutine routine) => estimateRoutineCalories(
    name: routine.name,
    type: routine.type,
    minutes: routine.type == '근력' && (routine.sets ?? 0) > 0
        ? minutesFromSets(routine.sets!)
        : routine.minutes,
    intensity: routine.intensity,
  )?.calories;

  /// 이름 뒤 옅은 한 줄 — 효과가 있으면 효과, 없을 때만 옛 사유(#2951).
  static String? _effectOf(AppLocalizations l, AssignedRoutine routine) {
    if (routine.effect.isNotEmpty) return routineEffectText(l, routine.effect);
    if (routine.reason.isNotEmpty) return routine.reason;
    return null;
  }

  /// 머리 줄 알약 옆 — "9/29(화) 보냄 · 10/5(월)까지". 지금 걸린 개인운동이
  /// 없으면(기한 없는 따로 배정뿐) 적지 않는다.
  static String? _todayWindow(
    AppLocalizations l,
    RoutineDays days,
    DateTime today,
  ) {
    final RoutineDayGroup? group = days.currentPersonal(today);
    final DateTime? last = group?.lastDay;
    if (group == null || last == null) return null;
    return l.workoutRoutineSentUntil(
      routineDayLabel(l, group.sentOn),
      routineDayLabel(l, last),
    );
  }
}

/// 펼친 날의 한 줄 — `[머리] 내용 …… 오른쪽 값` (식단 `_DayRow` 와 같은 틀).
class _WorkoutDayRow extends StatelessWidget {
  const _WorkoutDayRow({
    super.key,
    required this.label,
    required this.lines,
    this.trailing,
    this.divider = true,
  });

  /// 위에 선을 긋는가 — 첫 줄(하루 합계)은 긋지 않는다.
  final bool divider;

  /// 머리 칸 — 출처 알약이나 `하루 합계`.
  final Widget label;
  final List<Widget> lines;
  final Widget? trailing;

  /// 머리 칸 폭 — 식단 펼친 날과 같다.
  static const double labelWidth = 64;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing = this.trailing;
    return Container(
      padding: EdgeInsets.only(
        top: divider ? OnCareSpacing.s12 : OnCareSpacing.s4,
        bottom: OnCareSpacing.s12,
      ),
      decoration: divider
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 알약 길이가 줄마다 달라(PT·개인운동·회원 추가) 가운데에 세운다.
          SizedBox(
            width: labelWidth,
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: label),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lines,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s12),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// 배정 한 줄이 말하는 **양**. 근력은 세트·횟수·중량, 나머지는 시간이다.
///
/// 프로그램 탭 AI 개인 운동 제안 카드의 [routineSuggestionAmountLabel] 과 같은
/// 규칙이다 — 다만 이 목록은 [RoutineSuggestion] 이 아니라 이미 배정된
/// [AssignedRoutine] 을 다룬다.
///
/// 맨몸 운동(0kg)과 중량이 없는 옛 행은 중량 자리를 비운다(#2533).
String _pendingRoutineAmountLabel(AppLocalizations l, AssignedRoutine routine) {
  if (routine.type != '근력') return formatExerciseDuration(l, routine.seconds);
  final List<String> parts = <String>[
    if (routine.sets != null) l.progSetsValue(routine.sets!),
    // 버티는 운동은 회가 아니라 초로 읽는다 — 둘은 배타다(#1969).
    if (routine.holdSeconds != null)
      l.progHoldValue(routine.holdSeconds!)
    else if (routine.reps != null)
      l.progRepsValue(routine.reps!),
    ?strengthWeightLabel(l, routine.weight),
  ];
  return parts.isEmpty ? l.minutesShort(routine.minutes) : parts.join(' · ');
}

/// 고객이 그날 한 운동 한 줄 — `벤치프레스 · 4세트 · 10회 · 40kg`. (#1902)
///
/// 단위는 로케일을 타는 문구라 여기서 붙인다. 예전에는 이 수가 이름 문자열
/// 안에 있어서(`레그프레스 70kg · 4세트`), 값을 필드로 옮기면 화면에서 사라졌다.
///
/// 근력은 세트·횟수·중량으로, 나머지는 시간으로 읽는다 — 회원 앱과 같은 규칙이다
/// (#1262). 시간은 회원이 적은 만큼 초까지 보인다(`45초`·`1시간 5분 30초`).
/// 적히지 않은 칸은 건너뛴다.
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
    ?strengthWeightLabel(l, weight),
    // 회원이 초까지 적은 기록은 초까지 읽는다 — 분으로 접으면 `45초` 가
    // `1분` 이 된다(#2071).
    if (sets == null && item.seconds > 0)
      formatExerciseDuration(l, item.seconds),
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
