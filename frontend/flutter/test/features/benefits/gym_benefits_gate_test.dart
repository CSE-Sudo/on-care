/// 헬스장 혜택 기능 플래그(#2822) — 제휴 헬스장이 없는 실서버 응답이면 PT 재등록·락커
/// 사용처와 분석용 식판 카드가 보이지 않고, 데모(목업) 응답은 지금 그대로다.
///
/// 사용처 목록은 서버가 두 항목을 빼서 보내므로 앱은 받은 대로 그린다. 식판 카드는
/// 응답의 `enabled` 를 보고 내린다. 필드가 없는 응답(데모 목업)은 열린 것으로 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

const DietTray _trayOpen = DietTray(
  status: DietTrayStatus.progress,
  photoDays: 12,
  requiredDays: 20,
  windowDays: 28,
  hasTrainer: true,
);

const DietTray _trayClosed = DietTray(
  status: DietTrayStatus.progress,
  photoDays: 20,
  requiredDays: 20,
  windowDays: 28,
  hasTrainer: true,
  enabled: false,
);

/// 실서버(헬스장 혜택 닫힘) 응답 — 서버가 두 항목을 빼고 보낸 목록.
PointsShop _closedShop() => PointsShop(
  balance: 30000,
  hasTrainer: true,
  hasGym: true,
  gymBenefitsEnabled: false,
  items: <ShopItem>[
    for (final ShopItem item in shopWith(balance: 30000).items)
      if (item.id != 'pt_renewal' && item.id != 'locker_month') item,
  ],
);

void main() {
  group('응답 해석', () {
    test('식판 응답에 enabled 가 없으면 열린 것으로 읽는다(데모 목업)', () {
      final DietTray tray = DietTray.fromJson(<String, Object?>{
        'status': 'progress',
        'photo_days': 3,
        'required_days': 20,
        'window_days': 28,
        'has_trainer': true,
      });
      expect(tray.enabled, isTrue);
    });

    test('식판 응답의 enabled: false 를 그대로 읽는다', () {
      final DietTray tray = DietTray.fromJson(<String, Object?>{
        'status': 'progress',
        'photo_days': 20,
        'required_days': 20,
        'window_days': 28,
        'has_trainer': true,
        'enabled': false,
      });
      expect(tray.enabled, isFalse);
    });

    test('사용처 응답의 gym_benefits_enabled 를 읽고, 없으면 참이다', () {
      final PointsShop closed = PointsShop.fromJson(<String, Object?>{
        'balance': 0,
        'has_trainer': false,
        'has_gym': false,
        'gym_benefits_enabled': false,
        'items': <Object?>[],
      });
      expect(closed.gymBenefitsEnabled, isFalse);

      final PointsShop legacy = PointsShop.fromJson(<String, Object?>{
        'balance': 0,
        'has_trainer': false,
        'has_gym': false,
        'items': <Object?>[],
      });
      expect(legacy.gymBenefitsEnabled, isTrue);
    });
  });

  group('포인트 사용처 화면', () {
    Future<void> pumpShop(
      WidgetTester tester,
      FakeBenefitsRepository repo,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            benefitsRepositoryProvider.overrideWithValue(repo),
            challengeRepositoryProvider.overrideWithValue(
              FakeChallengeRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PointsBenefitsPage(points: 30000),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('혜택이 닫힌 실서버 응답이면 두 쿠폰과 식판 카드가 없다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository(
        shop: _closedShop(),
      )..tray = _trayClosed;
      await pumpShop(tester, repo);

      expect(find.byKey(const Key('dietTrayCard')), findsNothing);
      expect(find.text('PT 재등록 3만원 할인'), findsNothing);
      expect(find.text('개인 락커 1개월 무료'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('shop-exchange-pt_renewal')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('shop-exchange-locker_month')),
        findsNothing,
      );
      // 화면 자체는 그대로 열린다 — 잔액과 내 혜택 입구가 남는다.
      expect(find.byKey(const Key('pointsShopBalance')), findsOneWidget);
      expect(find.byKey(const Key('pointsShopMyBenefits')), findsOneWidget);
    });

    testWidgets('데모(목업) 응답은 두 쿠폰과 식판 카드가 지금처럼 선다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository(
        shop: shopWith(balance: 30000),
      )..tray = _trayOpen;
      await pumpShop(tester, repo);

      expect(find.byKey(const Key('dietTrayCard')), findsOneWidget);
      expect(find.text('PT 재등록 3만원 할인'), findsOneWidget);
      expect(find.text('개인 락커 1개월 무료'), findsOneWidget);
    });

    testWidgets('식판만 닫혀도 카드만 내리고 사용처 목록은 그대로다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository(
        shop: shopWith(balance: 30000),
      )..tray = _trayClosed;
      await pumpShop(tester, repo);

      expect(find.byKey(const Key('dietTrayCard')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('shop-exchange-locker_month')),
        findsOneWidget,
      );
    });
  });
}
