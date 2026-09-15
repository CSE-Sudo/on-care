import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/icons.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 카드(#1694, #1690 확정) — 흰색·반경 20·1px 옅은 테두리·카드 그림자·안쪽 16.
///
/// 모서리·테두리·그림자를 바꾸는 인자는 없다. 선택 가능한 카드는 [selected] 로
/// 옅은 브랜드 채움 + 브랜드 테두리가 된다.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.all(OnCareSpacing.cardPadding),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  /// 차트처럼 가장자리까지 채울 때만 줄인다.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: OnCareRadius.xlAll,
        boxShadow: OnCareShadows.card,
      ),
      child: Material(
        color: selected ? tokens.brand.surface : OnCareColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.xlAll,
          side: BorderSide(
            color: selected ? tokens.brand.primary : OnCareColors.lineSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: onTap == null ? null : tokens.brand.surface,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 카드 안 구획 — 옅은 브랜드 채움·반경 12·안쪽 12.
class AppTile extends StatelessWidget {
  const AppTile({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.oncare.brand.surface,
      borderRadius: OnCareRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
          child: child,
        ),
      ),
    );
  }
}

/// 섹션·카드 제목 — `titleSmall` + 앞 아이콘 + 뒤 링크.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          AppIcon(
            icon,
            size: OnCareSize.iconMedium,
            color: tokens.brand.primary,
          ),
          const SizedBox(width: OnCareSpacing.s8),
        ],
        Expanded(
          child: Text(
            title,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ),
        if (actionLabel != null)
          AppButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            trailingIcon: AppIcon.setOf(context).disclosure,
          ),
      ],
    );
  }
}

/// 지표 카드 — 큰 숫자(`display`) + 라벨(`caption`) + 선택 보조 문구.
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.icon,
    this.onTap,
    this.toneColor,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onTap;

  /// 판단을 담는 지표의 상태색(예: 위험 [OnCareColors.danger], 정상
  /// [OnCareColors.success]). 주면 숫자와 아이콘을 이 색으로 칠한다. 비우면
  /// 숫자는 기본 글자색, 아이콘은 브랜드 메인 색이다.
  final Color? toneColor;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color? tone = toneColor;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                AppIcon(
                  icon,
                  size: OnCareSize.iconSmall,
                  color: tone ?? tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: value,
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.display),
                  ).copyWith(color: tone ?? OnCareColors.textPrimary),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
              ],
            ),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              caption!,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 목록 행 — 앞(아바타·아이콘) / 제목 `bodyLarge` / 부제 `bodySmall` / 뒤 슬롯.
///
/// 최소 높이는 밀도를 따른다(56/48). 선택은 옅은 브랜드 채움 + 브랜드 테두리,
/// 읽지 않음은 빨간 점 + 제목 600 이다.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.unread = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle titleStyle = tokens
        .text(
          unread
              ? OnCareTypography.strong(OnCareTypography.bodyLarge)
              : OnCareTypography.bodyLarge,
        )
        .copyWith(color: OnCareColors.textPrimary);
    return Material(
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tokens.density.listRowMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OnCareSpacing.s16,
              vertical: OnCareSpacing.s12,
            ),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: OnCareSpacing.s12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: OnCareColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (unread) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  const _Dot(),
                ],
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnCareSize.dot,
      height: OnCareSize.dot,
      decoration: const BoxDecoration(
        color: OnCareColors.danger,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 안내 배너 톤.
enum AppBannerTone { info, success, caution, danger }

/// 안내 배너 — 반경 12, 아이콘 20 + `titleSmall` 제목 + `bodySmall` 본문 + 선택 동작.
///
/// 채팅의 시스템 안내·리포트 등록(#1577), 경고 배너, AI 안내·메모 박스가 모두 쓴다.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.tone = AppBannerTone.info,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final AppBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color accent = switch (tone) {
      AppBannerTone.info => tokens.brand.primary,
      AppBannerTone.success => OnCareColors.success,
      AppBannerTone.caution => OnCareColors.caution,
      AppBannerTone.danger => OnCareColors.danger,
    };
    final Color fill = tone == AppBannerTone.info
        ? tokens.brand.surface
        : OnCareColors.onWhite(accent, OnCareAlpha.subtle);
    final Color border = tone == AppBannerTone.info
        ? tokens.brand.border
        : OnCareColors.onWhite(accent, OnCareAlpha.strong);
    final OnCareIconSet icons = AppIcon.setOf(context);
    final IconData resolvedIcon =
        icon ??
        switch (tone) {
          AppBannerTone.info => icons.info,
          AppBannerTone.success => icons.success,
          AppBannerTone.caution => icons.caution,
          AppBannerTone.danger => icons.error,
        };
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon(resolvedIcon, size: OnCareSize.iconMedium, color: accent),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                if (message != null) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s2),
                  Text(
                    message!,
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
                if (actionLabel != null) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s8),
                  AppButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    variant: AppButtonVariant.secondary,
                    size: OnCareButtonSize.small,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 구분선 — 1px 옅은 선.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
    height: OnCareSize.hairline,
    thickness: OnCareSize.hairline,
    color: OnCareColors.lineSubtle,
  );
}

