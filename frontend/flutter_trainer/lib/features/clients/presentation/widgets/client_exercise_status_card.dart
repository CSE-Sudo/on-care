import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart'
    show clientExerciseLine;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
// 차트 그림(BurnDonut·BurnGoalRings·BurnBarChart·ActivityHeadlineLine)은 패키지에
// 대응이 없어 앱 위젯을 그대로 쓴다. BurnBarChart 가 받는 선택 상태도 그 앱
// 쪽 [PeriodChartSelection] 이라 이것만 가져온다.
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 데이터를 받는 동안 비워 두는 높이 — 받은 뒤의 그래프 자리와 크게 어긋나지
/// 않게 둔다.
const double _loadingHeight = 170;

/// `전체` 상세 영역의 최대 높이 (#1426).
///
/// 기록 수만큼 열이 길어지면 프로그램 탭의 좁은 칸이 통째로 목록이 되어,
/// 프로그램 작성 화면과 나란히 볼 수 없다. 넘치는 만큼은 이 영역 **안에서**
/// 스크롤한다. 기록이 적으면 그만큼만 차지한다 — 늘 이 높이를 차지하면 빈
/// 칸이 남는다.
const double _allMaxHeight = 260;

/// `전체` 카드 머리줄의 기준 높이 — 유형별 내역 세 줄이 들어간다.
const double _allHeaderHeight = 44;

/// 막대 영역의 최소 높이. 좁은 칸에서도 막대가 사라지지 않게 한다.
const double _minBarHeight = 40;

/// 그래프 자리가 따라가는 글자 배율의 하한·상한.
const double _minChartTextScale = 1;
const double _maxChartTextScale = 1.6;

/// 고객 운동 현황 — 회원 앱 운동 탭 `운동 현황` 과 **같은 그림**이다. (#943)
///
/// `오늘` 은 도넛 + 유형별 시간, `이번 주`·`이번 달` 은 유형별 3색 누적 막대다.
/// 예전에는 트레이너만 다른 그래프를 봤다 — 회원이 "이번 주 근력이 적었죠" 라고
/// 말해도 트레이너 화면에는 그 근거가 없었다.
///
/// 기간 토글은 이 카드가 아니라 바깥 [ClientPeriodSection] 이 그린다. 카드
/// 안에 두면 기간을 바꿀 때 토글이 함께 움직인다.
///
/// `clientName` 을 주면 그래프 아래에 **상세 운동 내역**(종목별 완료 여부)이
/// 붙는다(#1027).
class ClientExerciseStatusCard extends ConsumerWidget {
  /// Creates the card for [clientId] over [period].
  const ClientExerciseStatusCard({
    super.key,
    required this.clientId,
    required this.period,
    this.clientName,
  });

  final String clientId;
  final ClientPeriod period;

  /// 값을 주면(빈 문자열이 아니어도 됨 — 실제로는 opt-in 스위치) 그래프 아래에
  /// **상세 운동 내역**이 함께 붙는다. 그래프는 "얼마나 오래" 만 말해서, 다음
  /// 프로그램을 짤 때 정작 필요한 "무엇을 몇 세트" 가 화면 밖에 있었다(#1027).
  ///
  /// 상세 내역은 고객 탭 `운동 기록`(`clientHistoryProvider`)과 같은 자료다.
  /// 고객 탭은 같은 화면에 `운동 기록` 카드가 이미 있으므로 이 파라미터를
  /// 주지 않는다 — 한 화면에서 같은 목록을 두 번 읽게 하지 않는다.
  final String? clientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ClientPeriodKey key = clientPeriodKeyNow(clientId, period);
    final AsyncValue<ClientExercisePeriod> async = ref.watch(
      clientExercisePeriodProvider(key),
    );
    final String? name = clientName;
    // 제목은 바깥 섹션 헤더가 그린다 — 카드는 흰 판만 맡는다.
    return AppCard(
      key: const ValueKey<String>('client-exercise-status-card'),
      // 좌우를 세로보다 넉넉하게 둔다 — 도넛과 상세 묶음이 카드 양 끝에 붙지
      // 않게 하는 회원 앱 운동 카드와 같은 비율이다. (회원 앱 #1151)
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s24,
        vertical: OnCareSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          async.when(
            loading: () => const SizedBox(
              height: _loadingHeight,
              child: AppLoading(placement: AppStatePlacement.card),
            ),
            error: (_, _) => AppErrorState(
              key: const ValueKey<String>('weekly-exercise-retry'),
              title: l.clientTrendLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(clientExercisePeriodProvider(key)),
              placement: AppStatePlacement.card,
            ),
            data: (ClientExercisePeriod data) => period == ClientPeriod.today
                ? _Today(clientId: clientId, period: data)
                : _Range(period: data),
          ),
          if (name != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            _WorkoutDetail(clientId: clientId, period: period),
          ],
        ],
      ),
    );
  }
}

