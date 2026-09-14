/// 끼니 카드의 오른쪽 위 아이콘은 '수정'을 뜻해야 한다 (#1431).
///
/// 카드를 누르면 하위 상세 화면이 아니라 그 끼니의 **수정** 화면이 열린다.
/// `>` 는 더 볼 것이 남았다는 뜻으로 읽혀 데모에서 카드 밖에 더 많은 정보가
/// 있는 것처럼 보였다. 연필로 바꾸고, 아이콘을 눌러도 카드 본문과 똑같이
/// 수정 화면으로 가는지까지 확인한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 끼니 카드 하나로 범위를 좁히는 검색자. 화면 위쪽 요약 카드에도 아이콘이
/// 있어 좁히지 않으면 그쪽이 함께 잡힌다.
Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

void main() {
  Future<void> pumpDiet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 수정 화면으로 실제로 이동하는지 보려면 라우터가 필요하다. 앱 전체
    // 라우터 대신 이 흐름에 쓰이는 두 경로만 세운다.
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
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
        child: MaterialApp.router(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('끼니 카드에는 `>` 대신 연필 아이콘이 있다', (WidgetTester tester) async {
    await pumpDiet(tester);

    expect(
      find.descendant(
        of: _anyMealCard,
        matching: find.byIcon(Icons.edit_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _anyMealCard,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('연필 아이콘은 `식사 수정`으로 안내된다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final Icon icon = tester.widget<Icon>(
      find
          .descendant(
            of: _anyMealCard,
            matching: find.byIcon(Icons.edit_rounded),
          )
          .first,
    );
    expect(icon.semanticLabel, '식사 수정');
    expect(
      find.descendant(of: _anyMealCard, matching: find.byType(Tooltip)),
      findsWidgets,
    );
  });

  testWidgets('아이콘을 눌러도 카드 본문과 같은 수정 화면이 열린다', (WidgetTester tester) async {
    await pumpDiet(tester);

    await tester.tap(
      find
          .descendant(
            of: _anyMealCard,
            matching: find.byIcon(Icons.edit_rounded),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DietMealDetailPage), findsOneWidget);

    // 카드 본문 탭도 같은 화면이다 — 되돌아가 헤더를 눌러 확인한다.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    // 카드 본문 = 카드 전체를 덮는 `InkWell`. 헤더 줄을 직접 누르면 그
    // 가운데가 `spaceBetween` 의 빈 틈이라 줄 자체는 히트되지 않는다.
    final Finder body = find.descendant(
      of: _anyMealCard,
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(body.first);
    await tester.pumpAndSettle();
    await tester.tap(body.first);
    await tester.pumpAndSettle();
    expect(find.byType(DietMealDetailPage), findsOneWidget);
  });
}
