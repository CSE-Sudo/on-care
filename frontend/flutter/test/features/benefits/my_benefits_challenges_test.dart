/// 내 혜택의 주간 챌린지 구역 — 진행 중·성공·실패 결과. (#1789)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/pages/my_benefits_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeChallengeRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(
            FakeBenefitsRepository(),
          ),
          challengeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyBenefitsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('참가한 챌린지가 없으면 빈 상태를 보여 준다', (tester) async {
    await pump(tester, FakeChallengeRepository());

    expect(find.text('주간 챌린지'), findsOneWidget);
    expect(find.text('참가한 챌린지가 없어요'), findsOneWidget);
    // 사용처 바로가기는 쿠폰 빈 상태에만 있다.
    expect(find.text('포인트 사용처'), findsOneWidget);
  });

  testWidgets('쿠폰 아래에 이번 주 진행과 지난 주 결과를 보여 준다', (tester) async {
    await pump(
      tester,
      FakeChallengeRepository(
        history: <Challenge>[
          challengeOf(id: 'now', progress: 2),
          challengeOf(
            id: 'won',
            progress: 3,
            status: ChallengeStatus.succeeded,
            weekStart: DateTime(2026, 9, 7),
          ),
          challengeOf(
            id: 'lost',
            progress: 1,
            status: ChallengeStatus.failed,
            weekStart: DateTime(2026, 8, 31),
          ),
        ],
      ),
    );

    expect(
      tester.getTopLeft(find.text('주간 챌린지')).dy,
      greaterThan(tester.getTopLeft(find.text('쿠폰')).dy),
    );

    expect(find.text('9.14~9.20 챌린지'), findsOneWidget);
    expect(find.text('2 / 3회'), findsOneWidget);
    expect(_tag(tester, 'now'), '진행 중');

    expect(find.text('9.7~9.13 챌린지'), findsOneWidget);
    expect(find.text('목표 3회 중 3회 · 200P 받음'), findsOneWidget);
    expect(_tag(tester, 'won'), '성공');

    expect(find.text('8.31~9.6 챌린지'), findsOneWidget);
    expect(find.text('목표 3회 중 1회 · 건 100P 소멸'), findsOneWidget);
    expect(_tag(tester, 'lost'), '실패');
  });
}

String _tag(WidgetTester tester, String id) => tester
    .widget<AppTag>(find.byKey(ValueKey<String>('challenge-status-$id')))
    .label;
