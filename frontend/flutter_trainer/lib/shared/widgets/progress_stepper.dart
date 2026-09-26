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
  });

  /// 단계 이름. 로케일을 따르므로 호출자가 만들어 넘긴다.
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

  /// 번호 원의 지름.
  static const double _circle = OnCareSize.avatarMedium;

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
          // 단계는 폭을 똑같이 나눠 갖고 저마다 자기 칸의 가운데에 선다.
          // 잇는 선은 첫 칸의 가운데에서 마지막 칸의 가운데까지 — 칸의 절반
          // 만큼 양쪽을 비우면 선이 원의 한가운데를 지난다.
          final double inset = constraints.maxWidth / labels.length / 2;
          return Stack(
            children: <Widget>[
              Positioned(
                top: (_circle - OnCareSize.hairline) / 2,
                left: inset,
                right: inset,
                child: const ColoredBox(
                  color: OnCareColors.lineSubtle,
                  child: SizedBox(height: OnCareSize.hairline),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int index = 0; index < labels.length; index++)
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _step(tokens, labels[index], index),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _step(OnCareTokens tokens, String label, int index) {
    final bool current = index == stage;
    return InkWell(
      key: ValueKey<String>('$keyPrefix-$index'),
      borderRadius: OnCareRadius.smAll,
      onTap: index <= maxReachedStage ? () => onStageTap(index) : null,
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
                  : Border.all(color: OnCareColors.lineStrong),
            ),
            child: Text(
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
        ],
      ),
    );
  }
}