/// 빈 화면·오류·로딩이 놓이는 자리.
enum AppStatePlacement {
  /// 페이지 가운데.
  page,

  /// 카드 안 — 최소 높이 120.
  card,
}

const double _cardStateMinHeight = 120;

/// 빈 화면 — 아이콘 40 + `titleSmall` + `bodySmall` + 선택 동작 버튼.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.placement = AppStatePlacement.page,
  });

  final String title;
  final String? message;

  /// 비우면 아이콘 묶음의 빈 화면 아이콘이다.
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppStatePlacement placement;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIcon(
          icon ?? AppIcon.setOf(context).empty,
          size: OnCareSize.iconEmptyState,
          color: OnCareColors.textTertiary,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: tokens
              .text(OnCareTypography.titleSmall)
              .copyWith(color: OnCareColors.textPrimary),
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
        if (actionLabel != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s16),
          AppButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: AppButtonVariant.secondary,
          ),
        ],
      ],
    );
    return _StateFrame(placement: placement, child: body);
  }
}

/// 오류 — 빈 화면과 같은 틀에 [다시 시도] 버튼.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.title,
    this.message,
    required this.retryLabel,
    required this.onRetry,
    this.placement = AppStatePlacement.page,
  });

  final String title;
  final String? message;
  final String retryLabel;
  final VoidCallback? onRetry;
  final AppStatePlacement placement;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title,
      message: message,
      icon: AppIcon.setOf(context).offline,
      actionLabel: retryLabel,
      onAction: onRetry,
      placement: placement,
    );
  }
}

/// 로딩 — 스피너 24·선 2.5·브랜드색. 인라인은 16.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.placement = AppStatePlacement.page});

  /// 글자 옆 작은 스피너.
  const AppLoading.inline({super.key}) : placement = null;

  final AppStatePlacement? placement;

  @override
  Widget build(BuildContext context) {
    final Color color = context.oncare.brand.primary;
    if (placement == null) {
      return SizedBox.square(
        dimension: OnCareSize.inlineSpinner,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return _StateFrame(
      placement: placement!,
      child: SizedBox.square(
        dimension: OnCareSize.spinner,
        child: CircularProgressIndicator(
          strokeWidth: OnCareSize.spinnerStroke,
          color: color,
        ),
      ),
    );
  }
}

class _StateFrame extends StatelessWidget {
  const _StateFrame({required this.placement, required this.child});

  final AppStatePlacement placement;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return switch (placement) {
      AppStatePlacement.page => Center(
        child: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s24),
          child: child,
        ),
      ),
      AppStatePlacement.card => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _cardStateMinHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
            child: child,
          ),
        ),
      ),
    };
  }
}
