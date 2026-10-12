/// 교환·식판 받기·챌린지 참가의 요청 키와 실패 안내. (#3363)
///
/// 서버가 처리하고 응답만 잃은 요청을 회원이 다시 누르면 같은 키로 나가야 서버가
/// 처음 결과를 돌려준다 — 보호권은 여러 장 살 수 있어, 새 키로 나가면 한 장이 더
/// 생기고 포인트가 한 번 더 빠진다. 서버가 거절한 요청은 까닭에 맞는 말을 하고,
/// 실패 뒤에도 잔액은 서버 값으로 다시 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_activity_calendar_repository.dart';
import '../exercise/fake_streak_shield_repository.dart';
import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

final DateTime _today = DateTime(2026, 9, 17);
final DateTime _yesterday = DateTime(2026, 9, 16);

ServerError _conflict(String detail) =>
    ServerError(statusCode: 409, message: detail, detail: detail);

/// 보호권 한 항목만 파는 사용처 — 서버처럼 요청 키로 재전송을 한 번으로 처리한다.
class _ShieldShopRepository extends FakeBenefitsRepository {
  int balance = 1000;

  /// 서버가 실제로 만든 보호권 수.
  int bought = 0;

  /// 받은 요청 키, 받은 순서대로.
  final List<String?> requestIds = <String?>[];

  /// 이 횟수만큼 교환을 처리한 뒤 응답을 잃는다.
  int lostResponses = 0;

  /// 앞에서부터 꺼내 던진다 — 서버 거절.
  final List<Object> errors = <Object>[];

  int shopCalls = 0;

  final Set<String?> _done = <String?>{};

