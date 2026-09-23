import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

void main() {
  final results = find.byKey(clientSearchResultsKey);

  Future<void> openDesktop(WidgetTester tester, String route) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(tester, token: 'demo-trainer-token', at: route);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(clientSearchFieldKey), query);
    await settle(tester);
  }

  Finder resultRow(String name) =>
      find.descendant(of: results, matching: find.text(name));

  String location(WidgetTester tester) => GoRouter.of(
    tester.element(find.byKey(clientSearchFieldKey)),
  ).state.uri.toString();

  testWidgets('모든 주요 화면 헤더에 같은 통합 검색 바가 표시된다', (tester) async {
    await openDesktop(tester, AppRoutes.dashboard);

    for (final route in <String>[
      AppRoutes.dashboard,
      AppRoutes.clients,
      AppRoutes.schedule,
      AppRoutes.messages,
      AppRoutes.coaching,
      AppRoutes.reports,
    ]) {
      GoRouter.of(tester.element(find.byKey(clientSearchFieldKey))).go(route);
      await settle(tester);
      expect(find.byKey(clientSearchFieldKey), findsOneWidget, reason: route);
    }
  });

  testWidgets('검색 바는 모든 탭에서 헤더 한가운데 같은 가로 위치에 선다', (tester) async {
    await openDesktop(tester, AppRoutes.dashboard);

    double? firstCenter;
    for (final route in <String>[
      AppRoutes.dashboard,
      AppRoutes.clients,
      AppRoutes.schedule,
      AppRoutes.messages,
      AppRoutes.coaching,
      AppRoutes.reports,
    ]) {
      GoRouter.of(tester.element(find.byKey(clientSearchFieldKey))).go(route);
      await settle(tester);

      final field = find.byKey(clientSearchFieldKey);
      final double center = tester.getCenter(field).dx;
      // 제목 길이·액션 수와 무관하게 페이지(=헤더) 폭의 가운데다.
      final page = find.ancestor(of: field, matching: find.byType(AppWebPage));
      expect(
        center,
        moreOrLessEquals(tester.getCenter(page.first).dx, epsilon: 0.5),
        reason: route,
      );
      firstCenter ??= center;
      expect(
        center,
        moreOrLessEquals(firstCenter, epsilon: 0.5),
        reason: route,
      );
    }
  });

  testWidgets('긴 검색 범위 안내를 생략하지 않는 너비와 글자 크기를 사용한다', (tester) async {
    await openDesktop(tester, AppRoutes.dashboard);

    // 긴 안내는 줄임표 없이 들어갈 폭에서만 쓴다. 헤더 동작이 많은 화면(AI
    // 코칭)은 짧은 안내로 바뀐다 — 어느 쪽이든 잘리지 않고 한 줄이어야 한다.
    final longHintRoutes = <String>{};
    for (final route in <String>[
      AppRoutes.dashboard,
      AppRoutes.clients,
      AppRoutes.schedule,
      AppRoutes.messages,
      AppRoutes.coaching,
      AppRoutes.reports,
    ]) {
      GoRouter.of(tester.element(find.byKey(clientSearchFieldKey))).go(route);
      await settle(tester);

      final field = find.byKey(clientSearchFieldKey);
      final context = tester.element(field);
      final l = AppLocalizations.of(context);
      final longHint = find.descendant(
        of: field,
        matching: find.text(l.searchClientsHint),
      );
      final bool isLong = longHint.evaluate().isNotEmpty;
      if (isLong) longHintRoutes.add(route);
      final hint = isLong ? l.searchClientsHint : l.searchClients;

      // 안내가 실제로 그려지고, 입력창 규격(body 역할)의 힌트 글씨로
      // 줄임표 없이 한 줄에 들어가야 한다.
      final hintText = find.descendant(of: field, matching: find.text(hint));
      expect(hintText, findsOneWidget, reason: route);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: hintText, matching: find.byType(RichText)),
      );
      final hintStyle = Theme.of(context).inputDecorationTheme.hintStyle;
      final visibleSize = paragraph.textScaler.scale(
        paragraph.text.style?.fontSize ?? 0,
      );
      expect(
        visibleSize,
        moreOrLessEquals(
          MediaQuery.textScalerOf(context).scale(hintStyle?.fontSize ?? 0),
        ),
        reason: route,
      );
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '$route: available=${paragraph.size.width}, '
            'hint=${paragraph.getMaxIntrinsicWidth(double.infinity)}',
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: route);
    }
    // 자리가 넉넉한 대시보드에서는 긴 안내를 보여 준다.
    expect(longHintRoutes, contains(AppRoutes.dashboard));
  });

  testWidgets('화면별 회원 검색 입력은 제거하고 통합 검색만 유지한다', (tester) async {
    await openDesktop(tester, AppRoutes.clients);
    expect(
      find.byKey(const ValueKey<String>('clients-roster-search')),
      findsNothing,
    );

    GoRouter.of(
      tester.element(find.byKey(clientSearchFieldKey)),
    ).go(AppRoutes.messages);
    await settle(tester);
    expect(find.byType(TextField), findsOneWidget);

    GoRouter.of(
      tester.element(find.byKey(clientSearchFieldKey)),
    ).go(AppRoutes.coaching);
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('program-member-search')),
      findsNothing,
    );
  });

  testWidgets('Enter로 선택하면 현재 탭 안에서 해당 회원을 연다', (tester) async {
    await openDesktop(tester, AppRoutes.messages);
    for (final (route, expected) in <(String, String)>[
      (
        AppRoutes.clientDetail('seed-client-2', section: 'workout'),
        AppRoutes.clientDetail('seed-client-1', section: 'workout'),
      ),
      (AppRoutes.messages, AppRoutes.messagesFor('seed-client-1')),
      (AppRoutes.coaching, AppRoutes.coachingFor('seed-client-1')),
      (AppRoutes.reports, AppRoutes.reportFor('seed-client-1')),
    ]) {
      GoRouter.of(tester.element(find.byKey(clientSearchFieldKey))).go(route);
      await settle(tester);
      await search(tester, '김민수');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(location(tester), expected, reason: route);
    }
  });

  // #2185 — 날짜만 넘기던 때에는 그날 첫 세션(12:00 이지수)이 상세에 열렸다.
  testWidgets('스케줄 탭에서 회원을 고르면 그 회원의 PT 가 상세에 열린다', (tester) async {
    await openDesktop(tester, AppRoutes.schedule);
    await search(tester, '김민수');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // 고른 순간 그 회원의 세션을 drift 에서 한 번 읽는다 — 가짜 시계 밖에서
    // 흘려 보내야 읽기가 끝난다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);

    final uri = Uri.parse(location(tester));
    expect(uri.path, AppRoutes.schedule);
    expect(uri.queryParameters['session'], isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('week-detail')),
        matching: find.text('김민수'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('이름이 아닌 최근 메시지로도 회원을 통합 검색한다', (tester) async {
    await openDesktop(tester, AppRoutes.dashboard);
    await search(tester, '장거리');

    expect(results, findsOneWidget);
    expect(
      find.descendant(of: results, matching: find.textContaining('장거리')),
      findsOneWidget,
    );
  });

  testWidgets('한 결과에서 메시지·일정·코칭·리포트로 바로 이동할 수 있다', (tester) async {
    await openDesktop(tester, AppRoutes.dashboard);
    await search(tester, '김민수');

    await tester.tap(find.byKey(clientSearchQuickActionsKey('seed-client-1')));
    await settle(tester);
    expect(
      find.byKey(clientSearchDestinationKey('seed-client-1', 'messages')),
      findsOneWidget,
    );
    expect(
      find.byKey(clientSearchDestinationKey('seed-client-1', 'coaching')),
      findsOneWidget,
    );
    expect(
      find.byKey(clientSearchDestinationKey('seed-client-1', 'reports')),
      findsOneWidget,
    );
  });

  testWidgets('좁은 화면에서는 검색 아이콘으로 동일한 통합 검색을 연다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.messages,
    );

    expect(find.byKey(clientSearchFieldKey), findsNothing);
    await tester.tap(find.byKey(clientSearchIconKey));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '김민수');
    await settle(tester);
    await tester.tap(resultRow('김민수'));
    await settle(tester);

    expect(
      GoRouter.of(
        tester.element(find.byKey(clientSearchIconKey)),
      ).state.uri.toString(),
      AppRoutes.messagesFor('seed-client-1'),
    );
  });
}
