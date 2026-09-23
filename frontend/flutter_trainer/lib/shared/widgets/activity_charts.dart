/// 운동 그래프 — 회원 앱 운동 탭 `운동 현황` 과 **같은 그림**이다. (#943, #1077,
/// #1168)
///
/// 회원 앱 `features/exercise/presentation/widgets/exercise_activity_status.dart`
/// 의 도넛·링·막대를 트레이너 콘솔 토큰으로 옮긴 것이다. 두 앱은 패키지가 갈라져
/// 있어 코드를 공유할 수 없으므로, 규칙을 여기에도 적어 둔다 —
/// `metric_trend_chart` 를 옮겨 둔 것과 같은 방식이다. 한쪽만 고치면 회원이 보는
/// 그래프와 트레이너가 보는 그래프가 다른 이야기를 한다.
///
///  * 축은 **소모 칼로리**다. 유산소는 분, 근력은 세트, 스트레칭은 분으로 재는
///    값이라 서로 더할 수 없는데, 칼로리는 셋이 함께 만든 하나의 결과다.
///  * 유형 순서는 언제나 유산소 → 근력 → 스트레칭이다. 링도 목록도 같은 순서라,
///    색을 외우지 않아도 자리로 읽힌다.
///  * 목표가 없는 `기타` 는 그리지 않고 분 수만 적는다.
///  * 기록이 없는 칸은 3px 짜리 회색 그루터기다. 0 을 아예 안 그리면 그 칸이
///    빠진 것처럼 보이고, 색을 주면 짧은 운동을 한 것처럼 보인다.
///  * 링 12시에는 그 링이 무엇인지 말하는 흰 기호를, 원호 **끝**에는 그림자와
///    얇은 `>` 를 얹는다 — 한 바퀴를 넘겨 겹쳐도 어디서 멈췄는지 읽힌다. 목표의
///    정확한 배수(100%·200% …)에서는 끝이 12시 기호와 겹치므로 둘 다 생략한다
///    (회원 앱 #1462).
///  * 목표는 코드 상수가 아니라 회원 프로필에서 읽은 [ExerciseBurnGoals] 다
///    (회원 앱 #1139, #2157).
///
/// 회원 앱에는 진입 애니메이션이 있지만 여기서는 정적으로 그린다. 트레이너
/// 콘솔의 다른 차트(`BarSeriesChart`)도 정적이라, 한 화면에서 어떤 그래프는
/// 자라고 어떤 그래프는 이미 서 있으면 그게 더 튄다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/widgets/chart_semantics.dart';
import 'package:oncare_trainer/shared/widgets/period_range_label.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 소모 칼로리 색. **트레이너 메인 색**이다 (#1168).
///
/// 유형 셋이 쓰는 램프([OnCareBrand.trainer.exerciseCardio] 이하)보다 한 단계 진하다 — 도넛과
/// 링이 재는 것은 유형이 아니라 그 셋이 함께 만든 결과라, 램프의 어느 단계와도
/// 겹치면 안 된다. 흰 글자 대비로 4.5 : 3.4 : 2.0 : 1.4 로 네 값이 차례로
/// 벌어진다(회원 앱과 같은 간격).
final Color kBurnColor = OnCareBrand.trainer.primary;

/// 유형 색 — 회원 앱과 같은 순서·같은 농담이다.
Color kindColor(ExerciseKind kind) => switch (kind) {
  ExerciseKind.cardio => OnCareBrand.trainer.exerciseCardio,
  ExerciseKind.strength => OnCareBrand.trainer.exerciseStrength,
  ExerciseKind.stretching => OnCareBrand.trainer.exerciseStretching,
};

/// 유형 이름.
String kindLabel(AppLocalizations l, ExerciseKind kind) => switch (kind) {
  ExerciseKind.cardio => l.routineTypeCardio,
  ExerciseKind.strength => l.routineTypeStrength,
  ExerciseKind.stretching => l.routineTypeStretching,
};

/// 유형의 값을 **그 유형의 단위**로 — 유산소·스트레칭은 분, 근력은 세트.
String kindValueText(AppLocalizations l, ExerciseKind kind, num value) =>
    switch (kind) {
      ExerciseKind.cardio ||
      ExerciseKind.stretching => l.minutesShort(value.round()),
      ExerciseKind.strength => l.progSetsValue(value.round()),
    };

/// 링 12시에 얹는 유형 기호 (회원 앱 #1128).
///
/// 이 링이 무엇인지(유산소·근력·스트레칭)와 어디서 출발했는지를 말한다. 자리를
/// 고정해 두어야 링끼리 견줄 수 있다 — 어디까지 왔는지는 원호 끝의 그림자가
/// 짚는다.
IconData ringStartIcon(ExerciseKind kind) => switch (kind) {
  ExerciseKind.cardio => Icons.directions_run_rounded,
  ExerciseKind.strength => Icons.fitness_center_rounded,
  ExerciseKind.stretching => Icons.self_improvement_rounded,
};

/// 소모 칼로리 도넛의 12시 기호.
const IconData kBurnStartIcon = Icons.local_fire_department_rounded;

/// 세 기간 카드의 **공통 높이**. 토글을 눌러도 카드가 커졌다 작아졌다 하지
/// 않도록 셋을 같은 높이로 둔다. 회원 앱과 같은 값이다.
const double kActivityCardHeight = 218;

/// 도넛·링 오른쪽 상세 목록 칸의 너비. 회원 앱과 같은 값이다.
const double _kDetailWidth = 150;