/// 고객 탭 `운동 기록`(`WorkoutView`)과 **같은 자료**를 그래프 아래에 붙인다.
/// (#1027 팔로업)
///
/// 처음에는 스케줄에 붙은 PT 세션(`clientSessionsProvider`)을 그래프와 같은
/// 기간으로 걸러 보여줬다. 그런데 그 세션은 트레이너가 예약한 슬롯일 뿐이고,
/// 고객 탭이 "운동 기록"이라 부르는 것은 완료율·피드백까지 포함한 별개의
/// 이력(`clientHistoryProvider`)이다 — 데모에서는 전자가 하루치뿐이라 두 탭이
/// 같은 고객을 보고도 다른 개수를 말했다. 같은 이름을 쓰는 이상 같은 자료를
/// 봐야 하므로 소스를 맞춘다.
///
/// 이 이력에는 믿을 만한 날짜 필드가 없어(`dateLabel` 은 표시용 문자열) 그래프
/// 처럼 기간으로 거를 수 없다 — 고객 탭의 `운동 기록` 도 같은 이유로 기간과
/// 무관하게 전체를 보여준다. 대신 접힌 기본 상태에서는 가장 최근 기록 하나만
/// 보이고, 아래 캐럿을 누르면 전체 이력으로 펼쳐진다.
class _WorkoutDetail extends ConsumerStatefulWidget {
  const _WorkoutDetail({required this.clientId, required this.period});

  final String clientId;

  /// 지금 보고 있는 기간. 펼쳤을 때 얼마나 보여 줄지가 이 값에 달렸다 —
  /// `이번 주` 는 한 주치를 그대로 늘어놓고, `전체` 는 정해진 높이 안에서
  /// 스크롤한다.
  final ClientPeriod period;

  @override
  ConsumerState<_WorkoutDetail> createState() => _WorkoutDetailState();
}

class _WorkoutDetailState extends ConsumerState<_WorkoutDetail> {
  /// `이번 주` 에서 펼쳤을 때 늘어놓는 최대 기록 수 — **한 주**다 (#1172).
  static const int _weekLimit = 7;

