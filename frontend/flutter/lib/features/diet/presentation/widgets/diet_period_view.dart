import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/chart_semantics.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare/shared/widgets/period_range_label.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 영양 요약 카드의 기준 높이. 오늘·이번 주·전체 세 화면이 함께 쓴다 — 기간
/// 토글을 눌렀을 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
/// 최소 높이라 글자 배율이 커지면 셋이 함께 커진다. (#1124)
///
/// 이 값은 **가장 키가 큰 카드(오늘)** 의 실제 내용 높이를 재서 4 격자의 다음
/// 값으로 올린 것이다. 나머지 둘이 거기에 맞춰진다. 그 규칙으로 240 → 248
/// (#1699) → 284 (#1879, 나트륨 진행바 한 줄이 붙으며) 로 올라왔다.
///
/// 나트륨이 당류와 같은 자리로 내려가며(#1986) 그 줄이 빠졌다. 올릴 때의 근거가
/// 사라졌으므로 같은 규칙으로 다시 잰다 — `오늘` 카드 내용이 283 에서 214 로
/// 내려가, 4 격자의 다음 값은 216 이다.
const double kDietSummaryCardHeight = 216;

/// `전체` 그래프가 한 화면에 보여주는 날 수.
///
/// 처음에는 30(≈한 달)이었다. 막대 사이를 띄우려면(양옆 [OnCareSpacing.s2])
/// 그 여유가 어딘가에서 나와야 하는데, 칸 수를 30으로 둔 채 벌리면 전부 막대
/// 두께에서 깎인다 — 기준 폭(375)에서 6.5 → 4.5 가 된다. 칸 수를 줄여 자리를
/// 만들면 막대는 그대로(6.6)이고 벌린 만큼이 전부 사이로 간다.
///
/// 폭에서 칸 수를 구하지 않고 **상수로 못박는 이유**는 카드 머리의 `하루 평균`
/// 이 지금 보이는 구간만 세기 때문이다(#1018). 칸 수가 폭을 따라가면 같은
/// 기록도 기기마다 다른 구간의 평균이 된다.
const int _kAllDaysPerScreen = 24;

/// 머리줄 오른쪽 칸 맨 위에 날짜 기간이 얹히며 머리줄이 키가 커진 만큼 (#2009).
///
/// 재서 얻은 값이다. 날짜에 제 줄을 따로 주면 24(한 줄 + 간격)가 들고 그 줄
/// 왼쪽이 통째로 비었다 — 탄단지 위에 얹으면 16 으로 줄고 빈 줄도 없다.
///
/// 카드 높이([kDietSummaryCardHeight])는 **`오늘` 카드**를 따라가고 그 카드는
/// 이 날짜를 갖지 않으므로 상수 자체는 그대로다. 대신 기간 카드의 그래프가
/// 이만큼 자리를 내준다 — 그러지 않으면 기간 카드만 키가 커져 토글을 누를 때
/// 아래 내용이 뛴다(#1124). 글자 지표가 바뀌어 이 값이 어긋나면
/// `diet_summary_card_height_test.dart` 가 세 카드 높이로 알려 준다.
const double _kHeadlineRangeExtent = 16;

/// 머리줄(숫자 + 오른쪽 칸)이 늘 차지하는 최소 높이 (#2009).
///
/// 재서 얻은 값이다 — 날을 고르지 않았을 때(날짜 기간 + 탄단지) 72, 고른 뒤
/// (회색 바탕 + 탄단지) 67~71. 둘 중 큰 쪽에 맞춰 두 상태가 같은 자리를
/// 쓰게 한다. 글자 배율을 따라 함께 커진다 — 운동 탭 `전체` 의 머리줄과 같은
/// 규칙이다(#1194).
const double _kHeadlineMinHeight = 72;

/// 식단 탭의 기간 뷰(이번 주 / 전체).
///
/// 탭의 `운동 현황` 과 같은 기간 토글 아래에서 **하루 평균**을 머리 숫자로
/// 보여준다. 합계가 아니라 평균인 이유는 주(7일)와 달(30일)의 길이가 달라
/// 합계끼리는 견줄 수 없기 때문이다.
///
/// 두 기간 모두 **칼로리** 하나를 본다. 그램이 아니라 칼로리가 기간이 묻는
/// 값이고, 탄단지는 고르는 지표가 아니라 그 칼로리를 무엇이 채웠는지로 따로
/// 나타난다 — 머리 숫자 옆의 세 줄과 막대의 누적 구간이다.
///
/// 한동안 나트륨을 함께 오가며 봤지만(#1879) 당류와 같은 자리로 내려갔다
/// (#1986) — 그래프로 그리지 않고 AI 맞춤 조언이 말로 알려 준다. 고를 것이
/// 칼로리 하나뿐이므로 **지표 칩 줄 자체가 없다.** 고를 것이 하나인 자리는
/// 고르는 자리가 아니다. 그 줄에 함께 있던 날짜 기간은 남는다.
///
/// 기간에 따라 그림만 다르다.
///
///  * **이번 주** — 일곱 칸의 꺾은선. 홈 식단·영양 카드와 **같은 그림**이다
///    ([MetricTrendChart]) — 한 주를 두 화면이 다른 모양으로 말하면 본 것을
///    머릿속에서 다시 맞춰야 한다.
///  * **전체** — 옆으로 미는 막대. 하루하루가 탄단지 색 구간으로 쌓인다.
class DietPeriodView extends ConsumerStatefulWidget {
  const DietPeriodView({
    required this.range,
    required this.weekly,
    this.profile,
    super.key,
  });

