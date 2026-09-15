/// 내 혜택 목록과 쿠폰 화면. (#1787)
///
/// 모든 쿠폰은 헬스장이 주는 혜택이고, 직원이 확인한 뒤 회원 휴대폰에서 `사용 완료` 를
/// 누른다. PT 재등록 쿠폰은 혜택·담당 트레이너·헬스장·만료일(D-n)을, 개인 락커 쿠폰은
/// 혜택·헬스장·만료일을 보여 준다. 버튼 바로 위에 직원 확인 안내(PT 는 트레이너·헬스장
/// 직원, 락커는 헬스장 직원)가 서고, 확인창도 직원 확인용이다. 카드 아래 만료 안내는
/// 아이콘 없는 한 줄이다. 사용하면 연하늘 사용 완료 줄과 사용 시각을 보여 주고 안내는
/// 숨긴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/pages/coupon_detail_page.dart';
import 'package:oncare/features/benefits/presentation/pages/my_benefits_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    FakeBenefitsRepository repo,
    String location,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.myBenefits,
          builder: (_, _) => const MyBenefitsPage(),
        ),
        GoRoute(
          path: AppRoutes.myCouponDetail,
          builder: (_, GoRouterState state) =>
              CouponDetailPage(couponId: state.pathParameters['couponId']!),
        ),
        GoRoute(
          path: AppRoutes.myPoints,
          builder: (_, _) => const Placeholder(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[benefitsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 토스트가 스스로 사라질 때까지 흘려보낸다 — 남은 타이머로 테스트가 깨지지 않게.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  Finder useButton() => find.byKey(const Key('couponUseButton'));
  Finder staffNote() => find.byKey(const Key('couponStaffNote'));

  testWidgets('보유 쿠폰이 없으면 빈 상태와 사용처 바로가기를 보여 준다', (tester) async {
    await pumpAt(tester, FakeBenefitsRepository(), AppRoutes.myBenefits);

    expect(find.text('내 혜택'), findsOneWidget);
    expect(find.text('쿠폰'), findsOneWidget);
    expect(find.text('보유한 쿠폰이 없어요'), findsOneWidget);

    await tester.tap(find.text('포인트 사용처'));
    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('쿠폰 목록은 혜택·마지막 사용일·상태를 보여 준다', (tester) async {
    await pumpAt(
      tester,
      FakeBenefitsRepository(
        coupons: <Coupon>[
          couponOf(id: 'c-renewal', item: 'pt_renewal', daysLeft: 27),
          couponOf(id: 'c-locker', item: 'locker_month', daysLeft: 0),
          couponOf(
            id: 'c-locker-old',
            item: 'locker_month',
            status: CouponStatus.used,
          ),
        ],
      ),
      AppRoutes.myBenefits,
    );

    expect(find.text('PT 재등록 30,000원 할인'), findsOneWidget);
    expect(find.text('개인 락커 1개월 무료'), findsNWidgets(2));
    expect(find.byIcon(Icons.checkroom_rounded), findsNWidgets(2));
    expect(find.text('2026.10.15까지'), findsNWidgets(3));
    final AppTag renewalTag = tester.widget<AppTag>(
      find.byKey(const ValueKey<String>('coupon-status-c-renewal')),
    );
    expect(renewalTag.label, 'D-27');
    expect(renewalTag.tone, AppTagTone.brand);
    expect(
      tester
          .widget<AppTag>(find.byKey(const ValueKey<String>('coupon-status-c-locker')))
          .label,
      'D-day',
    );
    final AppTag usedTag = tester.widget<AppTag>(
      find.byKey(const ValueKey<String>('coupon-status-c-locker-old')),
    );
    expect(usedTag.label, '사용 완료');
    expect(usedTag.tone, AppTagTone.neutral);
  });

  testWidgets('PT 재등록 쿠폰 화면은 트레이너·헬스장·D-n 과 직원 확인 안내·사용 완료 버튼을 보여 준다', (
    tester,
  ) async {
    await pumpAt(
      tester,
      FakeBenefitsRepository(
        coupons: <Coupon>[couponOf(id: 'c-renewal', item: 'pt_renewal')],
      ),
      AppRoutes.myBenefits,
    );

    await tester.tap(find.byKey(const ValueKey<String>('coupon-c-renewal')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('couponDetailPage')), findsOneWidget);
    expect(find.text('PT 재등록 30,000원 할인'), findsOneWidget);
    // 쿠폰 코드는 없다 — 코드 상자·이름표를 그리지 않는다.
    expect(find.textContaining('코드'), findsNothing);
    expect(find.text('김트레이너'), findsOneWidget);
    expect(find.text('온케어짐 신촌점'), findsOneWidget);
    expect(find.text('2026.09.15'), findsOneWidget);
    expect(find.text('2026.10.15 (D-30)'), findsOneWidget);
    expect(find.text('사용 가능'), findsOneWidget);
    // 제목이 한 줄에 들어가도록 제목 옆 상태 태그는 두지 않는다.
    expect(
      find.byKey(const ValueKey<String>('coupon-status-c-renewal')),
      findsNothing,
    );
    // 직원에게 보여 주라는 안내는 버튼 위 직원 안내 줄과 겹쳐 따로 두지 않는다.
    expect(find.textContaining('직원에게 보여 주세요'), findsNothing);
    expect(
      find.byKey(const Key('couponExpireNotice')),
      findsOneWidget,
    );
    expect(find.text('만료되면 포인트는 돌려받을 수 없어요.'), findsOneWidget);
    expect(find.byIcon(Icons.info_rounded), findsNothing);

    // 직원에게 말하는 안내가 버튼 바로 위에 선다.
    expect(staffNote(), findsOneWidget);
    expect(
      find.descendant(
        of: staffNote(),
        matching: find.text('트레이너·헬스장 직원이 확인한 뒤 눌러 주세요'),
      ),
      findsOneWidget,
    );
    expect(useButton(), findsOneWidget);
    expect(tester.widget<AppButton>(useButton()).label, '사용 완료');
    expect(
      tester.getBottomLeft(staffNote()).dy,
      lessThan(tester.getTopLeft(useButton()).dy),
    );
    expect(find.byKey(const Key('couponUsedBanner')), findsNothing);
  });

  testWidgets('PT 재등록 쿠폰은 직원 확인용 파란 확인창을 거쳐 사용 완료되고 사용 시각을 보여 준다', (
    tester,
  ) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository(
      coupons: <Coupon>[couponOf(id: 'c-renewal', item: 'pt_renewal')],
    );
    await pumpAt(tester, repo, AppRoutes.myCouponDetailPath('c-renewal'));

    await tester.tap(useButton());
    await tester.pumpAndSettle();

    expect(find.text('쿠폰을 사용 완료할까요?'), findsOneWidget);
    expect(find.text('직원 확인용 · 사용 후 되돌릴 수 없어요'), findsOneWidget);
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '사용 완료');
    // 확정은 파란(브랜드) 채움이다.
    expect(pair.destructive, isFalse);

    // 취소하면 아무것도 바뀌지 않는다.
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.used, isEmpty);
    expect(useButton(), findsOneWidget);

    await tester.tap(useButton());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text('사용 완료'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.used, <String>['c-renewal']);
    // 사용 완료 상태 — 배너와 사용 시각, 버튼·직원 안내는 사라진다.
    expect(
      find.descendant(
        of: find.byKey(const Key('couponUsedBanner')),
        matching: find.text('2026.09.20 14:30에 사용 완료했어요'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('couponUsedAt')),
        matching: find.text('2026.09.20 14:30'),
      ),
      findsOneWidget,
    );
    // 제목 옆 상태 태그는 없다 — 상태 줄이 사용 완료를 말한다.
    expect(
      find.byKey(const ValueKey<String>('coupon-status-c-renewal')),
      findsNothing,
    );
    expect(find.text('사용 완료'), findsOneWidget);
    expect(useButton(), findsNothing);
    expect(staffNote(), findsNothing);
    // 사용한 쿠폰에는 만료 안내를 두지 않는다.
    expect(find.byKey(const Key('couponExpireNotice')), findsNothing);
    // 사용 완료 줄은 초록이 아니라 브랜드 연하늘이다.
    final Icon bannerIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('couponUsedBanner')),
        matching: find.byType(Icon),
      ),
    );
    expect(bannerIcon.color, isNot(OnCareColors.success));
    await drainToast(tester);
  });

  testWidgets('개인 락커 쿠폰은 헬스장만 보여 주고 헬스장 직원 확인 뒤 사용 완료를 누른다', (
    tester,
  ) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository(
      coupons: <Coupon>[couponOf(id: 'c-locker', item: 'locker_month')],
    );
    await pumpAt(tester, repo, AppRoutes.myCouponDetailPath('c-locker'));

    expect(find.text('개인 락커 1개월 무료'), findsOneWidget);
    expect(find.byIcon(Icons.checkroom_rounded), findsOneWidget);
    // 헬스장 줄은 있고 담당 트레이너 줄은 없다.
    expect(find.text('담당 트레이너'), findsNothing);
    expect(find.text('김트레이너'), findsNothing);
    expect(find.text('헬스장'), findsOneWidget);
    expect(find.text('온케어짐 신촌점'), findsOneWidget);
    expect(find.text('2026.10.15 (D-30)'), findsOneWidget);
    expect(find.textContaining('코드'), findsNothing);
    expect(find.textContaining('매장'), findsNothing);
    expect(find.byKey(const Key('couponExpireNotice')), findsOneWidget);

    // 직원 안내는 PT 재등록과 같은 자리, 버튼 바로 위에 헬스장 직원에게 말한다.
    expect(
      find.descendant(
        of: staffNote(),
        matching: find.text('헬스장 직원이 확인한 뒤 눌러 주세요'),
      ),
      findsOneWidget,
    );
    expect(find.text('트레이너·헬스장 직원이 확인한 뒤 눌러 주세요'), findsNothing);
    expect(
      tester.getBottomLeft(staffNote()).dy,
      lessThan(tester.getTopLeft(useButton()).dy),
    );

    await tester.tap(useButton());
    await tester.pumpAndSettle();

    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '사용 완료');
    expect(pair.destructive, isFalse);
    expect(find.text('쿠폰을 사용 완료할까요?'), findsOneWidget);
    expect(find.text('직원 확인용 · 사용 후 되돌릴 수 없어요'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text('사용 완료'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.used, <String>['c-locker']);
    expect(useButton(), findsNothing);
    expect(staffNote(), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('coupon-status-c-locker')),
      findsNothing,
    );
    expect(find.text('사용 완료'), findsOneWidget);
    expect(find.byKey(const Key('couponUsedBanner')), findsOneWidget);
    expect(find.byKey(const Key('couponUsedAt')), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('없는 쿠폰이면 찾을 수 없다고 말한다', (tester) async {
    await pumpAt(
      tester,
      FakeBenefitsRepository(),
      AppRoutes.myCouponDetailPath('missing'),
    );
    expect(find.text('쿠폰을 찾을 수 없어요'), findsOneWidget);
  });
}