  /// 펼쳤는가. 접힌 기본 상태는 가장 최근 기록 하나다.
  ///
  /// 예전에는 누를 때마다 일곱씩 늘어나는 수(`_shown`)였다. 그래서 한 번 펼친
  /// 뒤에는 `더보기` 와 `접기` 가 나란히 서고, 계속 눌러 열을 늘릴 수 있었다.
  /// 펼침은 한 번이면 되고, 그 자리에 버튼도 하나면 된다(#1426).
  bool _expanded = false;

  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_WorkoutDetail old) {
    super.didUpdateWidget(old);
    // 기간이나 고객이 바뀌면 접힌 상태로 돌아간다 — 앞 고객의 스크롤 위치가
    // 다음 고객 목록에 남아 있으면 어디를 보고 있는지 알 수 없다.
    if (old.clientId != widget.clientId || old.period != widget.period) {
      _expanded = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<List<RoutineHistoryEntry>> async = ref.watch(
      clientHistoryProvider(widget.clientId),
    );
    // `전체` 만 안쪽 스크롤을 쓴다. `이번 주` 는 최대 일곱 줄이라 카드 높이를
    // 넘기지 않고, 넘기지 않는 목록에 스크롤을 달면 바깥 스크롤과 겹친다.
    final bool scrollsInside = widget.period == ClientPeriod.month;
    return Column(
      key: const ValueKey<String>('client-exercise-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l.workoutRecords,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textTertiary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
            child: Center(child: AppLoading.inline()),
          ),
          error: (_, _) => AppEmptyState(
            title: l.workoutLoadFailed,
            icon: Icons.cloud_off_rounded,
            placement: AppStatePlacement.card,
          ),
          data: (List<RoutineHistoryEntry> entries) {
            if (entries.isEmpty) {
              return AppEmptyState(
                title: l.workoutEmpty,
                icon: Icons.fitness_center_rounded,
                placement: AppStatePlacement.card,
              );
            }
            // 이력은 이미 최신순이다(`clientHistoryProvider`) — 접힌 상태의
            // 첫 항목이 곧 가장 최근 기록이다.
            final int limit = !_expanded
                ? 1
                : scrollsInside
                ? entries.length
                : math.min(_weekLimit, entries.length);
            final List<RoutineHistoryEntry> shown = entries
                .take(limit)
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_expanded && scrollsInside)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: _allMaxHeight),
                    // 스크롤바는 테마 기본(스크롤할 때 나타남)을 따른다 — 늘
                    // 보이게 강제하지 않는다.
                    child: ListView(
                      key: const ValueKey<String>(
                        'client-exercise-detail-scroll',
                      ),
                      controller: _scroll,
                      // 바깥 세로 스크롤이 이 목록을 자기 것으로 삼지 않게
                      // 한다 — `primary` 로 두면 두 스크롤이 같은 손짓을
                      // 두고 다툰다.
                      primary: false,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final RoutineHistoryEntry entry in shown)
                          _DetailEntry(entry: entry),
                      ],
                    ),
                  )
                else
                  for (final RoutineHistoryEntry entry in shown)
                    _DetailEntry(entry: entry),
                // 펼침 버튼은 늘 한 자리에 하나다 — 접혔으면 `더보기`,
                // 펼쳤으면 `접기`(#1426). 화살표 방향이 곧 무엇을 하는
                // 버튼인지라, 옆에 적힌 글자를 안 읽어도 안다.
                if (entries.length > 1)
                  Center(
                    child: AppButton(
                      key: ValueKey<String>(
                        _expanded
                            ? 'client-exercise-detail-collapse'
                            : 'client-exercise-detail-toggle',
                      ),
                      label: _expanded
                          ? l.workoutRecordsShowLess
                          : l.workoutRecordsShowMore,
                      trailingIcon: _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      variant: AppButtonVariant.text,
                      size: OnCareButtonSize.small,
                      onPressed: _toggle,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 이력 한 건 — 날짜·종류, 몇 개 중 몇 개를 했는지, 그리고 종목별 수행 여부.
/// 고객 탭 `_HistoryCard` 와 같은 자료를 쓰되, 사이드바 폭에 맞춰 완료율
/// 도넛·피드백·트레이너 메모는 뺀 압축판이다 — 그 편집 동작은 고객 탭에만
/// 있고, 여긴 그래프 옆 참고 자료다.
class _DetailEntry extends StatelessWidget {
  const _DetailEntry({required this.entry});

  final RoutineHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${entry.dateLabel} · ${entry.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              // 고객 탭 기록 카드와 같은 표기다(#1484) — 좁은 칸이라
              // `3/3 · 100%` 로 붙여 적고, 자리가 모자라면 퍼센트부터
              // 줄어든다.
              if (entry.totalCount > 0)
                Flexible(
                  child: Text(
                    '${entry.completionCountLabel} · ${entry.displayRate}%',
                    key: ValueKey<String>('program-done-count-${entry.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(
                          OnCareTypography.numeric(OnCareTypography.caption),
                        )
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          for (final ClientExerciseItem item in entry.exercises)
            _ExerciseLine(line: clientExerciseLine(l, item), done: item.done),
        ],
      ),
    );
  }
}

/// 기록된 운동 한 줄 — 이름과 수행 여부.
///
/// 저장된 문자열은 끝에 '✓' / '✗' 로 결과를 표시한다. 그 글자는 **저장 규칙**
/// 이지 화면에 찍을 것이 아니다: Flutter web 의 폰트 스택에 글리프가 없어
/// 두부 상자로 그려진다. 표시를 읽어 아이콘과 취소선으로 바꿔 그린다 — 앱의
/// 운동 기록 탭(`ExerciseLine`)과 같은 규칙이다.
class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.line, this.done = true});

  /// 이미 조립된 한 줄 — `벤치프레스 · 4세트 · 10회 · 40kg`.
  final String line;

  /// 실제로 했는가. 예전에는 줄 끝의 `✓`/`✗` 로 알았다(#1902).
  final bool done;

  @override
  Widget build(BuildContext context) {
    final bool skipped = line.contains('✗');
    final String text = line.replaceAll(RegExp(r'\s*[✓✗]\s*'), ' ').trim();
    final Color color = skipped
        ? OnCareColors.textDisabled
        : OnCareColors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          skipped ? Icons.close_rounded : Icons.check_rounded,
          size: OnCareSize.iconSmall,
          color: skipped ? OnCareColors.textDisabled : OnCareColors.success,
        ),
        const SizedBox(width: OnCareSpacing.s4),
        Expanded(
          child: Text(
            text,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(
                  color: color,
                  decoration: skipped ? TextDecoration.lineThrough : null,
                  decorationColor: color,
                ),
          ),
        ),
      ],
    );
  }
}

