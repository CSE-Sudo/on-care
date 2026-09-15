/// 내 혜택 목록과 쿠폰 화면. (#1787)
///
/// PT 재등록 쿠폰은 혜택·담당 트레이너·헬스장·코드·만료일(D-n)을 보여 주고 사용
/// 버튼이 없다(트레이너가 처리). 건강식 쿠폰은 회원이 `사용 완료` 를 누른다.
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
          couponOf(id: 'c-salad', item: 'salad_discount', daysLeft: 0),
          couponOf(
            id: 'c-protein',
            item: 'protein_discount',
            status: CouponStatus.used,
          ),
        ],
      ),
      AppRoutes.myBenefits,
    );

    expect(find.text('PT 재등록 10,000원 할인'), findsOneWidget);
    expect(find.text('2026.10.15까지'), findsNWidgets(3));
    final AppTag renewalTag = tester.widget<AppTag>(
      find.byKey(const ValueKey<String>('coupon-status-c-renewal')),
    );
    expect(renewalTag.label, 'D-27');
    expect(renewalTag.tone, AppTagTone.brand);
    expect(
      tester
          .widget<AppTag>(find.byKey(const ValueKey<String>('coupon-status-c-salad')))
          .label,
      'D-day',
    );
    final AppTag usedTag = tester.widget<AppTag>(
      find.byKey(const ValueKey<String>('coupon-status-c-protein')),
    );
    expect(usedTag.label, '사용 완료');
    expect(usedTag.tone, AppTagTone.neutral);
  });

  testWidgets('PT 재등록 쿠폰 화면은 트레이너·헬스장·코드·D-n 을 보여 주고 사용 버튼이 없다', (
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
    expect(find.text('PT 재등록 10,000원 할인'), findsOneWidget);
    expect(find.text('ABCD-2345'), findsOneWidget);
    expect(find.text('김트레이너'), findsOneWidget);
    expect(find.text('온케어짐 신촌점'), findsOneWidget);
    expect(find.text('2026.09.15'), findsOneWidget);
    expect(find.text('2026.10.15 (D-30)'), findsOneWidget);
    expect(find.text('사용 가능'), findsOneWidget);
    expect(find.textContaining('트레이너가 사용 처리해요'), findsOneWidget);
    expect(find.text('만료되면 포인트는 돌려받을 수 없어요.'), findsOneWidget);
    expect(find.byKey(const Key('couponUseButton')), findsNothing);
  });

  testWidgets('건강식 쿠폰은 회원이 파란 확인창을 거쳐 사용 완료를 누른다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository(
      coupons: <Coupon>[couponOf(id: 'c-salad', item: 'salad_discount')],
    );
    await pumpAt(
      tester,
      repo,
      AppRoutes.myCouponDetailPath('c-salad'),
    );

    expect(find.text('담당 트레이너'), findsNothing);
    expect(find.textContaining('매장에서 코드를 보여 준 뒤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('couponUseButton')));
    await tester.pumpAndSettle();

    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '사용 완료');
    expect(pair.destructive, isFalse);
    expect(find.text('사용 완료로 바꾸면 되돌릴 수 없어요.'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text('사용 완료'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.used, <String>['c-salad']);
    expect(find.byKey(const Key('couponUseButton')), findsNothing);
    expect(
      tester
          .widget<AppTag>(find.byKey(const ValueKey<String>('coupon-status-c-salad')))
          .label,
      '사용 완료',
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
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
