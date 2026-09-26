/// 끼니를 고쳐 저장하면 식단 탭 AI 맞춤 조언도 새 합계를 말한다. (#2078)
///
/// 조언(`dietAdviceProvider`)은 한 번 받은 값을 들고 있는데, 끼니를 바꾸는 자리
/// 어디서도 이 값을 비우지 않아 영양 요약은 새 합계인데 조언만 옛 합계를 말했다.
/// 여기서는 조언이 **저장된 기록으로 매번 계산되는** 대역을 두고, 상세에서 음식의
/// 나트륨을 고쳐 저장한 뒤 돌아온 식단 탭의 조언 문장이 새 합계인지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 조언을 지금 저장된 끼니의 나트륨 합계로 매번 만든다 — 서버와 같다.
class _LiveAdviceRepository extends FakeDietRepository {
  int adviceCalls = 0;

  @override
  Future<DietAdvice> fetchAdvice(String period, {String lang = 'ko'}) async {
    adviceCalls++;
    final DietDay day = await fetchToday();
    final int sodium = day.entries.fold<int>(
      0,
      (int sum, DietEntry e) => sum + e.sodiumMg,
    );
    return DietAdvice(
      message: '나트륨 ${sodium}mg',
      analysis: DietAdviceLine(
        text: '나트륨 **${sodium}mg**',
        key: 'today_sodium_over',
        params: <String, Object>{'sodium_mg': sodium},
      ),
    );
  }
}

String _sodiumLine(int sodium) =>
    '나트륨 ${NumberFormat.decimalPattern('ko').format(sodium)}mg, 권장량 초과예요.';

void main() {
  testWidgets('음식 나트륨을 고쳐 저장하면 돌아온 식단 탭 조언이 새 합계를 말한다', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _LiveAdviceRepository repo = _LiveAdviceRepository();

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

    final DietDay before = (await tester.runAsync(repo.fetchToday))!;
    final int total = before.entries.fold<int>(
      0,
      (int sum, DietEntry e) => sum + e.sodiumMg,
    );
    expect(find.text(_sodiumLine(total)), findsOneWidget);
    final int callsBefore = repo.adviceCalls;

    // 아침 첫 음식(스크램블 에그)의 나트륨을 900 으로 고쳐 저장한다.
    final DietEntry breakfast = before.entries.firstWhere(
      (DietEntry e) => e.id == 'mock-breakfast',
    );
    final int eggSodium = breakfast.foods.first.sodiumMg;
    await tester.tap(
      find.byKey(const ValueKey<String>('mealCard-mock-breakfast')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mealDetailEditButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-sodium-1')),
      '900',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(
      repo.adviceCalls,
      greaterThan(callsBefore),
      reason: '저장 뒤 조언을 다시 받는다',
    );
    expect(find.text(_sodiumLine(total - eggSodium + 900)), findsOneWidget);
    expect(find.text(_sodiumLine(total)), findsNothing);
  });
}
