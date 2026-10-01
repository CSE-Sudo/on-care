/// 지난 날 끼니 상세를 웹에서 새로고침해도 같은 끼니가 열린다. (#2881)
///
/// 목록에서 끼니를 누르면 경로에 id 만 싣고 끼니는 `extra` 로 넘겼다. 새로고침하면
/// `extra` 가 사라지고, 상세는 **오늘** 목록에서만 id 를 찾아 지난 날 끼니는
/// 늘 `불러오지 못했어요` 였다. 이제 주소에 날짜를 싣고 그 날의 목록에서 찾는다.
/// 목록을 읽었는데 끼니가 없으면(지워진 기록) 읽기 실패와 다른 안내를 보인다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/wire_date.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 오늘은 2026년 8월 20일(목), 어제는 19일이다.
final DateTime _yesterday = DateTime(2026, 8, 19);

String _label(DateTime date) => DateFormat.yMMMd('ko').format(date);

Finder get _detailPage => find.byKey(const Key('mealDetailPage'));
Finder get _dateValue => find.byKey(const Key('meal-detail-date'));

/// 앱 라우터(`app_router.dart`)와 같은 방식으로 상세를 만든다 — 주소의
/// `date` 를 읽고, `extra` 는 있을 때만 쓴다.
Future<GoRouter> _pumpApp(WidgetTester tester, FakeDietRepository repo) async {
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DietRecordPage()),
      GoRoute(path: AppRoutes.diet, builder: (_, _) => const DietRecordPage()),
      GoRoute(
        path: AppRoutes.dietEntryDetail,
        builder: (BuildContext context, GoRouterState state) =>
            DietMealDetailPage(
              entryId: state.pathParameters['entryId']!,
              date: parseWireDate(state.uri.queryParameters['date']),
              initialMeal: state.extra is DietMeal
                  ? state.extra! as DietMeal
                  : null,
            ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// 빠진 정보 없이 주소만으로 상세를 연다 — 새로고침·주소 다시 열기와 같다.
Future<void> _openByAddress(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  router.go(location);
  await tester.pumpAndSettle();
}

void main() {
  group('주소', () {
    test('끼니 상세 주소는 날짜를 싣는다', () {
      expect(
        AppRoutes.dietEntryDetailPath('diet-1', date: _yesterday),
        '/diet/entries/diet-1?date=2026-08-19',
      );
    });

    test('날짜 없이 만들면 지금처럼 id 만이다', () {
      expect(AppRoutes.dietEntryDetailPath('diet-1'), '/diet/entries/diet-1');
    });

    test('주소의 날짜는 YYYY-MM-DD 만 읽는다', () {
      expect(parseWireDate('2026-08-19'), DateTime(2026, 8, 19));
      expect(parseWireDate(null), isNull);
      expect(parseWireDate('20260819'), isNull);
      expect(parseWireDate('2026-02-30'), isNull, reason: '다른 날로 굴리지 않는다');
      expect(parseWireDate('yesterday'), isNull);
    });
  });

  testWidgets('어제 끼니 상세를 주소만으로 열어도 그 끼니가 열리고 날짜는 어제다', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await _pumpApp(tester, FakeDietRepository());
    await _openByAddress(
      tester,
      router,
      AppRoutes.dietEntryDetailPath(
        'mock-yesterday-breakfast',
        date: _yesterday,
      ),
    );

    expect(_detailPage, findsOneWidget);
    expect(tester.widget<Text>(_dateValue).data, _label(_yesterday));
    expect(find.text('식단 정보를 불러오지 못했어요.'), findsNothing);
  });

  testWidgets('목록에서 연 어제 끼니는 주소에 그 날짜가 실린다', (WidgetTester tester) async {
    final GoRouter router = await _pumpApp(tester, FakeDietRepository());
    await tester.tap(find.text('${_yesterday.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('mealCard-mock-yesterday-breakfast')),
    );
    await tester.pumpAndSettle();

    final Uri uri = router.routerDelegate.currentConfiguration.uri;
    expect(uri.path, '/diet/entries/mock-yesterday-breakfast');
    expect(uri.queryParameters['date'], '2026-08-19');
  });

  testWidgets('새로고침한 어제 끼니를 저장해도 날짜가 오늘로 옮겨지지 않는다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = FakeDietRepository();
    final GoRouter router = await _pumpApp(tester, repo);
    await _openByAddress(
      tester,
      router,
      AppRoutes.dietEntryDetailPath(
        'mock-yesterday-breakfast',
        date: _yesterday,
      ),
    );

    await tester.tap(find.byKey(const Key('mealDetailEditButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final List<DietEntry> today = (await repo.fetchToday()).entries;
    expect(
      today.map((DietEntry e) => e.id),
      isNot(contains('mock-yesterday-breakfast')),
    );
    expect(
      repo.movedEntries['mock-yesterday-breakfast']?.date,
      isNot('2026-08-20'),
    );
  });

  testWidgets('날짜 없는 옛 주소는 지금처럼 오늘 목록에서 찾는다', (WidgetTester tester) async {
    final GoRouter router = await _pumpApp(tester, FakeDietRepository());
    unawaited(
      router.push<void>(AppRoutes.dietEntryDetailPath('mock-breakfast')),
    );
    await tester.pumpAndSettle();

    expect(_detailPage, findsOneWidget);
    expect(tester.widget<Text>(_dateValue).data, _label(DateTime(2026, 8, 20)));
  });

  testWidgets('지워졌거나 없는 끼니는 읽기 실패와 다른 안내와 식단 탭 버튼을 보인다', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await _pumpApp(tester, FakeDietRepository());
    await _openByAddress(
      tester,
      router,
      AppRoutes.dietEntryDetailPath('gone-entry', date: _yesterday),
    );

    expect(find.byKey(const Key('dietMealNotFound')), findsOneWidget);
    expect(find.text('삭제됐거나 없는 기록이에요'), findsOneWidget);
    expect(find.text('식단 정보를 불러오지 못했어요.'), findsNothing);

    await tester.tap(find.byKey(const Key('dietMealNotFoundAction')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.diet);
  });
}