  @override
  Future<PointsShop> fetchShop() async {
    shopCalls++;
    return PointsShop(
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
          blockReason: balance >= 300
              ? null
              : ShopBlockReason.insufficientPoints,
          shortfall: balance >= 300 ? 0 : 300 - balance,
        ),
      ],
    );
  }

  @override
  Future<CouponExchange> exchange(
    String itemId, {
    String? option,
    String? clientRequestId,
  }) async {
    requestIds.add(clientRequestId);
    if (errors.isNotEmpty) throw errors.removeAt(0);
    if (_done.add(clientRequestId)) {
      bought++;
      balance -= 300;
    }
    if (lostResponses > 0) {
      lostResponses--;
      throw const NetworkError();
    }
    return CouponExchange(coupon: null, spent: 300, balance: balance);
  }
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required FakeBenefitsRepository benefits,
    FakeChallengeRepository? challenges,
    FakeStreakShieldRepository? shields,
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(benefits),
          challengeRepositoryProvider.overrideWithValue(
            challenges ?? FakeChallengeRepository(),
          ),
          streakShieldRepositoryProvider.overrideWithValue(
            shields ?? FakeStreakShieldRepository(),
          ),
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
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsBenefitsPage(points: 1000),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 토스트가 스스로 사라질 때까지 흘려보낸다.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> exchange(WidgetTester tester, String item) async {
    await tester.tap(find.byKey(ValueKey<String>('shop-exchange-$item')));
    await tester.pumpAndSettle();
    await confirm(tester, '교환');
  }

  /// 토스트 문구. 이 시험의 사용처 카드는 같은 글자를 그리지 않는다.
  Finder toast(String text) => find.text(text);

  group('보호권 교환', () {
    testWidgets('응답을 잃은 뒤 다시 눌러도 같은 키로 나가 한 장만 생긴다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..lostResponses = 1;
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'streak_shield');
      expect(toast('교환하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      // 실패 뒤에도 잔액은 서버 값이다 — 서버는 이미 300P 를 뺐다.
      expect(find.text('보유 700P'), findsOneWidget);
      await drainToast(tester);

      await exchange(tester, 'streak_shield');
      expect(toast('교환했어요'), findsOneWidget);
      await drainToast(tester);

      expect(repo.requestIds, hasLength(2));
      expect(repo.requestIds[0], isNotNull);
      expect(repo.requestIds[1], repo.requestIds[0]);
      expect(repo.bought, 1);
      expect(repo.balance, 700);
      expect(find.text('보유 700P'), findsOneWidget);
    });

    testWidgets('성공한 뒤 다시 누르면 새 교환이라 새 키다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository();
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'streak_shield');
      await drainToast(tester);
      await exchange(tester, 'streak_shield');
      await drainToast(tester);

      expect(repo.requestIds, hasLength(2));
      expect(repo.requestIds[1], isNot(repo.requestIds[0]));
      expect(repo.bought, 2);
      expect(find.text('보유 400P'), findsOneWidget);
    });

    testWidgets('잔액 부족으로 거절되면 부족한 만큼을 알리고 키를 버린다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..errors.add(_conflict('포인트가 200P 부족해요.'));
      await pumpPage(tester, benefits: repo);
      final int callsBefore = repo.shopCalls;

      await exchange(tester, 'streak_shield');
      expect(toast('200P 부족해요'), findsOneWidget);
      expect(toast('교환하지 못했어요. 다시 시도해 주세요.'), findsNothing);
      // 거절 뒤에도 사용처를 다시 읽는다.
      expect(repo.shopCalls, greaterThan(callsBefore));
      await drainToast(tester);

      await exchange(tester, 'streak_shield');
      await drainToast(tester);
      // 서버가 거절한 키로는 만들어진 것이 없다 — 다음은 새 시도다.
      expect(repo.requestIds[1], isNot(repo.requestIds[0]));
      expect(repo.bought, 1);
    });

    testWidgets('최대 보유로 거절되면 한도를 알린다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..errors.add(_conflict('보호권은 최대 4개까지 가질 수 있어요.'));
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'streak_shield');
      expect(toast('보호권은 최대 4개까지 가질 수 있어요'), findsOneWidget);
      expect(repo.bought, 0);
      await drainToast(tester);
    });

    testWidgets('그 밖의 거절은 서버 사유를 그대로 보이고 다시 시도를 권하지 않는다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..errors.add(_conflict('지금은 교환할 수 없는 항목이에요.'));
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'streak_shield');
      expect(toast('지금은 교환할 수 없는 항목이에요.'), findsOneWidget);
      await drainToast(tester);
    });

    testWidgets('영어 화면에서는 서버 사유 대신 앱 문구로 물러난다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..errors.addAll(<Object>[
          _conflict('지금은 교환할 수 없는 항목이에요.'),
          _conflict('포인트가 부족해요.'),
        ]);
      await pumpPage(tester, benefits: repo, locale: const Locale('en'));
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(PointsBenefitsPage)),
      );

      Future<void> redeem() async {
        await tester.tap(
          find.byKey(const ValueKey<String>('shop-exchange-streak_shield')),
        );
        await tester.pumpAndSettle();
        await confirm(tester, l.myPointsExchangeConfirmAction);
      }

      await redeem();
      expect(toast(l.myPointsExchangeBlocked), findsOneWidget);
      await drainToast(tester);

      await redeem();
      expect(toast(l.myPointsInsufficient), findsOneWidget);
      await drainToast(tester);
    });
  });

  group('쿠폰 교환', () {
    testWidgets('이미 교환된 항목이면 실패가 아니라 이미 받았다고 알린다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository()
        ..exchangeErrors.add(_conflict('사용하지 않은 쿠폰이 이미 있어요.'));
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'locker_month');

      expect(toast('이미 받았어요'), findsOneWidget);
      expect(toast('교환하지 못했어요. 다시 시도해 주세요.'), findsNothing);
      await drainToast(tester);
    });

    testWidgets('이번 달 한도로 거절되면 한도를 알린다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository()
        ..exchangeErrors.add(_conflict('이번 달에는 이미 교환했어요.'));
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'locker_month');

      expect(toast('이번 달에는 이미 교환했어요'), findsOneWidget);
      await drainToast(tester);
    });

    testWidgets('답을 받지 못하면 같은 키로 다시 나간다', (tester) async {
      final FakeBenefitsRepository repo = FakeBenefitsRepository()
        ..exchangeErrors.add(const NetworkError());
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'locker_month');
      expect(toast('교환하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      await drainToast(tester);
      await exchange(tester, 'locker_month');
      await drainToast(tester);

      expect(repo.exchangeRequestIds, hasLength(2));
      expect(repo.exchangeRequestIds[0], isNotNull);
      expect(repo.exchangeRequestIds[1], repo.exchangeRequestIds[0]);
      expect(repo.exchanged, <String>['locker_month']);
    });
  });

  group('기록 그래프에서 보호권 구매', () {
    Future<void> buyOnYesterday(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('record-cell-2026-09-16')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recordGraphProtect')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppButtonPair),
          matching: find.text('구매하고 사용'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('구매 응답을 잃은 뒤 다시 눌러도 한 장만 사서 그날에 쓴다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..lostResponses = 1;
      final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
      await pumpPage(tester, benefits: repo, shields: shields);

      await buyOnYesterday(tester);
      expect(toast('교환하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(shields.used, isEmpty);
      await drainToast(tester);

      await buyOnYesterday(tester);
      await drainToast(tester);

      expect(repo.requestIds, hasLength(2));
      expect(repo.requestIds[1], repo.requestIds[0]);
      expect(repo.bought, 1);
      expect(repo.balance, 700);
      expect(shields.used, <DateTime>[_yesterday]);
    });

    testWidgets('사용처 카드에서 잃은 구매를 그래프에서 다시 눌러도 같은 키다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..lostResponses = 1;
      await pumpPage(tester, benefits: repo);

      await exchange(tester, 'streak_shield');
      await drainToast(tester);
      await buyOnYesterday(tester);
      await drainToast(tester);

      expect(repo.requestIds[1], repo.requestIds[0]);
      expect(repo.bought, 1);
    });

    testWidgets('구매가 잔액 부족으로 거절되면 부족한 만큼을 알리고 쓰지 않는다', (tester) async {
      final _ShieldShopRepository repo = _ShieldShopRepository()
        ..errors.add(_conflict('포인트가 50P 부족해요.'));
      final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
      await pumpPage(tester, benefits: repo, shields: shields);

      await buyOnYesterday(tester);

      expect(toast('50P 부족해요'), findsOneWidget);
      expect(shields.used, isEmpty);
      await drainToast(tester);
    });
  });

  group('식판 받기', () {
    FakeBenefitsRepository claimable() =>
        FakeBenefitsRepository()
          ..tray = const DietTray(
            status: DietTrayStatus.claimable,
            photoDays: 20,
            requiredDays: 20,
            windowDays: 28,
            hasTrainer: true,
          );

    Future<void> claim(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('dietTrayClaim')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('받기')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('답을 받지 못하면 같은 키로 다시 나간다', (tester) async {
      final FakeBenefitsRepository repo = claimable()
        ..trayErrors.add(const NetworkError());
      await pumpPage(tester, benefits: repo);

      await claim(tester);
      expect(toast('식판 수령 쿠폰을 받지 못했어요'), findsOneWidget);
      await drainToast(tester);
      await claim(tester);
      await drainToast(tester);

      expect(repo.trayRequestIds, hasLength(2));
      expect(repo.trayRequestIds[0], isNotNull);
      expect(repo.trayRequestIds[1], repo.trayRequestIds[0]);
      expect(repo.trayClaims, 1);
    });

    testWidgets('이미 받았으면 이미 받았다고 알린다', (tester) async {
      final FakeBenefitsRepository repo = claimable()
        ..trayErrors.add(_conflict('받지 않은 식판 쿠폰이 이미 있어요.'));
      await pumpPage(tester, benefits: repo);

      await claim(tester);

      expect(toast('이미 받았어요'), findsOneWidget);
      expect(repo.trayClaims, 0);
      await drainToast(tester);
    });

    testWidgets('조건에 막히면 서버 사유를 보인다', (tester) async {
      final FakeBenefitsRepository repo = claimable()
        ..trayErrors.add(_conflict('식단 사진 기록이 1일 더 필요해요.'));
      await pumpPage(tester, benefits: repo);

      await claim(tester);

      expect(toast('식단 사진 기록이 1일 더 필요해요.'), findsOneWidget);
      await drainToast(tester);
    });
  });

  group('챌린지 참가', () {
    Future<void> join(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('weeklyChallengeJoin')));
      await tester.pumpAndSettle();
      await confirm(tester, '참가');
    }

    testWidgets('답을 받지 못하면 같은 키로 다시 나간다', (tester) async {
      final FakeChallengeRepository challenges = FakeChallengeRepository()
        ..joinErrors.add(const NetworkError());
      await pumpPage(
        tester,
        benefits: FakeBenefitsRepository(),
        challenges: challenges,
      );

      await join(tester);
      expect(toast('참가하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      await drainToast(tester);
      await join(tester);
      await drainToast(tester);

      expect(challenges.joinRequestIds, hasLength(2));
      expect(challenges.joinRequestIds[0], isNotNull);
      expect(challenges.joinRequestIds[1], challenges.joinRequestIds[0]);
    });

    testWidgets('이미 참가했으면 이미 참가했다고 알린다', (tester) async {
      final FakeChallengeRepository challenges = FakeChallengeRepository()
        ..joinErrors.add(_conflict('이번 주 챌린지에 이미 참가했어요.'));
      await pumpPage(
        tester,
        benefits: FakeBenefitsRepository(),
        challenges: challenges,
      );

      await join(tester);

      expect(toast('이미 참가했어요'), findsOneWidget);
      expect(toast('참가하지 못했어요. 다시 시도해 주세요.'), findsNothing);
      await drainToast(tester);
    });

    testWidgets('잔액 부족으로 거절되면 부족한 만큼을 알리고 카드를 다시 읽는다', (tester) async {
      final FakeChallengeRepository challenges = FakeChallengeRepository()
        ..joinErrors.add(_conflict('포인트가 40P 부족해요.'));
      await pumpPage(
        tester,
        benefits: FakeBenefitsRepository(),
        challenges: challenges,
      );
      final int callsBefore = challenges.weeklyCalls;

      await join(tester);

      expect(toast('40P 부족해요'), findsOneWidget);
      expect(challenges.weeklyCalls, greaterThan(callsBefore));
      await drainToast(tester);
    });

    testWidgets('참가 요일이 지나 거절되면 서버 사유를 보인다', (tester) async {
      final FakeChallengeRepository challenges = FakeChallengeRepository()
        ..joinErrors.add(_conflict('주간 챌린지는 월·화요일에만 참가할 수 있어요.'));
      await pumpPage(
        tester,
        benefits: FakeBenefitsRepository(),
        challenges: challenges,
      );

      await join(tester);

      expect(toast('주간 챌린지는 월·화요일에만 참가할 수 있어요.'), findsOneWidget);
      await drainToast(tester);
    });
  });
}
