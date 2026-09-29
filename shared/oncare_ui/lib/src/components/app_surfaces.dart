import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/icons.dart';
import 'package:oncare_ui/src/tokens/layout.dart';
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
    this.backgroundColor,
    this.padding = const EdgeInsets.all(OnCareSpacing.cardPadding),
  });

  /// 목록에 줄지어 선 줄 카드의 안쪽 — 가로 16·세로 12(#2397, #2469).
  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: OnCareSpacing.s16,
    vertical: OnCareSpacing.s12,
  );

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  /// 특정 의미를 가진 강조 카드의 채움. 없으면 기본 카드/선택 카드 색을 쓴다.
  ///
  /// 채운 카드는 흰 글자를 얹는 카드라([OnCareColors.textOnFill]), 누름·hover 도
  /// 채움이 아니라 **그 글자색 8%** 로 얹는다 — 옅은 브랜드 채움을 그대로 얹으면
  /// 어느 색으로 채웠든 카드가 눌릴 때마다 파랗게 물든다(#2076).
  final Color? backgroundColor;

  /// 차트처럼 가장자리까지 채울 때만 줄인다.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 누름·hover 에 얹는 색. 흰 카드는 옅은 브랜드 채움이고, 채운 카드는 그 위에
    // 서는 글자색 8% 다.
    final Color ink = backgroundColor == null
        ? tokens.brand.surface
        : OnCareColors.textOnFill.withValues(alpha: OnCareAlpha.subtle);
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: OnCareRadius.xlAll,
        boxShadow: OnCareShadows.card,
      ),
      child: Material(
        color:
            backgroundColor ??
            (selected ? tokens.brand.surface : OnCareColors.surfaceCard),
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.xlAll,
          side: BorderSide(
            color: selected ? tokens.brand.primary : OnCareColors.lineSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: onTap == null ? null : ink,
          highlightColor: onTap == null || backgroundColor == null ? null : ink,
          splashColor: onTap == null || backgroundColor == null ? null : ink,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// [AppTile] 의 채움.
enum AppTileTone {
  /// 옅은 브랜드 채움 — 기본값.
  brand,

  /// [brand] 보다 한 단계 옅은 브랜드 채움. 같은 구획이 여러 개 이어져 목록이
  /// 무겁게 읽히는 자리에 쓴다(#2177).
  brandSoft,

  /// 옅은 회색 채움. 입력 칸이 놓인 구획에 쓴다 — 채움이 "여기에 적는다"는
  /// 신호가 된다.
  neutral,

  /// 채우지 않는다. 읽기만 하는 줄은 굳이 바탕을 깔 이유가 없다.
  none,
}

/// 카드 안 구획 — 반경 12·안쪽 12. 채움은 [tone] 을 따른다.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.child,
    this.onTap,
    this.tone = AppTileTone.brand,
  });

  final Widget child;
  final VoidCallback? onTap;
  final AppTileTone tone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: switch (tone) {
        AppTileTone.brand => context.oncare.brand.surface,
        AppTileTone.brandSoft => context.oncare.brand.surfaceSoft,
        AppTileTone.neutral => OnCareColors.surfaceInput,
        AppTileTone.none => Colors.transparent,
      },
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

/// [AppSectionHeader.trailing] 이 폭이 모자랄 때 서는 방식.
enum AppSectionTrailingFit {
  /// 제 폭만큼 선다. 제목이 남는 폭을 모두 갖는다 — 수·배지·작은 버튼.
  natural,

  /// 제목과 끝 요소가 남는 폭을 반씩 나눠 갖고, 끝 요소는 그 절반 안에서
  /// 오른쪽에 붙는다. 범례·기간 토글처럼 줄어들어도 되는 끝 요소에 쓴다 —
  /// 무엇을 줄일지는 끝 요소가 정한다(범례만 `FittedBox` 로 줄이고 주 이동
  /// 버튼은 터치 크기를 지키는 식).
  shrink,

  /// 한 줄에 다 서지 못하면 끝 요소를 다음 줄로 넘긴다. 줄이면 읽기 어려워지는
  /// 끝 요소(정렬 메뉴 버튼)에 쓴다(#849).
  wrap,
}

