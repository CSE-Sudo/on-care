import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_ai_analysis_card.dart';
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

/// 수행 피드백 입력의 최대 글자 수 — 서버 계약 값이다.
const int _feedbackMaxLength = 2000;

/// 수행 피드백 입력 칸의 줄 수.
const int _feedbackLines = 5;

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
      const SizedBox(height: OnCareSpacing.s12),
      // 현황을 본 다음 같은 기간의 AI 해석을 읽고, 바로 아래에서 날짜별
      // 근거를 확인한다. 긴 기록 끝에 분석을 두지 않는다. (#1284)
      _ExerciseAiComment(clientId: client.id, period: _period),
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

/// 완료 상태 색 — 100% 완료(초록) / 진행 중(주황) / 미시작(회색).
///
/// '부분' 은 진행 상태이지 주의가 아니다. 빨강으로 올리면 아무것도 하지 않은
/// 0%(회색)보다 부분 완료가 더 위험해 보여 척도가 뒤집힌다(#690).
///
/// 화면 밖에서도 읽을 수 있게 열어 둔다 — 이 세 단계가 곧 `완료` 의 정의라,
/// 색이 흔들리면 테스트가 먼저 걸린다(#1239).
Color workoutRateColor(int rate) {
  // 100% 는 두 앱이 함께 쓰는 **완료 초록**이다(#1239). 예전에는 어두운 초록
  // (`#22A882`)이었는데, 그 색은 회원 앱에서 식단 화면의 계열색으로 남아 있어
  // 같은 `완료` 를 두 앱이 다른 초록으로 칠하고 있었다 — 트레이너 앱 안에서도
  // 일정·할 일 완료와 이 배지의 초록이 갈렸다.
  if (rate >= 100) return OnCareColors.success;
  if (rate > 0) return OnCareColors.caution;
  // 미시작은 `borderStrong`(#DEE8F1) 이었다. 4px 띠일 때는 옅어도 보였지만,
  // 색 띠를 걷어낸 지금은 이 색이 배지의 글자색이라 판에 거의 묻힌다.
  // 비활성이되 읽히는 회색으로 내린다 — 뜻은 그대로다(#1025).
  return OnCareColors.textSecondary;
}

/// [workoutRateColor] 와 같은 세 단계를 태그 톤으로 옮긴 것. 배지는 [AppTag]
/// 라 색을 직접 받지 않는다 — 두 함수가 같은 단계를 같은 색으로 말한다.
AppTagTone workoutRateTone(int rate) {
  if (rate >= 100) return AppTagTone.success;
  if (rate > 0) return AppTagTone.caution;
  return AppTagTone.neutral;
}

/// A single workout record, styled as a mission card: date/kind, a
/// completion badge, exercise lines (skipped ones struck through), client
/// feedback, trainer note.
class _HistoryCard extends ConsumerStatefulWidget {
  const _HistoryCard({required this.clientId, required this.entry});

  final String clientId;
  final RoutineHistoryEntry entry;

