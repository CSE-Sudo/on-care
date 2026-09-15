import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 혜택 — 포인트로 교환한 쿠폰을 모아 본다. (#1787)
///
/// MY 의 포인트 카드 바로 아래 줄과 포인트 사용처 화면에서 들어온다. 지금은 쿠폰
/// 한 구역뿐이지만, 연속 기록 보호권·참가 챌린지(#1788, #1789)가 같은 화면에
/// 구역으로 더해진다 — 그래서 목록 위에 구역 제목을 둔다.
class MyBenefitsPage extends ConsumerWidget {
  const MyBenefitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<Coupon>> coupons = ref.watch(myCouponsProvider);
    final AsyncValue<List<Challenge>> challenges = ref.watch(
      myChallengesProvider,
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
                      icon: Icons.redeem_rounded,
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
        // 참가 챌린지(#1789) — 이번 주 진행과 지난 주 결과.
        const SizedBox(height: OnCareSpacing.sectionGap),
        AppSectionHeader(title: l.myBenefitsChallenges),
        const SizedBox(height: OnCareSpacing.s12),
        ...challenges.when(
          loading: () => const <Widget>[
            AppCard(child: AppLoading(placement: AppStatePlacement.card)),
          ],
          error: (_, _) => <Widget>[
            AppCard(
              child: AppErrorState(
                title: l.challengeLoadFailed,
                retryLabel: l.actionRetry,
                onRetry: () => ref.invalidate(myChallengesProvider),
                placement: AppStatePlacement.card,
              ),
            ),
          ],
          data: (List<Challenge> list) => list.isEmpty
              ? <Widget>[
                  // 바로가기 버튼은 쿠폰 빈 상태에만 둔다 — 같은 버튼이 둘이면 어느
                  // 쪽을 눌러야 할지 흐려진다. 안내 문구가 사용처를 가리킨다.
                  AppCard(
                    child: AppEmptyState(
                      title: l.myBenefitsChallengesEmpty,
                      message: l.myBenefitsChallengesEmptyMessage,
                      icon: kChallengeIcon,
                      placement: AppStatePlacement.card,
                    ),
                  ),
                ]
              : <Widget>[
                  for (int i = 0; i < list.length; i++) ...<Widget>[
                    ChallengeListCard(challenge: list[i]),
                    if (i < list.length - 1)
                      const SizedBox(height: OnCareSpacing.cardGap),
                  ],
                ],
        ),
      ],
    );
  }
}
