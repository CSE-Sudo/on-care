import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_detail_view.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('an unknown client id shows a safe not-found state', (
    tester,
  ) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('no-such-client'),
    );

    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('회원 목록으로'));
    await settle(tester);
    expect(find.text('회원 관리'), findsWidgets);
  });

  testWidgets('a provider error offers retry', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.error(StateError('db down')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.clientDetail('seed-client-1'));

    expect(find.text('회원 정보를 불러오지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the alert remains visible above the detail tabs', (
    tester,
  ) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-8', section: 'diet'),
    );

    // 오세라는 대화에서 허리가 아프다고 한 회원이다 — PT 관리 신호(#2243)의
    // `통증·불편` 이 헤더에 붙는다. 이 테스트가 재는 것은 "배지가 탭 위에
    // 남는가" 다.
    expect(find.text('통증·불편'), findsOneWidget);
    // 식단·운동은 자기 `ListView` 를 만들지 않는다(#1024) — 위의 식단↔운동
    // 전환 스트립과 하나의 스크롤을 공유한다. 그 `ListView` 가 이 키를 단다.
    final scroll = find.byKey(
      const ValueKey<String>('client-detail-tabs-seed-client-8'),
    );
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pump();
    expect(find.text('통증·불편'), findsOneWidget);
  });

  testWidgets('diet and workout are separated into tabs', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
    );

    expect(
      find.byKey(const ValueKey<String>('client-detail-sub-tabs')),
      findsOneWidget,
    );
    // 이식 전에도 프로그램 탭과 같은 식단·운동 스트립이었다 — 같은 흰 엄지
    // 모양을 쓴다(#1024, #1777).
    expect(
      tester
          .widget<AppSegmentedToggle<String>>(
            find.byKey(const ValueKey<String>('client-detail-sub-tabs')),
          )
          .style,
      AppSegmentedToggleStyle.thumb,
    );
    expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
    expect(find.text('운동 현황'), findsNothing);

    await tester.tap(find.text('운동'));
    await settle(tester);

    expect(find.text('운동 현황'), findsOneWidget);
    expect(find.text('오늘 섭취 칼로리'), findsNothing);
    final context = tester.element(find.byType(Navigator).first);
    expect(
      GoRouter.of(context).routeInformationProvider.value.uri.path,
      '/clients/seed-client-1/workout',
    );
  });

  testWidgets('workout deep-link opens only the workout tab', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
    );

    expect(find.text('운동 현황'), findsOneWidget);
    expect(find.text('오늘 섭취 칼로리'), findsNothing);
  });

  testWidgets('상세 머리도 이름 옆에 목록과 같은 성별·나이를 적는다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
    );

    final BuildContext context = tester.element(
      find.byKey(const ValueKey<String>('client-detail-identity')),
    );
    final TrainerClient client = ProviderScope.containerOf(context)
        .read(clientsProvider)
        .requireValue
        .firstWhere((TrainerClient c) => c.id == 'seed-client-1');
    final Finder demographics = find.byKey(
      const ValueKey<String>('client-detail-demographics'),
    );
    expect(
      tester.widget<Text>(demographics).data,
      clientDemographicsLabel(context, client),
    );
    // 이름과 같은 줄, 이름 오른쪽이다.
    final Finder row = find.byKey(
      const ValueKey<String>('client-detail-name-row'),
    );
    final Finder name = find.descendant(
      of: row,
      matching: find.text(client.name),
    );
    expect(name, findsOneWidget);
    expect(
      tester.getRect(demographics).left,
      greaterThan(tester.getRect(name).right),
    );
  });

  test('legacy chat section safely resolves to the diet tab', () {
    final view = ClientDetailView(
      clientId: 'seed-client-1',
      section: 'chat',
      onSectionChange: (_) {},
    );

    expect(view.resolvedSection, AppRoutes.defaultClientSection);
  });

  testWidgets('빠른 동작이 이 회원의 메시지·프로그램까지 잇는다 (#823)', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-3'),
    );

    // 식단·운동을 읽다가 그 자리에서 이어지는 동작들. 예전에는 말을 걸려면
    // 메시지 탭에서 같은 사람을 다시 찾아야 했다(#823). 이 묶음에는 '다른
    // 화면으로 나가는' 동작만 있고, 아이콘만 그린다 — 이름은 툴팁이다(#2330).
    expect(find.byTooltip('메시지'), findsOneWidget);
    expect(find.byTooltip('프로그램'), findsOneWidget);
    expect(find.byTooltip('리포트'), findsOneWidget);
    expect(find.text('후속 관리'), findsNothing);
    // 일정 등록은 스케줄 라우트에 회원을 실을 자리가 없어 아직 넣지 않는다.
    expect(find.text('일정 등록'), findsNothing);
    expect(find.text('주간 리포트'), findsNothing);

    final actions = find.byKey(
      const ValueKey<String>('client-detail-quick-actions'),
    );
    expect(actions, findsOneWidget);
    // 이제 리포트가 줄의 오른쪽 끝을 지킨다(#729, #1024).
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey<String>('client-detail-open-report')),
          )
          .right,
      closeTo(tester.getRect(actions).right, 0.1),
    );

    // 신체·목표 → 메모는 이 화면에서 끝나는 동작이라 이름 옆, 나가는 묶음보다
    // 왼쪽에 선다(#2330). 새로고침은 없다 — 늘 자동으로 맞춘다.
    final health = tester.getRect(
      find.byKey(const ValueKey<String>('client-detail-open-health')),
    );
    final memo = tester.getRect(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    expect(health.right, lessThanOrEqualTo(memo.left));
    expect(memo.right, lessThan(tester.getRect(actions).left));
    // 나가는 묶음은 이름 줄이 아니라 `<`·아바타와 함께 이름·목표 두 줄의
    // 세로 가운데에 선다 — 메시지 탭 대화 머리와 같은 정렬이다.
    final back = tester.getRect(
      find.byKey(const ValueKey<String>('client-detail-back')),
    );
    final identity = tester.getRect(
      find.byKey(const ValueKey<String>('client-detail-identity')),
    );
    expect(tester.getRect(actions).center.dy, closeTo(back.center.dy, 0.5));
    expect(back.center.dy, closeTo(identity.center.dy, 0.5));
    expect(memo.center.dy, lessThan(tester.getRect(actions).center.dy));
    expect(
      find.byKey(const ValueKey<String>('client-data-refresh')),
      findsNothing,
    );
  });

  testWidgets('빠른 동작이 지금 보고 있는 회원을 물고 간다 (#823)', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-3'),
    );
    final router = GoRouter.of(tester.element(find.byType(ClientDetailView)));
    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-program')),
    );
    await tester.pumpAndSettle();
    expect(location(), contains('/coaching'));
    expect(location(), contains('client=seed-client-3'));
  });

  testWidgets('신체·목표와 메모는 각자 창을 연다 (#2330)', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-3'),
    );

    const dialog = ValueKey<String>('client-profile-dialog');
    const memoDialog = ValueKey<String>('client-memo-dialog');
    // 열기 전에는 어느 쪽도 화면에 없다 — 페이지에 펼쳐 두지 않고, 눌렀을
    // 때만 뜨는 작은 창이다.
    expect(find.byKey(dialog), findsNothing);
    expect(find.byKey(memoDialog), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    await tester.pumpAndSettle();

    // 메모 창에는 메모만 있다 — 목표 폼을 지나 스크롤하지 않는다.
    expect(find.byKey(memoDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-memo-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('client-profile-gender')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(memoDialog),
        matching: find.byTooltip('닫기'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-health')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dialog), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(dialog), matching: find.text('신체·목표')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('client-profile-gender')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('client-memo-input')),
      findsNothing,
    );

    // 닫기는 창 헤더의 X 하나다(AppDialog) — 접근성 이름으로 찾는다.
    await tester.tap(
      find.descendant(of: find.byKey(dialog), matching: find.byTooltip('닫기')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
