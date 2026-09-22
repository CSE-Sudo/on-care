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
///  * 웹 넓은 화면 전용 3열: 달성률 도넛(맨 왼쪽) | `오늘 섭취 칼로리` → 큰 숫자
///    `값 / 목표 kcal` | **탄·단·지 진행 바 세 줄**(위아래). 회원 앱 `오늘`
///    카드의 구분선 아래 세 칸과 같은 것이다(#2156). 초과분은 라벨 오른쪽에
///    `+12g` 로 작게 빨간 글씨.
///  * 나트륨·당류는 없다. 회원 앱이 두 지표를 그래프에서 내리고 AI 맞춤 조언이
///    말로 알려 주게 했다(#1986) — 회원 화면에 없는 경고 막대를 트레이너만 보면
///    같은 하루를 두 사람이 다른 그림으로 이야기한다.
///  * 색은 **목표 안쪽 = 트레이너 메인 색(`brand.statusWithinGoal`),
///    초과 = 빨강** 하나의 규칙이다. 초록은 쓰지 않는다 — "정상" 으로 읽혀서
///    목표에 한참 못 미친 날까지 괜찮다고 말한다(회원 앱 #1070).
///
/// 목표값은 **회원의 목표**다 — 건강 프로필([MemberHealthProfile])의 하루 목표를
/// 읽고, 비어 있으면 회원 앱 기본값(`UserProfile.defaultDaily*`)을 쓴다
/// ([clientDietGoalsOf]).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 앱 `UserProfile` 의 기본 목표와 같은 값. 칼로리·나트륨·당류는
/// `trainer_client.dart` 가 이미 들고 있다(로스터 카드도 같은 값을 본다).
const int carbsTargetG = 275;
const int proteinTargetG = 100;
const int fatTargetG = 55;

/// 고객의 하루 식단 목표 한 벌.
typedef ClientDietGoals = ({int calories, int carbsG, int proteinG, int fatG});

/// [profile] 의 하루 식단 목표. 비어 있는 칸은 회원 앱 기본값이다 — 회원 앱
/// `UserProfile.effectiveDaily*` 와 같은 규칙이라, 회원이 자기 폰에서 초과라고
/// 본 날이 트레이너 화면에서도 초과다(#2156). 프로필을 아직 못 읽었으면
/// ([profile] 이 null) 전부 기본값이다.
ClientDietGoals clientDietGoalsOf(MemberHealthProfile? profile) => (
  calories: profile?.dailyCalories ?? calorieTargetKcal,
  carbsG: profile?.dailyCarbsG ?? carbsTargetG,
  proteinG: profile?.dailyProteinG ?? proteinTargetG,
  fatG: profile?.dailyFatG ?? fatTargetG,
);

/// 영양 요약 카드의 기준 높이. `오늘`·`이번 주`·`전체` 세 화면이 함께 쓴다 —
/// 기간 토글을 눌렀을 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
/// 최소 높이라 글자 배율이 커지면 셋이 함께 커진다. (회원 앱 #1124)
const double kClientNutritionCardHeight = 240;

/// 칼로리 칸의 폭 — 콘텐츠 고유 치수. 좁은 카드에서는 [_infoColumnWidthNarrow].
const double _infoColumnWidth = 240;
const double _infoColumnWidthNarrow = 200;

/// 탄단지 진행 바 칸은 남는 폭을 쓰되 이만큼에서 멈춘다 — 넓은 화면에서 바가
/// 끝없이 늘어나면 값과 라벨이 서로 멀어져 한 줄로 읽히지 않는다.
const double _macroColumnMaxWidth = 360;

/// 탄단지 칸이 이보다 좁아지면 한 줄(라벨 · 값/목표)이 넘친다.
const double _macroColumnMinWidth = 160;

/// 달성률 도넛의 지름.
const double _donutDimension = 136;

/// 달성률 도넛의 선 굵기.
const double _donutStroke = 12;

/// 도넛 | 칼로리 | 탄단지 세 칸 사이의 간격. 넓은 카드는 [_columnGapWide],
/// 좁은 카드는 [_columnGapNarrow] 다. 한 카드 안에서는 둘 다 같은 값을 써서
/// 리듬이 고르게 읽힌다.
const double _columnGapWide = OnCareSpacing.s40;
const double _columnGapNarrow = OnCareSpacing.s24;

/// 이 폭부터 넓은 카드다 — 1440 화면의 회원 상세(카드 안쪽 약 716)가 여기
/// 든다. 1280 화면(약 556)은 좁은 카드다.
const double _wideCardWidth = 680;

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

/// 오늘 섭취 칼로리 + 탄단지. 카드는 **한 장**이다.
class NutritionSummaryCard extends StatelessWidget {
  /// Creates the summary for [client] against the goals in [profile].
  const NutritionSummaryCard({super.key, required this.client, this.profile});

  /// 오늘 합계를 들고 있는 고객.
  final TrainerClient client;

  /// 목표를 읽을 건강 프로필. 아직 못 읽었으면 null 이고 기본값으로 그린다.
  final MemberHealthProfile? profile;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ClientDietGoals goals = clientDietGoalsOf(profile);

