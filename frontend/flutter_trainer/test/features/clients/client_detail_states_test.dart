import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_detail_view.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

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
      at: AppRoutes.clientDetail('seed-client-3', section: 'diet'),
    );

    // 박성호의 스레드는 트레이너가 마지막으로 답장해 두어 `답장 대기`가
    // 아니다. 이 테스트가 재는 것은 "배지가 탭 위에 남는가" 이므로 그가
    // 실제로 달고 있는 건강 신호로 확인한다.
    expect(find.text('나트륨 초과'), findsOneWidget);
    // 식단·운동은 자기 `ListView` 를 만들지 않는다(#1024) — 위의 식단↔운동
    // 전환 스트립과 하나의 스크롤을 공유한다. 그 `ListView` 가 이 키를 단다.
    final scroll = find.byKey(
      const ValueKey<String>('client-detail-tabs-seed-client-3'),
    );
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pump();
    expect(find.text('나트륨 초과'), findsOneWidget);
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

    // 식단·운동을 읽다가 그 자리에서 이어지는 동작들. 예전에는 이 줄이
    // 신체·목표와 메모 둘뿐이라, 말을 걸려면 메시지 탭에서 같은 사람을 다시
    // 찾아야 했다(#823). 신체·목표·후속 관리·메모는 #1024 에서 이 줄을
    // 떠났다 — 앞의 둘은 메모와 한 대화상자로 합쳐졌고, 메모 자신은 위
    // 프로필 줄의 아이콘 버튼이 되었다. 이 줄에는 '다른 화면으로 나가는'
    // 동작만 남는다.
    expect(find.text('메시지'), findsOneWidget);
    expect(find.text('프로그램'), findsOneWidget);
    expect(find.text('리포트'), findsOneWidget);
    expect(find.text('회원 신체·목표 관리'), findsNothing);
    expect(find.text('후속 관리'), findsNothing);
    expect(find.text('메모'), findsNothing);
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

    // 메모는 새로고침 바로 왼쪽에, 같은 아이콘 버튼 모양으로 선다 — 화면을
    // 떠나지 않고 여기서 끝나는 동작끼리 한 줄에 모인다(#1024).
    final memo = tester.getRect(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    final refresh = tester.getRect(
      find.byKey(const ValueKey<String>('client-data-refresh')),
    );
    expect(memo.right, lessThanOrEqualTo(refresh.left));
    expect(memo.center.dy, closeTo(refresh.center.dy, 0.1));
    // 빠른 동작 줄보다 위다 — 프로필 줄로 옮겨 갔다는 뜻이다.
    expect(memo.bottom, lessThanOrEqualTo(tester.getRect(actions).top));
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

  testWidgets('메모 버튼이 신체·목표와 메모를 한 창으로 연다 (#1024)', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-3'),
    );

    const dialog = ValueKey<String>('client-profile-dialog');
    // 열기 전에는 어느 쪽도 화면에 없다 — 페이지에 펼쳐 두지 않고, 눌렀을
    // 때만 뜨는 작은 창이다.
    expect(find.byKey(dialog), findsNothing);
    expect(find.text('회원 신체·목표 관리'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    await tester.pumpAndSettle();

    // 한 창 안에 상단 신체·목표, 하단 메모가 함께 선다 — 예전처럼 하나를
    // 닫아야 다른 하나를 열 수 있지 않다.
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.text('회원 신체·목표 관리'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-memo-input')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('client-profile-dialog-close')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
