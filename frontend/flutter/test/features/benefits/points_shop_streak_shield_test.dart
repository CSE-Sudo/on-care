/// 포인트 사용처의 연속 기록 보호권 카드 — 가격·설명, 보유 한도에 막힘, 교환. (#1788)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';

PointsShop _shop({required bool full}) => PointsShop(
  balance: 1000,
  hasTrainer: true,
  items: <ShopItem>[
    ShopItem(
      id: 'streak_shield',
      title: '연속 기록 보호권',
      benefit: '',
      description: '',
      cost: 300,
      validDays: 0,
      redeemer: CouponRedeemer.member,
      available: !full,
      blockReason: full ? ShopBlockReason.shieldLimit : null,
    ),
  ],
);

void main() {
  Future<void> pumpShop(WidgetTester tester, FakeBenefitsRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[benefitsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsBenefitsPage(points: 1000),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const ValueKey<String> exchangeKey = ValueKey<String>(
    'shop-exchange-streak_shield',
  );

  testWidgets('보호권 카드는 300P·설명을 보이고 기한 줄이 없다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository(shop: _shop(full: false)));

    expect(find.text('연속 기록 보호권'), findsOneWidget);
    expect(find.text('300P'), findsOneWidget);
    expect(find.textContaining('운동을 못 한 어제를 연속 기록에 이어 붙여요'), findsOneWidget);
    expect(find.textContaining('동안 사용'), findsNothing);
    expect(tester.widget<AppButton>(find.byKey(exchangeKey)).onPressed, isNotNull);
  });

  testWidgets('보호권을 두 개 가지고 있으면 버튼을 막고 이유를 적는다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository(shop: _shop(full: true)));

    expect(find.text('보호권은 최대 2개까지 가질 수 있어요'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byKey(exchangeKey)).onPressed, isNull);
  });

  testWidgets('보호권도 파란 확인창을 거쳐 교환한다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository(
      shop: _shop(full: false),
    );
    await pumpShop(tester, repo);

    await tester.tap(find.byKey(exchangeKey));
    await tester.pumpAndSettle();
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.destructive, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text(pair.confirmLabel),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.exchanged, <String>['streak_shield']);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