    final _Item calories = _Item(
      label: l.metricCalories,
      value: formatNumber(client.calories),
      goal: formatNumber(goals.calories),
      unit: 'kcal',
      current: client.calories,
      target: goals.calories,
    );
    final List<_Item> macros = <_Item>[
      _Item(
        label: l.metricCarbs,
        value: formatNumber(client.carbsG),
        goal: formatNumber(goals.carbsG),
        unit: 'g',
        current: client.carbsG,
        target: goals.carbsG,
      ),
      _Item(
        label: l.metricProtein,
        value: formatNumber(client.proteinG),
        goal: formatNumber(goals.proteinG),
        unit: 'g',
        current: client.proteinG,
        target: goals.proteinG,
      ),
      _Item(
        label: l.metricFat,
        value: formatNumber(client.fatG),
        goal: formatNumber(goals.fatG),
        unit: 'g',
        current: client.fatG,
        target: goals.fatG,
      ),
    ];
    final Color calorieColor = _statusColor(context, calories);
    // 오늘·이번 주·전체가 같은 크기여야 토글을 눌러도 화면이 튀지 않는다.
    // 글자 배율이 커지면 셋 다 함께 커진다 — 최소 높이라 넘치지 않는다.
    return ConstrainedBox(
      key: const Key('client-nutrition-summary-card'),
      constraints: const BoxConstraints(minHeight: kClientNutritionCardHeight),
      child: AppCard(
        // 웹 화면 3열: 도넛 | 칼로리 | 탄단지(위아래). 세 칸 덩어리를
        // `Center` 가 카드 한가운데 두어 좌우 여백이 정확히 같다.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            // 폭에 따라 간격과 칼로리 칸만 바뀌고, 탄단지 칸이 남는 폭을
            // 가져간다(최대 [_macroColumnMaxWidth]). 세 칸 덩어리는 카드
            // 가운데에 놓인다 — 1280 화면에서도 글자를 줄이지 않는다(#2156).
            final bool wide = c.maxWidth >= _wideCardWidth;
            final double gap = wide ? _columnGapWide : _columnGapNarrow;
            final double infoWidth = wide
                ? _infoColumnWidth
                : _infoColumnWidthNarrow;
            final double fixed = _donutDimension + gap * 2 + infoWidth;
            final double contentWidth = math.min(
              c.maxWidth,
              fixed + _macroColumnMaxWidth,
            );
            final Widget row = Row(
              children: <Widget>[
                // 1열 — 달성률 도넛.
                _CalorieDonut(calories: calories, color: calorieColor),
                SizedBox(width: gap),
                // 2열 — 칼로리.
                SizedBox(
                  width: infoWidth,
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
                    ],
                  ),
                ),
                SizedBox(width: gap),
                // 3열 — 탄·단·지 진행 바를 위에서부터. 회원 앱 `오늘` 카드의
                // 세 칸과 같은 것이다(#2156) — 글자만 적으면 목표에 얼마나
                // 닿았는지를 트레이너가 숫자로 나눠 봐야 한다. 폭을 고정해 바
                // 길이를 제한한다.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final _Item m in macros) ...<Widget>[
                        _MacroProgressItem(item: m),
                        if (m != macros.last)
                          const SizedBox(height: OnCareSpacing.s16),
                      ],
                    ],
                  ),
                ),
              ],
            );
            // 탄단지 칸까지 최소 폭이 안 나오는 아주 좁은 카드는 전체를 비례
            // 축소한다 — 넘치지 않게 하는 안전장치일 뿐 좁은 화면 설계는 아니다.
            if (c.maxWidth < fixed + _macroColumnMinWidth) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: fixed + _macroColumnMinWidth,
                  child: row,
                ),
              );
            }
            return Center(
              child: SizedBox(width: contentWidth, child: row),
            );
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

/// 탄·단·지 한 칸 — 라벨(+초과분) · 값/목표 · 진행 바. 회원 앱 `오늘` 카드의
/// `_MacroProgressItem` 과 같은 구성·같은 글자 규격이다(#2156).
class _MacroProgressItem extends StatelessWidget {
  const _MacroProgressItem({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 넘긴 항목은 빨강 (회원 앱 #890). 초과가 아닌 쪽은 메인 색이다.
    final Color color = _statusColor(context, item);
    final TextStyle captionStrong = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    return Column(
      key: Key('client-nutrition-macro-${item.label}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 라벨과 수치를 **한 줄**에 둔다 — 왼쪽이 라벨(+초과분), 오른쪽이
        // `값 / 목표`. 두 줄로 쌓으면 세 칸이 카드 높이를 넘겨 도넛·칼로리 칸과
        // 균형이 깨진다(#2156).
        //
        // 좁은 카드·큰 글씨에서는 둘이 반씩 나눠 갖고 넘치는 쪽이 줄어든다 —
        // 라벨은 말줄임, 수치는 글자 크기를 줄인다(끝자리가 잘리면 안 된다).
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: item.label),
                    // 초과분은 라벨 오른쪽에 빨간 글씨로. 초과가 아닐 때는
                    // 아무것도 붙이지 않는다 — 체크 표시를 두면 목표에 한참 못
                    // 미친 날도 "정상" 이라고 말한다. (회원 앱 #1070)
                    if (item.isOverGoal)
                      TextSpan(
                        text: ' +${item.difference}${item.unit}',
                        style: captionStrong.copyWith(
                          color: OnCareColors.danger,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: captionStrong.copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: item.value,
                        style: tokens
                            .text(
                              OnCareTypography.numeric(
                                OnCareTypography.strong(
                                  OnCareTypography.bodySmall,
                                ),
                              ),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      TextSpan(
                        text: ' / ${item.goal}${item.unit}',
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppProgressBar(
          key: Key('client-nutrition-macro-progress-${item.label}'),
          value: item.gaugeValue,
          color: color,
        ),
      ],
    );
  }
}
