import 'package:flutter/material.dart';

import 'package:oncare_ui/oncare_ui.dart';

/// 운동 탭 카드의 운동 한 줄 — `[유형] 이름 · 운동량 … [강도]`. (#2507)
///
/// PT 카드와 직접 기록한 운동 카드가 같은 줄을 쓴다. 같은 화면에서 같은
/// 값(유형·강도)이 카드마다 다른 자리에 있으면 회원이 매번 다시 읽어야 한다.
///
/// - [typeLabel]: 파란 유형 태그. 모르면 비운다 — 없는 값을 지어내지 않는다.
/// - [trailing]: 오른쪽 끝(강도 태그). 강도는 늘 오른쪽이다.
class ExerciseRecordLine extends StatelessWidget {
  const ExerciseRecordLine({
    super.key,
    required this.name,
    this.amount = '',
    this.typeLabel,
    this.trailing = const <Widget>[],
  });

  final String name;

  /// `4세트 · 10회 · 40kg`·`30분`. 비었으면 이름만 적는다.
  final String amount;

  final String? typeLabel;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final String? type = typeLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (type != null && type.isNotEmpty) ...<Widget>[
                  AppTag(label: type, tone: AppTagTone.brand),
                  const SizedBox(width: OnCareSpacing.s8),
                ],
                // 말줄임이 아니라 줄바꿈이다 — `벤치프레스 · 4세트 · 10회
                // · 40kg` 이 잘리면 몇 회를 몇 kg 로 했는지가 사라진다(#766).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: OnCareSpacing.s2),
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: name,
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.bodySmall,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                          if (amount.isNotEmpty)
                            TextSpan(
                              text: ' · $amount',
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s8),
            Wrap(
              spacing: OnCareSpacing.s4,
              runSpacing: OnCareSpacing.s4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: trailing,
            ),
          ],
        ],
      ),
    );
  }
}

/// 강도 한 값의 태그 — `보통`. 두 카드가 같은 모양으로 오른쪽 끝에 둔다.
/// "수행" 같은 말머리를 붙이지 않는다: 근력 줄은 세트·횟수·중량으로 이미 길어
/// 태그가 짧아야 한 줄에 남는다(#2507). 권한 강도만 `권장` 을 붙여 가른다.
Widget exerciseIntensityTag(String label, {Key? key, bool brand = false}) =>
    FittedBox(
      key: key,
      fit: BoxFit.scaleDown,
      child: AppTag(
        label: label,
        tone: brand ? AppTagTone.brand : AppTagTone.neutral,
      ),
    );