/// 섹션·카드 제목 — `titleSmall` 검정 + 앞 아이콘(브랜드색) 또는 번호 원 +
/// 곁말·배지·아래 줄 설명 + 뒤 요소·링크 (#2468).
///
/// 카드 제목은 모두 이 한 모양이다. 제목 줄 오른쪽에 무언가(수·배지·버튼·토글)
/// 를 둘 때 화면에서 `Row(Expanded(AppSectionHeader), …)` 로 감싸지 않고
/// [trailing] 에 넣는다.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.number,
    this.titleMeta,
    this.titleBadge,
    this.subtitle,
    this.subtitleMaxLines,
    this.trailing,
    this.trailingFit = AppSectionTrailingFit.natural,
    this.actionLabel,
    this.onAction,
  }) : assert(icon == null || number == null, '아이콘과 번호는 하나만 단다');

  final String title;

  /// 제목 앞 아이콘. 늘 브랜드색 20 이다.
  final IconData? icon;

  /// 제목 앞 번호 원(1부터). 순서대로 읽는 카드(리포트 ①~③)에 아이콘 대신
  /// 단다 — 아이콘은 무엇에 관한 카드인지만 말하고 읽는 순서는 말하지 않는다.
  final int? number;

  /// 제목 옆 **같은 줄**에 ` · ` 로 이어 붙는 짧은 곁말(caption·흐린 색).
  ///
  /// 아래 줄로 내리지 않는 까닭은 나란히 선 카드의 제목 줄 높이가 달라지지
  /// 않게 하려는 것이다. 곁말이 있으면 제목 줄은 한 줄이고, 좁아지면 곁말이
  /// 먼저 말줄임된다([AppListRow.titleMeta] 와 같은 뜻).
  final String? titleMeta;

  /// 제목(곁말) 바로 옆에 붙는 배지 — 목록 상자의 인원 수처럼 제목을 꾸미는
  /// 것. 줄 끝으로 밀리는 [trailing] 과 다르다.
  final Widget? titleBadge;

  /// 제목 **아래 줄** 설명(caption·보조 글자색).
  final String? subtitle;

  /// [subtitle] 의 최대 줄 수. 비우면 줄바꿈한다. 주면 넘칠 때 말줄임한다.
  final int? subtitleMaxLines;

  /// 줄 오른쪽 끝에 놓는 것(수·배지·버튼·토글·주 이동). 제 폭만큼 선다.
  final Widget? trailing;

  /// 폭이 모자랄 때 [trailing] 이 서는 방식.
  final AppSectionTrailingFit trailingFit;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle titleStyle = tokens
        .text(OnCareTypography.titleSmall)
        .copyWith(color: OnCareColors.textPrimary);
    final bool oneLine = titleMeta != null || titleBadge != null;
    // 제목 줄은 내용 폭만큼만 선다 — 끝 요소를 다음 줄로 넘기는 배치([wrap])
    // 에서도 같은 줄을 쓰고, 다른 배치에서는 바깥 `Expanded` 가 폭을 준다.
    final Widget titleLine = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          AppIcon(
            icon,
            size: OnCareSize.iconMedium,
            color: tokens.brand.primary,
          ),
          const SizedBox(width: OnCareSpacing.s8),
        ] else if (number != null) ...<Widget>[
          _SectionNumber(number!),
          const SizedBox(width: OnCareSpacing.s8),
        ],
        if (!oneLine)
          Flexible(child: Text(title, style: titleStyle))
        else ...<Widget>[
          // 제목과 곁말을 **따로** 둔다. 한 덩이로 묶으면 제목만 짚어 읽을 수
          // 없고, 좁아졌을 때 줄어드는 쪽을 고를 수 없다 — 곁말이 먼저(flex 1),
          // 제목이 나중(flex 2)이다.
          Flexible(
            flex: 2,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          if (titleMeta != null) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s8),
            Flexible(
              child: Text(
                '· $titleMeta',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ],
          if (titleBadge != null) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s8),
            titleBadge!,
          ],
        ],
      ],
    );
    final Widget titleBlock = subtitle == null
        ? titleLine
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              titleLine,
              const SizedBox(height: OnCareSpacing.s4),
              Text(
                subtitle!,
                maxLines: subtitleMaxLines,
                overflow: subtitleMaxLines == null
                    ? null
                    : TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ],
          );
    final Widget? end = trailing;
    if (end != null && trailingFit == AppSectionTrailingFit.wrap) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: OnCareSpacing.s12,
        runSpacing: OnCareSpacing.s8,
        children: <Widget>[titleBlock, end],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: titleBlock),
        if (end != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          if (trailingFit == AppSectionTrailingFit.shrink)
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: end),
            )
          else
            end,
        ],
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

