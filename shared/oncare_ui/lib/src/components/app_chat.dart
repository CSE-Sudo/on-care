import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 채팅 말풍선(#1697) — 회원 AI 코치·회원 트레이너 채팅·트레이너 고객 채팅 공용.
///
/// 내 것 = 브랜드 채움·흰 글자, 상대 = 흰 카드 + 옅은 테두리. 반경 16, 보낸 쪽
/// 아래 모서리만 4. 최대 폭은 가용 폭의 72%, 안쪽은 밀도를 따른다.
class AppChatBubble extends StatelessWidget {
  const AppChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.time,
  });

  final bool mine;
  final Widget child;

  /// 말풍선 옆에 붙는 시간(`caption`).
  final String? time;

  static const double maxWidthFactor = 0.72;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle textStyle = tokens
        .text(
          tokens.density.isWeb
              ? OnCareTypography.bodySmall
              : OnCareTypography.body,
        )
        .copyWith(
          color: mine ? OnCareColors.textOnFill : OnCareColors.textPrimary,
        );
    final Widget bubble = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * maxWidthFactor,
            ),
            child: Container(
              padding: tokens.density.chatBubblePadding,
              decoration: BoxDecoration(
                color: mine ? tokens.brand.primary : OnCareColors.surfaceCard,
                border: mine
                    ? null
                    : Border.all(color: OnCareColors.lineSubtle),
                borderRadius: BorderRadius.only(
                  topLeft: OnCareRadius.lg,
                  topRight: OnCareRadius.lg,
                  bottomLeft: mine ? OnCareRadius.lg : OnCareRadius.xs,
                  bottomRight: mine ? OnCareRadius.xs : OnCareRadius.lg,
                ),
              ),
              child: DefaultTextStyle.merge(style: textStyle, child: child),
            ),
          ),
    );
    final Widget? stamp = time == null ? null : AppChatTimestamp(time!);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (mine && stamp != null) ...<Widget>[
            stamp,
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Flexible(child: bubble),
          if (!mine && stamp != null) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s4),
            stamp,
          ],
        ],
      ),
    );
  }
}

/// 말풍선 옆 시간.
class AppChatTimestamp extends StatelessWidget {
  const AppChatTimestamp(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.oncare
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary),
  );
}

/// 날짜 구분선 — 가운데 `caption` 600. 날짜 문구(요일 포함)는 앱 l10n 이 만든다.
class AppChatDateDivider extends StatelessWidget {
  const AppChatDateDivider(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider(color: OnCareColors.lineSubtle)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
            child: Text(
              label,
              style: context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
          const Expanded(child: Divider(color: OnCareColors.lineSubtle)),
        ],
      ),
    );
  }
}

/// 첨부 파일 카드(PDF 등) — 타일 틀·아이콘·파일명·보조 문구.
class AppChatFileCard extends StatelessWidget {
  const AppChatFileCard({
    super.key,
    required this.name,
    this.detail,
    this.icon = Icons.picture_as_pdf_rounded,
    this.onTap,
  });

  final String name;
  final String? detail;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: OnCareColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: BorderSide(color: OnCareColors.lineSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: OnCareSize.iconLarge,
                color: OnCareColors.danger,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                          )
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 채팅 입력줄 — 입력창(여러 줄 자동 높이) + 선택 첨부 버튼 + 전송(filled).
class AppChatInputBar extends StatelessWidget {
  const AppChatInputBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.sendTooltip,
    required this.onSend,
    this.attachTooltip,
    this.onAttach,
    this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final String sendTooltip;
  final VoidCallback? onSend;
  final String? attachTooltip;
  final VoidCallback? onAttach;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (onAttach != null) ...<Widget>[
                AppIconButton(
                  icon: Icons.add_photo_alternate_rounded,
                  tooltip: attachTooltip ?? '',
                  onPressed: enabled ? onAttach : null,
                ),
                const SizedBox(width: OnCareSpacing.s8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: tokens
                      .text(OnCareTypography.body)
                      .copyWith(color: OnCareColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: hint,
                    constraints: BoxConstraints(
                      minHeight: tokens.density.iconButton,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppIconButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: sendTooltip,
                variant: AppIconButtonVariant.filled,
                onPressed: enabled ? onSend : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 입력 중 표시 — 점 세 개가 차례로 옅어졌다 진해진다.
class AppTypingIndicator extends StatefulWidget {
  const AppTypingIndicator({super.key});

  @override
  State<AppTypingIndicator> createState() => _AppTypingIndicatorState();
}

class _AppTypingIndicatorState extends State<AppTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < 3; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: OnCareSpacing.s4),
            Opacity(
              opacity:
                  0.3 + 0.7 * (((_controller.value * 3 - i) % 3) < 1 ? 1 : 0),
              child: Container(
                width: OnCareSize.dot,
                height: OnCareSize.dot,
                decoration: const BoxDecoration(
                  color: OnCareColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
