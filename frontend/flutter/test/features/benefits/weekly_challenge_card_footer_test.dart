/// 주간 운동 챌린지 카드의 아랫줄 — 목표가 어디서 오는지와 지난 결과로 가는 길. (#3361)
///
/// 목표 횟수는 MY 건강 목표의 주간 운동 횟수다. 카드가 그것을 말해 주지 않으면
/// 회원은 3회가 어디서 왔는지, 어디서 바꾸는지 알 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_challenge_repository.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    WeeklyChallenge state, {
    VoidCallback? onViewHistory,
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyChallengeCard(
              state: state,
              onJoin: () {},
              onViewHistory: onViewHistory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Finder historyButton = find.byKey(const Key('weeklyChallengeHistory'));

  testWidgets('참가 전 카드는 목표가 MY 주간 운동 횟수에서 온다고 적는다', (tester) async {
    await pumpCard(tester, weeklyWith(goal: 5), onViewHistory: () {});

    expect(
      find.text(keepWords('목표 횟수는 MY 건강 목표의 주간 운동 횟수를 따라요')),
      findsOneWidget,
    );
    expect(
      find.text(keepWords('100P를 걸고 이번 주 5회 운동하면 200P를 돌려받아요')),
      findsOneWidget,
    );
    // 참가 버튼은 그대로 선다.
    expect(find.byKey(const Key('weeklyChallengeJoin')), findsOneWidget);
  });

  testWidgets('지난 결과를 누르면 이력으로 가는 길을 부른다', (tester) async {
    int opened = 0;
    await pumpCard(tester, weeklyWith(), onViewHistory: () => opened++);

    expect(tester.widget<AppButton>(historyButton).label, '지난 결과');
    await tester.tap(historyButton);
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('참가한 주에도 아랫줄은 남는다 — 지난 결과는 언제든 본다', (tester) async {
    int opened = 0;
    await pumpCard(
      tester,
      weeklyWith(
        joinable: false,
        blockReason: ChallengeBlockReason.alreadyJoined,
        challenge: challengeOf(goal: 4, progress: 2),
        goal: 4,
        progress: 2,
      ),
      onViewHistory: () => opened++,
    );

    expect(find.byKey(const Key('weeklyChallengeJoin')), findsNothing);
    expect(find.byKey(const Key('weeklyChallengeGoalSource')), findsOneWidget);
    await tester.tap(historyButton);
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('참가가 막힌 날에도 지난 결과는 열린다', (tester) async {
    int opened = 0;
    await pumpCard(
      tester,
      weeklyWith(joinable: false, blockReason: ChallengeBlockReason.joinClosed),
      onViewHistory: () => opened++,
    );

    expect(tester.widget<AppButton>(historyButton).onPressed, isNotNull);
    await tester.tap(historyButton);
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('갈 곳을 주지 않으면 지난 결과 버튼을 세우지 않는다', (tester) async {
    await pumpCard(tester, weeklyWith());

    expect(historyButton, findsNothing);
    expect(find.byKey(const Key('weeklyChallengeGoalSource')), findsOneWidget);
  });
}