/// [AppSectionHeader.number] 의 번호 원 — 브랜드 채움 + 흰 숫자.
class _SectionNumber extends StatelessWidget {
  const _SectionNumber(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: OnCareSize.sectionNumber,
      height: OnCareSize.sectionNumber,
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

/// 목록 행 — 앞(아바타·아이콘) / 제목 `bodyLarge` (+ 같은 줄 [titleMeta]) /
/// 부제 `bodySmall` / 뒤 슬롯, 그리고 부제 아래 [below] 슬롯.
///
/// 최소 높이는 밀도를 따른다(56/48). 선택은 옅은 브랜드 채움 + 브랜드 테두리,
/// 읽지 않음은 빨간 점 + 제목 600 이다.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.titleMeta,
    this.subtitle,
    this.leading,
    this.trailing,
    this.below,
    this.onTap,
    this.selected = false,
    this.unread = false,
  });

  final String title;

  /// 제목 옆 **같은 줄**에 붙는 짧은 속성 — 트레이너 이름 옆 직함처럼 제목을
  /// 꾸며 주는 말이다 (#2082). 이름과 짧은 속성은 한 줄에 읽혀야 하고, 제목
  /// 아래 줄을 하나 더 쓰는 것은 기능을 풀어 쓰는 부제의 몫이다(#2038).
  /// 부제와 같은 한 단계 작은 회색 글씨이고, 폭이 모자라면 이쪽이 먼저
  /// 말줄임된다. 없으면 제목만 선다.
  final String? titleMeta;

  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// 부제 아래에 붙는 것 — 태그 묶음처럼 한 줄 글로는 안 되는 내용을 놓는다.
  /// 제목·부제와 같은 칸에 들어가므로 앞 칸(leading)에 맞춰 들여쓰기되고,
  /// 뒤 슬롯(trailing)에 가리지 않는다. 행 높이는 내용만큼 늘어난다.
  final Widget? below;

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
    final TextStyle subtitleStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
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
                      if (titleMeta == null)
                        Text(
                          title,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        // 제목과 속성을 한 문단에 적는다. 두 칸(Row)으로 나누면
                        // 칸마다 남는 폭을 반씩 나눠 가져, 짧은 이름 옆에서도
                        // 속성이 먼저 잘린다. 한 문단이면 말줄임이 줄 끝인
                        // 속성부터 먹고, 두 글씨가 한 기준선에 선다.
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(text: title, style: titleStyle),
                              const WidgetSpan(
                                child: SizedBox(width: OnCareSpacing.s8),
                              ),
                              TextSpan(text: titleMeta),
                            ],
                          ),
                          // 바탕 글씨를 속성 글씨로 둬 말줄임표도 속성처럼
                          // 흐리게 찍힌다.
                          style: subtitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: subtitleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (below != null) ...<Widget>[
                        const SizedBox(height: OnCareSpacing.s8),
                        below!,
                      ],
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

/// [AppBanner] 의 밀도.
enum AppBannerDensity {
  /// 아이콘 20 + `titleSmall` 제목 + `bodySmall` 본문, 안쪽 12. 본문은 아이콘
  /// 오른쪽 칸에 들여 선다.
  regular,

  /// 아이콘 16 + 톤색 굵은 `bodySmall` 한 줄 제목 + `caption` 본문, 안쪽 세로
  /// 8·가로 12. 제목 줄 아래 본문은 폭을 다 쓴다. 대화 흐름이나 카드 안 좁은 칸에
  /// 서는 감지 경고처럼 무게를 낮춰야 하는 안내에 쓴다.
  compact,
}

/// [AppBanner] 가 서는 자리.
enum AppBannerPlacement {
  /// 카드·창 안 — 반경 12, 그림자 없음.
  inline,

