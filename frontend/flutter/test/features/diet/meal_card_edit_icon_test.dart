/// 끼니 카드의 오른쪽 끝 아이콘은 '들어간다'를 뜻해야 한다 (#1848).
///
/// 카드는 그 끼니의 상세 화면을 여는 자리다. 연필은 "이 자리에서 고친다"로
/// 읽혀, 카드가 총 칼로리만 남기고 세부를 상세로 옮긴 뒤로는 뜻이 어긋난다
/// (#1431 에서 `>` → 연필, 여기서 되돌린다). 화살표로 바꾸고, 아이콘을 눌러도
/// 카드 본문과 똑같이 그 화면으로 가는지까지 확인한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
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

    // 상세 화면으로 실제로 이동하는지 보려면 라우터가 필요하다. 앱 전체
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
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('끼니 카드에는 연필 대신 오른쪽 화살표가 있다', (WidgetTester tester) async {
    await pumpDiet(tester);

    expect(
      find.descendant(
        of: _anyMealCard,
        matching: find.byIcon(AppIcons.chevronRight),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _anyMealCard, matching: find.byIcon(AppIcons.edit)),
      findsNothing,
    );
  });

  testWidgets('화살표는 `식사 수정`으로 안내된다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final Icon icon = tester.widget<Icon>(
      find
          .descendant(
            of: _anyMealCard,
            matching: find.byIcon(AppIcons.chevronRight),
          )
          .first,
    );
    expect(icon.semanticLabel, '식사 수정');
    expect(
      find.descendant(of: _anyMealCard, matching: find.byType(Tooltip)),
      findsWidgets,
    );
  });

  testWidgets('아이콘을 눌러도 카드 본문과 같은 화면이 열린다', (WidgetTester tester) async {
    await pumpDiet(tester);

    await tester.tap(
      find
          .descendant(
            of: _anyMealCard,
            matching: find.byIcon(AppIcons.chevronRight),
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
