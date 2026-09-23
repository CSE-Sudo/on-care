/// 포인트 사용처의 주간 운동 챌린지 카드 — 참가 확인창과 진행·막힌 이유. (#1789)
///
/// 참가는 `참가` → 파란 2열 확인창(`취소 / 참가하기`)에서 건 포인트·목표·보상을
/// 밝힌 뒤 건다. 참가했으면 버튼 대신 이번 주 진행(예: 2 / 3회)이 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
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
    FakeChallengeRepository challenges,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(
            FakeBenefitsRepository(),
          ),
          challengeRepositoryProvider.overrideWithValue(challenges),
        ],
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

  final Finder joinButton = find.byKey(const Key('weeklyChallengeJoin'));

  AppButton joinButtonOf(WidgetTester tester) =>
      tester.widget<AppButton>(joinButton);

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('참가 전 카드는 건 포인트·목표·보상과 참가 기간을 보여 준다', (tester) async {
    await pumpShop(tester, FakeChallengeRepository());

    expect(find.byKey(const Key('weeklyChallengeCard')), findsOneWidget);
    expect(find.text('주간 운동 챌린지'), findsOneWidget);
    expect(find.text('100P'), findsOneWidget);
    expect(
      find.text(keepWords('100P를 걸고 이번 주 3회 운동하면 200P를 돌려받아요')),
      findsOneWidget,
    );
    expect(find.text(keepWords('월·화요일에만 참가할 수 있어요')), findsOneWidget);
    expect(joinButtonOf(tester).onPressed, isNotNull);

    // 챌린지 카드는 쿠폰 교환 목록 위에 선다.
    expect(
      tester.getTopLeft(find.byKey(const Key('weeklyChallengeCard'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('shop-item-pt_renewal')))
            .dy,
      ),
    );
  });

  testWidgets('참가 → 파란 2열 확인창 → 참가하기로 포인트를 건다', (tester) async {
    final FakeChallengeRepository repo = FakeChallengeRepository(
      weekly: weeklyWith(goal: 4),
    );
    await pumpShop(tester, repo);

    await tester.tap(joinButton);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('주간 챌린지에 참가할까요?'), findsOneWidget);
    expect(
      find.text(
        '100P를 걸고 이번 주 4회 운동에 도전해요. 일요일까지 채우면 200P를 돌려받고, '
        '못 채우면 건 포인트는 사라져요.',
      ),
      findsOneWidget,
    );
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '참가하기');
    // 일반 확정은 파란(브랜드) 채움이다.
    expect(pair.destructive, isFalse);

    await tester.tap(find.text('참가하기'));
    await tester.pumpAndSettle();

    expect(repo.joins, 1);
    expect(find.byType(AppDialog), findsNothing);
    expect(find.text('챌린지에 참가했어요'), findsOneWidget);
    // 다시 읽어 버튼 대신 진행이 선다.
    expect(joinButton, findsNothing);
    expect(find.text('0 / 4회'), findsOneWidget);
    expect(find.text(keepWords('일요일까지 4회 더 운동하면 200P를 돌려받아요')), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('확인창에서 취소하면 참가하지 않는다', (tester) async {
    final FakeChallengeRepository repo = FakeChallengeRepository();
    await pumpShop(tester, repo);

    await tester.tap(joinButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(repo.joins, 0);
    expect(joinButton, findsOneWidget);
  });

  testWidgets('참가에 실패하면 알리고 버튼을 되살린다', (tester) async {
    final FakeChallengeRepository repo = FakeChallengeRepository()
      ..failJoin = true;
    await pumpShop(tester, repo);

    await tester.tap(joinButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('참가하기'));
    await tester.pumpAndSettle();

    expect(repo.joins, 1);
    expect(find.text('참가하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(joinButtonOf(tester).onPressed, isNotNull);
    await drainToast(tester);
  });

  testWidgets('월·화요일이 지나면 버튼이 막히고 다음 참가일을 알려 준다', (tester) async {
    await pumpShop(
      tester,
      FakeChallengeRepository(
        weekly: weeklyWith(
          joinable: false,
          blockReason: ChallengeBlockReason.joinClosed,
        ),
      ),
    );

    expect(joinButtonOf(tester).onPressed, isNull);
    expect(find.text(keepWords('다음 주 월요일에 다시 참가할 수 있어요')), findsOneWidget);
  });

  testWidgets('잔액이 모자라면 버튼이 막히고 부족한 포인트를 알려 준다', (tester) async {
    await pumpShop(
      tester,
      FakeChallengeRepository(
        weekly: weeklyWith(
          balance: 60,
          joinable: false,
          blockReason: ChallengeBlockReason.insufficientPoints,
          shortfall: 40,
        ),
      ),
    );

    expect(joinButtonOf(tester).onPressed, isNull);
    expect(find.text(keepWords('40P 부족해요')), findsOneWidget);
  });

  testWidgets('참가했으면 진행과 남은 횟수, 채웠으면 달성 안내를 보여 준다', (tester) async {
    await pumpShop(
      tester,
      FakeChallengeRepository(
        weekly: weeklyWith(
          progress: 2,
          joinable: false,
          blockReason: ChallengeBlockReason.alreadyJoined,
          challenge: challengeOf(progress: 2),
        ),
      ),
    );

    expect(joinButton, findsNothing);
    expect(find.text('2 / 3회'), findsOneWidget);
    expect(find.text(keepWords('일요일까지 1회 더 운동하면 200P를 돌려받아요')), findsOneWidget);
  });

  testWidgets('목표를 채운 진행 중 챌린지는 주가 끝나면 받는다고 알린다', (tester) async {
    await pumpShop(
      tester,
      FakeChallengeRepository(
        weekly: weeklyWith(
          progress: 3,
          joinable: false,
          blockReason: ChallengeBlockReason.alreadyJoined,
          challenge: challengeOf(progress: 3),
        ),
      ),
    );

    expect(find.text('3 / 3회'), findsOneWidget);
    expect(find.text(keepWords('목표 달성! 주가 끝나면 200P를 받아요')), findsOneWidget);
  });
}
