/// 고객의 오늘 영양 요약 — **회원 앱 식단 탭 `오늘` 카드와 같은 한 장**이다.
/// (#698, #1166)
///
/// 예전에는 카드가 세 장이었다(칼로리+탄단지 / 나트륨 / 당류). 회원 앱은 한
/// 장이라 같은 하루를 회원과 트레이너가 다른 그림으로 봤다 — 회원이 "나트륨
/// 카드가 빨개요" 라고 말할 때 트레이너 화면에는 같은 자리가 없었다.
///
/// 두 앱은 서로 다른 Dart 패키지라 위젯을 그대로 가져올 수 없어 여기에 옮겼다.
/// 모양은 공용 규격(`oncare_ui`)을 쓰되 **구성과 규칙은 회원 앱을 따른다.**
///
///  * 웹 넓은 화면 전용 3열: `오늘 섭취 칼로리` → 큰 숫자 `값 / 목표 kcal` →
///    **탄·단·지 글자 세 줄**(막대 없음) | 나트륨·당류 세로 진행 바(위아래) |
///    달성률 도넛(맨 왼쪽). 칼로리가 무엇으로
///    채워졌는지가 그 숫자 바로 아래에서 읽혀야 한다. 초과분은 라벨
///    오른쪽에 `+1,429mg` 로 작게 빨간 글씨.
///  * 색은 **목표 안쪽 = 트레이너 메인 색(`brand.statusWithinGoal`),
///    초과 = 빨강** 하나의 규칙이다. 초록은 쓰지 않는다 — "정상" 으로 읽혀서
///    목표에 한참 못 미친 날까지 괜찮다고 말한다(회원 앱 #1070).
///
/// 목표값은 회원 앱 기본값과 같다(`UserProfile.defaultDaily*`). 회원이 자기
/// 목표를 바꿔도 트레이너 API 가 그 값을 주지 않아, 지금은 기본값으로 그린다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 앱 `UserProfile` 의 기본 목표와 같은 값. 칼로리·나트륨·당류는
/// `trainer_client.dart` 가 이미 들고 있다(로스터 카드도 같은 값을 본다).
const int carbsTargetG = 275;
const int proteinTargetG = 100;
const int fatTargetG = 55;

/// 영양 요약 카드의 기준 높이. `오늘`·`이번 주`·`전체` 세 화면이 함께 쓴다 —
/// 기간 토글을 눌렀을 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
/// 최소 높이라 글자 배율이 커지면 셋이 함께 커진다. (회원 앱 #1124)
const double kClientNutritionCardHeight = 240;

/// 정보(칼로리+탄단지) 칸의 고정 폭 — 콘텐츠 고유 치수.
const double _infoColumnWidth = 260;

/// 나트륨·당류 칸의 최대 폭 — 진행 바 길이를 여기서 제한한다. 폭 그대로
/// 늘어나게 두면 넓은 화면에서 바가 지나치게 길어진다.
const double _mineralColumnWidth = 260;

/// 달성률 도넛의 지름.
const double _donutDimension = 112;

/// 달성률 도넛의 선 굵기.
const double _donutStroke = 10;

/// 도넛 | 정보 | 나트륨·당류 세 칸 사이의 간격. 셋 다 같은 값을 써서
/// 리듬이 고르게 읽힌다.
const double _columnGap = OnCareSpacing.s24;

/// 세 칸 + 간격을 다 더한 콘텐츠 폭. 카드가 이보다 좁아지면 가운데
/// 정렬 대신 전체를 비례 축소해 넘침·경계 밖 렌더링을 막는다.
const double _contentWidth =
    _donutDimension + _columnGap * 2 + _infoColumnWidth + _mineralColumnWidth;

/// 한 지표의 표시값 한 벌.
class _Item {
  const _Item({
    required this.label,
    required this.value,
    required this.goal,
    required this.unit,
    required this.current,
    required this.target,
  });

  final String label;
  final String value;
  final String goal;
  final String unit;
  final num current;
  final num target;

  /// 목표 대비 실제 비율. **자르지 않는다** — 목표를 넘기면 1.0 을 넘는다.
  /// 달성률 라벨이 이 값을 적는다. 여기서 잘라 두면 목표를 260kcal 넘긴 날에도
  /// '100%' 라고 말해 바로 아래 문구와 어긋난다(#820).
  double get ratio => target <= 0 ? 0 : current / target;

  /// 게이지에 넣을 값. 링과 막대는 1.0 을 넘으면 눈금이 깨지므로 그릴 때만
  /// 자른다.
  double get gaugeValue => ratio.clamp(0.0, 1.0).toDouble();

  bool get isOverGoal => current > target;

  /// 목표까지 남은/넘은 양.
  String get difference => formatNumber((current - target).abs());
}

/// 오늘 섭취 칼로리 + 탄단지 + 나트륨·당류. 카드는 **한 장**이다.
class NutritionSummaryCard extends StatelessWidget {
  /// Creates the summary for [client].
  const NutritionSummaryCard({super.key, required this.client});

  /// 오늘 합계를 들고 있는 고객.
  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;