  final DietDateRange range;

  /// 이번 주인가. 주간은 한 화면에 일곱 칸을 요일 라벨로, 전체는 칸을 옆으로
  /// 밀어 보는 막대로 그린다 — 두 기간이 같은 패키지 그래프를 쓴다(#1700).
  final bool weekly;

  final UserProfile? profile;

  @override
  ConsumerState<DietPeriodView> createState() => _DietPeriodViewState();
}

class _DietPeriodViewState extends ConsumerState<DietPeriodView> {
  /// 그래프의 스크롤 위치와 고른 날. 머리의 숫자와 막대가 같은 상태를
  /// 봐야 해서 여기서 들고 둘에게 건넨다. (#1018)
  final PeriodChartSelection _selection = PeriodChartSelection();

  @override
  void didUpdateWidget(DietPeriodView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 기간 토글을 눌러도 이 위젯은 트리의 같은 자리에 같은 타입으로 남아
    // `State` 가 재사용된다 — 바뀌는 것은 `range` 와 `weekly` 뿐이고 고른
    // **인덱스**는 그대로 살아남아 다음 기간의 배열에 쓰인다. `전체`(84칸)의
    // 78 이 `이번 주`(7칸)로 넘어오면 `values[picked]` 가 범위를 벗어나 카드가
    // 통째로 죽고, 반대 방향은 터지지 않는 대신 회원이 고른 적 없는 날을
    // 가리킨다. 보이는 구간도 같이 남아 `하루 평균` 이 앞 기간의 창으로
    // 계산된다. 배열이 바뀌면 둘을 함께 푼다. (#1984)
    if (widget.range != oldWidget.range || widget.weekly != oldWidget.weekly) {
      _selection.reset(includeVisible: true);
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// 꺾은선의 세로 눈금. **홈 탭과 같은 값**이라 두 화면의 축이 어긋나지
  /// 않는다(`dashboard_content.dart` 의 `_kCalorieTicks` 와 짝).
  static const List<double> _ticks = <double>[0, 1500, 2500];

  int get _goal =>
      widget.profile?.effectiveDailyCalories ??
      UserProfile.defaultDailyCalories;

  /// 소수 첫째 자리까지만 남기고 정수는 콤마만 붙인다(당류 17.8 이 18 로
  /// 반올림돼 하루 뷰와 어긋나지 않도록).
  String _number(num v) => v == v.roundToDouble()
      ? NumberFormat('#,###').format(v)
      : NumberFormat('#,##0.#').format(v);

  void _retry() {
    // 실패는 날짜별 provider 에 남아 있다. 집계만 무효화하면 같은 에러를 다시
    // 읽어 와 아무 일도 일어나지 않는다.
    for (final DateTime d in dietRangeDates(widget.range)) {
      ref.invalidate(dietByDateProvider(d));
    }
    ref.invalidate(dietPeriodProvider(widget.range));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<DietPeriod> async = ref.watch(
      dietPeriodProvider(widget.range),
    );
    // 바깥 섹션(영양 요약)이 이미 제목과 좌우 여백을 갖는다 — 여기서 또 두면
    // 제목이 두 줄로 겹치고 여백이 이중으로 들어간다(#681).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 날짜 기간은 **카드 안** 오른쪽 위에 있다 (#2009) — 운동 탭과 같은
        // 자리다. 카드 밖에 두면 카드가 제 기간을 스스로 말하지 않는다.
        async.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (Object e, StackTrace _) => AppErrorState(
            title: l.dietLoadError,
            retryLabel: l.actionRetry,
            onRetry: _retry,
            placement: AppStatePlacement.card,
          ),
          data: (DietPeriod period) => period.isEmpty
              ? AppEmptyState(
                  title: l.dietPeriodEmpty,
                  icon: AppIcons.diet,
                  placement: AppStatePlacement.card,
                )
              : _PeriodBody(
                  period: period,
                  metricLabel: l.dietCalories,
                  unit: l.unitKcal,
                  goal: _goal.toDouble(),
                  ticks: _ticks,
                  values: <double>[
                    for (final DietPeriodDay d in period.days)
                      d.calories.toDouble(),
                  ],
                  dates: <DateTime>[
                    for (final DietPeriodDay d in period.days) d.date,
                  ],
                  // 칼로리 막대는 탄단지로 쌓아 그린다.
                  days: period.days,
                  format: _number,
                  weekly: widget.weekly,
                  selection: _selection,
                ),
        ),
      ],
    );
  }
}

