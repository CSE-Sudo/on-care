/// 기록 그래프를 읽지 못한 채 그래프 색 `교환` — 조용히 끝나지 않고 실패를 알린다. (#3098)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/graph_color_sheet.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_activity_calendar_repository.dart';
import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

/// 기록 그래프 조회가 늘 실패하는 대역.
class _FailingCalendarRepository extends FakeActivityCalendarRepository {
  @override
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to}) async =>
      throw StateError('네트워크 없음');
}

const PointsShop _shop = PointsShop(
  balance: 9000,
  hasTrainer: true,
  hasGym: true,
  items: <ShopItem>[
    ShopItem(
      id: kGraphColorItem,
      title: '그래프 색',
      benefit: '',
      description: '',
      cost: 500,
      validDays: 0,
      available: true,
    ),
  ],
);

void main() {
  testWidgets('기록 그래프를 못 읽었으면 색 교환에서 실패 토스트가 뜬다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final FakeBenefitsRepository benefits = FakeBenefitsRepository(shop: _shop);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(benefits),
          challengeRepositoryProvider.overrideWithValue(
            FakeChallengeRepository(),
          ),
          activityCalendarRepositoryProvider.overrideWithValue(
            _FailingCalendarRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsBenefitsPage(points: 9000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder exchange = find.byKey(
      const ValueKey<String>('shop-exchange-$kGraphColorItem'),
    );
    await tester.ensureVisible(exchange);
    await tester.tap(exchange);
    await tester.pumpAndSettle();

    expect(find.byType(GraphColorSheet), findsNothing);
    expect(find.text('그래프 색을 바꾸지 못했어요'), findsOneWidget);
    expect(benefits.exchanged, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