/// 세 기간이 함께 쓰는 그래프 자리. 높이를 같게 두어야 토글을 눌러도 카드가
/// 커졌다 작아지지 않는다 — 그 아래 기록 목록이 그때마다 뛴다.
///
/// 글자 배율을 따라간다. 배율만 커지면 고정 높이 안에서 내용이 넘친다.
class _ChartSlot extends StatelessWidget {
  const _ChartSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kActivityCardHeight * _chartTextScale(context),
    child: child,
  );
}

class _Today extends ConsumerWidget {
  const _Today({required this.clientId, required this.period});

  final String clientId;
  final ClientExercisePeriod period;

  /// 이번 주 안에서 **활동한 날의 최장 연속 구간**. 회원 앱 `week.streakDays`
  /// 와 같은 규칙이다(#1168) — 오늘 하루만 읽어서는 알 수 없어 같은 주를 함께
  /// 본다. 이번 주는 기간 토글이 어차피 읽는 값이라 Riverpod 캐시를 나눠 쓴다.
  int _streakOf(WidgetRef ref) {
    final ClientExercisePeriod? week = ref
        .watch(
          clientExercisePeriodProvider(
            clientPeriodKeyNow(clientId, ClientPeriod.week),
          ),
        )
        .valueOrNull;
    if (week == null) return 0;
    int best = 0;
    int run = 0;
    for (final ClientExerciseDay d in week.days) {
      if (d.logged) {
        run += 1;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (period.isEmpty) {
      return _ChartSlot(
        child: AppEmptyState(
          title: l.clientTrendTodayEmpty,
          icon: Icons.fitness_center_rounded,
        ),
      );
    }
    // 유형 분해가 없으면 전부 유산소로 본다. 임의로 나누면 없는 근력 시간을
    // 지어내는 셈이다.
    final bool split = period.days.any((ClientExerciseDay d) => d.hasTypeSplit);
    return _ChartSlot(
      child: BurnDonut(
        title: l.exBurnTodayTitle,
        calories: period.totalCalories,
        goal: kDailyBurnKcal,
        streakDays: _streakOf(ref),
        split: ActivitySplit(
          cardioMinutes: split
              ? period.totalCardioMinutes
              : period.totalMinutes,
          strengthSets: split ? period.totalStrengthSets : 0,
          stretchingMinutes: split ? period.totalStretchingMinutes : 0,
          otherMinutes: period.totalOtherMinutes,
        ),
      ),
    );
  }
}

class _Range extends StatefulWidget {
  const _Range({required this.period});

  final ClientExercisePeriod period;

  @override
  State<_Range> createState() => _RangeState();
}

class _RangeState extends State<_Range> {
  /// `전체` 그래프의 스크롤 위치와 고른 칸. 머리의 숫자가 이걸 따라간다 —
  /// 보이지 않는 구간까지 더한 합계는 지금 화면을 설명하지 못한다. (#1018)
  final PeriodChartSelection _selection = PeriodChartSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String locale = Localizations.localeOf(context).toString();
    final ClientExercisePeriod period = widget.period;
    final List<ClientExerciseDay> days = period.days;
    final bool all = days.length > 10;

    // `이번 주` 는 유형별 주간 목표를 채우는 3중 링이다 — 회원 앱과 같다.
    if (!all) {
      final bool split = days.any((ClientExerciseDay d) => d.hasTypeSplit);
      return _ChartSlot(
        child: BurnGoalRings(
          title: l.exBurnWeekTitle,
          calories: period.totalCalories,
          split: ActivitySplit(
            cardioMinutes: split
                ? period.totalCardioMinutes
                : period.totalMinutes,
            strengthSets: split ? period.totalStrengthSets : 0,
            stretchingMinutes: split ? period.totalStretchingMinutes : 0,
            otherMinutes: period.totalOtherMinutes,
          ),
        ),
      );
    }

    // `전체` 는 **한 칸이 한 주**다. 회원 앱 운동 탭과 같은 눈금이라야 둘이
    // 같은 그림을 보고 이야기할 수 있다 — 일별 막대는 여덟 달을 늘어놓으면
    // 실오라기가 되고, 한 주를 잘한 것인지 한 날을 잘한 것인지도 흐려진다.
    // (#1077)
    final List<_WeekBucket> weeks = _weekBucketsOf(days);
    return _ChartSlot(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListenableBuilder(
            listenable: _selection,
            builder: (BuildContext context, Widget? _) {
              final int? picked = _selection.selected;
              final _WeekBucket? week = picked == null ? null : weeks[picked];
              final (int first, int last) =
                  _selection.visible ?? (0, weeks.length - 1);
              final List<_WeekBucket> visible = weeks.sublist(
                first.clamp(0, weeks.length - 1),
                (last + 1).clamp(1, weeks.length),
              );
              // 고른 주가 없으면 **지금 보이는 구간의 주 평균**이다. 여덟 달을
              // 통째로 평균 내면 어느 달을 보고 있든 같은 숫자라, 그래프를 미는
              // 의미가 없다. (#1018)
              final double value =
                  week?.calories.toDouble() ??
                  (visible.isEmpty
                      ? 0
                      : visible.fold<int>(
                              0,
                              (int a, _WeekBucket w) => a + w.calories,
                            ) /
                            visible.length);
              // 머리줄은 **고른 주가 있든 없든 같은 높이**를 쓴다 (회원 앱
              // #1194). 오른쪽 내용이 한 줄(기간)에서 서너 줄(유형별 내역)로
              // 바뀌는 만큼 아래 그래프 몫이 줄어, 막대를 고를 때마다 그래프가
              // 작아졌다.
              return SizedBox(
                height: _allPeriodHeaderHeight(context),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 6,
                      child: ActivityHeadlineLine(
                        caption: week == null
                            ? l.exBurnAllTitle
                            : l.exWeekOfMonthLabel(
                                week.monday.month,
                                _weekOfMonth(week.monday),
                              ),
                        value: activityValueOfGoal(
                          locale,
                          value,
                          kWeeklyBurnKcal,
                        ),
                        unit: l.unitKcal,
                      ),
                    ),
                    // 고른 주의 내역은 kcal **오른쪽**에 붙는다 (#1129) —
                    // 그래프 아래에 따로 두면 구분선까지 필요해져 카드가 셋으로
                    // 갈린다.
                    if (week != null) ...<Widget>[
                      const SizedBox(width: OnCareSpacing.s8),
                      Expanded(
                        flex: 5,
                        // `기타` 까지 네 줄이 되는 주도 있다 — 그때는 목록
                        // 전체가 한 번에 줄어 같은 높이 안에 들어간다.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final ExerciseKind kind
                                  in ExerciseKind.values)
                                _DetailLine(
                                  label: kindLabel(l, kind),
                                  value: kindValueText(
                                    l,
                                    kind,
                                    week.split.valueOf(kind),
                                  ),
                                  color: kindColor(kind),
                                ),
                              // `기타` 는 유형이 아니다 — 셋의 남색 램프에
                              // 끼워 넣지 않고 회색으로 둔다.
                              if (week.split.otherMinutes > 0)
                                _DetailLine(
                                  label: l.exTypeOther,
                                  value: l.minutesShort(
                                    week.split.otherMinutes.round(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (visible.isNotEmpty) ...<Widget>[
                      const SizedBox(width: OnCareSpacing.s8),
                      // 평균이 어느 구간의 것인지 숫자만으로는 알 수 없다 — 밀
                      // 때마다 바뀌는 값이라 기간을 옆에 붙여 둔다.
                      Expanded(
                        flex: 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${DateFormat.Md(locale).format(visible.first.monday)}'
                            ' ~ '
                            '${DateFormat.Md(locale).format(_sundayOf(visible.last.monday))}',
                            maxLines: 1,
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.caption,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) => BurnBarChart(
                title: l.clientTrendTitle,
                selection: _selection,
                goalKcal: kWeeklyBurnKcal,
                // 막대 영역만의 높이다 — 아래 날짜 라벨 줄은 따로 자리를
                // 차지한다.
                height: math.max(
                  c.maxHeight - kBurnBarChartExtraHeight,
                  _minBarHeight,
                ),
                calories: <int>[for (final _WeekBucket w in weeks) w.calories],
                splits: <ActivitySplit>[
                  for (final _WeekBucket w in weeks) w.split,
                ],
                dates: <DateTime>[for (final _WeekBucket w in weeks) w.monday],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 고른 주의 유형별 내역 한 줄 — `유산소 195분`. 색 네모 없이 글자만 쓴다
/// (#1129) — 색은 바로 옆 막대가 이미 말하고 있다.
///
/// 색은 **유형 이름에만** 주고, 그 색은 옆 막대·링과 **같은 [kindColor]** 다
/// (회원 앱 #1364). 글자와 막대가 한눈에 짝지어져야 어느 줄이 어느 막대인지
/// 읽힌다. 값(`195분`, `12세트`)은 검정이다 — 색이 가리키는 것은 유형이지
/// 수가 아니다.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value, this.color});

  /// 유형 이름. 이 조각만 [color] 로 칠한다.
  final String label;

  /// 그 유형의 값. 언제나 검정이다.
  final String value;

  /// 유형 색([kindColor]). null 이면 회색 — 유형이 아닌 `기타` 줄이다.
  final Color? color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: label,
            style: TextStyle(color: color ?? OnCareColors.textSecondary),
          ),
          TextSpan(
            text: ' $value',
            style: const TextStyle(color: OnCareColors.textPrimary),
          ),
        ],
      ),
      maxLines: 1,
      style: context.oncare.text(
        OnCareTypography.strong(OnCareTypography.caption),
      ),
    ),
  );
}

/// `전체` 카드 머리줄의 **고정 높이**.
///
/// 유형별 내역 세 줄이 들어가는 높이다. 고른 주가 없을 때도 같은 자리를 비워
/// 두어, 막대를 골라도 그래프가 줄지 않는다 (회원 앱 #1194). 글자 배율을 따라
/// 커지되 카드와 같은 선(1.6)에서 멈춘다.
double _allPeriodHeaderHeight(BuildContext context) =>
    _allHeaderHeight * _chartTextScale(context);

/// 그래프 자리가 따라가는 글자 배율 — 1 아래로는 줄지 않고 [_maxChartTextScale]
/// 에서 멈춘다. 배율만 커지면 고정 높이 안에서 내용이 넘친다.
double _chartTextScale(BuildContext context) => MediaQuery.textScalerOf(
  context,
).scale(1).clamp(_minChartTextScale, _maxChartTextScale);

/// 그 달의 몇 번째 주인지 — `8월 1주차` 의 1.
int _weekOfMonth(DateTime monday) => ((monday.day - 1) ~/ 7) + 1;

DateTime _sundayOf(DateTime monday) =>
    DateTime(monday.year, monday.month, monday.day + 6);

/// `전체` 그래프의 한 칸 — 한 주(월~일)의 합계.
class _WeekBucket {
  _WeekBucket(this.monday);

  final DateTime monday;
  int calories = 0;

  int _cardioMinutes = 0;
  int _strengthSets = 0;

  /// 근력에 쓴 **시간**. 화면에는 세트로 적지만, 막대를 유형별로 나눌 때는
  /// 셋을 같은 단위(분)로 놓아야 몫이 뜻을 갖는다 (회원 앱 #1177).
  int _strengthMinutes = 0;

  int _stretchingMinutes = 0;
  int _otherMinutes = 0;

  ActivitySplit get split => ActivitySplit(
    cardioMinutes: _cardioMinutes.toDouble(),
    strengthSets: _strengthSets.toDouble(),
    // 막대를 유형별로 나눌 때 쓰는 **분**. 화면에는 세트로 적지만, 셋을 같은
    // 단위에 놓아야 몫이 뜻을 갖는다 (회원 앱 #1177).
    strengthMinutes: _strengthMinutes.toDouble(),
    stretchingMinutes: _stretchingMinutes.toDouble(),
    otherMinutes: _otherMinutes.toDouble(),
  );

  void add(ClientExerciseDay d) {
    calories += d.calories;
    // 유형 분해가 없는 날은 전부 유산소로 본다 — 임의로 나누면 없는 근력을
    // 지어내는 셈이다.
    _cardioMinutes += d.hasTypeSplit ? d.cardioMinutes : d.minutes;
    _strengthSets += d.strengthSets;
    _strengthMinutes += d.strengthMinutes;
    _stretchingMinutes += d.stretchingMinutes;
    _otherMinutes += d.otherMinutes;
  }
}

/// 날짜별 기록을 주 단위로 묶는다(오래된 → 최근).
///
/// 첫 주는 기간이 주 가운데에서 시작해 잘려 있을 수 있다. 그래도 그 주의
/// 자리는 남긴다 — 없애면 달 경계가 한 칸씩 밀린다.
List<_WeekBucket> _weekBucketsOf(List<ClientExerciseDay> days) {
  final List<_WeekBucket> out = <_WeekBucket>[];
  for (final ClientExerciseDay d in days) {
    final DateTime monday = clientMondayOf(d.date);
    if (out.isEmpty || out.last.monday != monday) out.add(_WeekBucket(monday));
    out.last.add(d);
  }
  return out;
}
