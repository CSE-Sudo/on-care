/// 포인트 화면의 분석용 식판 카드 — 진행률, 담당 없음, 받기 흐름, 받은 뒤. (#2150)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

void main() {
  Future<void> pumpShop(
    WidgetTester tester,
    FakeBenefitsRepository repo,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
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
          home: const PointsBenefitsPage(points: 9000),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 카드는 줄이 띄어쓰기에서만 바뀌게 글자 사이에 줄바꿈 금지 문자를 끼운다 —
  /// 비교할 때는 뺀다.
  String plain(String text) => text.replaceAll('\u2060', '');

  String statusLine(WidgetTester tester) => plain(
    tester.widget<Text>(find.byKey(const Key('dietTrayStatusLine'))).data!,
  );

  DietTray trayOf(
    DietTrayStatus status, {
    int days = 12,
    bool hasTrainer = true,
    Coupon? coupon,
  }) => DietTray(
    status: status,
    photoDays: days,
    requiredDays: 20,
    windowDays: 28,
    hasTrainer: hasTrainer,
    coupon: coupon,
  );

  testWidgets('진행 중이면 사진 기록일과 남은 날, 유의사항을 보여 준다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository());

    expect(find.text('분석용 식판 무료 제공'), findsOneWidget);
    expect(find.text('무료'), findsOneWidget);
    expect(find.text('최근 28일 사진 기록'), findsOneWidget);
    expect(find.text('12 / 20일'), findsOneWidget);
    expect(statusLine(tester), '8일 더 찍으면 받을 수 있어요');
    expect(find.byKey(const Key('dietTrayClaim')), findsNothing);
    expect(
      plain(tester.widget<Text>(find.byKey(const Key('dietTrayNotice'))).data!),
      contains('1인 1회'),
    );
  });

  testWidgets('담당 트레이너가 없으면 조건을 채워도 연결 안내만 보인다', (tester) async {
    await pumpShop(
      tester,
      FakeBenefitsRepository()
        ..tray = trayOf(DietTrayStatus.progress, days: 22, hasTrainer: false),
    );

    expect(statusLine(tester), '담당 트레이너를 연결하면 받을 수 있어요');
    expect(find.byKey(const Key('dietTrayClaim')), findsNothing);
  });

  testWidgets('받기 → 확인창 → 수령 쿠폰이 생기고 쿠폰 보기로 바뀐다', (tester) async {
    final FakeBenefitsRepository repo = FakeBenefitsRepository()
      ..tray = trayOf(DietTrayStatus.claimable, days: 20);
    await pumpShop(tester, repo);

    expect(statusLine(tester), '조건을 채웠어요! 담당 트레이너의 헬스장에서 받아요');
    await tester.tap(find.byKey(const Key('dietTrayClaim')));
    await tester.pumpAndSettle();
    expect(find.text('식판 수령 쿠폰을 받을까요?'), findsOneWidget);
    // 확인창의 `받기` — 카드의 버튼과 같은 글자라 창 안에서 찾는다.
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('받기')),
    );
    await tester.pumpAndSettle();

    expect(repo.trayClaims, 1);
    expect(repo.coupons.first.item, 'diet_tray');
    expect(find.byKey(const Key('dietTrayViewCoupon')), findsOneWidget);
    expect(find.byKey(const Key('dietTrayProgress')), findsNothing);
    expect(
      statusLine(tester),
      '온케어짐 신촌점에서 받아요. 가기 전에 담당 트레이너에게 준비됐는지 채팅으로 물어보세요',
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('설명·안내 줄은 낱말 안에서 끊기지 않는다', (tester) async {
    await pumpShop(tester, FakeBenefitsRepository());

    final String notice = tester
        .widget<Text>(find.byKey(const Key('dietTrayNotice')))
        .data!;
    // 띄어쓰기 자리에서만 줄이 바뀐다 — 낱말 안 글자 사이에는 금지 문자가 있다.
    expect(notice.split(' ').first, '1\u2060인');
  });

  testWidgets('받은 뒤에는 막대와 버튼 없이 받았다고만 말한다', (tester) async {
    await pumpShop(
      tester,
      FakeBenefitsRepository()
        ..tray = trayOf(
          DietTrayStatus.received,
          days: 20,
          coupon: couponOf(
            id: 'cpn-tray',
            item: 'diet_tray',
            status: CouponStatus.used,
          ),
        ),
    );

    expect(statusLine(tester), '식판을 받았어요. 식판에 담아 찍어 보세요');
    expect(find.byKey(const Key('dietTrayProgress')), findsNothing);
    expect(find.byKey(const Key('dietTrayClaim')), findsNothing);
    expect(find.byKey(const Key('dietTrayViewCoupon')), findsNothing);
    expect(find.byType(AppProgressBar), findsNothing);
  });
}
