import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 ①~④ 카드의 제목 줄 — 번호 · 제목 · 곁말. (#2232)
///
/// 아이콘 대신 **번호**를 다는 까닭은 이 화면이 순서가 있는 읽기이기 때문이다.
/// 아이콘은 카드가 무엇에 관한 것인지만 말하고, 어느 것을 먼저 읽어야 하는지는
/// 말하지 않는다. ① 수치를 읽고 → ②③ 으로 그 수치를 해석하고 → ④ 로 이번
/// 주가 흐름의 어디쯤인지 본다 — 그 순서가 곧 트레이너의 판단 순서다.
///
/// 곁말([subtitle])은 제목 옆에 이어 붙는다. 아래 줄로 내리면 카드마다 제목
/// 줄 높이가 달라져, 나란히 선 ②·③ 의 첫 줄이 서로 어긋난다.
class ReportCardHeader extends StatelessWidget {
  /// Creates the header.
  const ReportCardHeader({
    super.key,
    this.number,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });

  /// 카드 번호(1부터). null 이면 번호 없는 카드다 — 요약 카드가 그렇다.
  final int? number;

  final String title;

  /// 제목 뒤에 ` · ` 로 이어 붙는 곁말. 비면 붙이지 않는다.
  final String subtitle;

  /// 줄 오른쪽에 놓을 것(딱지·주 이동 따위).
  final Widget? trailing;

  /// 번호 원의 지름.
  static const double _badge = 22;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Widget? end = trailing;
    return Row(
      children: <Widget>[
        if (number != null) ...<Widget>[
          Container(
            width: _badge,
            height: _badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.brand.primary,
            ),
            child: Text(
              '$number',
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textOnFill),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
        ],
        // 제목과 곁말을 **따로** 둔다. 한 덩이 rich text 로 묶으면 화면에서
        // 제목만 짚어 읽을 수 없고, 좁아졌을 때 줄어드는 쪽을 고를 수도 없다.
        // 좁아지면 제목도 줄어든다. 제목을 고정 폭으로 두면 곁말이 다 줄어든
        // 뒤에도 줄이 칸을 넘어선다 — 줄어드는 쪽을 고를 수 있다는 것이 둘을
        // 따로 둔 까닭이다. 곁말이 먼저(flex 1), 제목이 나중(flex 2)이다.
        // 제목·곁말을 한 칸에 묶고, 그 칸이 남는 폭을 모두 가진다. 둘을 곧장
        // 바깥 줄에 두면 `Spacer` 와 폭을 나눠 가져, 끝의 배지가 카드 가운데에
        // 선다.
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                flex: 2,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.body))
                      .copyWith(color: tokens.brand.primary),
                ),
              ),
              if (subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                Flexible(
                  child: Text(
                    '· $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (end != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          end,
        ],
      ],
    );
  }
}
