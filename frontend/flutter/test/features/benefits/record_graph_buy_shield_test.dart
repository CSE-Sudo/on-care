/// 기록 그래프에서 보호권 없이 `보호권 쓰기` — 구매를 묻고, 사면 그날에 바로 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_activity_calendar_repository.dart';
import '../exercise/fake_streak_shield_repository.dart';
import 'fake_benefits_repository.dart';

final DateTime _today = DateTime(2026, 9, 17);
final DateTime _yesterday = DateTime(2026, 9, 16);

PointsShop _shop({int balance = 1000}) => PointsShop(
  balance: balance,
  hasTrainer: true,
  hasGym: true,
  items: <ShopItem>[
    ShopItem(
      id: 'streak_shield',
      title: '연속 기록 보호권',
      benefit: '',
      description: '',
      cost: 300,
      validDays: 0,
      available: balance >= 300,
      blockReason: balance >= 300 ? null : ShopBlockReason.insufficientPoints,
      shortfall: balance >= 300 ? 0 : 300 - balance,
    ),
  ],
);

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required FakeBenefitsRepository benefits,
    required FakeStreakShieldRepository shields,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(benefits),
          streakShieldRepositoryProvider.overrideWithValue(shields),
          activityCalendarRepositoryProvider.overrideWithValue(
            FakeActivityCalendarRepository(
              now: () => _today,
              protectableFrom: DateTime(2026, 8, 18),
              protectableTo: _yesterday,
            ),
          ),
        ],
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

  Future<void> tapProtectOnYesterday(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('record-cell-2026-09-16')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordGraphProtect')));
    await tester.pumpAndSettle();
  }

  testWidgets('보호권이 없으면 구매를 묻고, 사면 그날에 바로 쓴다', (tester) async {
    final FakeBenefitsRepository benefits = FakeBenefitsRepository(
      shop: _shop(),
    );
    final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
    await pumpPage(tester, benefits: benefits, shields: shields);

    await tapProtectOnYesterday(tester);

    expect(find.text('보호권을 구매할까요?'), findsOneWidget);
    expect(find.textContaining('300P로 보호권을 구매하고 9월 16일을'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text('구매하고 쓰기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(benefits.exchanged, <String>['streak_shield']);
    expect(shields.used, <DateTime>[_yesterday]);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('구매를 취소하면 사지도 쓰지도 않는다', (tester) async {
    final FakeBenefitsRepository benefits = FakeBenefitsRepository(
      shop: _shop(),
    );
    final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
    await pumpPage(tester, benefits: benefits, shields: shields);

    await tapProtectOnYesterday(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text('취소'),
      ),
    );
    await tester.pumpAndSettle();

    expect(benefits.exchanged, isEmpty);
    expect(shields.used, isEmpty);
  });

  testWidgets('포인트가 모자라면 확인창 대신 부족한 만큼을 알린다', (tester) async {
    final FakeBenefitsRepository benefits = FakeBenefitsRepository(
      shop: _shop(balance: 100),
    );
    final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
    await pumpPage(tester, benefits: benefits, shields: shields);

    await tapProtectOnYesterday(tester);

    expect(find.text('보호권을 구매할까요?'), findsNothing);
    expect(find.text('200P 부족해요'), findsWidgets);
    expect(benefits.exchanged, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