    final _Item calories = _Item(
      label: l.metricCalories,
      value: formatNumber(client.calories),
      goal: formatNumber(calorieTargetKcal),
      unit: 'kcal',
      current: client.calories,
      target: calorieTargetKcal,
    );
    final List<_Item> macros = <_Item>[
      _Item(
        label: l.metricCarbs,
        value: formatNumber(client.carbsG),
        goal: formatNumber(carbsTargetG),
        unit: 'g',
        current: client.carbsG,
        target: carbsTargetG,
      ),
      _Item(
        label: l.metricProtein,
        value: formatNumber(client.proteinG),
        goal: formatNumber(proteinTargetG),
        unit: 'g',
        current: client.proteinG,
        target: proteinTargetG,
      ),
      _Item(
        label: l.metricFat,
        value: formatNumber(client.fatG),
        goal: formatNumber(fatTargetG),
        unit: 'g',
        current: client.fatG,
        target: fatTargetG,
      ),
    ];
    final List<_Item> minerals = <_Item>[
      _Item(
        label: l.metricSodium,
        value: formatNumber(client.sodiumMg),
        goal: formatNumber(sodiumTargetMg),
        unit: 'mg',
        current: client.sodiumMg,
        target: sodiumTargetMg,
      ),
      _Item(
        label: l.metricSugar,
        value: formatNumber(client.sugarG),
        goal: formatNumber(sugarTargetG),
        unit: 'g',
        current: client.sugarG,
        target: sugarTargetG,
      ),
    ];

    final Color calorieColor = _statusColor(context, calories);
    // 오늘·이번 주·전체가 같은 크기여야 토글을 눌러도 화면이 튀지 않는다.
    // 글자 배율이 커지면 셋 다 함께 커진다 — 최소 높이라 넘치지 않는다.
    return ConstrainedBox(
      key: const Key('client-nutrition-summary-card'),
      constraints: const BoxConstraints(minHeight: kClientNutritionCardHeight),
      child: AppCard(
        // 넓은 웹 화면 전용 3열: 도넛 | 정보 | 나트륨·당류(위아래).
        // 세 칸 모두 고정 폭이고 사이 간격도 [_columnGap] 하나로 통일해
        // 리듬이 고르게 읽힌다. `Row` 는 내용 크기만큼만 차지하고
        // (`mainAxisSize.min`), 그 덩어리를 `Center` 가 카드 한가운데
        // 두어 좌우 여백이 정확히 같다. 좁은 화면(분할 패널 등)에 맞춰
        // 배치를 다시 짜지는 않지만, 카드가 [_contentWidth] 보다 좁아지면
        // 넘치는 대신 전체가 비례 축소된다 — 화면이 깨지지 않게 하는
        // 안전장치일 뿐 좁은 화면을 위한 설계는 아니다.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Widget row = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 1열 — 달성률 도넛.
                _CalorieDonut(calories: calories, color: calorieColor),
                const SizedBox(width: _columnGap),
                // 2열 — 칼로리 + 탄단지.
                SizedBox(
                  width: _infoColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.dietCalorieIntake,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: calories.value,
                                style: tokens
                                    .text(
                                      OnCareTypography.numeric(
                                        OnCareTypography.display,
                                      ),
                                    )
                                    .copyWith(color: calorieColor),
                              ),
                              TextSpan(
                                text: ' / ${calories.goal} ${calories.unit}',
                                style: tokens
                                    .text(OnCareTypography.label)
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                      // 탄단지는 칼로리 숫자 바로 아래에 둔다 — 칼로리가
                      // 무엇으로 채워졌는지가 그 숫자 아래에서 곧장 읽혀야
                      // 한다.
                      const SizedBox(height: OnCareSpacing.s12),
                      for (final _Item m in macros) ...<Widget>[
                        _MacroTextLine(item: m),
                        if (m != macros.last)
                          const SizedBox(height: OnCareSpacing.s4),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: _columnGap),
                // 3열 — 나트륨 위, 당류 아래. 폭을 고정해 바 길이를 제한한다.
                SizedBox(
                  width: _mineralColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final _Item m in minerals) ...<Widget>[
                        _MineralItem(item: m),
                        if (m != minerals.last)
                          const SizedBox(height: OnCareSpacing.s12),
                      ],
                    ],
                  ),
                ),
              ],
            );
            // 카드가 [_contentWidth] 보다 좁아지면 전체를 비례 축소한다 —
            // 카드 밖으로 요소가 벗어나지 않아야 하므로 스크롤이 아니라
            // `FittedBox` 다(이 파일의 칼로리 숫자·탄단지 줄과 같은 패턴).
            return c.maxWidth >= _contentWidth
                ? Center(child: row)
                : FittedBox(fit: BoxFit.scaleDown, child: row);
          },
        ),
      ),
    );
  }
}

/// 목표 안쪽이면 메인 색, 넘겼으면 빨강. 카드 전체가 이 한 규칙을 쓴다.
Color _statusColor(BuildContext context, _Item item) => item.isOverGoal
    ? OnCareColors.danger
    : context.oncare.brand.statusWithinGoal;

