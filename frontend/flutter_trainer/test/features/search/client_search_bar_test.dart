import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

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

  testWidgets('긴 검색 범위 안내를 생략하지 않는 너비와 글자 크기를 사용한다', (tester) async {
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

      final field = find.byKey(clientSearchFieldKey);
      final context = tester.element(field);
      final input = tester.widget<TextField>(field);
      final hintStyle = input.decoration?.hintStyle;
      final hint = AppLocalizations.of(context).searchClientsHint;
      final painter = TextPainter(
        text: TextSpan(text: hint, style: hintStyle),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final availableWidth = tester.getSize(field).width - 40 - 16;

      expect(hintStyle?.fontSize, 13, reason: route);
      expect(
        availableWidth,
        greaterThan(painter.width),
        reason: '$route: available=$availableWidth, hint=${painter.width}',
      );
    }
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