/// 원호 끝 그림자 두 겹 — 넓고 흐린 것 / 좁고 진한 것. 회원 앱 #1161 과 같은 값.
const double _kCapShadowOuterSpread = 4;
const double _kCapShadowOuterBlur = 12;
const double _kCapShadowOuterAlpha = 0.75;
const double _kCapShadowInnerSpread = 1;
const double _kCapShadowInnerBlur = 5;
const double _kCapShadowInnerAlpha = 0.65;

/// `397/500` — 값과 목표를 한 덩어리로. 목표를 따로 떼어 적으면 머리 줄이
/// 길어져 카드 폭을 다 먹는다.
String activityValueOfGoal(String locale, num value, num goal) {
  final NumberFormat nf = NumberFormat.decimalPattern(locale);
  return '${nf.format(value.round())}/${nf.format(goal.round())}';
}

/// 하루/기간의 유형별 값 한 벌. 단위가 서로 다르므로 더하지 않는다.
class ActivitySplit {
  /// Creates one split.
  const ActivitySplit({
    this.cardioMinutes = 0,
    this.strengthSets = 0,
    this.stretchingMinutes = 0,
    this.otherMinutes = 0,
    // 인자 이름은 `strengthMinutes` 로 두고, 같은 이름은 아래 getter 가
    // 가져간다 — 주지 않은 곳에서는 세트에서 되짚어야 하기 때문이다.
    num? strengthMinutes,
    // ignore: prefer_initializing_formals
  }) : _strengthMinutes = strengthMinutes;

  final num cardioMinutes;
  final num strengthSets;

  /// 근력에 쓴 **시간**. 화면에는 세트로 적지만, 막대를 유형별로 나눌 때는
  /// 셋을 같은 단위(분)로 놓아야 몫이 뜻을 갖는다. 주지 않으면 세트에서
  /// 되짚는다 — 그때도 셋의 비율은 흔들리지 않는다.
  final num? _strengthMinutes;

  num get strengthMinutes =>
      _strengthMinutes ?? strengthSets * kStrengthMinutesPerSet;

  final num stretchingMinutes;

  /// 목표가 없는 나머지 운동. 그래프에는 그리지 않는다.
  final num otherMinutes;

  num valueOf(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => cardioMinutes,
    ExerciseKind.strength => strengthSets,
    ExerciseKind.stretching => stretchingMinutes,
  };

  /// 막대를 나누는 몫 — **셋 모두 분**이다.
  ///
  /// 막대 **높이**는 소모 칼로리이고 막대 **안**은 이 몫으로 나뉜다. 세트로
  /// 나누면 근력 한 세트가 유산소 1분과 같은 자리를 차지해, 칼로리 막대인데
  /// 칼로리와 다른 이야기를 하게 된다. (회원 앱 `_WeekBucket.minutesByKind`)
  Map<ExerciseKind, num> get minutesByKind => <ExerciseKind, num>{
    ExerciseKind.cardio: cardioMinutes,
    ExerciseKind.strength: strengthMinutes,
    ExerciseKind.stretching: stretchingMinutes,
  };
}

/// `오늘` — 소모 칼로리 도넛 하나 + 유형별로 얼마나 했는지 적은 줄.
///
/// 도넛은 **왼쪽**, 유형별 값은 오른쪽이다. 둘을 한 덩어리로 카드 가운데에
/// 세운다 (회원 앱 #1151·#1159). 소모 칼로리는 도넛 **안에서** 말한다 — 링 옆에
/// 같은 숫자를 또 적으면 한 화면에서 같은 말이 두 번 나온다 (#1127).
class BurnDonut extends StatelessWidget {
  /// Creates the donut.
  const BurnDonut({
    super.key,
    required this.calories,
    required this.goal,
    required this.split,
    required this.title,
    this.streakDays,
  });

  final int calories;

  /// 하루 소모 목표(kcal). 0 이면 트랙만 그린다.
  final double goal;
  final ActivitySplit split;

  /// 시맨틱 라벨이 부르는 이름 — `오늘 소모`.
  final String title;

