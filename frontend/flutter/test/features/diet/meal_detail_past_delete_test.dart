/// 지난 날짜의 끼니를 식단 상세에서 지우면 그 날 목록에서도 사라진다. (#2626)
///
/// 삭제가 오늘 캐시만 비워, 돌아온 지난 날 목록과 영양 요약에 방금 지운 끼니가
/// 남았다. 저장과 분석 시트의 삭제는 그 날을 함께 비웠는데 이 자리만 빠져 있었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/record_span.dart';

/// 오늘은 2026년 8월 20일(목), 지울 끼니는 어제(19일) 아침이다.
final DateTime _yesterday = DateTime(2026, 8, 19);
const String _pastId = 'mock-yesterday-breakfast';

Finder get _pastCard => find.byKey(const Key('mealCard-$_pastId'));

/// 지난 날의 기록도 지울 수 있는 저장소. 기본 대역은 오늘 기록만 지운다.
class _PastDeletableRepository extends FakeDietRepository {
  final Set<String> deleted = <String>{};
  final Map<DateTime, int> byDateCalls = <DateTime, int>{};

  @override
  Future<void> deleteEntry(String id) async {
    deleted.add(id);
    await super.deleteEntry(id);
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    final DateTime day = DateTime(date.year, date.month, date.day);
    byDateCalls[day] = (byDateCalls[day] ?? 0) + 1;
    final DietDay base = await super.fetchByDate(date);
    final List<DietEntry> kept = base.entries
        .where((DietEntry e) => !deleted.contains(e.id))
        .toList();
    if (kept.length == base.entries.length) return base;
    return DietDay(
      entries: kept,
      totalCalories: kept.fold<int>(
        0,
        (int sum, DietEntry e) => sum + e.totalCalories,
      ),
      totalSodiumMg: kept.fold<int>(
        0,
        (int sum, DietEntry e) => sum + e.sodiumMg,
      ),
      totalSugarG: kept.fold<double>(
        0,
        (double sum, DietEntry e) => sum + e.sugarG,
      ),
      macros: const DietMacros.zero(),
      aiCoachMessage: base.aiCoachMessage,
    );
  }
}

Future<void> _pumpApp(WidgetTester tester, FakeDietRepository repo) async {
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DietRecordPage()),
      GoRoute(
        path: '/diet/entries/:entryId',
        builder: (BuildContext context, GoRouterState state) =>
            DietMealDetailPage(
              entryId: state.pathParameters['entryId']!,
              initialMeal: state.extra as DietMeal?,
            ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(repo),
        testRecordSpanOverride(),
      ],
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
}

/// 주간 띠에서 어제를 눌러 그 날 목록을 연다.
Future<void> _openYesterday(WidgetTester tester) async {
  await tester.tap(find.text('${_yesterday.day}').first);
  await tester.pumpAndSettle();
}

/// 상세 아래 `식단 삭제` → 확인 대화상자의 `삭제`.
Future<void> _deleteFromDetail(WidgetTester tester) async {
  await tester.ensureVisible(find.text('식단 삭제'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('식단 삭제'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('삭제'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('어제 끼니를 지우고 돌아오면 어제 목록에 그 카드가 없다', (WidgetTester tester) async {
    final _PastDeletableRepository repo = _PastDeletableRepository();
    await _pumpApp(tester, repo);
    await _openYesterday(tester);
    expect(_pastCard, findsOneWidget);

    await tester.tap(_pastCard);
    await tester.pumpAndSettle();
    await _deleteFromDetail(tester);

    expect(repo.deleted, <String>{_pastId});
    // 상세는 닫혔고 어제 목록으로 돌아왔다.
    expect(find.byKey(const Key('mealDetailPage')), findsNothing);
    expect(_pastCard, findsNothing);
    expect(find.text('식단을 삭제했어요'), findsOneWidget);
  });

  testWidgets('삭제 뒤 끼니가 놓였던 날을 다시 읽는다 — 영양 요약도 새 합계다', (
    WidgetTester tester,
  ) async {
    final _PastDeletableRepository repo = _PastDeletableRepository();
    await _pumpApp(tester, repo);
    await _openYesterday(tester);
    await tester.tap(_pastCard);
    await tester.pumpAndSettle();
    final int before = repo.byDateCalls[_yesterday] ?? 0;

    await _deleteFromDetail(tester);

    // 그 날의 캐시를 비웠기 때문에 목록이 서버(대역)에 다시 물었다. 합계는
    // 그 응답에서 오므로 목록과 영양 요약이 함께 바뀐다.
    expect(repo.byDateCalls[_yesterday], greaterThan(before));
  });

  testWidgets('오늘 끼니 삭제는 전처럼 오늘 목록에서 사라진다', (WidgetTester tester) async {
    final _PastDeletableRepository repo = _PastDeletableRepository();
    await _pumpApp(tester, repo);
    final Finder todayCard = find.byKey(const Key('mealCard-mock-breakfast'));
    expect(todayCard, findsOneWidget);

    await tester.tap(todayCard);
    await tester.pumpAndSettle();
    await _deleteFromDetail(tester);

    expect(repo.deleted, <String>{'mock-breakfast'});
    expect(todayCard, findsNothing);
  });
}
