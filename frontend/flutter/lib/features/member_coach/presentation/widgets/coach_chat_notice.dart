import 'package:flutter/material.dart';

import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 채팅 가운데에 뜨는 안내 상자. (#543, #1379, #1600)
///
/// 말풍선이 아니라 스레드에 무슨 일이 있었는가를 적는 자리라 가운데에 작게
/// 뜬다. 첫 줄은 아이콘 + 메인 색 굵은 제목, 둘째 줄은 회색 보조 문구, 필요하면
/// 셋째 줄에 메인 색 글자 링크 하나를 둔다.
///
/// 바탕은 두 가지다. 데모 흐름 안내(`분석했어요`·`개인 추천운동을 받았어요`)는
/// 옅은 메인 색 채움 + 옅은 테두리([CoachChatNoticeStyle.tinted]), 리포트 등록
/// 안내는 흰 바탕 + 메인 색 테두리([CoachChatNoticeStyle.outlined])다.
class CoachChatNotice extends StatelessWidget {
  /// Creates the notice.
  const CoachChatNotice({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.style = CoachChatNoticeStyle.tinted,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// 제목 앞 아이콘.
  final IconData icon;

  /// 메인 색 굵은 첫 줄.
  final String title;

  /// 회색 보조 문구.
  final String subtitle;

  /// 바탕 모양.
  final CoachChatNoticeStyle style;

  /// 셋째 줄 글자 링크. [onAction] 과 함께 줄 때만 그린다.
  final String? actionLabel;

  /// 링크를 눌렀을 때.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color brand = tokens.brand.primary;
    final bool tinted = style == CoachChatNoticeStyle.tinted;
    final TextStyle strong = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: brand);
    final String? label = actionLabel;
    final VoidCallback? action = onAction;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s12,
          vertical: OnCareSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: tinted
              ? OnCareColors.onWhite(brand, OnCareAlpha.subtle)
              : OnCareColors.surfaceCard,
          borderRadius: OnCareRadius.mdAll,
          border: Border.all(color: tinted ? tokens.brand.border : brand),
        ),
        // 글자 배율을 키우면 제목·보조 문구·링크가 차례로 길어진다. 한 줄에 이어
        // 붙이지 않고 세로로 쌓아 두면 잘리는 대신 상자가 아래로 자란다.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: OnCareSize.iconSmall, color: brand),
                const SizedBox(width: OnCareSpacing.s4),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: strong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
            if (label != null && action != null)
              // 테두리 없는 글자 링크. 안내 상자 안에서 두 번째 테두리를 그리면
              // 상자가 둘로 보인다 — 여기서 눌릴 것은 하나뿐이라 글자로 충분하다.
              Semantics(
                button: true,
                child: InkWell(
                  onTap: action,
                  borderRadius: OnCareRadius.smAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnCareSpacing.s8,
                      vertical: OnCareSpacing.s4,
                    ),
                    child: Text(label, style: strong),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [CoachChatNotice] 바탕 모양.
enum CoachChatNoticeStyle {
  /// 옅은 메인 색 채움 + 옅은 메인 색 테두리.
  tinted,

  /// 흰 바탕 + 메인 색 테두리.
  outlined,
}