  /// 며칠 연속 운동 중인지. null 이면 그 줄을 그리지 않는다.
  final int? streakDays;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final int? streak = streakDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (streak != null) ...<Widget>[
          ActivityStreakLine(days: streak),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double size = math.min(
                c.maxHeight,
                (c.maxWidth - 170).clamp(96.0, 150.0),
              );
              return Row(
                // 도넛과 상세를 한 덩어리로 **카드 가운데**에 세운다.
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Semantics(
                    container: true,
                    label: chartSemanticsLabel(
                      l,
                      title: title,
                      points: calories == 0
                          ? const <String>[]
                          : <String>['$calories${l.unitKcal}'],
                    ),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(
                          painter: _DonutPainter(
                            ratio: goal <= 0 ? 0 : calories / goal,
                            center: NumberFormat.decimalPattern(
                              locale,
                            ).format(calories),
                            // 도넛 안에서 `411` 아래 `/300kcal` 로 읽힌다
                            // (#1127) — 목표는 한 단계 작고 흐리게.
                            unit:
                                '/${NumberFormat.decimalPattern(locale).format(goal.round())}'
                                '${l.unitKcal}',
                            // 회원 앱 홈 운동 카드가 쓰는 것과 같은 말이다 —
                            // 두 화면이 같은 값을 다른 이름으로 부르지 않게
                            // 한 문구를 나눠 쓴다. (회원 앱 #1352)
                            caption: l.clientTrendCaloriesBurned,
                            startIcon: kBurnStartIcon,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  // 상세는 폭을 못 박아 줄들이 서로 붙어 읽힌다. 자리가
                  // 모자라면(좁은 사이드바·큰 글자) `Flexible` 이 그만큼 줄여
                  // 준다 — 못 박기만 하면 카드 밖으로 밀려난다.
                  Flexible(
                    child: SizedBox(
                      width: _kDetailWidth,
                      child: Center(
                        // 목록 전체를 **한 번에** 줄인다 (#1170) — 줄마다 따로
                        // 줄이면 나란히 선 세 줄의 글자 크기가 제각각이 된다.
                        //
                        // 폭은 못 박지 않고 **가장 긴 줄에 맞춘다** (#1173).
                        // 못 박으면 그보다 긴 값이 잘리는데, 바깥 `FittedBox`
                        // 는 칸 안에서 잘린 것을 모른다.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: IntrinsicWidth(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              // 세 줄이 **같은 너비**로 서야 값의 오른쪽 끝이
                              // 가지런하다 — 줄마다 제 너비면 값이 들쭉날쭉
                              // 끝난다. (#1173)
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (final ExerciseKind kind
                                    in ExerciseKind.values)
                                  ActivityValueRow(
                                    label: kindLabel(l, kind),
                                    value: kindValueText(
                                      l,
                                      kind,
                                      split.valueOf(kind),
                                    ),
                                  ),
                                // 세 유형은 0 이어도 줄로 남는다 — `오늘 무엇을
                                // 안 했는지` 도 이 카드가 답해야 한다. 반대로
                                // `기타` 는 기록이 있을 때만 맨 아래 회색 한
                                // 줄로 붙는다 (회원 앱 #1352).
                                if (split.otherMinutes > 0)
                                  ActivityValueRow(
                                    label: l.exTypeOther,
                                    value: l.minutesShort(
                                      split.otherMinutes.round(),
                                    ),
                                    muted: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// `🔥 5일 연속 운동 중이에요!` — 응원 문구 한 줄. (회원 앱 #1160)
///
/// 옅은 주황 알약을 깔아 **응원**임을 표시한다. 배경은 글자 색을 그대로 옅게 쓴
/// 것이라 색이 하나 더 늘지 않는다.
class ActivityStreakLine extends StatelessWidget {
  /// Creates the streak line.
  const ActivityStreakLine({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s12,
          vertical: OnCareSpacing.s4,
        ),
        decoration: BoxDecoration(
          // 흰 카드 위 톤 채움 — 불투명 값으로 둔다.
          color: OnCareColors.onWhite(
            OnCareColors.cautionFill,
            OnCareAlpha.subtle,
          ),
          borderRadius: OnCareRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 불꽃은 소모 칼로리 도넛이 쓴다 — 연속은 '기세' 쪽 기호로 갈라
            // 둔다. 한 화면에서 같은 그림이 두 가지를 뜻하면 안 된다.
            const Icon(
              Icons.bolt_rounded,
              size: OnCareSize.iconSmall,
              color: OnCareColors.cautionFill,
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Flexible(
              child: Text(
                days > 0 ? l.exStreakCheer(days) : l.exStreakStart,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.oncare
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.cautionFill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `이번 주` — 유형별 주간 목표를 크기 순으로 겹친 세 링 + 유형별 진행.
///
/// 단위가 서로 다르니 높이를 나란히 두지 않고, 각자의 주간 목표에 대한
/// **달성률**만 같은 모양으로 겹쳐 보여 준다.
class BurnGoalRings extends StatelessWidget {
  /// Creates the rings.
  const BurnGoalRings({
    super.key,
    required this.calories,
    required this.split,
    required this.title,
    this.goals = kDefaultExerciseBurnGoals,
    this.range,
  });

  final int calories;
  final ActivitySplit split;
  final String title;

  /// 회원의 목표 — 머리줄의 주간 소모 목표와 링 셋의 주간 목표(#2157).
  final ExerciseBurnGoals goals;

  /// 이 카드가 집계한 주(월~일). 주면 머리줄 **같은 줄** 오른쪽에 적는다
  /// (회원 앱 #2007) — 제 줄을 쓰면 고정 높이 안에서 링과 목록이 그만큼
  /// 깎인다. `전체` 는 제 기간을 스스로 적는데 `이번 주` 만 비어 있으면, 이
  /// 숫자가 어느 주의 것인지 카드가 말하지 않는다.
  final ({DateTime from, DateTime to})? range;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final ({DateTime from, DateTime to})? r = range;
    final List<double> ratios = <double>[
      for (final ExerciseKind kind in ExerciseKind.values)
        goals.weeklyGoalOf(kind) <= 0
            ? 0
            : split.valueOf(kind) / goals.weeklyGoalOf(kind),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 6,
              child: ActivityHeadlineLine(
                caption: title,
                value: activityValueOfGoal(
                  locale,
                  calories,
                  goals.weeklyBurnKcal,
                ),
                unit: l.unitKcal,
              ),
            ),
            if (r != null) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                flex: 4,
                child: PeriodRangeLabel(
                  key: const Key('client-exercise-week-range'),
                  text: periodRangeText(locale, r.from, r.to),
                ),
              ),
            ],
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double size = math.min(
                c.maxHeight,
                (c.maxWidth - 170).clamp(96.0, 150.0),
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Semantics(
                    container: true,
                    label: chartSemanticsLabel(
                      l,
                      title: title,
                      points: <String>[
                        for (int i = 0; i < ExerciseKind.values.length; i++)
                          '${kindLabel(l, ExerciseKind.values[i])} ${(ratios[i] * 100).round()}%',
                      ],
                    ),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(painter: _GoalRingsPainter(ratios)),
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Flexible(
                    child: SizedBox(
                      width: _kDetailWidth,
                      child: Center(
                        // 목록 전체를 **한 번에** 줄인다 (#1170) — 줄마다 따로
                        // 줄이면 나란히 선 세 줄의 글자 크기가 제각각이 된다.
                        //
                        // 폭은 못 박지 않고 **가장 긴 줄에 맞춘다** (#1173).
                        // 못 박으면 그보다 긴 값이 잘리는데, 바깥 `FittedBox`
                        // 는 칸 안에서 잘린 것을 모른다.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: IntrinsicWidth(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              // 세 줄이 **같은 너비**로 서야 값의 오른쪽 끝이
                              // 가지런하다 — 줄마다 제 너비면 값이 들쭉날쭉
                              // 끝난다. (#1173)
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (final ExerciseKind kind
                                    in ExerciseKind.values)
                                  ActivityValueRow(
                                    color: kindColor(kind),
                                    label: kindLabel(l, kind),
                                    value: '${split.valueOf(kind).round()}',
                                    goal:
                                        '/${kindValueText(l, kind, goals.weeklyGoalOf(kind))}',
                                  ),
                                // 기타는 목표가 없다 — 오늘 카드와 같이 분만
                                // 적고, 한 주에 기록이 있을 때만 맨 아래 회색
                                // 한 줄로 붙는다 (회원 앱 #1352).
                                if (split.otherMinutes > 0)
                                  ActivityValueRow(
                                    color: OnCareColors.lineStrong,
                                    label: l.exTypeOther,
                                    value: l.minutesShort(
                                      split.otherMinutes.round(),
                                    ),
                                    muted: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// `소모  411/300 kcal` — 한 줄짜리 머리.
class ActivityHeadlineLine extends StatelessWidget {
  /// Creates the headline.
  const ActivityHeadlineLine({
    super.key,
    required this.caption,
    required this.value,
    required this.unit,
    this.stacked = false,
  });

  final String caption;
  final String value;
  final String unit;

  /// 이름을 위 한 줄, 숫자를 그 아래 한 줄로 쌓을지. `전체` 가 쓴다 — 오른쪽
  /// 칸이 날짜 기간 + 유형별 내역 여러 줄이라, 한 줄 머리는 숫자 아래가
  /// 통째로 빈다(회원 앱 #2061).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle minor = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    final Widget captionText = Text(
      caption,
      style: minor.copyWith(color: OnCareColors.textSecondary),
    );
    final List<Widget> number = <Widget>[
      Text(
        value,
        style: tokens
            .text(OnCareTypography.numeric(OnCareTypography.titleLarge))
            .copyWith(color: OnCareColors.textPrimary),
      ),
      const SizedBox(width: OnCareSpacing.s4),
      Text(unit, style: minor.copyWith(color: OnCareColors.textTertiary)),
    ];
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: captionText,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: number,
            ),
          ),
        ],
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          captionText,
          const SizedBox(width: OnCareSpacing.s8),
          ...number,
        ],
      ),
    );
  }
}

/// `▪ 유산소   145/150분` — 유형 한 줄.
class ActivityValueRow extends StatelessWidget {
  /// Creates one row.
  const ActivityValueRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.goal,
    this.muted = false,
  });

  final String label;
  final String value;

  /// 세 유형 아래 덧붙는 `기타` 줄인가. 목표도 색도 없는 값이라 **회색**으로
  /// 한 단계 물려 적는다 (회원 앱 #1352) — 유형 셋과 같은 진하기로 적으면
  /// 네 번째 유형처럼 읽힌다.
  final bool muted;

  /// 색 점. 옆에 같은 색 링이 있는 화면에서만 준다 — 오늘 카드는 도넛이
  /// 하나뿐이라 점이 가리킬 데가 없다.
  final Color? color;

  /// `/150분` 처럼 값 뒤에 붙는 목표. 값보다 연하게 적어, 눈이 앞의 숫자를
  /// 먼저 읽고 뒤의 기준을 나중에 보게 한다.
  final String? goal;

  @override
  Widget build(BuildContext context) {
    final Color? c = color;
    final String? g = goal;
    final OnCareTokens tokens = context.oncare;
    final Color tone = muted
        ? OnCareColors.textDisabled
        : OnCareColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(
        bottom: OnCareSpacing.s8,
        left: OnCareSpacing.s8,
        right: OnCareSpacing.s8,
      ),
      child: Row(
        children: <Widget>[
          if (c != null) ...<Widget>[
            AppChartSwatch(color: c),
            const SizedBox(width: OnCareSpacing.s8),
          ],
          // **줄마다 따로 줄이지 않는다** (#1170). 칸마다 `FittedBox` 를 두면
          // 긴 값(`180/150분`)만 더 작아져, 나란히 선 세 줄의 글자 크기가
          // 제각각이 된다 — 세 줄은 같은 성격의 값이라 같은 크기로 읽혀야
          // 한다. 좁아질 때는 목록 전체가 한 번에 줄어든다(부르는 쪽의
          // `FittedBox`).
          //
          // 칸을 `Expanded` 로 나누지도 않는다 (#1173). 나누면 값 칸이 글자보다
          // 좁아질 수 있는데, 그때 글자는 줄어드는 대신 **잘린다** — 그리고
          // 바깥 `FittedBox` 는 칸이 넘친 것을 모르니 줄여 주지도 않는다.
          // 라벨과 값을 제 너비로 두고 그 사이를 [Spacer] 가 벌리면, 줄의 고유
          // 너비가 곧 글자가 필요로 하는 너비라 바깥이 그만큼 줄여 준다.
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: tone),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: value),
                if (g != null)
                  TextSpan(
                    text: g,
                    style: const TextStyle(color: OnCareColors.textSecondary),
                  ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            style: tokens
                .text(OnCareTypography.numeric(OnCareTypography.label))
                .copyWith(
                  color: muted
                      ? OnCareColors.textDisabled
                      : OnCareColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

/// 범례 한 줄 — 색 사각형 + 이름. 식단 기간 카드가 함께 쓴다.
class ActivityLegend extends StatelessWidget {
  /// Creates one legend entry.
  const ActivityLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      AppChartSwatch(color: color),
      const SizedBox(width: OnCareSpacing.s8),
      Text(
        label,
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: OnCareColors.textSecondary),
      ),
    ],
  );
}

/// [BurnBarChart] 가 막대 영역 **밖에** 더 쓰는 세로 크기(간격 + 날짜 라벨 줄).
/// 남는 자리를 그래프에 넘길 때 이만큼을 빼야 카드가 넘치지 않는다.
const double kBurnBarChartExtraHeight =
    OnCareSpacing.s8 + 16; // 공용 PeriodScrollChart 의 라벨 간격 + 라벨 줄 높이

/// `전체` — **한 칸이 한 주**인 소모 칼로리 막대. 한 칸을 고르면 그 주의
/// 내역이 카드 머리 오른쪽에 뜬다.
class BurnBarChart extends StatelessWidget {
  /// Creates the chart.
  const BurnBarChart({
    super.key,
    required this.calories,
    required this.splits,
    required this.dates,
    required this.title,
    required this.selection,
    this.goalKcal = kDailyBurnKcal,
    this.height = 132,
  });

  final List<int> calories;
  final List<ActivitySplit> splits;
  final List<DateTime> dates;

  /// 그래프가 무엇을 그린 것인지 — 기록이 하나도 없는 기간에 비어 있다고 말할
  /// 때 이 이름으로 부른다(#972).
  final String title;
  final PeriodChartSelection selection;

  /// 한 칸의 소모 목표(kcal). 칸이 하루면 하루 목표, 한 주면 주간 목표다.
  /// 0 이면 목표선을 그리지 않는다.
  final double goalKcal;

  /// **막대 영역**의 세로 크기. 아래 날짜 라벨 줄은 여기에 들어가지 않는다 —
  /// 남는 자리에 맞춰 넘겨줄 때는 [kBurnBarChartExtraHeight] 를 빼야 한다.
  final double height;

  /// 한 화면에 보일 칸 수. 칸 하나가 한 주라, 한 화면이 대략 석 달이다.
  static const int _slotsPerScreen = 13;

  /// 막대 하나의 툴팁 — 소모 칼로리와 그 주의 유형별 내역.
  List<InlineSpan> _tipSpans(AppLocalizations l, int i) {
    final ActivitySplit s = splits[i];
    final List<String> rows = <String>[
      for (final ExerciseKind kind in ExerciseKind.values)
        if (s.valueOf(kind) > 0)
          '${kindLabel(l, kind)}   ${kindValueText(l, kind, s.valueOf(kind))}',
      if (s.otherMinutes > 0)
        '${l.exTypeOther}   ${l.minutesShort(s.otherMinutes.round())}',
    ];
    if (calories[i] <= 0 && rows.isEmpty) {
      return <InlineSpan>[TextSpan(text: l.chartNoRecord)];
    }
    return <InlineSpan>[
      TextSpan(text: '${calories[i]}${l.unitKcal}'),
      if (rows.isNotEmpty) TextSpan(text: '\n${rows.join('\n')}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool empty = calories.every((int c) => c <= 0);
    final double chartHeight = height;
    final double peak = <double>[
      goalKcal,
      for (final int c in calories) c.toDouble(),
    ].fold<double>(1, (double a, double b) => math.max(a, b));
    final double max = peak * 1.15;
    final String locale = Localizations.localeOf(context).toString();

    return Semantics(
      container: true,
      label: empty
          ? chartSemanticsLabel(l, title: title, points: const <String>[])
          : null,
      child: ExcludeSemantics(
        excluding: empty,
        child: ListenableBuilder(
          listenable: selection,
          builder: (BuildContext context, Widget? _) => PeriodScrollChart(
            count: calories.length,
            height: chartHeight,
            selectedIndex: selection.selected,
            onSelected: selection.select,
            onVisibleRangeChanged: selection.setVisible,
            daysPerScreen: _slotsPerScreen,
            // 목표치는 왼쪽 칸에 두 줄로 적는다 (#1071). 단위는 붙이지 않는다 —
            // 회원 앱 `전체` 와 같은 `목표\n2100` 이다(#2157). kcal 은 바로
            // 위 머리줄이 이미 말한다.
            goalBottom: goalKcal > 0
                ? chartHeight * (goalKcal / max).clamp(0.0, 1.0)
                : null,
            goalLabel: '${l.clientPeriodGoal}\n${goalKcal.round()}',
            // 달이 바뀌는 칸에만 적는다 — 모든 칸에 적으면 글자가 서로 겹쳐
            // 아무것도 읽히지 않는다. 회원 앱 `전체` 그래프와 같은 규칙이다.
            labelBuilder: (int i) =>
                i < dates.length &&
                    (i == 0 || dates[i].month != dates[i - 1].month)
                ? DateFormat.MMM(locale).format(dates[i])
                : '',
            // 눈금선(0·50·100%)과 달 경계 파선을 막대 뒤에 깐다 — 회원 앱
            // 운동 탭 `전체` 그래프와 같은 자다.
            background: _ChartGridPainter(
              count: calories.length,
              monthBreaks: <int>[
                for (int i = 1; i < dates.length; i++)
                  if (dates[i].month != dates[i - 1].month) i,
              ],
            ),
            // 한 칸이 한 주라, 어느 주를 고른 것인지 달 라벨에서도 읽혀야 한다.
            boldSelectedLabel: true,
            barBuilder: (BuildContext context, int i) => Tooltip(
              key: Key('client-exercise-bar-$i'),
              richMessage: TextSpan(
                style: context.oncare
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.textPrimary),
                children: _tipSpans(l, i),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s12,
                vertical: OnCareSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: OnCareColors.surfaceInput,
                borderRadius: OnCareRadius.mdAll,
                border: Border.all(color: OnCareColors.lineStrong),
                boxShadow: OnCareShadows.card,
              ),
              child: _BurnBarColumn(
                value: calories[i].toDouble(),
                max: max,
                height: chartHeight,
                parts: splits[i].minutesByKind,
                dimmed: selection.selected != null && selection.selected != i,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 막대 한 칸.
///
/// 막대 **높이**는 소모 칼로리이고, 막대 **안**은 유형별 시간 몫으로 나뉜다 —
/// 식단의 칼로리 막대가 탄·단·지로 쌓이는 것과 같은 규칙이다(회원 앱 #1177).
/// 유형 분해가 없는 칸만 한 색([kBurnColor])으로 채운다.
class _BurnBarColumn extends StatelessWidget {
  const _BurnBarColumn({
    required this.value,
    required this.max,
    required this.height,
    required this.dimmed,
    this.parts = const <ExerciseKind, num>{},
  });

  final double value;
  final double max;
  final double height;
  final bool dimmed;

  /// 그 칸의 유형별 시간(분). 비어 있으면 한 색으로 채운다.
  final Map<ExerciseKind, num> parts;

  /// 칸에서 막대가 차지하는 비율. 나머지가 이웃과의 사이가 된다. 회원 앱
  /// `전체` 그래프의 12/26 과 같은 몫이다.
  static const double _fill = 0.46;

  /// 값이 아주 작아도 막대로 읽히는 최소 높이.
  static const double _minBarHeight = 3;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) {
      // 기록이 없는 칸은 0 짜리 막대가 아니라 그루터기다.
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: _fill,
          child: Container(
            height: 4,
            decoration: const BoxDecoration(
              color: OnCareColors.lineStrong,
              borderRadius: OnCareRadius.pillAll,
            ),
          ),
        ),
      );
    }
    final num total = parts.values.fold<num>(0, (num a, num b) => a + b);
    final double barHeight = math.max(
      (value / max).clamp(0.0, 1.0) * height,
      _minBarHeight,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        // 칸 폭을 다 채우면 막대가 서로 붙어 한 덩어리로 보인다 — 어디까지가
        // 한 주인지 눈으로 셀 수 있어야 한다.
        child: FractionallySizedBox(
          widthFactor: _fill,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: OnCareRadius.xs),
            child: SizedBox(
              height: barHeight,
              child: total <= 0
                  ? ColoredBox(color: kBurnColor)
                  : Column(
                      // 가로로 늘려야 한다 — 가운데 정렬(기본값)이면 조각마다
                      // 폭이 0 이 되어 막대가 통째로 사라진다.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // 위에서부터 스트레칭·근력·유산소 순으로 쌓는다 —
                        // 바닥이 늘 유산소라 주끼리 견줄 때 기준이 흔들리지
                        // 않는다.
                        for (final ExerciseKind k
                            in ExerciseKind.values.reversed)
                          Expanded(
                            flex: ((parts[k] ?? 0) * 100).round().clamp(
                              0,
                              1 << 30,
                            ),
                            child: ColoredBox(color: kindColor(k)),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 소모 칼로리 도넛. 목표를 넘기면 한 바퀴를 넘어 계속 돈다. 가운데에 값과
/// 목표를 두 줄로 적는다 (#1127).
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.ratio,
    required this.center,
    required this.unit,
    this.caption = '',
    this.startIcon,
  });

  final double ratio;

  /// 값 **위**에 얹는 회색 머리 — 이 링이 무엇을 재는지 (회원 앱 #1352). 비면
  /// 그리지 않는다. 불꽃 기호만으로는 12시의 그림이 소모 칼로리를 뜻하는지 알
  /// 수 없다.
  final String caption;

  final String center;
  final String unit;

  /// 12시 방향 링 머리에 얹을 기호. null 이면 그리지 않는다.
  final IconData? startIcon;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double stroke = size.width * 0.13;
    final double r = size.width / 2 - stroke / 2;
    paintRing(canvas, c, r, stroke, ratio, kBurnColor, startIcon: startIcon);
    // 안쪽 구멍의 지름. 세 줄 다 이 폭 안에 들어간다.
    final double inner = (r - stroke / 2) * 1.75;
    // 머리 → 값 → 목표 순으로 쌓아 **구멍 한가운데**에 세운다 (회원 앱 #1352).
    // 예전에는 두 줄을 중심에서 각각 -0.09 · +0.10 만큼 밀어 놓았는데, 그
    // 자리는 두 줄일 때만 맞는 값이라 머리줄이 붙으면 묶음이 아래로 쏠린다.
    // 이제는 세 줄의 실제 높이를 재서 묶음째 가운데로 옮긴다.
    final TextStyle minor = OnCareTypography.strong(OnCareTypography.caption);
    _paintCenteredLines(canvas, c, <TextPainter>[
      if (caption.isNotEmpty)
        _layout(
          caption,
          size.width * 0.085,
          minor,
          OnCareColors.textTertiary,
          inner,
        ),
      _layout(
        center,
        size.width * 0.2,
        OnCareTypography.numeric(OnCareTypography.display),
        OnCareColors.textPrimary,
        inner,
      ),
      _layout(
        unit,
        size.width * 0.105,
        minor,
        OnCareColors.textTertiary,
        inner,
      ),
    ], gap: size.width * 0.012);
  }

  TextPainter _layout(
    String s,
    double size,
    TextStyle role,
    Color color,
    double maxWidth,
  ) {
    TextPainter at(double fontSize) => TextPainter(
      text: TextSpan(
        text: s,
        // 캔버스에 직접 그리는 글자는 테마를 타지 않는다 — 역할 스타일(앱 폰트
        // 포함)을 손으로 붙여 준다. 기본 폰트로 떨어지면 웹에서 두부(□)로
        // 나온다 (회원 앱 #1352). 크기는 도넛 지름을 따른다.
        style: role.copyWith(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final TextPainter tp = at(size);
    // 도넛 **안**에 들어가야 한다. 넘치면 그만큼 글자를 줄인다 — 링 밖으로
    // 삐져나온 글씨는 어느 링의 값인지 알려 주지 못한다. (#1127)
    if (tp.width > maxWidth) return at(size * (maxWidth / tp.width));
    return tp;
  }

  /// [lines] 를 [center] 기준으로 가로·세로 모두 가운데에 쌓아 그린다.
  void _paintCenteredLines(
    Canvas canvas,
    Offset center,
    List<TextPainter> lines, {
    required double gap,
  }) {
    if (lines.isEmpty) return;
    final double total =
        lines.fold<double>(0, (double a, TextPainter tp) => a + tp.height) +
        gap * (lines.length - 1);
    double y = center.dy - total / 2;
    for (final TextPainter tp in lines) {
      tp.paint(canvas, Offset(center.dx - tp.width / 2, y));
      y += tp.height + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.ratio != ratio ||
      old.center != center ||
      old.unit != unit ||
      old.caption != caption;
}

/// 막대 뒤에 까는 자 — 가로 눈금선 셋과 달이 바뀌는 자리의 세로 파선.
///
/// 회원 앱 운동 탭 `전체` 그래프의 `_ChartGridPainter` 와 같은 값·같은 규칙이다.
/// 데이터가 아니라 데이터를 읽을 기준이라, 목표선보다도 뒤에 깔린다.
class _ChartGridPainter extends CustomPainter {
  _ChartGridPainter({required this.count, required this.monthBreaks});

  /// 칸 개수. 달 경계 자리를 재는 데 쓴다.
  final int count;

  /// 달이 바뀌는 칸의 인덱스.
  final List<int> monthBreaks;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = OnCareColors.lineSubtle
      ..strokeWidth = 1;
    for (final double f in <double>[0, 0.5, 1]) {
      final double y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    if (count <= 0) return;
    final double step = size.width / count;
    final Paint dash = Paint()
      ..color = OnCareColors.lineStrong
      ..strokeWidth = 1;
    for (final int i in monthBreaks) {
      final double x = step * i;
      for (double y = 0; y < size.height; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridPainter old) =>
      old.count != count || old.monthBreaks != monthBreaks;
}

/// 유형별 주간 목표를 크기 순으로 겹친 세 링.
class _GoalRingsPainter extends CustomPainter {
  _GoalRingsPainter(this.ratios);

  final List<double> ratios;

  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    final double hole = radius * 0.22;
    final double stroke = (radius - _gap * 2 - hole) / 3;
    double r = radius - stroke / 2;
    for (int i = 0; i < ratios.length; i++) {
      final ExerciseKind kind = ExerciseKind.values[i];
      paintRing(
        canvas,
        c,
        r,
        stroke,
        ratios[i],
        kindColor(kind),
        startIcon: ringStartIcon(kind),
      );
      r -= stroke + _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _GoalRingsPainter old) => old.ratios != ratios;
}

/// 한 바퀴를 넘긴 원호가 **다시 도는 몫**(0 이상 1 미만).
///
/// 넘친 몫을 1 에서 자르면 두 바퀴를 넘긴 순간(209%, 300% …) 끝이 12시로
/// 되돌아가, 그 자리에 고정으로 얹는 유형 기호 아래 캡 표시가 숨는다 —
/// 도넛이 그냥 꽉 찬 원으로만 보인다. 자르지 말고 **바퀴마다 감아 돌린다**
/// (#1178). 209% 면 두 번째 바퀴의 9% 지점, 200%·300% 면 12시가 맞다.
double ringOverflowTurn(double ratio) {
  if (!ratio.isFinite) return 0;
  return ratio - ratio.floorToDouble();
}

/// 부동소수점 오차를 감안한 허용 오차 (회원 앱 #1462).
const double _kRingMultipleEpsilon = 1e-6;

/// [filled] 가 목표의 정확한 양의 정수 배(1, 2, 3 …)에 아주 가까운가.
///
/// 이 자리에서는 원호 끝이 12시의 고정 시작 기호와 겹친다 — 캡 그림자와
/// 진행 끝 `>` 기호를 여기 또 그리면 검은 얼룩과 아이콘 중복으로 보인다
/// (회원 앱 #1462). 0(아직 시작 전)은 배수로 치지 않는다.
bool isAtRingMultiple(double filled) {
  if (!filled.isFinite || filled < 1 - _kRingMultipleEpsilon) return false;
  final double nearest = filled.roundToDouble();
  return nearest >= 1 && (filled - nearest).abs() <= _kRingMultipleEpsilon;
}

/// 링 하나 — 트랙 + 채운 호. 목표를 넘기면 한 바퀴를 넘어 이어 그리고, 겹친
/// 끝 아래에 그림자를 깔아 어디서 멈췄는지 보이게 한다. 그림자는 그 링의
/// 두께로 잘라 밖으로 번지지 않는다.
///
/// [startIcon] 을 주면 12시에 흰 기호를 얹는다 — 이 링이 무엇인지와 어디서
/// 출발했는지를 말한다. 원호의 **끝**에는 얇은 `>` 를 얹어 어디까지 왔는지와
/// 어느 쪽으로 도는지를 함께 짚는다.
void paintRing(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double ratio,
  Color color, {
  IconData? startIcon,
}) {
  final Rect rect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      // 흰 카드 위 트랙 — 불투명 값이라 한 바퀴 넘긴 원호 아래로 비치지 않는다.
      ..color = OnCareColors.onWhite(color, OnCareAlpha.medium),
  );
  double capAngle = -math.pi / 2;
  final Paint arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..color = color;
  // 정확한 목표 배수(100%, 200% …)에서는 캡 그림자와 끝 `>` 를 그리지 않는다
  // (회원 앱 #1462) — 끝이 12시 기호와 겹쳐 검은 얼룩과 기호 둘로 보인다.
  final bool atMultiple = isAtRingMultiple(ratio);
  if (ratio >= 1 - _kRingMultipleEpsilon) {
    // 한 바퀴는 **끝이 없는 원**으로. 2π 원호에 둥근 끝을 주면 시작과 끝의
    // 캡이 같은 자리에 겹쳐 혹처럼 튀어나온다.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    final double over = atMultiple ? 0 : ringOverflowTurn(ratio);
    capAngle = -math.pi / 2 + math.pi * 2 * over;
    if (!atMultiple) {
      _paintCapShadow(canvas, center, radius, stroke, capAngle);
      if (over > 0) {
        canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * over, false, arc);
      }
    }
  } else if (ratio > 0) {
    capAngle = -math.pi / 2 + math.pi * 2 * ratio;
    _paintCapShadow(canvas, center, radius, stroke, capAngle);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * ratio, false, arc);
  }
  if (ratio > 0 && !atMultiple) {
    _paintCapChevron(canvas, center, radius, stroke, capAngle);
  }
  // 유형 기호는 12시에 고정한다 — 링이 한 바퀴를 넘겨 겹쳐도 가려지지 않게
  // 맨 위에 그린다.
  if (startIcon != null) {
    _paintStartIcon(canvas, center, radius, stroke, startIcon);
  }
}

/// 원호의 **끝(캡)** 아래에 깔 그림자. 넓고 흐린 것 위에 좁고 진한 것을 겹쳐
/// 찍어, 끝이 아래 트랙(또는 한 바퀴 돈 같은 색 원)에 묻히지 않게 한다.
///
/// 그리기 전에 캔버스를 **그 링의 두께**로 자른다 — 자르지 않으면 흐린
/// 가장자리가 링 밖으로 번져 도넛 주위에 얼룩이 남는다.
void _paintCapShadow(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double capAngle,
) {
  final Path ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: radius + stroke / 2))
    ..addOval(Rect.fromCircle(center: center, radius: radius - stroke / 2));
  final Offset cap =
      center + Offset(math.cos(capAngle), math.sin(capAngle)) * radius;
  canvas
    ..save()
    ..clipPath(ring)
    // 두 겹으로 깐다. 넓고 흐린 것이 링 위에 얹힌 느낌을 만들고, 좁고 진한
    // 것이 끝의 위치를 못 박는다. 가장 연한 링(스트레칭) 위에서도 보여야
    // 하므로 진하고 넓게 둔다. (회원 앱 #1161 과 같은 값)
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowOuterSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowOuterAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowOuterBlur,
        ),
    )
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowInnerSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowInnerAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowInnerBlur,
        ),
    )
    ..restore();
}

/// 원호의 **끝**에 얹는 얇고 작은 흰 `>`. 어디까지 왔는지와 어느 쪽으로 도는지를
/// 함께 짚는다. 링이 너무 얇으면 기호가 링을 다 덮으므로 그리지 않는다.
void _paintCapChevron(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double angle,
) {
  final double arm = stroke * 0.16;
  if (arm < 1.4) return;
  final Offset at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    // 접선 방향으로 눕힌다 — 시계 방향으로 도는 원호에서는 각도 + 90도다.
    ..rotate(angle + math.pi / 2)
    ..drawPath(
      Path()
        ..moveTo(-arm * 0.55, -arm)
        ..lineTo(arm * 0.55, 0)
        ..lineTo(-arm * 0.55, arm),
      Paint()
        ..color = OnCareColors.textOnFill
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(stroke * 0.07, 1)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..restore();
}

/// 링 12시에 흰 기호를 얹는다. 링 두께 안에 들어가도록 두께에 맞춰 줄인다.
void _paintStartIcon(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  IconData icon,
) {
  final double glyph = stroke * 0.78;
  if (glyph < 6) return;
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: glyph,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: OnCareColors.textOnFill,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final Offset at = center + const Offset(0, -1) * radius;
  tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
}