class _PeriodBody extends StatelessWidget {
  const _PeriodBody({
    required this.period,
    required this.metricLabel,
    required this.unit,
    required this.goal,
    required this.ticks,
    required this.values,
    required this.dates,
    required this.format,
    required this.weekly,
    required this.selection,
    this.days,
  });

  final DietPeriod period;
  final String metricLabel;
  final String unit;
  final double goal;

  /// 이번 주 꺾은선의 세로 축을 잡는 값들. 홈과 같은 눈금이라 두 화면이 같은
  /// 기준으로 읽힌다. 전체(막대)는 쓰지 않는다.
  final List<double> ticks;

  final List<double> values;
  final List<DateTime> dates;
  final String Function(num) format;

  /// 칼로리 막대를 탄단지로 쌓기 위한 원본.
  final List<DietPeriodDay>? days;

  /// 이번 주면 일곱 칸 한 화면, 전체면 옆으로 미는 막대.
  final bool weekly;

  /// 그래프의 스크롤·선택 상태. 머리의 숫자가 이걸 보고 평균과 하루 값을
  /// 오간다. (#1018)
  final PeriodChartSelection selection;

  /// 고른 날의 머리 문구 — `8. 17.` 처럼 월·일만 적는다.
  ///
  /// 날을 고르면 사라지는 날짜 기간(`8. 17. ~ 8. 23.`, [periodRangeText])과
  /// 같은 형식이다. 연도를 붙이면 같은 카드 안에서 날짜 말투가 둘로 갈린다.
  /// 기간이 1년이 안 돼 월·일만으로 가리키는 날이 하나뿐이다.
  String _dayHeadline(BuildContext context, DateTime date) =>
      DateFormat.Md(Localizations.localeOf(context).toString()).format(date);

  /// 카드 머리 위에 적을 날짜 기간의 양끝.
  ///
  /// `전체` 는 열두 주가 한 화면에 들어가지 않아 옆으로 밀어 본다 — 그때 적어야
  /// 할 것은 기간 전체가 아니라 **지금 보이는 막대의 구간**이다. 바로 아래의
  /// `하루 평균` 이 이미 보이는 구간만 세므로(#1018), 날짜만 12주에 머물면 한
  /// 카드의 두 글이 서로 다른 기간을 말한다(#1985).
  ///
  /// `이번 주` 는 일곱 칸이 한 화면에 다 들어가 밀리지 않으므로 늘 월~일이다.
  /// 보이는 구간을 아직 모르는 첫 프레임도 기간 전체를 적는다 — 날짜 줄이
  /// 비었다 채워지며 깜빡이지 않게. 그래프가 자리를 잡으면 곧 따라온다.
  (DateTime, DateTime) _shownRange() {
    final (int, int)? visible = selection.visible;
    if (weekly || visible == null) return (dates.first, dates.last);
    final int from = visible.$1.clamp(0, dates.length - 1);
    final int to = visible.$2.clamp(from, dates.length - 1);
    return (dates[from], dates[to]);
  }

