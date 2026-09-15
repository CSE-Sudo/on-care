/// 포인트 사용처 — 교환 카드, 잔액 부족 상태, 파란 2열 확인창 흐름. (#1787)
///
/// 예전 세 카드(결제 차감 할인·예측 리포트·레시피)는 사라지고 교환할 수 있는
/// 항목이 선다. 교환은 `교환` → `취소 / 교환하기` 확인창 → 포인트 차감 순서다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';

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
          home: const PointsBenefitsPage(points: 1240),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder exchangeButton(String item) =>
      find.byKey(ValueKey<String>('shop-exchange-$item'));

  AppButton buttonOf(WidgetTester tester, String item) =>
      tester.widget<AppButton>(exchangeButton(item));

  /// 토스트가 스스로 사라질 때까지 흘려보낸다 — 남은 타이머로 테스트가 깨지지 않게.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('교환할 수 있는 세 항목이 서고 예전 카드는 없다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository());

    expect(find.text('PT 재등록 할인 쿠폰'), findsOneWidget);
    expect(find.text('샐러드 10% 할인'), findsOneWidget);
    expect(find.text('프로틴 3,000원 할인'), findsOneWidget);
    expect(find.text('5,000P'), findsOneWidget);
    expect(find.text('1,000P'), findsNWidgets(2));
    expect(find.text('교환 후 30일 동안 사용'), findsNWidgets(3));
    expect(find.text('보유 1,240P'), findsNothing);
    expect(find.text('보유 1240P'), findsOneWidget);

    expect(find.textContaining('결제'), findsNothing);
    expect(find.textContaining('리포트'), findsNothing);
    expect(find.textContaining('레시피'), findsNothing);
    // 헤더의 적립 안내 (i) 는 그대로다.
    expect(
      find.descendant(
        of: find.byType(AppTopBar),
        matching: find.byType(AppIconButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('잔액이 모자라면 버튼이 막히고 부족한 포인트를 알려 준다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository());

    expect(buttonOf(tester, 'pt_renewal').onPressed, isNull);
    expect(
      find.byKey(const ValueKey<String>('shop-blocked-pt_renewal')),
      findsOneWidget,
    );
    expect(find.text('3,760P 부족해요'), findsOneWidget);
    expect(buttonOf(tester, 'salad_discount').onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey<String>('shop-blocked-salad_discount')),
      findsNothing,
    );
  });

  testWidgets('담당 트레이너가 없으면 재등록 쿠폰은 그 이유로 막힌다', (tester) async {
    await pumpShop(
      tester,
      FakeBenefitsRepository(shop: shopWith(balance: 9000, hasTrainer: false)),
    );

    expect(buttonOf(tester, 'pt_renewal').onPressed, isNull);
    expect(find.text('담당 트레이너가 있어야 교환할 수 있어요'), findsOneWidget);
  });

  testWidgets('교환 → 파란 2열 확인창 → 교환하기로 포인트를 쓴다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository();
    await pumpShop(tester, repo);

    await tester.tap(exchangeButton('salad_discount'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('포인트로 교환할까요?'), findsOneWidget);
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '교환하기');
    // 일반 확정은 파란(브랜드) 채움이다.
    expect(pair.destructive, isFalse);

    await tester.tap(find.text('교환하기'));
    await tester.pumpAndSettle();

    expect(repo.exchanged, <String>['salad_discount']);
    expect(find.byType(AppDialog), findsNothing);
    // 목록을 다시 읽어 잔액이 줄었다.
    expect(find.text('보유 240P'), findsOneWidget);
    expect(find.text('교환했어요'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('사용하지 않은 같은 종류 쿠폰이 있으면 그 카드만 막힌다', (tester) async {
    await pumpShop(
      tester,
      FakeBenefitsRepository(
        shop: shopWith(balance: 9000, activeItems: <String>{'salad_discount'}),
      ),
    );

    expect(buttonOf(tester, 'salad_discount').onPressed, isNull);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('shop-blocked-salad_discount')),
          )
          .data,
      '사용하지 않은 쿠폰이 있어요',
    );
    // 다른 종류는 따로 센다.
    expect(buttonOf(tester, 'protein_discount').onPressed, isNotNull);
    expect(buttonOf(tester, 'pt_renewal').onPressed, isNotNull);
  });

  testWidgets('건강식 쿠폰을 교환하면 그 카드가 사용하지 않은 쿠폰으로 막힌다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository(
      shop: shopWith(balance: 3000),
    );
    await pumpShop(tester, repo);

    await tester.tap(exchangeButton('protein_discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('교환하기'));
    await tester.pumpAndSettle();

    expect(repo.exchanged, <String>['protein_discount']);
    expect(buttonOf(tester, 'protein_discount').onPressed, isNull);
    expect(
      find.byKey(const ValueKey<String>('shop-blocked-protein_discount')),
      findsOneWidget,
    );
    expect(buttonOf(tester, 'salad_discount').onPressed, isNotNull);
    await drainToast(tester);
  });

  testWidgets('확인창에서 취소하면 교환하지 않는다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository();
    await pumpShop(tester, repo);

    await tester.tap(exchangeButton('protein_discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(repo.exchanged, isEmpty);
    expect(find.text('보유 1240P'), findsOneWidget);
  });
}