  /// 페이지에 카드처럼 홀로 서는 안내(대시보드 활동 피드백·리포트 요약·식단
  /// 분석) — 카드와 같은 반경 20·카드 그림자·안쪽 16. 머리는 카드 제목
  /// ([AppSectionHeader])과 같고, 본문은 그 아래 폭을 다 쓴다. `info` 톤
  /// 전용이다.
  card,
}

/// 안내 배너 — 톤색 옅은 채움 + 톤색 테두리, 아이콘 + 제목 + 본문 + 선택
/// 동작·자유 내용.
///
/// 채팅의 시스템 안내·리포트 등록(#1577), 경고 배너, AI 안내·메모 박스가 모두
/// 쓴다. 같은 종류의 안내는 같은 모양이다 — 페이지에 홀로 서는 AI·요약 안내는
/// [AppBannerPlacement.card], 감지 경고는 [AppBannerDensity.compact] (#2468).
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.tone = AppBannerTone.info,
    this.actionLabel,
    this.onAction,
    this.titleMeta,
    this.trailing,
    this.child,
    this.expandChild = false,
    this.density = AppBannerDensity.regular,
    this.placement = AppBannerPlacement.inline,
  }) : assert(
         placement == AppBannerPlacement.inline ||
             (tone == AppBannerTone.info &&
                 density == AppBannerDensity.regular),
         '카드 자리 배너는 info 톤·기본 밀도만 쓴다',
       );

  final String title;
  final String? message;
  final IconData? icon;
  final AppBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 제목 옆 같은 줄 곁말([AppSectionHeader.titleMeta] 와 같은 모양).
  final String? titleMeta;

  /// 제목 줄 오른쪽 끝 — 생성 배지·"메모 추가" 알약처럼 짧은 것.
  final Widget? trailing;

  /// 본문([message]) 아래 자유 내용 — 목록·추천 메뉴·버튼 묶음.
  final Widget? child;

  /// 배너가 부모에게서 높이를 받을 때(고정 높이 칸), [child] 가 남는 높이를
  /// 모두 갖는다. 목록을 배너 안에서 스크롤할 때 켠다.
  final bool expandChild;

  final AppBannerDensity density;
  final AppBannerPlacement placement;

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
    final bool card = placement == AppBannerPlacement.card;
    final bool compact = density == AppBannerDensity.compact;
    final BorderRadius radius = card ? OnCareRadius.xlAll : OnCareRadius.mdAll;
    final EdgeInsetsGeometry padding = card
        ? const EdgeInsets.all(OnCareSpacing.cardPadding)
        : compact
        ? const EdgeInsets.symmetric(
            horizontal: OnCareSpacing.tilePadding,
            vertical: OnCareSpacing.s8,
          )
        : const EdgeInsets.all(OnCareSpacing.tilePadding);
    final MainAxisSize columnSize = expandChild
        ? MainAxisSize.max
        : MainAxisSize.min;

    final String? message = this.message;
    final Widget? messageText = message == null
        ? null
        : Text(
            message,
            style: tokens
                .text(
                  compact
                      ? OnCareTypography.caption
                      : OnCareTypography.bodySmall,
                )
                .copyWith(color: OnCareColors.textSecondary),
          );
    final String? actionLabel = this.actionLabel;
    final Widget? action = actionLabel == null
        ? null
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: actionLabel,
              onPressed: onAction,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
            ),
          );
    final Widget? child = this.child;
    final Widget? extra = child == null
        ? null
        : expandChild
        ? Expanded(child: child)
        : child;
    // 제목 줄 아래 — 본문·자유 내용·동작 순.
    List<Widget> below(double firstGap) => <Widget>[
      if (messageText != null) ...<Widget>[
        SizedBox(height: firstGap),
        messageText,
      ],
      if (extra != null) ...<Widget>[
        SizedBox(height: messageText == null ? firstGap : OnCareSpacing.s8),
        extra,
      ],
      if (action != null) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s8),
        action,
      ],
    ];
    final Widget? trailing = this.trailing;
    List<Widget> end() => <Widget>[
      if (trailing != null) ...<Widget>[
        const SizedBox(width: OnCareSpacing.s8),
        trailing,
      ],
    ];

    final Widget content;
    if (card) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: columnSize,
        children: <Widget>[
          AppSectionHeader(
            title: title,
            icon: resolvedIcon,
            titleMeta: titleMeta,
            trailing: trailing,
          ),
          ...below(OnCareSpacing.s12),
        ],
      );
    } else if (compact) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: columnSize,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIcon(resolvedIcon, size: OnCareSize.iconSmall, color: accent),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(
                // compact 는 고정 높이 칸에도 서므로 제목을 한 줄로 둔다.
                child: _BannerTitle(
                  title: title,
                  meta: titleMeta,
                  oneLine: true,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: accent),
                ),
              ),
              ...end(),
            ],
          ),
          ...below(OnCareSpacing.s2),
        ],
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon(resolvedIcon, size: OnCareSize.iconMedium, color: accent),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: columnSize,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _BannerTitle(
                        title: title,
                        meta: titleMeta,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    ...end(),
                  ],
                ),
                ...below(OnCareSpacing.s2),
              ],
            ),
          ),
        ],
      );
    }

    // 안쪽 투명 Material 은 버튼 잉크가 채움 위에 그려지게 한다. Container 라
    // 테두리 두께만큼 안쪽 여백이 붙는다(예전 모양 그대로).
    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: border),
        boxShadow: card ? OnCareShadows.card : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: content),
      ),
    );
  }
}