  /// 머리 숫자 옆에 붙일 탄단지. [picked] 이 있으면 그날 값, 없으면 기록이
  /// 있는 날의 하루 평균이다. 서버가 영양을 주지 않은 기간이면 null 이라
  /// 아무것도 붙지 않는다.
  _Macros? _macrosFor(int? picked) {
    final List<DietPeriodDay>? all = days;
    if (all == null) return null;
    if (picked != null) {
      final DietPeriodDay d = all[picked];
      return d.hasMacros
          ? _Macros(carbs: d.carbsG, protein: d.proteinG, fat: d.fatG)
          : null;
    }
    final List<DietPeriodDay> logged = all
        .where((DietPeriodDay d) => d.hasMacros)
        .toList();
    if (logged.isEmpty) return null;
    double avg(double Function(DietPeriodDay) of) =>
        logged.fold<double>(0, (double a, DietPeriodDay d) => a + of(d)) /
        logged.length;
    return _Macros(
      carbs: avg((DietPeriodDay d) => d.carbsG),
      protein: avg((DietPeriodDay d) => d.proteinG),
      fat: avg((DietPeriodDay d) => d.fatG),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 카드의 빈 곳을 누르면 고른 날이 풀려 다시 하루 평균이 뜬다 (#1123).
    // 막대는 자기 탭을 먼저 받으므로 이 손짓은 그 밖의 자리에만 닿는다.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => selection.select(null),
      // 오늘 카드와 같은 높이 (#1124) — 기간 토글을 눌러도 카드가 커졌다
      // 작아지지 않는다.
      child: ConstrainedBox(
        key: const Key('diet-period-card'),
        constraints: const BoxConstraints(
          minWidth: double.infinity,
          minHeight: kDietSummaryCardHeight,
        ),
        child: AppCard(
          child: Column(
            key: const Key('diet-period-card-content'),
            crossAxisAlignment: CrossAxisAlignment.start,
            // 내용은 오늘 카드보다 짧다(머리 숫자 + 그래프뿐이다). 위에서부터
            // 채우면 남는 자리가 전부 카드 아래로 몰려 그래프가 위로 쏠려
            // 보였다 — 남는 자리를 위아래로 나눠 가운데에 놓는다(#1956).
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 머리줄은 **날을 고르든 말든 같은 높이**를 쓴다 — 운동 탭 `전체` 와
              // 같다(#1194). 고르면 날짜 기간이 빠지고 회색 바탕의 여백이 붙어,
              // 두 상태의 높이가 몇 dp 씩 어긋났다(72 ↔ 67~71). 카드 내용이
              // 가운데 정렬이라 그 차이의 절반만큼 그래프가 위아래로 튀었다.
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      _kHeadlineMinHeight *
                      MediaQuery.textScalerOf(context).scale(1),
                ),
                child: ListenableBuilder(
                  listenable: selection,
                  builder: (BuildContext context, Widget? _) {
                    // 점을 골라 그날 값을 볼 수 있다 (#1122). 평소에는 **보이는
                    // 구간의** 평균, 날을 고르면 그날의 값. (#1018)
                    final int? picked = selection.selected;
                    final double value = picked == null
                        ? selection.averageOf(values)
                        : values[picked];
                    final bool over = goal > 0 && value > goal;
                    // 칼로리를 볼 때만 탄단지를 곁들인다. (#1121)
                    final _Macros? macros = _macrosFor(picked);
                    final (DateTime from, DateTime to) = _shownRange();
                    return PeriodChartHeadline(
                      selected: picked != null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  // 지표가 칼로리 하나뿐이라(#1986) `· 칼로리` 를 붙이지 않는다 —
                                  // 칼로리·나트륨 칩이 있던 시절 둘을 가르던 말이라 지금은 바로
                                  // 아래 숫자의 `kcal` 과 겹친다.
                                  picked == null
                                      ? l.dietPeriodAverage
                                      : _dayHeadline(context, dates[picked]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens
                                      .text(
                                        OnCareTypography.strong(
                                          OnCareTypography.caption,
                                        ),
                                      )
                                      .copyWith(
                                        color: OnCareColors.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: OnCareSpacing.s4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text.rich(
                                    TextSpan(
                                      children: <InlineSpan>[
                                        TextSpan(
                                          text: format(value),
                                          style:
                                              OnCareTypography.numeric(
                                                tokens.text(
                                                  OnCareTypography.display,
                                                ),
                                              ).copyWith(
                                                color: over
                                                    ? OnCareColors.danger
                                                    : OnCareColors.textPrimary,
                                              ),
                                        ),
                                        TextSpan(
                                          text: ' / ${format(goal)} $unit',
                                          style: tokens
                                              .text(OnCareTypography.bodySmall)
                                              .copyWith(
                                                color:
                                                    OnCareColors.textSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: OnCareSpacing.s12),
                          // 오른쪽 칸 — 맨 위가 날짜 기간, 그 아래가 탄단지다
                          // (#2009). 날짜에 제 줄을 따로 주면 그 줄 왼쪽이 통째로
                          // 비어 카드 한 줄을 버린다. 탄단지 위에 얹으면 빈 줄
                          // 없이 운동 탭처럼 **카드 오른쪽 위**에 놓인다.
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // 날을 고르면 날짜 기간은 빠진다 — 운동 탭 `전체`
                              // 와 같다. 머리 문구가 이미 `9. 17.`
                              // 로 그날을 말하므로, 보이는 구간까지 함께 적으면
                              // 한 카드에 날짜가 둘 떠 서로 다른 말을 한다.
                              //
                              // 빠진 자리는 회색 바탕([PeriodChartHeadline])의
                              // 위아래 여백이 메운다. 둘이 거의 같은 높이라, 날을
                              // 고르고 풀 때 카드가 커졌다 작아지며 그래프가
                              // 밀리던 것도 함께 잦아든다.
                              if (picked == null) ...<Widget>[
                                // 형식은 운동과 같은 함수로 적는다 — 두 탭이
                                // 서로 다른 말투로 말하지 않도록.
                                PeriodRangeLabel(
                                  key: const Key('diet-period-range'),
                                  text: periodRangeText(
                                    Localizations.localeOf(context).toString(),
                                    from,
                                    to,
                                  ),
                                ),
                                if (macros != null)
                                  const SizedBox(height: OnCareSpacing.s4),
                              ],
                              if (macros != null)
                                _MacroDetail(macros: macros, muted: weekly),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 기간 합계는 뺐다 (#1121). 머리와 그래프 사이의 구분선도 뺐다
              // (#1123) — 그 빈 칸을 그래프가 들고 있어(topGap) 고른 막대의
              // 세로선이 머리 카드까지 닿는다.
              if (weekly) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s12),
                _WeekTrend(
                  values: values,
                  dates: dates,
                  goal: goal,
                  ticks: ticks,
                  metricLabel: metricLabel,
                  unit: unit,
                  format: format,
                  selection: selection,
                ),
              ] else
                _PeriodBars(
                  values: values,
                  dates: dates,
                  goal: goal,
                  color: tokens.brand.dietChart,
                  weekly: weekly,
                  // 막대 툴팁이 "무슨 값을 얼마나" 라고 말하려면 지표 이름·단위와
                  // 숫자 서식이 카드 머리 숫자와 같아야 한다.
                  metricLabel: metricLabel,
                  unit: unit,
                  format: format,
                  selection: selection,
                  days: days,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 이번 주의 꺾은선 — 홈 식단·영양 카드와 **같은 위젯**이다(#1879).
///
/// 같은 한 주를 홈은 꺾은선, 식단 탭은 막대로 그리고 있었다. 둘을 견주려면 본
/// 것을 머릿속에서 다시 맞춰야 해서 한 그림으로 되돌린다. 점을 눌러 그날 값을
/// 보는 것(#1122)은 그대로다 — 카드 머리 숫자가 [selection] 을 같이 본다.
class _WeekTrend extends StatelessWidget {
  const _WeekTrend({
    required this.values,
    required this.dates,
    required this.goal,
    required this.ticks,
    required this.metricLabel,
    required this.unit,
    required this.format,
    required this.selection,
  });

  final List<double> values;
  final List<DateTime> dates;
  final double goal;
  final List<double> ticks;
  final String metricLabel;
  final String unit;
  final String Function(num) format;
  final PeriodChartSelection selection;

  /// 오늘·이번 주·전체 카드 높이를 같게 두면서(#1124) 남는 자리를 그래프가
  /// 쓴다 — 카드 높이에서 그래프가 아닌 것들(카드 안쪽 여백 32, 머리 숫자
  /// 한 덩어리, 그 아래 간격, 요일 라벨 줄)이 쓰는 자리를 뺀 나머지다.
  ///
  /// **고정값으로 두지 않는다**(#1956). 105 로 박아 둔 사이 카드 높이만
  /// 240 → 248 → 284 로 올라(#1699, #1879) 그 차이가 전부 카드 아래 빈 칸으로
  /// 남았다. 빼는 값은 실제로 재서 얻었고, 글자 지표가 조금 달라도 카드가
  /// 늘어나지 않도록 몇 dp 여유를 남긴다 — 남는 자리는 카드의 가운데 정렬이
  /// 위아래로 나눈다.
  static const double _chartHeight =
      kDietSummaryCardHeight - 128 - _kHeadlineRangeExtent;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> weekdays = _weekdayLabels(l);
    final List<String> days = <String>[
      for (final DateTime d in dates) weekdays[d.weekday - 1],
    ];
    final int today = _todayIndexIn(dates);
    return ListenableBuilder(
      listenable: selection,
      builder: (BuildContext context, Widget? _) => MetricTrendChart(
        values: values,
        dayLabels: days,
        goal: goal,
        ticks: ticks,
        selectedIndex: selection.selected,
        onSelected: selection.select,
        // 선은 오늘까지만 잇는다. 오늘이 이 범위 밖이면(지난 주를 보고 있으면)
        // 마지막 칸까지 전부 그린다.
        todayIndex: today,
        // 그래프가 칼로리 하나라 되감을 일이 없다 — 처음 한 번만 자란다.
        replayKey: metricLabel,
        // 카드 머리의 `하루 평균 · 탄수화물` 과 같은 지표 이름으로 시작한다.
        semanticsLabel: chartSemanticsLabel(
          l,
          title: metricLabel,
          points: chartSeriesPoints(
            l,
            values: values,
            dayLabels: days,
            format: (double v) => '${format(v)} $unit',
            upTo: today,
          ),
        ),
        goalLabel: '${l.homeGoal}\n${format(goal)}',
        formatTick: format,
        height: _chartHeight,
      ),
    );
  }
}

/// 오늘이 이 범위의 몇 번째 칸인가. 범위 밖이면 마지막 칸 — 지난 주를 보고
/// 있을 때 선이 중간에서 끊기지 않게 한다.
int _todayIndexIn(List<DateTime> dates) {
  final DateTime today = DateUtils.dateOnly(nowKst());
  for (int i = 0; i < dates.length; i++) {
    if (DateUtils.dateOnly(dates[i]) == today) return i;
  }
  return dates.length - 1;
}

/// 머리 숫자 옆의 탄단지 한 덩어리. 막대를 쌓은 색을 그대로 써서, 예전 그래프
/// 아래 범례가 하던 말(어느 색이 무엇인지)까지 여기서 함께 한다. (#1121)
class _Macros {
  const _Macros({
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  final double carbs;
  final double protein;
  final double fat;
}

class _MacroDetail extends StatelessWidget {
  const _MacroDetail({required this.macros, required this.muted});

  final _Macros macros;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    Color tone(Color color) => muted ? OnCareColors.textSecondary : color;
    final List<(String, double, Color)> rows = <(String, double, Color)>[
      (l.homeMacroCarbs, macros.carbs, tone(tokens.brand.macroCarbs)),
      (l.homeMacroProtein, macros.protein, tone(tokens.brand.macroProtein)),
      (l.homeMacroFat, macros.fat, tone(tokens.brand.macroFat)),
    ];
    final TextStyle base = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    return Column(
      key: const Key('diet-period-macros'),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (String label, double value, Color color) in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, maxLines: 1, style: base.copyWith(color: color)),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                _macroGrams(value),
                maxLines: 1,
                style: OnCareTypography.numeric(
                  base,
                ).copyWith(color: OnCareColors.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}

/// `204g` — 소수점은 버린다. 옆의 머리 숫자가 주인공이고 이 줄은 곁들이다.
String _macroGrams(double v) => '${v.round()}g';

/// 요일 라벨(월~일). 이번 주 그래프의 축에 적는다.
List<String> _weekdayLabels(AppLocalizations l) => <String>[
  l.dietWeekdayMon,
  l.dietWeekdayTue,
  l.dietWeekdayWed,
  l.dietWeekdayThu,
  l.dietWeekdayFri,
  l.dietWeekdaySat,
  l.dietWeekdaySun,
];

/// 일별 막대. 목표선을 얇은 점선으로 얹어 그날이 목표를 넘었는지 한눈에 보이게
/// 하고, 목표를 넘은 날만 경고색으로 칠한다.
class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.values,
    required this.dates,
    required this.goal,
    required this.color,
    required this.weekly,
    required this.metricLabel,
    required this.unit,
    required this.format,
    required this.selection,
    this.days,
  });

  final List<double> values;
  final List<DateTime> dates;
  final double goal;

  /// 스크롤 위치와 고른 날. 카드 머리의 숫자가 같은 상태를 본다. (#1018)
  final PeriodChartSelection selection;

  /// 영양 정보가 없는 날의 칼로리 막대 색.
  final Color color;

  /// 이번 주면 일곱 칸을 한 화면에 요일 라벨로 적는다.
  final bool weekly;

  /// 칼로리를 볼 때의 원본. 막대의 탄단지 구간과 툴팁에 사용한다.
  final List<DietPeriodDay>? days;

  /// 툴팁이 부를 지표 이름(칼로리·나트륨·당류)과 단위, 그리고 카드 머리 숫자와
  /// 같은 숫자 서식.
  final String metricLabel;
  final String unit;
  final String Function(num) format;

  /// 카드 높이를 오늘과 같게 맞추기 위한 그래프 높이다 (#1124). 꺾은선과 같은
  /// 규칙으로 카드 높이에서 나머지가 쓰는 자리를 뺀다 — 고정값 108 은 카드가
  /// 240 이던 시절 값이라 그 뒤 늘어난 만큼이 카드 아래 빈 칸이 됐다(#1956).
  /// 막대 쪽이 4dp 더 높은 것은 날짜 라벨 줄이 요일 라벨보다 낮아서다.
  static const double _chartHeight =
      kDietSummaryCardHeight - 124 - _kHeadlineRangeExtent;

  /// [i] 번째 칸의 원본. 칼로리를 보고 있지 않으면 null 이다.
  DietPeriodDay? _dayAt(int i) {
    final List<DietPeriodDay>? source = days;
    if (source == null || i >= source.length) return null;
    return source[i];
  }

  /// 아직 오지 않은 날인가. (#950)
  ///
  /// 기록하지 않은 것이 아니라 **기록할 수 없는** 날이다. 둘을 같은 말로 그리면
  /// 한 달을 훑으며 "며칠을 빠뜨렸나" 를 셀 때 미래의 빈 칸까지 빠뜨린 날처럼
  /// 읽힌다.
  bool _isPending(int i) =>
      DateUtils.dateOnly(dates[i]).isAfter(DateUtils.dateOnly(nowKst()));

  /// 툴팁과 **같은 내용**을 한 줄짜리 시맨틱 라벨로. 색 견본(`WidgetSpan`)은
  /// 빼고 줄바꿈은 쉼표로 바꾼다 — 음성 안내는 줄을 나누어 읽지 않는다.
  String _tipText(
    BuildContext context,
    AppLocalizations l,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) => TextSpan(children: _tipSpans(context, l, dayFormat, i, hasGoal))
      .toPlainText(includePlaceholders: false)
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .join(', ');

  WidgetSpan _swatch(Color color) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.only(right: OnCareSpacing.s4),
      child: AppChartSwatch(color: color),
    ),
  );

  /// 한 막대의 툴팁 내용 — 운동 탭 `운동 현황` 툴팁과 같은 구조다.
  /// `[색 견본] 지표  값 단위` 한 줄, 목표를 넘긴 날은 초과분을 한 줄 더.
  List<InlineSpan> _tipSpans(
    BuildContext context,
    AppLocalizations l,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) {
    final OnCareTokens tokens = context.oncare;
    final double value = values[i];
    final bool over = hasGoal && value > goal;
    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(
        text: '${dayFormat.format(dates[i])}\n',
        style: const TextStyle(color: OnCareColors.textSecondary),
      ),
    ];
    // 아직 오지 않은 날과 지나갔는데 비운 날은 다른 말이다(#950).
    if (_isPending(i)) {
      spans.add(TextSpan(text: l.dietPeriodNotYet));
      return spans;
    }
    // 기록이 없는 날은 0 이 아니라 '기록 없음' 이다.
    if (value <= 0) {
      spans.add(TextSpan(text: l.dietPeriodNoRecord));
      return spans;
    }
    // 막대와 같은 색이어야 툴팁의 첫 줄이 그 막대를 가리킨다.
    spans.add(_swatch(over ? OnCareColors.danger : color));
    spans.add(TextSpan(text: '$metricLabel   ${format(value)} $unit'));
    // 칼로리 뒤에는 그 칼로리가 어디서 왔는지를 적는다.
    final DietPeriodDay? day = _dayAt(i);
    if (day != null && day.hasMacros) {
      for (final ({Color color, String label, double grams}) m
          in <({Color color, String label, double grams})>[
            (
              color: tokens.brand.macroCarbs,
              label: l.homeMacroCarbs,
              grams: day.carbsG,
            ),
            (
              color: tokens.brand.macroProtein,
              label: l.homeMacroProtein,
              grams: day.proteinG,
            ),
            (
              color: tokens.brand.macroFat,
              label: l.homeMacroFat,
              grams: day.fatG,
            ),
          ]) {
        spans.add(const TextSpan(text: '\n'));
        spans.add(_swatch(m.color));
        spans.add(
          TextSpan(text: '${m.label}   ${format(m.grams)} ${l.dietUnitG}'),
        );
      }
    }
    // 막대가 왜 빨간지를 색이 아니라 글로도 말한다.
    if (over) {
      spans.add(
        TextSpan(
          text: '\n${l.dietPeriodOverGoal(format(value - goal), unit)}',
          style: const TextStyle(color: OnCareColors.danger),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // `8월 12일 (화)` / `Tue, Aug 12` — 어느 막대가 며칠인지 x축 라벨만으로는
    // 짚을 수 없다(달은 6칸에 하나만 적는다).
    final DateFormat dayFormat = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    );
    // 축 위쪽에 여유를 둔다. 목표를 넘은 날이 없으면 목표가 곧 최댓값이 되어
    // 목표선이 차트 맨 위(=바깥)에 놓여 잘려 보이지 않았다.
    final double peak = <double>[
      goal,
      ...values,
    ].fold<double>(1, (double a, double b) => b > a ? b : a);
    final double maxValue = peak * 1.15;
    // 목표가 0이면 초과 판정을 하지 않는다 — 카드 위쪽 숫자도 같은 규칙이다.
    final bool hasGoal = goal > 0;
    // 달(30칸)에서도 라벨이 겹치지 않도록 몇 칸에 하나만 적는다.
    final int labelStep = values.length > 10 ? (values.length / 6).ceil() : 1;
    final List<String> weekdays = _weekdayLabels(l);
    // 기록이 하나도 없는 기간은 막대마다 `기록 없음` 을 읽히는 대신 비어 있다고
    // 한 번만 말한다(#972).
    final bool empty = values.every((double v) => v <= 0);

    return Semantics(
      container: true,
      label: empty
          ? chartSemanticsLabel(l, title: metricLabel, points: const <String>[])
          : null,
      child: ExcludeSemantics(
        excluding: empty,
        child: ListenableBuilder(
          listenable: selection,
          builder: (BuildContext context, Widget? _) => PeriodScrollChart(
            count: values.length,
            height: _chartHeight,
            // 이번 주는 일곱 칸이 한 화면이라 밀리지 않는다.
            daysPerScreen: weekly ? values.length : _kAllDaysPerScreen,
            boldSelectedLabel: weekly,
            selectedIndex: selection.selected,
            onSelected: selection.select,
            onVisibleRangeChanged: selection.setVisible,
            // 목표선은 스크롤 안쪽에 얹혀 밀어도 막대와 같은 높이를 따라가고
            // (#1015), 목표치는 왼쪽 칸에 두 줄로 적힌다 (#1071).
            goalBottom: hasGoal
                ? _chartHeight * (goal / maxValue).clamp(0.0, 1.0)
                : null,
            goalLabel: '${l.homeGoal}\n${format(goal)}',
            // 머리 카드와 막대 사이의 빈 칸 — 고른 날의 세로선이 여기까지
            // 올라와 회색 카드에 닿는다 (#1123).
            topGap: OnCareSpacing.s12,
            // 되감을 일이 없다 — 처음 한 번만 바닥에서 자란다 (#1148).
            revealKey: metricLabel,
            // 이번 주는 요일, 전체는 달을 함께 적은 날짜다 (#1123).
            labelBuilder: (int i) => weekly
                ? weekdays[dates[i].weekday - 1]
                : i % labelStep == 0
                ? '${dates[i].month}/${dates[i].day}'
                : '',
            // 막대 사이를 띄운다 — 붙어 있으면 하루하루가 한 덩어리로 읽힌다.
            // 그 자리는 [_kAllDaysPerScreen] 이 내주므로 막대는 얇아지지 않는다.
            barBuilder: (BuildContext context, int i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s2),
              child: Semantics(
                label: _tipText(context, l, dayFormat, i, hasGoal),
                child: Tooltip(
                  key: Key('diet-period-bar-tip-$i'),
                  // 모양은 패키지 차트 툴팁 한 가지다(#1697). Material 툴팁은
                  // 띄우는 시점·위치만 맡고 바탕은 비워 둔다.
                  richMessage: WidgetSpan(
                    child: AppChartTooltip(
                      child: Text.rich(
                        TextSpan(
                          children: _tipSpans(
                            context,
                            l,
                            dayFormat,
                            i,
                            hasGoal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  decoration: const BoxDecoration(),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _Bar(
                      key: Key('diet-period-bar-$i'),
                      height:
                          _chartHeight * (values[i] / maxValue).clamp(0.0, 1.0),
                      pending: _isPending(i),
                      // 목표를 넘긴 날만 빨강이다. 칼로리는 탄단지 원본이 있으면
                      // 누적 구간, 나트륨·당류는 브랜드 색 한 칸이다.
                      over: hasGoal && values[i] > goal,
                      color: color,
                      day: _dayAt(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 칸의 막대. 탄단지가 있으면 아래에서부터 탄·단·지 순으로 쌓는다.
class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.height,
    required this.day,
    required this.over,
    required this.color,
    this.pending = false,
  });

  final double height;
  final DietPeriodDay? day;

  /// 아직 오지 않은 날인가. 빈 트랙 한 줄로만 그린다(#754, #950).
  final bool pending;

  /// 목표를 넘긴 날인가. 넘긴 날은 통째로 빨강으로 표시한다.
  final bool over;

  /// 탄단지 원본이 없을 때 사용하는 지표 색.
  final Color color;

  static const BorderRadius _radius = BorderRadius.vertical(
    top: OnCareRadius.xs,
  );

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final DietPeriodDay? d = day;
    if (pending) {
      // "대기" 표시는 한 가지 — 진한 선 4px 이다(#1697).
      return Container(
        height: OnCareSize.stepBar,
        decoration: const BoxDecoration(
          color: OnCareColors.lineStrong,
          borderRadius: _radius,
        ),
      );
    }
    if (over || d == null || !d.hasMacros) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: over ? OnCareColors.danger : color,
          borderRadius: _radius,
        ),
      );
    }
    final double total = d.carbsKcal + d.proteinKcal + d.fatKcal;
    if (total <= 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(color: color, borderRadius: _radius),
      );
    }
    // 총높이는 기록 칼로리를 따르되, 설명되지 않는 열량은 나머지 구간으로 둔다.
    // 탄단지 환산 열량이 더 크면 음수 나머지를 만들지 않고 그 합계를 기준으로 한다.
    final double basis = math.max(d.calories.toDouble(), total);
    final double rest = basis - total;
    final List<({Color color, double kcal})>
    parts = <({Color color, double kcal})>[
      if (rest / basis > 0.01) (color: OnCareColors.surfaceInput, kcal: rest),
      if (d.fatKcal > 0) (color: tokens.brand.macroFat, kcal: d.fatKcal),
      if (d.proteinKcal > 0)
        (color: tokens.brand.macroProtein, kcal: d.proteinKcal),
      if (d.carbsKcal > 0) (color: tokens.brand.macroCarbs, kcal: d.carbsKcal),
    ];
    return ClipRRect(
      borderRadius: _radius,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final ({Color color, double kcal}) part in parts)
              Expanded(
                flex: math.max(1, (part.kcal / basis * 1000).round()),
                child: ColoredBox(color: part.color),
              ),
          ],
        ),
      ),
    );
  }
}
