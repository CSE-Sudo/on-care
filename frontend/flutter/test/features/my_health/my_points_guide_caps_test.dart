/// 포인트 적립 안내창은 규칙마다 하루 한도를 함께 말한다. (#1786)
///
/// 한도를 넘으면 저장 알림에 적립 표시가 붙지 않는데, 안내창이 한도를 말하지
/// 않으면 회원은 왜 포인트가 안 들어왔는지 알 수 없다. 숫자는 적립 규칙
/// ([PointsRule]) 하나에서 읽어, 문구와 규칙이 따로 놀지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../benefits/fake_benefits_repository.dart';

void main() {
  Future<AppLocalizations> openGuide(WidgetTester tester, Locale locale) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        // 사용처 목록은 가짜 저장소로 채운다 — 이 테스트는 안내창만 본다(#1787).
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(FakeBenefitsRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsBenefitsPage(points: 1240),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppTopBar),
        matching: find.byType(AppIconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    return AppLocalizations.of(tester.element(find.byType(AppDialog)));
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AppDialog), matching: find.text(text));

  testWidgets('한국어 안내창은 규칙마다 하루 한도를 적는다', (WidgetTester tester) async {
    await openGuide(tester, const Locale('ko'));

    expect(inDialog('식단 추가 (하루 3회)'), findsOneWidget);
    expect(inDialog('운동 직접 추가 (하루 3회)'), findsOneWidget);
    expect(inDialog('추천·배정 운동 완료 (하루 1회)'), findsOneWidget);
    // 포인트는 예전처럼 줄 오른쪽에 선다.
    expect(inDialog('+50P'), findsNWidgets(2));
    expect(inDialog('+20P'), findsOneWidget);
    expect(
      tester.getTopLeft(inDialog('+20P')).dx,
      greaterThan(tester.getTopRight(inDialog('운동 직접 추가 (하루 3회)')).dx),
    );
  });

  testWidgets('영어 안내창은 한 번이면 once a day 로 적는다', (WidgetTester tester) async {
    await openGuide(tester, const Locale('en'));

    expect(inDialog('Log a meal (up to 3 times a day)'), findsOneWidget);
    expect(
      inDialog('Log a workout yourself (up to 3 times a day)'),
      findsOneWidget,
    );
    expect(
      inDialog('Complete a recommended or assigned workout (once a day)'),
      findsOneWidget,
    );
  });

  testWidgets('안내창의 숫자는 적립 규칙에서 읽는다', (WidgetTester tester) async {
    final AppLocalizations l = await openGuide(tester, const Locale('ko'));

    for (final (String action, PointsRule rule) in <(String, PointsRule)>[
      (l.myPointsDietAdd, PointsRule.dietEntry),
      (l.myPointsExerciseAdd, PointsRule.exerciseManual),
      (l.myPointsRoutineComplete, PointsRule.routineComplete),
    ]) {
      final Finder row = find.ancestor(
        of: inDialog(l.myPointsRuleWithDailyCap(action, rule.dailyCap)),
        matching: find.byType(Row),
      );
      expect(row, findsWidgets);
      expect(
        find.descendant(
          of: row.first,
          matching: find.text(l.pointsRewardBadge(rule.points)),
        ),
        findsOneWidget,
      );
    }
    // 서버 규칙과 같은 값이다 — 바꾸면 백엔드 `points_service` 도 함께 바꾼다.
    expect(
      <(int, int)>[
        for (final PointsRule r in PointsRule.values) (r.points, r.dailyCap),
      ],
      <(int, int)>[(50, 3), (20, 3), (50, 1)],
    );
  });
}
