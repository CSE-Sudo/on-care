import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
// 패키지에 대응이 없는 차트 예외(#1704): 주간 꺾은선과 음성 안내 문자열.
import 'package:oncare_trainer/shared/widgets/chart_semantics.dart';
import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart'
    show MetricTrendChart;
import 'package:oncare_trainer/shared/widgets/period_range_label.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 고객의 기간 영양 추이 — 회원 앱 식단 탭 기간 뷰와 **같은 것**을 트레이너에게.
/// (#914)
///
/// 머리 숫자를 합계가 아니라 **하루 평균**으로 두는 이유는 주(7일)와 달(30일)의
/// 길이가 달라 합계끼리는 견줄 수 없기 때문이다. 평균은 기록이 있는 날만으로
/// 나눈다 — 아직 오지 않은 날까지 나누면 달 초에는 늘 낮게 나온다.
///
/// 두 기간 모두 **칼로리** 하나를 본다(#2156). 회원 앱이 나트륨·당류를 그래프에서
/// 내리며(#1986) 지표 칩 줄을 걷어냈는데, 트레이너 화면에만 `칼로리·나트륨·당류`
/// 칩이 남아 회원이 볼 수 없는 그래프를 트레이너만 보고 있었다. 탄단지는 고르는
/// 지표가 아니라 머리 숫자 옆의 세 줄과 막대의 누적 구간으로 나타난다.
///
/// 목표선은 **회원의 목표**다([memberHealthProfileProvider]). 회원 앱은 MY 에서
/// 정한 하루 칼로리를 목표선으로 긋는다 — 상수 2,000 을 쓰면 목표를 1,800 으로 둔
/// 회원의 초과한 날이 트레이너 화면에서만 안쪽으로 읽힌다.
class ClientDietPeriodCard extends ConsumerStatefulWidget {
  /// Creates the period chart for [clientId] over [period].
  const ClientDietPeriodCard({
    super.key,
    required this.clientId,
    required this.period,
  });

  final String clientId;

  /// `오늘` 은 이 카드가 아니라 영양 요약 카드가 맡는다.
  final ClientPeriod period;

  @override
  ConsumerState<ClientDietPeriodCard> createState() =>
      _ClientDietPeriodCardState();
}

/// 머리줄(숫자 + 오른쪽 칸)이 늘 차지하는 최소 높이 — 회원 앱과 같은 값이다
/// (회원 앱 #2009). 날을 고르지 않았을 때(날짜 기간 + 탄단지)와 고른 뒤(회색
/// 바탕 + 탄단지)의 높이가 몇 dp 씩 어긋나, 고르고 풀 때마다 그래프가 위아래로
/// 튀었다. 큰 쪽에 맞춰 두 상태가 같은 자리를 쓴다. 글자 배율을 따라 커진다.
const double _headlineMinHeight = 72;

/// 머리줄 오른쪽 칸 맨 위에 날짜 기간이 얹히며 머리줄이 키가 커진 만큼 (회원 앱
/// #2009). 그만큼 그래프가 자리를 내준다 — 그러지 않으면 기간 카드만 키가 커져
/// 토글을 누를 때 아래 내용이 뛴다.
const double _headlineRangeExtent = 16;

/// 이번 주 꺾은선 높이. 카드 높이([kClientNutritionCardHeight])에서 그래프가
/// 아닌 것들(카드 안쪽 여백·머리줄·간격·요일 라벨 줄)이 쓰는 자리를 뺀 나머지다
/// — 회원 앱과 같은 식이다(회원 앱 #1956). 고정값으로 두면 카드 높이만 바뀌고
/// 그 차이가 카드 아래 빈 칸으로 남는다.
const double _trendChartHeight =
    kClientNutritionCardHeight - 128 - _headlineRangeExtent;

/// `전체` 막대 그래프 높이. 꺾은선과 같은 규칙이고, 날짜 라벨 줄이 요일 라벨보다
/// 낮아 4 더 높다(회원 앱과 같다).
const double _barChartHeight =
    kClientNutritionCardHeight - 124 - _headlineRangeExtent;

/// `전체` 그래프가 한 화면에 보여주는 날 수 — 회원 앱 `_kAllDaysPerScreen` 과
/// 같은 값이다(#2156). 카드 머리의 `하루 평균` 은 지금 보이는 구간만 세므로
/// (#1018), 칸 수가 다르면 같은 회원의 같은 기록이 두 앱에서 다른 구간의 평균이
/// 된다.
const int _allDaysPerScreen = 24;

