/// MY → `트레이너 리포트` 상자의 규격. (#2482)
///
/// 이 상자만 앞머리 아이콘이 검정·큰 크기로, 화살표도 기본 아이콘 테마로
/// 그려져 같은 탭의 설정 목록과 달라 보였다. 지금은 설정 행과 같은 이동 행을
/// 쓰므로 아이콘 칸·화살표·제목·부제가 설정 행과 같은 규격이어야 한다.
/// 흰 배경 돌출 카드 안에 서는 원래 모양은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../benefits/fake_benefits_repository.dart';

const Key _entry = ValueKey<String>('my-coach-reports-entry');

Future<void> _pumpMy(WidgetTester tester, {String locale = 'ko'}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.myHealth,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.myHealth,
        builder: (_, _) => const MyHealthPage(),
      ),
      GoRoute(
        path: AppRoutes.myCoachReports,
        builder: (_, _) => const Scaffold(body: Center(child: Text('리포트 목록'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        myHealthRepositoryProvider.overrideWithValue(
          const MockMyHealthRepository(),
        ),
        benefitsRepositoryProvider.overrideWithValue(FakeBenefitsRepository()),
        memberCoachRepositoryProvider.overrideWithValue(
          FakeMemberCoachRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyHealthPage)));

OnCareTokens _tokens(WidgetTester tester) =>
    tester.element(find.byType(MyHealthPage)).oncare;

/// 트레이너 리포트 상자의 목록 행.
Finder _coachRow() =>
    find.descendant(of: find.byKey(_entry), matching: find.byType(AppListRow));

/// 설정 목록에서 [title] 을 제목으로 가진 행.
Finder _settingRow(String title) => find.widgetWithText(AppListRow, title);

/// [row] 안에서 [icon] 을 그리는 [Icon].
Icon _iconIn(WidgetTester tester, Finder row, IconData icon) {
  final Finder found = find.descendant(
    of: row,
    matching: find.byWidgetPredicate((Widget w) => w is Icon && w.icon == icon),
  );
  expect(found, findsOneWidget);
  return tester.widget<Icon>(found);
}

/// [row] 안에서 [text] 를 그리는 [Text] 의 글자 스타일.
TextStyle _textStyleIn(WidgetTester tester, Finder row, String text) {
  final Finder found = find.descendant(of: row, matching: find.text(text));
  expect(found, findsOneWidget);
  return tester.widget<Text>(found).style!;
}

void main() {
  setUp(() => useFixedKstDate());

  group('앞머리 아이콘', () {
    testWidgets('브랜드 색으로 그린다 — 기본 아이콘 테마의 검정이 아니다', (tester) async {
      await _pumpMy(tester);

      final Icon leading = _iconIn(tester, _coachRow(), AppIcons.document);
      expect(leading.color, _tokens(tester).brand.primary);
    });

    testWidgets('설정 행 아이콘과 같은 크기다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final Icon coach = _iconIn(tester, _coachRow(), AppIcons.document);
      final Icon profile = _iconIn(
        tester,
        _settingRow(l.myProfileTitle),
        AppIcons.person,
      );
      expect(coach.size, OnCareSize.iconMedium);
      expect(coach.size, profile.size);
      expect(coach.color, profile.color);
    });

    testWidgets('설정 행과 같은 폭의 아이콘 칸 가운데에 선다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final Finder coach = find.descendant(
        of: _coachRow(),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == AppIcons.document,
        ),
      );
      final Finder profile = find.descendant(
        of: _settingRow(l.myProfileTitle),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == AppIcons.person,
        ),
      );
      expect(tester.getCenter(coach).dx, tester.getCenter(profile).dx);
    });
  });

  group('오른쪽 화살표', () {
    testWidgets('설정 행 화살표와 같은 색·크기다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final Icon coach = _iconIn(tester, _coachRow(), AppIcons.chevronRight);
      final Icon goals = _iconIn(
        tester,
        _settingRow(l.myHealthGoalsTitle),
        AppIcons.chevronRight,
      );
      expect(coach.size, OnCareSize.iconMedium);
      expect(coach.color, OnCareColors.textTertiary);
      expect(coach.size, goals.size);
      expect(coach.color, goals.color);
    });

    testWidgets('설정 행 화살표와 같은 세로선에 선다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final Finder coach = find.descendant(
        of: _coachRow(),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == AppIcons.chevronRight,
        ),
      );
      final Finder support = find.descendant(
        of: _settingRow(l.mySupportTitle),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == AppIcons.chevronRight,
        ),
      );
      expect(tester.getCenter(coach).dx, tester.getCenter(support).dx);
    });
  });

  group('제목·부제', () {
    testWidgets('제목 글자 크기·굵기·색이 설정 행 제목과 같다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final TextStyle coach = _textStyleIn(
        tester,
        _coachRow(),
        l.myCoachReportsEntry,
      );
      final TextStyle profile = _textStyleIn(
        tester,
        _settingRow(l.myProfileTitle),
        l.myProfileTitle,
      );
      expect(coach.fontSize, profile.fontSize);
      expect(coach.fontWeight, profile.fontWeight);
      expect(coach.color, profile.color);
    });

    testWidgets('부제는 목록 행 부제 규격이다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final TextStyle title = _textStyleIn(
        tester,
        _coachRow(),
        l.myCoachReportsEntry,
      );
      final TextStyle hint = _textStyleIn(
        tester,
        _coachRow(),
        l.myCoachReportsEntryHint,
      );
      expect(hint.fontSize, OnCareTypography.bodySmall.fontSize);
      expect(hint.color, OnCareColors.textSecondary);
      // 부제는 제목보다 작다 — 상자 안에서 부제가 제목을 누르지 않는다.
      expect(hint.fontSize!, lessThan(title.fontSize!));
    });

    testWidgets('제목이 설정 행 제목과 같은 세로선에서 시작한다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final double coach = tester
          .getTopLeft(
            find.descendant(
              of: _coachRow(),
              matching: find.text(l.myCoachReportsEntry),
            ),
          )
          .dx;
      final double profile = tester
          .getTopLeft(
            find.descendant(
              of: _settingRow(l.myProfileTitle),
              matching: find.text(l.myProfileTitle),
            ),
          )
          .dx;
      expect(coach, profile);
    });

    testWidgets('영어에서도 같은 규격이다', (tester) async {
      await _pumpMy(tester, locale: 'en');
      final AppLocalizations l = _l10n(tester);

      expect(l.myCoachReportsEntry, 'Trainer reports');
      final TextStyle coach = _textStyleIn(
        tester,
        _coachRow(),
        l.myCoachReportsEntry,
      );
      final TextStyle profile = _textStyleIn(
        tester,
        _settingRow(l.myProfileTitle),
        l.myProfileTitle,
      );
      expect(coach.fontSize, profile.fontSize);
      expect(coach.fontWeight, profile.fontWeight);
      final Icon leading = _iconIn(tester, _coachRow(), AppIcons.document);
      expect(leading.color, _tokens(tester).brand.primary);
    });
  });

  group('원래 모양', () {
    testWidgets('상자 안의 아이콘은 모두 색을 직접 갖는다', (tester) async {
      await _pumpMy(tester);

      final Iterable<Icon> icons = tester.widgetList<Icon>(
        find.descendant(of: _coachRow(), matching: find.byType(Icon)),
      );
      expect(icons, isNotEmpty);
      for (final Icon icon in icons) {
        expect(icon.color, isNotNull, reason: '${icon.icon} 가 테마 기본색을 받는다');
        expect(icon.size, isNotNull, reason: '${icon.icon} 가 테마 기본 크기를 받는다');
      }
    });

    testWidgets('흰 배경 돌출 카드 안에 선다', (tester) async {
      await _pumpMy(tester);

      expect(
        find.ancestor(of: find.byKey(_entry), matching: find.byType(AppCard)),
        findsOneWidget,
      );
    });

    testWidgets('설정 행과 한 줄 높이가 같거나 부제만큼만 크다', (tester) async {
      await _pumpMy(tester);
      final AppLocalizations l = _l10n(tester);

      final double coach = tester.getSize(_coachRow()).height;
      final double profile = tester
          .getSize(_settingRow(l.myProfileTitle))
          .height;
      expect(coach, greaterThanOrEqualTo(profile));
    });

    testWidgets('눌러도 리포트 목록으로 가는 동작은 그대로다', (tester) async {
      await _pumpMy(tester);

      await tester.tap(find.byKey(_entry));
      await tester.pumpAndSettle();

      expect(find.text('리포트 목록'), findsOneWidget);
    });
  });
}
