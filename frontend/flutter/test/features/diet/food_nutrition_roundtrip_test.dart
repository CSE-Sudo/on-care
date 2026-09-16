/// 끼니를 저장해도 음식별 영양이 남아야 한다 (#1853).
///
/// 끼니 단위 탄단지는 음식별 값의 합계로 만들어진다. 수정 화면이 그 값을
/// 되돌려 보내지 않으면 이름 한 글자만 고쳐도 그 끼니의 영양 정보가 통째로
/// 0 이 된다 — 화면에는 저장에 성공했다고 나오는데 숫자만 사라진다.
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

Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

void main() {
  testWidgets('음식 이름을 고쳐 저장해도 끼니 영양 정보가 그대로 남는다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository();
    await tester.binding.setSurfaceSize(const Size(900, 2400));
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
        overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          // 저장 성공 토스트가 라우터의 내비게이터보다 위에 있는 오버레이를
          // 찾는다. 앱에서는 중첩 내비게이터가 그 자리를 채우지만, 이 테스트는
          // 경로 둘만 세우므로 직접 얹어 준다.
          builder: (BuildContext context, Widget? child) => Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 고치기 전 값을 붙잡아 둔다 — 시드가 바뀌어도 테스트가 따라간다.
    //
    // 대역이 `Future.delayed` 로 지연을 흉내 내므로 `runAsync` 밖에서 기다리면
    // 가짜 시계가 그 타이머를 굴리지 않아 교착한다.
    final DietEntry before = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.first;
    expect(
      before.carbsG + before.proteinG + before.fatG,
      greaterThan(0),
      reason: '시드에 영양이 없으면 이 테스트는 아무것도 검증하지 못한다',
    );

    await tester.tap(_anyMealCard);
    await tester.pumpAndSettle();

    // 이름만 고친다. 영양 칸은 건드리지 않는다.
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-name-1')),
      '스크램블 에그(소금 적게)',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final DietEntry after = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.firstWhere((DietEntry e) => e.id == before.id);
    expect(after.foods.first.name, '스크램블 에그(소금 적게)');
    expect(after.carbsG, before.carbsG);
    expect(after.proteinG, before.proteinG);
    expect(after.fatG, before.fatG);
    expect(after.foods.first.sodiumMg, before.foods.first.sodiumMg);
    expect(after.foods.first.sugarG, before.foods.first.sugarG);
  });
}