/// 꺾은선의 세로 눈금. **회원 앱과 같은 값**이라 회원이 보는 그래프와 트레이너가
/// 보는 그래프의 눈금이 어긋나지 않는다.
const List<double> _calorieTicks = <double>[0, 1500, 2500];

class _ClientDietPeriodCardState extends ConsumerState<ClientDietPeriodCard> {
  /// 그래프의 스크롤 위치와 고른 날. (#1018)
  final PeriodChartSelection _selection = PeriodChartSelection();

  @override
  void didUpdateWidget(ClientDietPeriodCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 기간 토글을 눌러도 이 위젯은 트리의 같은 자리에 남아 `State` 가 재사용된다
    // — 고른 **인덱스**와 보이는 구간이 다음 기간의 배열에 그대로 쓰인다. `전체`
    // (84칸)에서 고른 칸이 `이번 주`(7칸)로 넘어오면 범위를 벗어난다. 배열이
    // 바뀌면 둘을 함께 푼다. (회원 앱 #1984)
    if (widget.period != oldWidget.period ||
        widget.clientId != oldWidget.clientId) {
      _selection.reset(includeVisible: true);
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 키에 오늘 날짜가 들어간다 — 자정을 넘기면 다음 rebuild 가 새 범위를 묻는다.
    final ClientPeriodKey key = clientPeriodKeyNow(
      widget.clientId,
      widget.period,
    );
    final AsyncValue<ClientDietPeriod> async = ref.watch(
      clientDietPeriodProvider(key),
    );
    // 목표는 회원 프로필에서 읽는다. 읽는 중이거나 실패하면 회원 앱 기본값으로
    // 그린다 — 목표 하나 때문에 그래프 전체가 로딩·오류에 막히지 않게.
    final MemberHealthProfile? profile = ref
        .watch(memberHealthProfileProvider(widget.clientId))
        .valueOrNull;
    final double goal = clientDietGoalsOf(profile).calories.toDouble();
    // 제목·아이콘·기간 토글은 바깥 `ClientPeriodSection` 이 든다(#944). 날짜
    // 기간은 **카드 안** 오른쪽 위다(회원 앱 #2009) — 카드가 제 기간을 스스로
    // 말한다.
    return _Card(
      child: async.when(
        loading: () => const AppLoading(placement: AppStatePlacement.card),
        error: (Object e, StackTrace _) => AppErrorState(
          title: l.dietLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(clientDietPeriodProvider(key)),
          placement: AppStatePlacement.card,
        ),
        data: (ClientDietPeriod period) => period.isEmpty
            ? AppEmptyState(
                title: l.clientPeriodEmpty,
                icon: Icons.restaurant_rounded,
                placement: AppStatePlacement.card,
              )
            : _Body(
                selection: _selection,
                label: l.metricCalories,
                unit: 'kcal',
                goal: goal,
                values: <double>[
                  for (final ClientDietDay d in period.days)
                    d.calories.toDouble(),
                ],
                logged: <bool>[
                  for (final ClientDietDay d in period.days) d.logged,
                ],
                dates: <DateTime>[
                  for (final ClientDietDay d in period.days) d.date,
                ],
                // 칼로리 막대는 탄단지로 쌓아 그린다.
                days: period.days,
                weekly: widget.period == ClientPeriod.week,
                ticks: _calorieTicks,
                // 영양 요약 카드와 **같은 서식**을 쓴다. 두 카드가 같은
                // 화면에 나란히 놓이므로 표기가 갈리면 바로 드러난다.
                format: formatNumber,
              ),
      ),
    );
  }
}

/// 제목 없는 흰 판 — 영양 요약 카드·운동 카드와 같은 모양이다.
///
/// 높이는 `오늘` 카드와 같은 [kClientNutritionCardHeight] 를 바닥으로 둔다
/// (#1167) — 기간 토글을 눌렀을 때 카드가 커졌다 작아지면 그 아래 날짜별 기록이
/// 그때마다 뛴다. 최소 높이라 글자 배율이 커지면 함께 커진다.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    key: const ValueKey<String>('client-diet-period-card'),
    constraints: const BoxConstraints(
      minWidth: double.infinity,
      minHeight: kClientNutritionCardHeight,
    ),
    child: AppCard(child: child),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.label,
    required this.unit,
    required this.goal,
    required this.values,
    required this.logged,
    required this.dates,
    required this.format,
    required this.weekly,
    required this.ticks,
    required this.selection,
    required this.days,
  });

  final String label;
  final String unit;
  final double goal;
  final List<double> values;
  final List<bool> logged;
  final List<DateTime> dates;
  final String Function(num) format;

  /// 탄단지가 있는 날은 막대를 셋으로 쌓는다.
  final List<ClientDietDay> days;

  /// 이번 주인가. 회원 앱과 같이 **주는 꺾은선, 전체는 막대**다 — 여든네 칸을
  /// 꺾은선으로 그리면 점과 값이 서로 겹친다.
  final bool weekly;

  /// 꺾은선의 세로 눈금. 회원 앱 홈·식단 탭과 같은 값이라 두 화면의 눈금이
  /// 어긋나지 않는다.
  final List<double> ticks;

  /// 그래프의 스크롤·선택 상태. 머리의 숫자가 이걸 보고 평균과 하루 값을
  /// 오간다. (#1018)
  final PeriodChartSelection selection;

  /// 카드 머리 위에 적을 날짜 기간의 양끝 — 회원 앱과 같은 규칙이다(#2009).
  ///
  /// `전체` 는 옆으로 밀어 보므로, 적어야 할 것은 기간 전체가 아니라 **지금
  /// 보이는 막대의 구간**이다. 바로 아래의 `하루 평균` 이 보이는 구간만 센다
  /// (회원 앱 #1985). 보이는 구간을 아직 모르는 첫 프레임은 기간 전체를 적는다.
  (DateTime, DateTime) _shownRange() {
    final (int, int)? visible = selection.visible;
    if (weekly || visible == null) return (dates.first, dates.last);
    final int from = visible.$1.clamp(0, dates.length - 1);
    final int to = visible.$2.clamp(from, dates.length - 1);
    return (dates[from], dates[to]);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String locale = Localizations.localeOf(context).toString();
    // 카드의 빈 곳을 누르면 고른 날이 풀려 다시 하루 평균이 뜬다 (회원 앱
    // #1123). 막대·점은 자기 탭을 먼저 받으므로 이 손짓은 그 밖의 자리에만
    // 닿는다.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => selection.select(null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // 남는 자리를 위아래로 나눠 가운데에 놓는다(회원 앱 #1956).
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 머리줄은 **날을 고르든 말든 같은 높이**를 쓴다(회원 앱 #1194).
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  _headlineMinHeight *
                  MediaQuery.textScalerOf(context).scale(1),
            ),
            child: ListenableBuilder(
              listenable: selection,
              builder: (BuildContext context, Widget? _) {
                // 평소에는 **보이는 구간의** 평균, 날을 고르면 그날의 값.
                // 이번 주도 점을 골라 그날 값을 볼 수 있다 (회원 앱 #1122).
                final int? picked = selection.selected;
                final double value = picked == null
                    ? selection.averageOf(values)
                    : values[picked];
                final bool over = goal > 0 && value > goal;
                // 날을 고르면 그날의 탄단지, 아니면 기록이 있는 날의 하루
                // 평균이다. (회원 앱 #1121)
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
                              // 지표가 칼로리 하나라 `· 칼로리` 를 붙이지
                              // 않는다 — 바로 아래 숫자의 `kcal` 과 겹친다.
                              // 고른 날은 `9. 17.` 처럼 월·일만 적는다 —
                              // 날짜 기간과 같은 형식이다(회원 앱 #2009).
                              picked == null
                                  ? l.clientPeriodAverage
                                  : DateFormat.Md(locale).format(dates[picked]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(
                                    OnCareTypography.strong(
                                      OnCareTypography.caption,
                                    ),
                                  )
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                            const SizedBox(height: OnCareSpacing.s4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(
                                TextSpan(
                                  text: format(value),
                                  style: tokens
                                      .text(
                                        OnCareTypography.numeric(
                                          OnCareTypography.display,
                                        ),
                                      )
                                      .copyWith(
                                        color: over
                                            ? OnCareColors.danger
                                            : OnCareColors.textPrimary,
                                      ),
                                  children: <InlineSpan>[
                                    TextSpan(
                                      text: ' / ${format(goal)} $unit',
                                      style: tokens
                                          .text(OnCareTypography.bodySmall)
                                          .copyWith(
                                            color: OnCareColors.textSecondary,
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
                      // (회원 앱 #2009). 날을 고르면 날짜 기간은 빠진다 —
                      // 머리 문구가 이미 그날을 말한다.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (picked == null) ...<Widget>[
                            PeriodRangeLabel(
                              key: const ValueKey<String>(
                                'client-diet-period-range',
                              ),
                              text: periodRangeText(locale, from, to),
                            ),
                            if (macros != null)
                              const SizedBox(height: OnCareSpacing.s4),
                          ],
                          if (macros != null)
                            _MacroDetail(
                              macros: macros,
                              format: format,
                              muted: weekly,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 머리와 그래프 사이의 구분선도 간격도 두지 않는다 (회원 앱 #1123).
          // `전체` 는 그 빈 칸을 그래프가 들고 있어(topGap) 고른 막대의
          // 세로선이 머리 카드까지 닿는다.
          if (weekly) const SizedBox(height: OnCareSpacing.s12),
          if (weekly)
            Builder(
              builder: (BuildContext context) {
                final days = <String>[
                  for (final DateTime d in dates) _weekdayLabel(l, d),
                ];
                final today = _todayIndexIn(dates);
                return ListenableBuilder(
                  listenable: selection,
                  builder: (BuildContext context, Widget? _) =>
                      MetricTrendChart(
                        values: values,
                        dayLabels: days,
                        goal: goal,
                        ticks: ticks,
                        selectedIndex: selection.selected,
                        onSelected: selection.select,
                        // 선은 오늘까지만 잇는다. 아직 오지 않은 요일의 0 이
                        // 급락처럼 보이면 안 된다.
                        todayIndex: today,
                        // 카드 머리의 지표 이름으로 시작한다 — 음성 안내에서도
                        // 이 그래프가 무엇의 것인지가 먼저 들린다(#972).
                        semanticsLabel: chartSemanticsLabel(
                          l,
                          title: label,
                          points: chartSeriesPoints(
                            l,
                            values: values,
                            dayLabels: days,
                            format: (double v) => '${format(v)} $unit',
                            upTo: today,
                          ),
                        ),
                        goalLabel: '${l.clientPeriodGoal}\n${format(goal)}',
                        formatTick: (double v) => format(v),
                        height: _trendChartHeight,
                      ),
                );
              },
            )
          else
            // 쌓은 색이 무엇을 뜻하는지는 카드 머리의 탄단지 줄이 말한다 —
            // 그래프 아래 범례는 뺐다 (#1167). 한 카드가 같은 말을 두 번 하지
            // 않는다.
            _PeriodBars(
              values: values,
              logged: logged,
              dates: dates,
              goal: goal,
              unit: unit,
              label: label,
              format: format,
              selection: selection,
              days: days,
            ),
        ],
      ),
    );
  }

  /// 머리 숫자 옆에 붙일 탄단지. [picked] 이 있으면 그날 값, 없으면 기록이
  /// 있는 날의 하루 평균이다. 서버가 영양을 주지 않은 기간이면 null 이라
  /// 아무것도 붙지 않는다.
  _Macros? _macrosFor(int? picked) {
    if (picked != null) {
      if (picked >= days.length) return null;
      final ClientDietDay d = days[picked];
      return d.hasMacros
          ? _Macros(carbs: d.carbsG, protein: d.proteinG, fat: d.fatG)
          : null;
    }
    final List<ClientDietDay> logged = days
        .where((ClientDietDay d) => d.hasMacros)
        .toList();
    if (logged.isEmpty) return null;
    double avg(double Function(ClientDietDay) of) =>
        logged.fold<double>(0, (double a, ClientDietDay d) => a + of(d)) /
        logged.length;
    return _Macros(
      carbs: avg((ClientDietDay d) => d.carbsG),
      protein: avg((ClientDietDay d) => d.proteinG),
      fat: avg((ClientDietDay d) => d.fatG),
    );
  }
}

/// 머리 숫자 옆의 탄단지 한 덩어리. 막대를 쌓은 색을 그대로 써서, 예전 그래프
/// 아래 범례가 하던 말(어느 색이 무엇인지)까지 여기서 함께 한다. (회원 앱 #1121)
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
  const _MacroDetail({
    required this.macros,
    required this.format,
    required this.muted,
  });

  final _Macros macros;
  final String Function(num) format;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final OnCareBrand brand = tokens.brand;
    final TextStyle captionStrong = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    final List<(String, double, Color)> rows = <(String, double, Color)>[
      (
        l.metricCarbs,
        macros.carbs,
        muted ? OnCareColors.textSecondary : brand.macroCarbs,
      ),
      (
        l.metricProtein,
        macros.protein,
        muted ? OnCareColors.textSecondary : brand.macroProtein,
      ),
      (
        l.metricFat,
        macros.fat,
        muted ? OnCareColors.textSecondary : brand.macroFat,
      ),
    ];
    return Column(
      key: const ValueKey<String>('client-diet-period-macros'),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (String label, double value, Color color) in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                style: captionStrong.copyWith(color: color),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                // `204g` — 소수점은 버린다. 옆의 머리 숫자가 주인공이고 이
                // 줄은 곁들이다. (회원 앱 `_macroGrams`)
                '${value.round()}g',
                maxLines: 1,
                style: OnCareTypography.numeric(
                  captionStrong,
                ).copyWith(color: OnCareColors.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}

/// 요일 라벨(월…일).
String _weekdayLabel(AppLocalizations l, DateTime d) => <String>[
  l.weekdayMon,
  l.weekdayTue,
  l.weekdayWed,
  l.weekdayThu,
  l.weekdayFri,
  l.weekdaySat,
  l.weekdaySun,
][d.weekday - 1];

/// 오늘이 이 범위의 몇 번째 칸인가. 범위 밖이면 마지막 칸 — 지난 주를 보고
/// 있을 때 선이 중간에서 끊기지 않게 한다.
int _todayIndexIn(List<DateTime> dates) {
  final DateTime today = todayKst();
  for (int i = 0; i < dates.length; i++) {
    final DateTime d = dates[i];
    if (DateTime(d.year, d.month, d.day) == today) return i;
  }
  return dates.length - 1;
}

/// 일별 막대. 목표선을 얇게 얹고, 목표를 넘긴 날만 경고색으로 칠한다 —
/// 회원 앱 식단 탭의 같은 그래프와 규칙이 같다.
class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.values,
    required this.logged,
    required this.dates,
    required this.goal,
    required this.unit,
    required this.label,
    required this.format,
    required this.selection,
    this.days,
  });

  final List<double> values;
  final List<bool> logged;
  final List<DateTime> dates;
  final double goal;
  final String unit;
  final String label;
  final String Function(num) format;

  /// 칼로리를 볼 때의 원본. 탄단지가 있는 날은 막대를 셋으로 쌓는다.
  final List<ClientDietDay>? days;

  /// 스크롤 위치와 고른 날. 카드 머리의 숫자가 같은 상태를 본다. (#1018)
  final PeriodChartSelection selection;

  /// [i] 번째 칸의 원본. 칼로리를 보고 있지 않으면 null 이다.
  ClientDietDay? _dayAt(int i) {
    final List<ClientDietDay>? source = days;
    if (source == null || i >= source.length) return null;
    return source[i];
  }

  /// 아직 오지 않은 날인가. (회원 앱 #950)
  ///
  /// 기록하지 않은 것이 아니라 **기록할 수 없는** 날이다. 둘을 같은 말로 그리면
  /// 한 달을 훑으며 "며칠을 빠뜨렸나" 를 셀 때 미래의 빈 칸까지 빠뜨린 날처럼
  /// 읽힌다 — 달 초에는 그 수가 스무 날이 넘는다.
  bool _isPending(int i) {
    final DateTime d = dates[i];
    return DateTime(d.year, d.month, d.day).isAfter(todayKst());
  }

  /// 툴팁과 **같은 내용**을 한 줄짜리 시맨틱 라벨로. 색 사각형(`WidgetSpan`)은
  /// 빼고 줄바꿈은 쉼표로 바꾼다 — 음성 안내는 줄을 나누어 읽지 않는다.
  String _tipText(
    AppLocalizations l,
    OnCareBrand brand,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) => TextSpan(children: _tipSpans(l, brand, dayFormat, i, hasGoal))
      .toPlainText(includePlaceholders: false)
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .join(', ');

  /// 색 사각형 하나 — 툴팁 줄 앞에 붙는 범례다.
  InlineSpan _swatch(Color color) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.only(right: OnCareSpacing.s8),
      child: AppChartSwatch(color: color),
    ),
  );

  /// 한 막대의 툴팁 내용 — 회원 앱 식단 탭 기간 막대와 같은 구조다.
  /// `[색 사각형] 지표  값 단위` 한 줄, 목표를 넘긴 날은 초과분을 한 줄 더.
  List<InlineSpan> _tipSpans(
    AppLocalizations l,
    OnCareBrand brand,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) {
    final double value = values[i];
    final bool over = hasGoal && value > goal;
    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(
        text: '${dayFormat.format(dates[i])}\n',
        style: const TextStyle(color: OnCareColors.textSecondary),
      ),
    ];
    // 아직 오지 않은 날과 지나갔는데 비운 날은 다른 말이다(회원 앱 #950).
    if (_isPending(i)) {
      spans.add(TextSpan(text: l.chartNotYet));
      return spans;
    }
    // 기록이 없는 날은 0 이 아니라 '기록 없음' 이다. 0 으로 적으면 굶은 날과
    // 적지 않은 날이 같은 말이 된다.
    if (!logged[i] || value <= 0) {
      spans.add(TextSpan(text: l.chartNoRecord));
      return spans;
    }
    spans.add(_swatch(over ? OnCareColors.danger : brand.dietChart));
    spans.add(TextSpan(text: '$label   ${format(value)} $unit'));
    // 칼로리 뒤에는 그 칼로리가 어디서 왔는지를 적는다 — 숫자 하나만 보고는
    // 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지 알 수 없다.
    final ClientDietDay? day = _dayAt(i);
    if (day != null && day.hasMacros) {
      for (final ({Color color, String label, double grams}) m
          in <({Color color, String label, double grams})>[
            (color: brand.macroCarbs, label: l.metricCarbs, grams: day.carbsG),
            (
              color: brand.macroProtein,
              label: l.metricProtein,
              grams: day.proteinG,
            ),
            (color: brand.macroFat, label: l.metricFat, grams: day.fatG),
          ]) {
        spans.add(const TextSpan(text: '\n'));
        spans.add(_swatch(m.color));
        spans.add(TextSpan(text: '${m.label}   ${format(m.grams)} g'));
      }
    }
    // 막대가 왜 빨간지를 색이 아니라 글로도 말한다.
    if (over) {
      spans.add(
        TextSpan(
          text: '\n${l.chartOverGoal(format(value - goal), unit)}',
          style: const TextStyle(color: OnCareColors.danger),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareBrand brand = context.oncare.brand;
    // `8월 12일 (화)` / `Tue, Aug 12` — 어느 막대가 며칠인지 x축 라벨만으로는
    // 짚을 수 없다(달은 6칸에 하나만 적는다).
    final DateFormat dayFormat = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    );
    const double chartHeight = _barChartHeight;
    // 축 위에 여유를 둔다. 목표를 넘은 날이 없으면 목표가 곧 최댓값이 되어
    // 목표선이 차트 맨 위(=바깥)에 놓여 잘려 보인다.
    final double peak = <double>[
      goal,
      ...values,
    ].fold<double>(1, (double a, double b) => math.max(a, b));
    final double maxValue = peak * 1.15;
    final bool hasGoal = goal > 0;
    // 달(30칸)에서도 라벨이 겹치지 않도록 몇 칸에 하나만 적는다.
    final int labelStep = values.length > 10 ? (values.length / 6).ceil() : 1;
    // 기록이 하나도 없는 달은 막대마다 `기록 없음` 을 서른 번 읽히는 대신 비어
    // 있다고 한 번만 말한다(#972).
    final bool empty = logged.every((bool it) => !it);

    return Semantics(
      container: true,
      label: empty
          ? chartSemanticsLabel(l, title: label, points: const <String>[])
          : null,
      child: ExcludeSemantics(
        excluding: empty,
        child: ListenableBuilder(
          listenable: selection,
          builder: (BuildContext context, Widget? _) => PeriodScrollChart(
            count: values.length,
            height: chartHeight,
            // 한 화면 칸 수가 회원 앱과 같아야 `하루 평균` 이 같은 구간을 센다.
            daysPerScreen: _allDaysPerScreen,
            selectedIndex: selection.selected,
            onSelected: selection.select,
            onVisibleRangeChanged: selection.setVisible,
            // 되감을 일이 없다 — 처음 한 번만 바닥에서 자란다. 날을 고르는
            // 것으로는 다시 그리지 않는다 (#1697, 회원 앱 #1148).
            revealKey: label,
            // 목표치는 왼쪽 칸에 두 줄로 적는다 (#1071).
            goalBottom: hasGoal
                ? chartHeight * (goal / maxValue).clamp(0.0, 1.0)
                : null,
            goalLabel: '${l.clientPeriodGoal}\n${format(goal)}',
            // 머리 카드와 막대 사이의 빈 칸 — 고른 날의 세로선이 여기까지
            // 올라와 회색 카드에 닿는다 (회원 앱 #1123).
            topGap: OnCareSpacing.s12,
            // 날짜만 적으면 `26`, `9` 가 무슨 날인지 알 수 없다 — 달을 함께
            // 적는다 (회원 앱 #1123).
            labelBuilder: (int i) =>
                i % labelStep == 0 ? '${dates[i].month}/${dates[i].day}' : '',
            barBuilder: (BuildContext context, int i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s2),
              // 툴팁은 올려야 보인다. 같은 내용을 시맨틱 라벨로도 준다 — 막대
              // 하나가 며칠 얼마인지는 이 노드 말고는 음성 안내에 나올 데가
              // 없다(#972).
              child: Semantics(
                label: _tipText(l, brand, dayFormat, i, hasGoal),
                child: Tooltip(
                  key: Key('client-diet-bar-$i'),
                  // 같은 말은 바깥 [Semantics] 가 이미 한다 — 상자 모양만
                  // 들어간 툴팁 문구는 음성 안내에서 뺀다.
                  excludeFromSemantics: true,
                  // 상자는 공용 [AppChartTooltip] 이 그린다. Tooltip 자체의
                  // 바탕·안쪽 여백은 비운다.
                  decoration: const BoxDecoration(),
                  padding: EdgeInsets.zero,
                  richMessage: WidgetSpan(
                    child: AppChartTooltip(
                      child: Text.rich(
                        TextSpan(
                          children: _tipSpans(l, brand, dayFormat, i, hasGoal),
                        ),
                      ),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _MacroBar(
                      height:
                          chartHeight * (values[i] / maxValue).clamp(0.0, 1.0),
                      day: _dayAt(i),
                      logged: logged[i],
                      pending: _isPending(i),
                      // 목표를 넘긴 날은 **통으로 빨강** 한 색이다 (회원 앱
                      // #1352) — 같은 카드의 나트륨·당류가 초과를 한 색으로
                      // 말하는데 칼로리만 초과의 생김새가 다르면, 눈이 지표마다
                      // 다른 문법을 다시 배워야 한다.
                      over: hasGoal && values[i] > goal,
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
///
/// 쌓는 기준은 **칼로리**다(탄·단 4kcal/g, 지 9kcal/g). 그램으로 쌓으면 지방
/// 1g 이 탄수화물 1g 과 같은 높이를 차지해, 칼로리 막대인데 칼로리와 다른
/// 이야기를 하게 된다.
class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.height,
    required this.day,
    required this.logged,
    required this.over,
    this.pending = false,
  });

  final double height;
  final ClientDietDay? day;

  /// 그날 기록이 있었는가. 없으면 색 없는 그루터기다.
  final bool logged;

  /// 아직 오지 않은 날인가. 지나간 빈 날의 그루터기보다 **더 옅게** 그린다 —
  /// 둘을 같은 그림으로 두면 달 초에 스무 날 넘는 미래가 전부 '빠뜨린 날' 로
  /// 읽힌다. (회원 앱 #950)
  final bool pending;

  /// 목표를 넘긴 날인가. 넘긴 날은 쌓지 않고 한 색으로 칠한다.
  final bool over;

  @override
  Widget build(BuildContext context) {
    // 차트 막대 반경(xs) — 좁은 칸에서 막대 끝이 반원처럼 뭉뚱그려지지 않는다.
    const BorderRadius radius = BorderRadius.vertical(top: OnCareRadius.xs);
    final OnCareBrand brand = context.oncare.brand;
    final ClientDietDay? d = day;
    if (pending) {
      // 아직 오지 않은 날은 **빈 트랙**이다. 지나간 빈 날과 같은 그루터기를
      // 그리면 둘이 구분되지 않는다. "대기" 표시는 회원 앱과 같은 한 가지 —
      // 진한 선 4px 이다(회원 앱 #1697).
      return Container(
        height: OnCareSize.stepBar,
        decoration: const BoxDecoration(
          color: OnCareColors.lineStrong,
          borderRadius: radius,
        ),
      );
    }
    final double total = d == null
        ? 0
        : d.carbsKcal + d.proteinKcal + d.fatKcal;
    // 목표를 넘긴 날은 **통으로 빨강** 한 색이다 (회원 앱 #1352). 탄단지를
    // 빨강 세 단계로 쌓아 봤지만(회원 앱 #1201), 같은 카드의 나트륨·당류는
    // 초과를 한 색으로 말하고 있어 칼로리만 초과의 생김새가 달랐다. 넘기지
    // 않은 날은 지금처럼 탄·단·지 남색 세 단계로 쌓는다.
    if (over || d == null || !d.hasMacros || total <= 0) {
      // 높이가 바뀔 때 애니메이션하지 않는다 — 기간을 옮길 때마다 서른 칸이
      // 함께 자라나면, 값을 읽으려는 사람이 그림이 멈추기를 기다려야
      // 한다. (#1027)
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: !logged
              // 기록이 없는 날은 색이 없다 — 0 으로 칠하면 '적지 않은 날' 이
              // '0kcal 먹은 날' 이 된다.
              ? OnCareColors.lineStrong
              : over
              ? OnCareColors.danger
              // 목표 안쪽 막대는 `brand.dietChart` — 이 앱의 브랜드
              // 남색이다. 한때 초록이었지만(#1027) 초록은 `정상` 으로 읽혀
              // 목표에 한참 못 미친 날까지 괜찮다고 말해 걷어냈다(#1168).
              // 판단은 초과 여부만 하고, 초과한 날만 빨강으로 갈린다(#1239).
              : brand.dietChart,
          borderRadius: radius,
        ),
      );
    }
    // 막대 **높이**는 칼로리를 따른다(목표선과 견주려면 그래야 한다). 그런데
    // 구간 비율만 탄단지 합계로 잡으면, 둘이 어긋나는 날에 구간이 실제 기여분
    // 보다 크게 그려진다 — 1,800kcal 인 날의 탄단지가 1,200kcal 어치뿐이어도
    // 세 색이 막대를 꽉 채워, 없는 기여분을 지어내는 셈이다.
    //
    // 그래서 분모를 **둘 중 큰 값**으로 둔다. 탄단지가 칼로리에 못 미치면 남는
    // 만큼이 `나머지` 로 위에 남고, 넘치면 탄단지 합계에 맞춰 꽉 찬다.
    final double basis = math.max(d.calories.toDouble(), total);
    final double rest = basis - total;
    // 값이 있는 구간만 만든다. `flex: 0` 이 터지지는 않지만(확인함), 셋이 모두
    // 0 으로 반올림되면 높이만 있고 아무것도 그려지지 않은 막대가 남는다 —
    // #947 과 같은 종류의 사라짐이다. 그래서 남는 구간에는 **최소 1** 을 준다:
    // 아주 적게 먹은 영양소는 실오라기로라도 보이는 편이 없는 것보다 낫다.
    //
    // 위에서부터 나머지·지방·단백질·탄수화물 — 아래가 탄수화물이라 눈이 바닥부터
    // 읽는 순서가 범례 순서(탄·단·지)와 같아진다.
    final List<({Color color, double kcal})>
    parts = <({Color color, double kcal})>[
      // 어느 영양소로도 설명되지 않는 칼로리. 반올림 때문에 생기는
      // 실오라기는 그리지 않는다 — 1% 를 넘을 때만 자리를 준다.
      if (rest / basis > 0.01) (color: OnCareColors.surfaceInput, kcal: rest),
      if (d.fatKcal > 0) (color: brand.macroFat, kcal: d.fatKcal),
      if (d.proteinKcal > 0) (color: brand.macroProtein, kcal: d.proteinKcal),
      if (d.carbsKcal > 0) (color: brand.macroCarbs, kcal: d.carbsKcal),
    ];
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Column(
          // **stretch 여야 한다.** 기본값(center)이면 자식이 가로로 느슨하게
          // 제약되는데, 자식 없는 `ColoredBox` 의 고유 너비는 0 이라 구간이
          // 통째로 사라진다(회원 앱 #947 에서 밟은 함정).
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
