import 'package:flutter/material.dart';

import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

/// 프로그램·리포트 탭 왼쪽 회원 열의 폭.
///
/// 분할 목록 폭([OnCareLayout.splitListWidth], 380)의 3분의 2를 4 배수로
/// 맞춘 값이다(380 − 128). 이 열은 회원을 고르는 자리일 뿐이라, 넓게 둘수록
/// 오른쪽 작업 영역(편집기·리포트)이 그만큼 좁아졌다.
const double clientPickerColumnWidth =
    OnCareLayout.splitListWidth -
    (OnCareSpacing.s48 + OnCareSpacing.s48 + OnCareSpacing.s32);

/// 회원 목록 카드 제목 옆 아이콘 — 두 탭이 같은 아이콘을 쓴다.
const IconData clientPickerHeaderIcon = Icons.people_rounded;

/// 회원 목록에 한 번에 보이는 행 수. 넘치면 목록 안에서 스크롤한다.
const int clientPickerVisibleRows = 5;

/// 회원 목록 한 줄 높이 — `이름 · 성별 · 나이` 와 목표 두 줄이 들어간다.
///
/// 밀도의 목록 행 최소 높이에 여유 16 을 더한 값이고, 접근성 글자 배율이
/// 올라가면 그만큼 함께 늘어난다(#995). 두 탭이 같은 높이를 쓴다.
double clientPickerRowHeight(BuildContext context) {
  final density = context.oncare.density;
  final double base = OnCareTypography.bodySmall.fontSize!;
  final scale = MediaQuery.textScalerOf(context).scale(base) / base;
  final extraScale = (scale - 1).clamp(0.0, 2.0);
  return density.listRowMin +
      OnCareSpacing.s16 +
      (density.listRowMin + OnCareSpacing.s8) * extraScale;
}

/// 프로그램·리포트 탭 왼쪽 목록의 회원 한 줄.
///
/// 아바타 옆 첫 줄에 이름과 `성별 · 나이` 를, 그 아래에 목표를 한 줄로 둔다.
/// 좁은 열에서도 넘치지 않도록 모든 글은 한 줄 말줄임이다. 고른 회원은 옅은
/// 브랜드 채움과 브랜드 테두리, 이름 굵기로 드러난다.
///
/// 행의 바닥에 [OnCareSpacing.s4] 간격을 포함하므로, 목록은 행 사이 간격을
/// 따로 두지 않고 [clientPickerRowHeight] 를 `itemExtent` 로 쓴다.
class ClientPickerCard extends StatelessWidget {
  const ClientPickerCard({
    super.key,
    required this.client,
    required this.selected,
    required this.onTap,
  });

  final TrainerClient client;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    final nameStyle = tokens
        .text(
          selected
              ? OnCareTypography.strong(OnCareTypography.bodySmall)
              : OnCareTypography.bodySmall,
        )
        .copyWith(color: OnCareColors.textPrimary);
    final detailStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Material(
        color: selected ? tokens.brand.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: selected
              ? BorderSide(color: tokens.brand.primary)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.brand.surface,
          child: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s8),
            child: Row(
              children: <Widget>[
                AppAvatar(name: client.name),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              client.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                          ),
                          const SizedBox(width: OnCareSpacing.s4),
                          Flexible(
                            child: Text(
                              clientDemographicsLabel(context, client),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: detailStyle,
                            ),
                          ),
                        ],
                      ),
                      // 목표는 늘 보인다(#898). 비어 있으면 빈 줄을 만들지 않는다.
                      if (client.goal.trim().isNotEmpty)
                        Text(
                          client.goal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: detailStyle,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