/// 배너 제목 — 곁말이 있으면 한 줄(곁말이 먼저 말줄임), 없으면 줄바꿈한다.
class _BannerTitle extends StatelessWidget {
  const _BannerTitle({
    required this.title,
    required this.style,
    this.meta,
    this.oneLine = false,
  });

  final String title;
  final String? meta;
  final TextStyle style;

  /// 곁말이 없어도 한 줄로 두고 말줄임한다.
  final bool oneLine;

  @override
  Widget build(BuildContext context) {
    final String? meta = this.meta;
    if (meta == null) {
      return Text(
        title,
        maxLines: oneLine ? 1 : null,
        overflow: oneLine ? TextOverflow.ellipsis : null,
        style: style,
      );
    }
    return Row(
      children: <Widget>[
        Flexible(
          flex: 2,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        Flexible(
          child: Text(
            '· $meta',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// 구분선 — 1px 옅은 선.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.color = OnCareColors.lineSubtle});

  /// 선 색. 기본 [OnCareColors.lineSubtle] 은 옅은 브랜드 바탕(`brand.surface`)
  /// 과 밝기가 거의 같아 묻힌다 — 그런 바탕 위에서는 [OnCareColors.lineStrong]
  /// 을 준다(#2202).
  final Color color;

  @override
  Widget build(BuildContext context) => Divider(
    height: OnCareSize.hairline,
    thickness: OnCareSize.hairline,
    color: color,
  );
}

/// 가운데에 글자가 있는 구분선 — 로그인 버튼과 소셜 로그인 버튼 사이(#1783).
///
/// 양옆은 [AppDivider], 글자는 캡션·힌트 색이다. 글자가 폭을 넘으면 양옆 선을
/// [_minLine] 만큼 남긴 채 가운데 정렬로 줄바꿈한다.
class AppLabeledDivider extends StatelessWidget {
  const AppLabeledDivider({super.key, required this.label});

  final String label;

  /// 글자가 길어도 양옆 선이 이만큼은 남는다.
  static const double _minLine = OnCareSpacing.s24;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 영어 문구(`Sign in with a social account`)는 큰 글자 배율에서 폭 400
        // 로그인 틀을 넘었다. 넘치게 두지 않고 줄바꿈한다(#1783).
        final double maxLabelWidth =
            (constraints.maxWidth - 2 * (OnCareSpacing.s12 + _minLine)).clamp(
              0.0,
              double.infinity,
            );
        return Row(
          children: <Widget>[
            const Expanded(child: AppDivider()),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s12,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.oncare
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            ),
            const Expanded(child: AppDivider()),
          ],
        );
      },
    );
  }
}

/// 빈 화면·오류·로딩이 놓이는 자리.
enum AppStatePlacement {
  /// 페이지 가운데.
  page,

  /// 카드 안 — 최소 높이 120.
  card,

  /// 글 흐름 안 한두 줄 — 아이콘·최소 높이 없이 왼쪽 정렬, 제목 `bodySmall`
  /// + 안내 `caption`, 흐린 글자색(#2469). 목록·칸이 비었다는 짧은 말에 쓴다.
  inline,
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
    this.actionKey,
    this.placement = AppStatePlacement.page,
  });

