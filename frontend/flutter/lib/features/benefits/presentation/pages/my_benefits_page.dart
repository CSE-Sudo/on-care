import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/streak_shield_card.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 혜택 — 포인트로 교환한 쿠폰을 모아 본다. (#1787)
///
/// MY 의 포인트 카드 바로 아래 줄과 포인트 사용처 화면에서 들어온다. 쿠폰 구역
/// 아래에 연속 기록 보호권(#1788) 구역이 서고, 참가 챌린지(#1789)도 같은 화면에
/// 구역으로 더해진다 — 그래서 목록 위에 구역 제목을 둔다.
class MyBenefitsPage extends ConsumerWidget {
  const MyBenefitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<Coupon>> coupons = ref.watch(myCouponsProvider);
    final AsyncValue<StreakShields> shields = ref.watch(
      myStreakShieldsProvider,
    );
    return AppPage(
      key: const Key('myBenefitsPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(title: l.myBenefitsTitle),
      children: <Widget>[
        AppSectionHeader(title: l.myBenefitsCoupons),
        const SizedBox(height: OnCareSpacing.s12),
        ...coupons.when(
          loading: () => const <Widget>[
            AppCard(child: AppLoading(placement: AppStatePlacement.card)),
          ],
          error: (_, _) => <Widget>[
            AppCard(
              child: AppErrorState(
                title: l.myBenefitsLoadFailed,
                retryLabel: l.actionRetry,
                onRetry: () => ref.invalidate(myCouponsProvider),
                placement: AppStatePlacement.card,
              ),
            ),
          ],
          data: (List<Coupon> list) => list.isEmpty
              ? <Widget>[
                  AppCard(
                    child: AppEmptyState(
                      title: l.myBenefitsEmpty,
                      message: l.myBenefitsEmptyMessage,
                      icon: AppIcons.coupon,
                      actionLabel: l.myPointsBenefitsTitle,
                      onAction: () => context.push<void>(AppRoutes.myPoints),
                      placement: AppStatePlacement.card,
                    ),
                  ),
                ]
              : <Widget>[
                  for (int i = 0; i < list.length; i++) ...<Widget>[
                    CouponListCard(
                      coupon: list[i],
                      onTap: () => context.push<void>(
                        AppRoutes.myCouponDetailPath(list[i].id),
                      ),
                    ),
                    if (i < list.length - 1)
                      const SizedBox(height: OnCareSpacing.cardGap),
                  ],
                ],
        ),
        // 연속 기록 보호권(#1788) — 보유 수와 보호한 날.
        const SizedBox(height: OnCareSpacing.s24),
        AppSectionHeader(title: l.myBenefitsStreakShields),
        const SizedBox(height: OnCareSpacing.s12),
        ...shields.when(
          loading: () => const <Widget>[
            AppCard(child: AppLoading(placement: AppStatePlacement.card)),
          ],
          error: (_, _) => <Widget>[
            AppCard(
              child: AppErrorState(
                title: l.myBenefitsLoadFailed,
                retryLabel: l.actionRetry,
                onRetry: () => ref.invalidate(myStreakShieldsProvider),
                placement: AppStatePlacement.card,
              ),
            ),
          ],
          data: (StreakShields data) => <Widget>[
            StreakShieldSummaryCard(shields: data),
          ],
        ),
      ],
    );
  }
}
