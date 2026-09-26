import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 번호가 붙은 단계 표시 — `① → ② → ③`.
///
/// AI 코칭의 추천안 만들기와 리포트 탭의 주간 리포트 작성이 **같은 형태**를
/// 쓴다. 두 화면 모두 "여러 단계를 거쳐 회원에게 보낼 무언가를 만든다"는
/// 같은 일을 하므로, 진행 표시가 다르면 같은 일을 다르게 배운 것처럼
/// 보인다(#2232).
///
/// 이미 지나온 단계는 눌러서 되돌아갈 수 있다 — [maxReachedStage] 보다 앞선
/// 단계만 열려 있다.
class ProgressStepper extends StatelessWidget {
  /// Creates the stepper.
  const ProgressStepper({
    super.key,
    required this.labels,
    required this.stage,
    required this.maxReachedStage,
    required this.onStageTap,
    required this.semanticsLabel,
    this.keyPrefix = 'stage',
    this.skipped = const <int>{},
    this.skippedLabel = '',
  });

  /// 단계 이름. 로케일을 따르므로 호출자가 만들어 넘긴다. 칸 수는 받은
  /// 만큼이다(#2223) — 표시줄이 몇 칸인지 스스로 정하지 않는다.
  final List<String> labels;

  /// 지금 서 있는 단계(0-based).
  final int stage;

  /// 지금까지 가 본 가장 먼 단계. 여기까지만 눌러서 돌아갈 수 있다.
  final int maxReachedStage;

  /// 지나온 단계를 눌렀을 때.
  final ValueChanged<int> onStageTap;

  /// 스크린 리더가 읽을 이 묶음의 이름.
  final String semanticsLabel;

  /// 단계 위젯 키의 앞자리 — 화면마다 다른 키를 쓴다.
  final String keyPrefix;

  /// 이번 흐름에서 밟지 않는 칸. 자리를 지우지 않고 흐리게 남겨
  /// [skippedLabel] 을 붙인다 — 칸이 사라지면 흐름 자체가 짧아진 것처럼
  /// 보인다(#2223).
  final Set<int> skipped;

  /// 건너뛴 칸 아래에 붙는 말.
  final String skippedLabel;

  /// 번호 원의 지름.
  static const double _circle = OnCareSize.avatarMedium;

  /// 원 하나가 차지하는 칸의 폭 — 원 지름 + 원 사이 간격. (#2219)
  ///
  /// 칸 폭이 곧 **원 중심 사이의 거리**다. 화면 폭을 n등분하면 창이 넓어질수록
  /// 원들이 좌우 끝으로 멀어진다. 단계 표시는 "몇 걸음 중 몇 번째"를 읽는 작은
  /// 눈금이라, 폭과 무관하게 같은 간격으로 모여 가운데에 선다.
  static const double _stepWidth =
      _circle + OnCareSpacing.s48 + OnCareSpacing.s32;

  bool _open(int index) => index <= maxReachedStage && !skipped.contains(index);

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      // 이름을 다는 것만으로는 스크린리더에 닿지 않는다 — 아래 단계들이 저마다
      // 노드를 만들어, 기본값(`container: false`)이면 얹을 자리가 없어 이름이
      // 그대로 사라진다. 묶음 노드를 만들어 이름을 그 위에 달고, 단계는
      // 각자의 노드로 남겨 하나씩 짚어 갈 수 있게 둔다.
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 칸을 다 늘어놓을 폭이 없으면(아주 좁은 창) 그만큼 좁힌다 —
          // 고정 간격을 지키느라 표시줄이 화면 밖으로 넘치지는 않는다.
          final double available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _stepWidth * labels.length;
          final double stepWidth = math.min(
            _stepWidth,
            available / labels.length,
          );
          return Center(
            child: SizedBox(
              width: stepWidth * labels.length,
              child: Stack(
                children: <Widget>[
                  // 첫 원의 가운데에서 마지막 원의 가운데까지만 잇는 가는 선.
                  // 원이 불투명해 선은 원 사이에서만 보인다.
                  Positioned(
                    top: (_circle - OnCareSize.hairline) / 2,
                    left: stepWidth / 2,
                    right: stepWidth / 2,
                    child: const ColoredBox(
                      color: OnCareColors.lineSubtle,
                      child: SizedBox(height: OnCareSize.hairline),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int index = 0; index < labels.length; index++)
                        SizedBox(
                          width: stepWidth,
                          child: _step(tokens, labels[index], index),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _step(OnCareTokens tokens, String label, int index) {
    final bool current = index == stage;
    final bool isSkipped = skipped.contains(index);
    return InkWell(
      key: ValueKey<String>('$keyPrefix-$index'),
      borderRadius: OnCareRadius.smAll,
      onTap: _open(index) ? () => onStageTap(index) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: _circle,
            height: _circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current ? tokens.brand.primary : OnCareColors.surfaceInput,
              border: current
                  ? null
                  : Border.all(
                      color: isSkipped
                          ? OnCareColors.lineSubtle
                          : OnCareColors.lineStrong,
                    ),
            ),
            // 건너뛴 칸은 번호 대신 가로줄을 둔다 — 밟지 않았을 뿐 자리는
            // 그대로라는 표시다(#2223).
            child: isSkipped
                ? const Icon(
                    Icons.remove_rounded,
                    size: OnCareSize.iconSmall,
                    color: OnCareColors.textTertiary,
                  )
                : Text(
                    '${index + 1}',
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.label))
                        .copyWith(
                          color: current
                              ? OnCareColors.textOnFill
                              : OnCareColors.textSecondary,
                        ),
                  ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: tokens
                .text(
                  current
                      ? OnCareTypography.strong(OnCareTypography.caption)
                      : OnCareTypography.caption,
                )
                .copyWith(
                  color: current
                      ? OnCareColors.textPrimary
                      : OnCareColors.textTertiary,
                ),
          ),
          if (isSkipped)
            Text(
              skippedLabel,
              key: ValueKey<String>('$keyPrefix-skipped-$index'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
        ],
      ),
    );
  }
}
