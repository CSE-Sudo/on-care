import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/design_system/tokens/layout.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/features/clients/presentation/pages/clients_page.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_detail_view.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/widgets/alert_badge.dart';

import '../../helpers/pump_app.dart';

/// Master-detail split on wide viewports (content ≥ AppLayout.splitBreakpoint).
///
/// Selection lives in the path (`/clients/<id>/<section>`), so these
/// tests assert on the URL as much as the pixels — a split panel that
/// doesn't survive a refresh is not the feature.
void main() {
  Future<void> openWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clients,
    );
  }

  /// The client's name in the roster card (the panel header shows it too).
  Finder card(String name) => find.text(name).first;

  /// Brings a roster card into view before tapping it. The roster is
  /// fifteen clients and lazily built, so anyone ranked below the fold
  /// simply does not exist yet.
  ///
  /// The scrollable is located through a card rather than by index — the
  /// sidebar and the open detail panel are scrollables too, and which
  /// one comes first in the tree is not this test's business.
  Future<void> scrollToCard(WidgetTester tester, String name) async {
    // Check the raw finder, not `card()` — `.first` throws rather than
    // reporting empty when nothing matched.
    final candidates = find.text(name);
    if (candidates.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(name),
        160,
        scrollable: find
            .ancestor(
              of: find.byType(ClientCard).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }

    // A lazily built card can already exist just beyond the viewport. In
    // that case scrollUntilVisible is skipped, but tapping still misses it.
    await tester.ensureVisible(candidates.first);
    await tester.pumpAndSettle();
  }

  testWidgets('wide viewport starts as a plain list; picking a client '
      'opens the side panel', (tester) async {
    await openWide(tester);

    // No selection yet — list only, with the empty-panel hint.
    expect(find.textContaining('왼쪽에서 회원을 선택하면'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClientCard),
        matching: find.byType(AlertBadge),
      ),
      findsNothing,
    );

    await tester.tap(card('김민수'));
    await settle(tester);

    // Panel opened in place with the unified detail, no push.
    expect(find.text('운동'), findsOneWidget);
    expect(find.text('메시지'), findsWidgets);
    expect(find.text('식단'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });

  testWidgets('회원 리스트 바로 위에 pill 필터·정렬 버튼이 있다', (tester) async {
    await openWide(tester);

    final search = find.byKey(clientSearchFieldKey);
    final filter = find.byKey(const ValueKey<String>('clients-filter-button'));
    final sort = find.byKey(const ValueKey<String>('clients-sort-button'));

    final firstCard = find.byType(ClientCard).first;

    expect(find.text('필터'), findsOneWidget);
    expect(
      tester.getTopLeft(filter).dy,
      greaterThan(tester.getBottomLeft(search).dy),
    );
    expect(
      tester.getBottomLeft(filter).dy,
      lessThan(tester.getTopLeft(firstCard).dy),
    );
    expect(tester.getTopRight(filter).dx, lessThan(tester.getTopLeft(sort).dx));
    expect(
      tester.getTopLeft(filter).dx,
      closeTo(tester.getTopLeft(firstCard).dx, 1),
    );
    expect(tester.getSize(filter).height, lessThanOrEqualTo(40));
    expect(tester.getSize(sort).height, lessThanOrEqualTo(40));
  });

  testWidgets('the roster card has visible space before the detail panel', (
    tester,
  ) async {
    await openWide(tester);
    await tester.tap(card('김민수'));
    await settle(tester);

    final cardRect = tester.getRect(find.byType(ClientCard).first);
    final detailRect = tester.getRect(find.byType(ClientDetailView));

    expect(
      detailRect.left - cardRect.right,
      AppSpacing.lg,
      reason: '목록 카드의 우측 테두리와 그림자가 잘리지 않아야 한다',
    );
    expect(
      find.byKey(const ValueKey<String>('clients-master-detail-gap')),
      findsOneWidget,
    );
  });

  testWidgets('picking a client does not expose the parent roster during '
      'the route change', (tester) async {
    await openWide(tester);

    await tester.tap(card('김민수'));
    await tester.pump();
    await tester.pump();

    // The detail route is nested under `/clients`. A default Material page
    // transition leaves the parent roster exposed while the new page enters,
    // which appears as a brief roster flash. The router consumes the first
    // pump; the second is the first frame that contains the detail route.
    expect(find.byType(ClientsPage), findsOneWidget);
    expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
  });

  testWidgets('the close button collapses the panel back to the list', (
    tester,
  ) async {
    await openWide(tester);

    await tester.tap(card('김민수'));
    await settle(tester);
    expect(find.text('운동'), findsOneWidget);

    await tester.tap(find.byTooltip('패널 닫기'));
    await settle(tester);

    expect(find.text('운동'), findsNothing);
    expect(find.textContaining('왼쪽에서 회원을 선택하면'), findsOneWidget);
  });

  testWidgets('selecting another client swaps the panel in place', (
    tester,
  ) async {
    await openWide(tester);

    await tester.tap(card('김민수'));
    await settle(tester);
    expect(find.textContaining('3,428', findRichText: true), findsWidgets);

    await scrollToCard(tester, '이지수');
    await tester.tap(card('이지수'));
    await settle(tester);

    expect(find.textContaining('3,428', findRichText: true), findsNothing);
    // Still embedded — no full-screen push happened.
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });

  testWidgets('the detail tab state does not leak into another client', (
    tester,
  ) async {
    await openWide(tester);

    await tester.tap(card('김민수'));
    await settle(tester);

    expect(
      find.byKey(const ValueKey<String>('client-detail-tabs-seed-client-1')),
      findsOneWidget,
    );

    await scrollToCard(tester, '이지수');
    await tester.tap(card('이지수'));
    await settle(tester);

    expect(
      find.byKey(const ValueKey<String>('client-detail-tabs-seed-client-2')),
      findsOneWidget,
    );
  });

  testWidgets('the section stays put when switching clients', (tester) async {
    await openWide(tester);

    // Open 식단 for 김민수 (3,428mg — appears on the summary card and as
    // the last sodium-trend bar label, so match ≥1)…
    await goTo(
      tester,
      AppRoutes.clientDetail('seed-client-1', section: 'diet'),
    );
    expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
    expect(find.textContaining('3,428', findRichText: true), findsWidgets);

    // …switch to 박성호: same sub-tab, his data (2,400mg).
    await scrollToCard(tester, '박성호');
    await tester.tap(card('박성호'));
    await settle(tester);
    expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
    expect(find.textContaining('2,400', findRichText: true), findsWidgets);
  });

  testWidgets('고른 정렬은 회원을 열어도 그대로다 (#816)', (tester) async {
    await openWide(tester);

    // 회원 목록 위의 pill 정렬 메뉴에서 이름순을 고른다.
    await tester.tap(find.text('정렬: 관리 필요 우선'));
    await tester.pumpAndSettle();
    final sortButton = find.byKey(
      const ValueKey<String>('clients-sort-button'),
    );
    final nameOptionFinder = find.text('이름 오름차순').last;
    final nameOption = tester.widget<Text>(nameOptionFinder);
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(
      tester.getTopLeft(nameOptionFinder).dy,
      greaterThan(tester.getBottomLeft(sortButton).dy),
    );
    expect(nameOption.style?.fontSize, 12.5);
    expect(nameOption.style?.fontWeight, FontWeight.w600);
    await tester.tap(nameOptionFinder);
    await tester.pumpAndSettle();
    expect(find.text('정렬: 이름 오름차순'), findsOneWidget);

    // 목록에서 회원을 연다 — 여기서 새 라우트가 만들어진다.
    await scrollToCard(tester, '김민수');
    await tester.tap(card('김민수'));
    await tester.pumpAndSettle();

    // 예전에는 상세가 자기 `ClientsPage` 를 새로 만들면서 정렬이 '관리 우선'
    // 로 돌아갔다.
    expect(find.text('정렬: 이름 오름차순'), findsOneWidget);
    expect(find.text('정렬: 관리 필요 우선'), findsNothing);
  });

  testWidgets('활성 회원 우선은 실제 active 필드로 정렬한다', (tester) async {
    await openWide(tester);
    const countSummary = '15명 · 활성 13명';
    expect(find.text(countSummary), findsWidgets);

    await tester.tap(find.text('정렬: 관리 필요 우선'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('활성 회원 우선').last);
    await tester.pumpAndSettle();

    expect(find.text('정렬: 활성 회원 우선'), findsOneWidget);
    final visibleCards = tester
        .widgetList<ClientCard>(find.byType(ClientCard))
        .toList(growable: false);
    expect(visibleCards, isNotEmpty);
    expect(visibleCards.every((card) => card.client.active), isTrue);

    // 활성 우선은 휴면 회원을 숨기는 필터가 아니다. 명단 수를 유지한
    // 채 활성 회원 뒤로 보낸다.
    await scrollToCard(tester, '박성호');
    final dormantCard = tester.widget<ClientCard>(
      find.ancestor(of: find.text('박성호'), matching: find.byType(ClientCard)),
    );
    expect(dormantCard.client.active, isFalse);
    expect(find.text(countSummary), findsWidgets);
  });

  testWidgets('대시보드에서 걸어 준 필터는 회원을 열어도 유지된다 (#816)', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientsFiltered('attention'),
    );
    await tester.pumpAndSettle();

    final banner = find.textContaining('주의 회원');
    expect(banner, findsWidgets);

    final first = tester.widgetList<ClientCard>(find.byType(ClientCard)).first;
    await tester.tap(card(first.client.name));
    await tester.pumpAndSettle();

    // 상세 경로가 `f` 를 물려받아야 배너와 좁힌 목록이 남는다.
    final router = GoRouter.of(tester.element(find.byType(ClientsPage)));
    final location = router.routerDelegate.currentConfiguration.uri.toString();
    expect(location, contains('f=attention'));
    expect(banner, findsWidgets);
  });

  testWidgets('the list is ordered by priority: sodium-over first', (
    tester,
  ) async {
    await openWide(tester);

    // Read the rendered order rather than three clients' Y positions:
    // the roster is long enough now that not every name is built, so
    // measuring specific ones would depend on where the list happens to
    // sit. Every over-target client must precede every under-target one.
    final rendered = tester
        .widgetList<ClientCard>(find.byType(ClientCard))
        .toList();
    expect(rendered.length, greaterThan(2));
    final firstUnderTarget = rendered.indexWhere(
      (c) => !c.client.sodiumOverBudget,
    );
    if (firstUnderTarget >= 0) {
      expect(
        rendered
            .skip(firstUnderTarget)
            .every((c) => !c.client.sodiumOverBudget),
        isTrue,
        reason: '나트륨 초과 회원이 목표 이내 회원보다 아래에 오면 안 된다',
      );
    }
    // The top of the list is where the trainer looks first.
    expect(rendered.first.client.sodiumOverBudget, isTrue);
  });

  testWidgets('회원 카드가 기록된 날의 주간 루틴 이행률을 보여 준다 (#1284)', (tester) async {
    await openWide(tester);
    await scrollToCard(tester, '배준혁');

    final clientCard = find.ancestor(
      of: find.text('배준혁'),
      matching: find.byType(ClientCard),
    );
    final progress = find.descendant(
      of: clientCard,
      matching: find.byKey(
        const ValueKey<String>('client-weekly-adherence-seed-client-9'),
      ),
    );
    expect(progress, findsOneWidget);
    final renderedClient = tester.widget<ClientCard>(clientCard).client;
    final expected = recordedCompletionMean(renderedClient)!;
    expect(
      find.descendant(
        of: clientCard,
        matching: find.text('${expected.round()}%'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<LinearProgressIndicator>(progress).value,
      closeTo(expected / 100, 0.001),
    );
  });

  testWidgets('루틴 기록이 없는 회원은 0%가 아니라 미집계로 표시한다 (#1284)', (tester) async {
    await openWide(tester);
    await scrollToCard(tester, '임도현');

    final clientCard = find.ancestor(
      of: find.text('임도현'),
      matching: find.byType(ClientCard),
    );
    expect(
      find.descendant(of: clientCard, matching: find.text('미집계')),
      findsOneWidget,
    );
    final progress = find.descendant(
      of: clientCard,
      matching: find.byKey(
        const ValueKey<String>('client-weekly-adherence-seed-client-7'),
      ),
    );
    expect(tester.widget<LinearProgressIndicator>(progress).value, 0);
  });

  testWidgets('the panel location is a path that encodes the section', (
    tester,
  ) async {
    await openWide(tester);
    await tester.tap(card('김민수'));
    await settle(tester);

    final ctx = tester.element(find.text('식단'));
    final uri = GoRouterState.of(ctx).uri;
    // Path-based, not `?c=`: refresh, back/forward and shared links all
    // restore the same client AND the same sub-tab.
    expect(uri.path, '/clients/seed-client-1/diet');
  });

  testWidgets('the detail header fits the narrowest split panel', (
    tester,
  ) async {
    // Exactly at the breakpoint the panel is its thinnest (viewport −
    // the 340px roster − the divider ≈ 559px), and the header is dense:
    // name + 활성 + 채팅 button + close on one row, then three metric
    // tiles, then two actions. Flutter throws on a RenderFlex overflow,
    // so rendering it here is the assertion.
    tester.view.physicalSize = const Size(AppLayout.splitBreakpoint, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      // 김민수 is over on sodium, so the alert row renders too.
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('나트륨 초과'), findsWidgets);
    // 신체·목표는 메모와 한 대화상자로 합쳐졌고, 메모 버튼은 프로필 줄의
    // 아이콘 버튼으로 옮겨 갔다(#1024).
    expect(find.text('리포트'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
      findsOneWidget,
    );
  });

  testWidgets('a percent-encoded id round-trips through the path', (
    tester,
  ) async {
    await openWide(tester);
    // A backend member id is not guaranteed URL-safe; the location must
    // survive one that isn't.
    expect(AppRoutes.clientDetail('a b/c'), '/clients/a%20b%2Fc/diet');
  });
}
