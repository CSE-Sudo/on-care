import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// AI 가 건네는 한 문단짜리 조언 카드. (#1021)
///
/// 식단 탭이 쓰던 그림을 그대로 꺼내 둔 것이다. 운동 탭도 같은 자리에서 같은
/// 말을 하게 됐는데, 두 탭이 조금씩 다른 카드를 쓰면 회원은 "이 카드가 그
/// 카드인가" 를 매번 다시 판단해야 한다.
///
/// 문구가 비면 아무것도 그리지 않는다 — 빈 카드는 자리만 차지하고 아무것도
/// 알려 주지 않는다.
class AiAdviceCard extends StatelessWidget {
  const AiAdviceCard({
    super.key,
    required this.title,
    required this.message,
  });

  /// 카드 머리 — `AI 맞춤 조언` 처럼 무슨 말인지 알려 주는 한 줄.
  final String title;

  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    final TextStyle style = context.oncare
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textPrimary);
    // 식단 조언은 메뉴 이름·수치를 `**` 로 감싸 오지만(#2251) 카드는 굵게 그리지
    // 않는다(#2255) — 한 화면의 운동 카드와 같은 평문이어야 두 카드가 같은 카드로
    // 읽힌다. 표시만 떼고, 서버는 그대로 보낸다(나중에 강조를 켤 수 있게).
    return AiAdviceShell(
      title: title,
      child: Text(message.replaceAll('**', ''), style: style),
    );
  }
}

/// 조언 카드의 그릇 — 오니·머리 한 줄·본문. 본문만 갈아 끼우면 로딩·실패도
/// 같은 카드 안에서 말할 수 있다. 상태마다 다른 그림을 그리면 기간을 옮길 때
/// 화면이 통째로 들썩인다. (#1574)
///
/// 앱의 AI 카드는 이 한 가지다(#1690) — 안내 배너(info)와 같은 옅은 브랜드
/// 채움·테두리·반경 12 에 아이콘 대신 오니를 둔다. [onTap] 을 주면 카드 전체가
/// 눌리고, [trailing] 에 이동 표시를 둘 수 있다.
class AiAdviceShell extends StatelessWidget {
  const AiAdviceShell({
    super.key,
    required this.title,
    required this.child,
    this.onTap,
    this.trailing,
  });

  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: tokens.brand.surface,
      shape: RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: BorderSide(color: tokens.brand.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const OniAvatar(),
              const SizedBox(width: OnCareSpacing.s12),
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
                    const SizedBox(height: OnCareSpacing.s4),
                    child,
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 기간을 따라가는 조언 카드. (#1574)
///
/// 기간 토글이 바뀌면 카드도 **그 기간의 상태**가 된다. 예전에는 주간·전체
/// 조언을 기다리는 동안 오늘 조언을 대신 그렸는데, 그러면 이번 주를 보고 있는데
/// "오늘 점심이 짰어요" 를 읽게 되고, 요청이 실패하면 그 말이 그대로 남았다.
///
/// 그래서 **폴백이 없다.** 아직 못 받았으면 못 받았다고, 실패했으면 실패했다고
/// 말하고 다시 시도할 길을 준다 — 다른 기간의 조언을 이 기간의 조언인 것처럼
/// 보여 주는 것보다 낫다.
class PeriodAiAdviceCard extends ConsumerWidget {
  const PeriodAiAdviceCard({
    super.key,
    required this.title,
    required this.advice,
    required this.onRetry,
  });

  final String title;

  /// 지금 고른 기간의 조언. 기간마다 provider 가 따로 서므로, 토글을 빠르게
  /// 옮겨도 이전 기간의 응답이 이 카드에 들어오지 않는다.
  final AsyncValue<String> advice;

  /// 실패한 기간을 다시 부른다.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle statusStyle = context.oncare
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    return advice.when(
      data: (String message) => AiAdviceCard(title: title, message: message),
      loading: () => AiAdviceShell(
        key: const ValueKey<String>('ai-advice-loading'),
        title: title,
        child: Text(l.aiAdviceLoading, style: statusStyle),
      ),
      error: (Object error, StackTrace _) => AiAdviceShell(
        key: const ValueKey<String>('ai-advice-error'),
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.aiAdviceError, style: statusStyle),
            const SizedBox(height: OnCareSpacing.s8),
            // 카드 안에 두는 이유: 실패한 것은 이 카드 하나다. 화면 전체를
            // 다시 부르면 방금 보던 그래프까지 깜빡인다.
            AppButton(
              key: const ValueKey<String>('ai-advice-retry'),
              label: l.actionRetry,
              onPressed: onRetry,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }
}