/// 칼로리 달성률 링. 한 바퀴에서 멈춘다 — 넘긴 양은 링이 그릴 수 없다.
///
/// [value] 는 0~1 로 자른 값이고, 숫자(`113%`)는 링 바깥에서 자르지 않고 적는다.
class NutritionCalorieRing extends StatelessWidget {
  /// Creates a ring filled to [value] with [color].
  const NutritionCalorieRing({
    super.key,
    required this.value,
    required this.color,
  });

  /// 채운 비율(0~1).
  final double value;

  /// 채운 호의 색.
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RingPainter(value: value.clamp(0.0, 1.0), color: color),
    child: const SizedBox.expand(),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(_donutStroke / 2);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _donutStroke
      ..color = OnCareColors.surfaceInput;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    final Paint fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _donutStroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

/// 칼로리 달성률 도넛. 링은 한 바퀴에서 멈추지만 숫자는 자르지 않는다.
class _CalorieDonut extends StatelessWidget {
  const _CalorieDonut({required this.calories, required this.color});

  final _Item calories;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SizedBox.square(
      dimension: _donutDimension,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: NutritionCalorieRing(
              key: const Key('client-nutrition-calorie-progress'),
              value: calories.gaugeValue,
              color: color,
            ),
          ),
          // 링은 지름이 고정이라 글자 배율이 커지면 안쪽 두 줄이 원을 넘어선다.
          // 원 안에 들어가도록 함께 줄인다.
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s20),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(calories.ratio * 100).round()}%',
                    style: tokens
                        .text(
                          OnCareTypography.numeric(OnCareTypography.display),
                        )
                        .copyWith(color: color),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    l.dietAchieveRate,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드 머리의 탄단지 한 줄 — `탄수화물 204 /275g`. 바 없이 글자만 쓴다.
class _MacroTextLine extends StatelessWidget {
  const _MacroTextLine({required this.item});

  final _Item item;

  /// 라벨이 차지하는 폭. `탄수화물`(네 글자)이 들어갈 만큼만 잡는다 — 값이
  /// 라벨 바로 옆에서 시작하면서도 세 줄의 숫자가 세로로 가지런하다. 글자
  /// 배율을 따라가야 큰 글씨에서 라벨이 잘리지 않는다. (회원 앱 #1149)
  static const double _labelWidth = 56;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle muted = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    return Row(
      key: Key('client-nutrition-macro-${item.label}'),
      children: <Widget>[
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(_labelWidth),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        const SizedBox(width: OnCareSpacing.s4),
        // 값은 라벨 바로 옆에서 시작한다. 글자 배율이 커지면 값부터 줄인다 —
        // 이 줄이 넘치면 카드 오른쪽의 도넛을 밀어낸다.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: item.value,
                    // 초과면 빨강 — 바가 없으니 색이 그 말을 대신한다.
                    // 세 항목이 각자 판단하므로 지방만 넘긴 날은 지방 줄만
                    // 빨개진다. (회원 앱 #890) 목표 안쪽은 메인 색의 한 단계
                    // 옅은 농담(탄단지 중간 단계와 같은 65%)이다 — 나트륨·당류
                    // 처럼 경고 지표가 아니라 또렷하게 두지 않는다.
                    style: tokens
                        .text(OnCareTypography.numeric(OnCareTypography.label))
                        .copyWith(
                          color: item.isOverGoal
                              ? OnCareColors.danger
                              : tokens.brand.macroProtein,
                        ),
                  ),
                  TextSpan(text: ' / ${item.goal}${item.unit}', style: muted),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// 아래 줄의 나트륨·당류 한 칸 — 라벨(+초과분) · 값/목표 · 진행 바.
///
/// 나트륨·당류는 탄단지와 달리 그 자체가 경고 지표라, 목표 안쪽일 때도 색이
/// 또렷하다(옅게 두지 않는다).
class _MineralItem extends StatelessWidget {
  const _MineralItem({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color color = _statusColor(context, item);
    final TextStyle captionStrong = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    return Column(
      key: Key('client-nutrition-mineral-${item.label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: item.label),
              // 초과분은 라벨 오른쪽에 빨간 글씨로. 초과가 아닐 때는 아무것도
              // 붙이지 않는다 — 체크 표시를 두면 목표에 한참 못 미친 날도
              // "정상" 이라고 말한다. (회원 앱 #1070)
              if (item.isOverGoal)
                TextSpan(
                  text: ' +${item.difference}${item.unit}',
                  style: captionStrong.copyWith(color: OnCareColors.danger),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: captionStrong.copyWith(color: OnCareColors.textPrimary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: item.value,
                  style: tokens
                      .text(OnCareTypography.numeric(OnCareTypography.label))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                TextSpan(
                  text: ' / ${item.goal}${item.unit}',
                  style: captionStrong.copyWith(
                    color: OnCareColors.textSecondary,
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppProgressBar(
          key: Key('client-nutrition-mineral-progress-${item.label}'),
          value: item.gaugeValue,
          color: color,
        ),
      ],
    );
  }
}
