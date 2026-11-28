/// 지난 챌린지 결과 — 참가한 주의 목표·운동한 날·성공 여부·받은 포인트. (#3361)
///
/// 사용처의 챌린지 카드 `지난 결과` 에서 들어온다. 서버가 주는 순서(최근 주 먼저)
/// 그대로 적고, 받은 포인트는 판정이 끝난 주에만 적는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/pages/challenge_history_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_challenge_repository.dart';

void main() {
  Future<void> pumpHistory(
    WidgetTester tester,
    FakeChallengeRepository challenges, {
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          challengeRepositoryProvider.overrideWithValue(challenges),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChallengeHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String tagOf(WidgetTester tester, String id) => tester
      .widget<AppTag>(
        find.byKey(ValueKey<String>('challenge-result-status-$id')),
      )
      .label;

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

  testWidgets('성공한 주는 목표·운동한 날·성공과 받은 포인트를 적는다', (tester) async {
    await pumpHistory(
      tester,
      FakeChallengeRepository(
        history: <Challenge>[
          challengeOf(
            id: 'won',
            goal: 4,
            progress: 5,
            status: ChallengeStatus.succeeded,
            weekStart: DateTime(2026, 9, 7),
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('challengeHistoryPage')), findsOneWidget);
    expect(find.text('지난 챌린지 결과'), findsOneWidget);
    expect(textOf(tester, 'challenge-result-days-won'), '목표 4회 · 5회 운동');
    expect(tagOf(tester, 'won'), '성공');
    expect(textOf(tester, 'challenge-result-points-won'), '+200P');
  });

  testWidgets('실패한 주는 실패와 0P 를 적는다', (tester) async {
    await pumpHistory(
      tester,
      FakeChallengeRepository(
        history: <Challenge>[
          challengeOf(
            id: 'lost',
            progress: 1,
            status: ChallengeStatus.failed,
            weekStart: DateTime(2026, 9, 7),
          ),
        ],
      ),
    );

    expect(textOf(tester, 'challenge-result-days-lost'), '목표 3회 · 1회 운동');
    expect(tagOf(tester, 'lost'), '실패');
    expect(textOf(tester, 'challenge-result-points-lost'), '0P');
  });

  testWidgets('판정 전인 주는 진행 중·집계 중으로 적고 받은 포인트를 비운다', (tester) async {
    await pumpHistory(
      tester,
      FakeChallengeRepository(
        history: <Challenge>[
          challengeOf(id: 'now', progress: 1),
          challengeOf(
            id: 'grace',
            progress: 3,
            weekStart: DateTime(2026, 9, 7),
            settling: true,
          ),
        ],
      ),
    );

    expect(tagOf(tester, 'now'), '진행 중');
    expect(tagOf(tester, 'grace'), '집계 중');
    // 진행 중인 주의 0P 는 실패처럼 읽힌다.
    expect(
      find.byKey(const ValueKey<String>('challenge-result-points-now')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('challenge-result-points-grace')),
      findsNothing,
    );
  });

  testWidgets('서버가 준 순서(최근 주 먼저) 그대로 적는다', (tester) async {
    await pumpHistory(
      tester,
      FakeChallengeRepository(
        history: <Challenge>[
          challengeOf(id: 'c3', weekStart: DateTime(2026, 9, 14)),
          challengeOf(
            id: 'c2',
            status: ChallengeStatus.failed,
            weekStart: DateTime(2026, 9, 7),
          ),
          challengeOf(
            id: 'c1',
            progress: 3,
            status: ChallengeStatus.succeeded,
            weekStart: DateTime(2026, 8, 31),
          ),
        ],
      ),
    );

    double topOf(String id) => tester
        .getTopLeft(find.byKey(ValueKey<String>('challenge-result-$id')))
        .dy;
    expect(topOf('c3'), lessThan(topOf('c2')));
    expect(topOf('c2'), lessThan(topOf('c1')));
    // 주마다 기간을 적는다.
    expect(find.text(periodRangeTextOf(tester, 2026, 9, 7)), findsOneWidget);
  });

  testWidgets('참가한 적이 없으면 빈 상태로 참가 방법을 알린다', (tester) async {
    await pumpHistory(tester, FakeChallengeRepository());

    expect(find.text('아직 참가한 챌린지가 없어요'), findsOneWidget);
    expect(find.textContaining('월·화요일에 주간 운동 챌린지에 참가하면'), findsOneWidget);
  });

  testWidgets('읽지 못하면 오류를 알리고 다시 시도로 다시 읽는다', (tester) async {
    final FakeChallengeRepository repo = FakeChallengeRepository(
      history: <Challenge>[
        challengeOf(id: 'won', progress: 3, status: ChallengeStatus.succeeded),
      ],
    )..failHistory = true;
    await pumpHistory(tester, repo);

    expect(find.text('챌린지 결과를 불러오지 못했어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('challenge-result-won')),
      findsNothing,
    );

    repo.failHistory = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repo.historyCalls, 2);
    expect(
      find.byKey(const ValueKey<String>('challenge-result-won')),
      findsOneWidget,
    );
  });
}

/// 그 주(월요일 [year]-[month]-[day])의 기간 표기 — 화면이 쓰는 공용 표기 그대로다.
String periodRangeTextOf(WidgetTester tester, int year, int month, int day) {
  final DateTime monday = DateTime(year, month, day);
  return periodRangeText(
    'ko',
    monday,
    DateTime(monday.year, monday.month, monday.day + 6),
  );
}