  @override
  ConsumerState<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends ConsumerState<_HistoryCard> {
  bool _saving = false;

  Future<void> _editFeedback() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? feedback = await showAppDialog<String>(
      context: context,
      builder: (_) => _FeedbackDialog(initialValue: widget.entry.trainerNote),
    );
    if (feedback == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(clientRepositoryProvider)
          .updateHistoryFeedback(widget.clientId, widget.entry.id, feedback);
      ref.invalidate(clientHistoryProvider(widget.clientId));
      if (!mounted) return;
      showAppToast(context, l.routineFeedbackSaved, type: AppToastType.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(
          l,
          error is AppError ? error.message : null,
          l.routineFeedbackFailed,
        ),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final RoutineHistoryEntry entry = widget.entry;
    // 미션 카드 — 왼쪽 띠 색이 완료 상태를 한눈에 말한다. 원형 게이지는
    // 지웠다: 몇 개 중 몇 개를 했는지는 바로 아래 줄이 이미 정확히 말하고,
    // 카드 전체가 "이 미션을 깼는가" 를 색 하나로 답하면 충분하다(#1025).
    //
    // 다른 세 변에는 색을 주지 않는다 — `Border` 에 보이는 색이 두 가지면
    // (띠 색 + 회색 테두리) `borderRadius` 와 함께 그릴 수 없어 런타임에
    // 터진다(Flutter `BoxBorder`, 보이는 색이 하나일 때만 둥근 모서리를
    // 그린다). `_NoteBox` 의 왼쪽 띠와 같은 규칙이다.
    // 배포된 화면과 같은 흰 판이다 — 색 띠를 두르지 않는다. 완료 상태는
    // 오른쪽 배지가 색과 숫자로 말하고, 판까지 그 색을 입으면 한 카드가
    // 같은 말을 두 번 한다(#1025).
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 날짜는 적지 않는다 — 이 판을 펼친 줄이 바로 위에서
                    // 이미 그 날을 말하고 있다(#1025).
                    AppTag(
                      label: routineKindLabel(l, entry.label),
                      tone: AppTagTone.brand,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 배지의 `67%` 가 어디서 나온 값인지 — 배정한 운동 중 몇 개를
              // 했는가다. 왼쪽에 한 문장으로 두던 것을 퍼센트 바로 옆으로
              // 옮겨 두 값을 한눈에 함께 읽는다(#1484).
              if (entry.totalCount > 0) ...<Widget>[
                Text(
                  entry.completionCountLabel,
                  key: ValueKey<String>('workout-done-count-${entry.id}'),
                  style: OnCareTypography.numeric(
                    tokens.text(
                      OnCareTypography.strong(OnCareTypography.caption),
                    ),
                  ).copyWith(color: OnCareColors.textTertiary),
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              _MissionBadge(rate: entry.displayRate),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          for (final (int i, ClientExerciseItem item)
              in entry.exercises.indexed)
            _ExerciseLine(
              key: ValueKey<String>('workout-exercise-line-${entry.id}-$i'),
              line: clientExerciseLine(l, item),
              done: item.done,
            ),
          // 개인 운동(배정 루틴)에 회원이 적는 피드백은 없앴다(#1825) — 회원의
          // 불편·부정적 반응은 채팅에서 감지해 모은다. 옛 데이터가 남아 있어도
          // 그리지 않는다. PT·프로그램 세션에 대한 회원 피드백은 그대로 보인다.
          if (entry.clientFeedback.isNotEmpty &&
              entry.assignedRoutineId == null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            _NoteBox(
              // 이 피드백이 **무엇에 대한 말인지** 제목이 말한다(#1453).
              title: clientFeedbackTitle(l, entry),
              body: entry.clientFeedback,
              color: tokens.brand.primary,
            ),
          ],
          if (entry.trainerNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            _NoteBox(
              title: l.trainerNote,
              body: entry.trainerNote,
              // 노트다. 주의가 아니므로 빨강으로 올리지 않는다(#690).
              color: OnCareColors.caution,
            ),
          ],
          if (entry.assignedRoutineId != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: ValueKey<String>('routine-feedback-${entry.id}'),
                label: entry.trainerNote.isEmpty
                    ? l.routineFeedbackWrite
                    : l.routineFeedbackEdit,
                onPressed: _saving ? null : _editFeedback,
                variant: AppButtonVariant.secondary,
                size: OnCareButtonSize.small,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 입력 폼이라 중간 폭이다.
    return AppDialog(
      title: l.routineFeedbackTitle,
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('routine-feedback-save'),
        confirmLabel: l.actionSave,
        onConfirm: () {
          final String text = _controller.text.trim();
          if (text.isNotEmpty) Navigator.of(context).pop(text);
        },
      ),
      child: AppTextField(
        key: const ValueKey<String>('routine-feedback-input'),
        controller: _controller,
        autofocus: true,
        maxLength: _feedbackMaxLength,
        maxLines: _feedbackLines,
        hint: l.routineFeedbackHint,
      ),
    );
  }
}

/// 완료 배지 — 원형 게이지 대신 아이콘·색·글자로 한 번에 말한다(#1025).
///
/// 미션을 깼는지가 중요하지, 정밀한 gauge 가 중요한 자리가 아니다. 100%는
/// 트로피, 진행 중은 깃발, 0%는 빈 원으로 — 숫자를 안 읽어도 색과 아이콘만
/// 으로 상태가 읽힌다.
class _MissionBadge extends StatelessWidget {
  const _MissionBadge({required this.rate});

  final int rate;

  @override
  Widget build(BuildContext context) {
    final IconData icon = rate >= 100
        ? Icons.emoji_events_rounded
        : rate > 0
        ? Icons.flag_rounded
        : Icons.radio_button_unchecked_rounded;
    // 판에서 색 띠를 걷어낸 뒤로 완료 상태를 말하는 것은 이 배지뿐이다.
    // 예전에는 오른쪽 원형 게이지가 그만한 자리를 차지했으니(배포된 화면),
    // 그 자리를 이어받을 만큼은 읽혀야 한다(#1025).
    return AppTag(label: '$rate%', icon: icon, tone: workoutRateTone(rate));
  }
}

/// Left-bordered note box ("고객 피드백" navy / "트레이너 메모" orange).
class _NoteBox extends StatelessWidget {
  const _NoteBox({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: OnCareColors.onWhite(color, OnCareAlpha.subtle),
        borderRadius: OnCareRadius.mdAll,
        border: Border(
          left: BorderSide(
            color: OnCareColors.onWhite(color, OnCareAlpha.strong),
            width: OnCareSpacing.s4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: color),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            body,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
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

/// 기간에 맞는 운동 조언. 식단과 **같은 카드**를 쓴다. (#1025)
///
/// 서버가 만든 문장이다 — 화면이 따로 계산하면 같은 회원의 같은 주를 두 곳이
/// 다르게 말한다(식단이 #1017 에서 겪은 것과 같은 문제다).
class _ExerciseAiComment extends ConsumerWidget {
  const _ExerciseAiComment({required this.clientId, required this.period});

  final String clientId;
  final ClientPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 아직 오지 않았거나 실패하면 카드를 세우지 않는다. 운동에는 식단의
    // `dietAiBalanced` 같은 화면 쪽 대체 문구가 없다 — 없는 조언을 지어내는
    // 대신 자리를 비운다.
    final String message =
        ref
            .watch(
              clientExerciseAdviceProvider((
                clientId: clientId,
                period: period,
              )),
            )
            .valueOrNull ??
        '';
    return ClientAiAnalysisCard(
      cardKey: const ValueKey<String>('exercise-ai-analysis'),
      period: period,
      message: message,
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
            _HistoryCard(clientId: widget.clientId, entry: entry),
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
                  // 그날의 미션 카드가 펼친 자리로 들어온다 — 이행률·종류·
                  // 피드백·메모까지, 예전 `운동 기록` 카드가 하던 말 그대로다.
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
              _HistoryCard(clientId: clientId, entry: entry),
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

/// 아직 하지 않은 개인 운동과 그 취소. (#1020)
///
/// 배정된 루틴 **목록**을 되살리는 것이 아니다. 지난 배정·PT 이력은 프로그램
/// 탭이 맡고, 여기에는 물릴 수 있는 것만 온다 — 아직 수행하지 않은 개인 운동.
/// 이미 한 운동은 여기 오지 않는다: 배정을 지운다고 한 일이 없던 일이 되지
/// 않으므로, 취소 버튼을 걸어 두면 기록까지 지운다고 오해하게 된다.
class _PendingRoutines extends ConsumerWidget {
  const _PendingRoutines({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<AssignedRoutine> pending =
        (ref.watch(assignedRoutinesProvider(clientId)).valueOrNull ??
                const <AssignedRoutine>[])
            .where((AssignedRoutine r) => !r.completed)
            .toList();
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
    if (routine.reps != null) l.progRepsValue(routine.reps!),
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
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s12,
      ),
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
  final double? weight = item.weight;
  final List<String> parts = <String>[
    item.name,
    if (sets != null && sets > 0) l.progSetsValue(sets),
    if (reps != null && reps > 0) l.progRepsValue(reps),
    if (weight != null && weight > 0)
      '${_trimZeroKg(weight)}${l.routineUnitKg}',
    if (sets == null && item.minutes > 0) l.minutesShort(item.minutes),
  ];
  return parts.join(' · ');
}

/// 20.0 → `20`, 62.5 → `62.5`. 정수 무게에 소수점이 붙으면 원판 단위가 아닌
/// 값을 적은 것처럼 읽힌다.
String _trimZeroKg(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
