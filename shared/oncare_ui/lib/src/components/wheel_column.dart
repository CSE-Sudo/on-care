import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 휠 여러 칸을 가로지르는 가운데 띠 — 고른 값이 서는 자리. (#2071, #2545)
///
/// 칸마다 띠를 두지 않고 한 줄로 긋는다. 어느 칸을 굴려도 읽는 높이가 같다.
/// 시·분·초 휠과 세트·횟수·중량 휠이 같은 띠를 써야, 유형을 바꿔도 시트의
/// 모양이 그대로다.
class WheelBand extends StatelessWidget {
  const WheelBand({super.key, required this.itemExtent, required this.child});

  final double itemExtent;

  /// 띠 위에 서는 칸들.
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned.fill(
        child: Center(
          child: Container(
            height: itemExtent,
            decoration: const BoxDecoration(
              color: OnCareColors.surfaceInput,
              borderRadius: OnCareRadius.mdAll,
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// 휠 한 칸 — `0..count-1` 번째 값을 굴린다. 칸에 무엇이 적히는지는
/// [labelAt] 이 정한다.
class WheelColumn extends StatelessWidget {
  const WheelColumn({
    super.key,
    required this.controller,
    required this.count,
    required this.labelAt,
    required this.unit,
    required this.itemExtent,
    required this.onSelectedItemChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) labelAt;

  /// 숫자 뒤에 붙는 단위. 읽어 주는 쪽에도 이 말이 간다 — 휠은 숫자만
  /// 보이므로, 이 이름이 없으면 `30` 이 무엇의 30인지 화면 밖에서는 모른다.
  final String unit;
  final double itemExtent;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      label: unit,
      container: true,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemExtent,
        // 칸에 맞춰 세운다. 이것이 없으면 기본 물리(iOS 는 bouncing)가 먹어
        // 칸과 칸 **사이**에 멎는다 — 띠 안에 아무 값도 들어오지 않는다.
        // 감아 돌지는 않는다(`FixedExtentScrollPhysics` 의 기본): 10시간
        // 다음이 0시간이 되면 굴리다 지나친 값을 되짚기 어렵다.
        physics: const FixedExtentScrollPhysics(),
        // 굴릴 때마다가 아니라 칸에 선 뒤에 부른다.
        onSelectedItemChanged: onSelectedItemChanged,
        // 위아래로 멀어질수록 눕는다 — 지금 고른 값이 어느 칸인지가 이
        // 기울기로 읽힌다. 기본보다 좁게 감아 세 칸만 보이는 높이에서도
        // 가운데 칸이 평평하게 선다.
        diameterRatio: 1.4,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (BuildContext context, int index) => Center(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: labelAt(index),
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.titleMedium),
                    ).copyWith(color: OnCareColors.textPrimary),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
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