  final String title;
  final String? message;

  /// 비우면 아이콘 묶음의 빈 화면 아이콘이다.
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 동작 버튼의 Key — 테스트·자동화가 버튼을 찾을 때.
  final Key? actionKey;
  final AppStatePlacement placement;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    if (placement == AppStatePlacement.inline) return _inline(tokens);
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
            key: actionKey,
            label: actionLabel!,
            onPressed: onAction,
            variant: AppButtonVariant.secondary,
          ),
        ],
      ],
    );
    return _StateFrame(placement: placement, child: body);
  }

  Widget _inline(OnCareTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textTertiary),
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            message!,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
        if (actionLabel != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          AppButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ],
      ],
    );
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
    this.retryKey,
    this.placement = AppStatePlacement.page,
  });

  final String title;
  final String? message;
  final String retryLabel;
  final VoidCallback? onRetry;

  /// [다시 시도] 버튼의 Key.
  final Key? retryKey;
  final AppStatePlacement placement;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title,
      message: message,
      icon: AppIcon.setOf(context).offline,
      actionLabel: retryLabel,
      onAction: onRetry,
      actionKey: retryKey,
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
      AppStatePlacement.inline => child,
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

/// 라벨·값 한 줄 — 왼쪽 고정 폭 라벨(`bodySmall`·흐린 글자) + 값(`bodySmall`
/// 600·본문 글자)(#2469).
///
/// 상담 요청·리포트 전송 미리보기·회원 피드백처럼 "무엇 : 얼마" 를 여러 줄
/// 늘어놓는 자리에 쓴다. 줄 사이 간격은 부르는 쪽이 둔다.
/// [AppKeyValueRow.stacked] 는 라벨 아래에 값을 두는 세로 칸이다.
class AppKeyValueRow extends StatelessWidget {
  const AppKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
    this.strongValue = true,
    this.valueColor,
    this.labelWidth = OnCareLayout.keyValueLabelWidth,
  }) : _stacked = false;

  /// 세로 칸 — 라벨(`caption`) 아래 값(`body`).
  const AppKeyValueRow.stacked({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
    this.valueColor,
  }) : _stacked = true,
       strongValue = false,
       labelWidth = OnCareLayout.keyValueLabelWidth;

  final String label;
  final String value;

  /// 값 글자의 Key — 테스트가 값을 찾을 때.
  final Key? valueKey;

  /// 값을 600 으로 — 긴 글(문의 내용 등)은 끈다.
  final bool strongValue;

  /// 값 글자색. 없으면 본문 글자색이다. 비었음·경고를 말할 때만 준다.
  final Color? valueColor;
  final double labelWidth;
  final bool _stacked;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    if (_stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            value,
            key: valueKey,
            style: tokens
                .text(OnCareTypography.body)
                .copyWith(color: valueColor ?? OnCareColors.textPrimary),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            style: tokens
                .text(
                  strongValue
                      ? OnCareTypography.strong(OnCareTypography.bodySmall)
                      : OnCareTypography.bodySmall,
                )
                .copyWith(color: valueColor ?? OnCareColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// 작은 머리글 — 메뉴 묶음 이름(`운영`·`코칭`, `내 정보`·`설정`) 같은 한 줄
/// `caption` 600·흐린 글자(#2469).
class AppOverline extends StatelessWidget {
  const AppOverline(this.label, {super.key, this.padding = menuPadding});

  final String label;
  final EdgeInsetsGeometry padding;

  /// 사이드바·메뉴 목록 안 — 항목 안쪽 여백(12)에 맞추고 아래는 붙인다.
  static const EdgeInsets menuPadding = EdgeInsets.fromLTRB(
    OnCareSpacing.s12,
    OnCareSpacing.s12,
    OnCareSpacing.s12,
    OnCareSpacing.s4,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        label,
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: OnCareColors.textTertiary),
      ),
    );
  }
}
