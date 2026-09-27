// 같은 탭에서 계정을 바꿨을 때 화면에 이전 트레이너의 데이터가 그려지지 않는가.
// (#2285)
//
// 앱의 라우터처럼 로그인한 동안에만 콘솔을 붙이고, 로그아웃하면 로그인 화면으로
// 바꾸는 작은 셸을 쓴다. 콘솔은 `valueOrNull` 로 그린다 — 응답을 기다리는 동안
// 이전 값을 그대로 보여 주는 가장 흔한 읽기 방식이라, 이전 계정의 값이 로딩 상태에
// 실려 있으면 바로 화면에 드러난다. 저장소 provider 는 실제 정의 그대로다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/account_switch_backend.dart';

class _Shell extends ConsumerWidget {
  const _Shell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionStatus status = ref.watch(
      sessionControllerProvider.select((SessionState s) => s.status),
    );
    return status == SessionStatus.authenticated
        ? const _Console()
        : const Text('login-screen');
  }
}

class _Console extends ConsumerWidget {
  const _Console();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];
    final managed = ref.watch(managedClientsProvider).valueOrNull ?? const [];
    final prioritized =
        ref.watch(prioritizedClientsProvider).valueOrNull ?? const [];
    final notifications =
        ref.watch(trainerNotificationsProvider).valueOrNull?.items ?? const [];
    final templates =
        ref.watch(programTemplatesProvider).valueOrNull ?? const [];
    return ListView(
      children: <Widget>[
        for (final c in clients) Text('client:${c.name}'),
        for (final c in managed) Text('managed:${c.name}'),
        for (final c in prioritized) Text('priority:${c.name}'),
        for (final n in notifications) Text('notification:${n.title}'),
        for (final t in templates) Text('template:${t.name}'),
      ],
    );
  }
}

void main() {
  late ProviderContainer container;
  late SessionController session;

  Future<void> pumpShell(WidgetTester tester) async {
    final setup = makeAccountSwitchContainer();
    container = setup.container;
    session = container.read(sessionControllerProvider.notifier);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _Shell())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 세션 동작을 시작하고, 끝날 때까지 가짜 시계를 돌린다.
  Future<void> act(WidgetTester tester, Future<void> Function() action) async {
    bool done = false;
    final Future<void> running = action().whenComplete(() => done = true);
    for (int i = 0; i < 50 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, isTrue, reason: '세션 동작이 끝나지 않았다');
    await running;
  }

  /// 응답을 기다리는 몇 프레임. 각 프레임마다 [eachFrame] 으로 화면을 검사한다.
  Future<void> pumpFrames(
    WidgetTester tester, {
    void Function()? eachFrame,
  }) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      eachFrame?.call();
    }
  }

  Finder anyOf(TestTrainer t) => find.byWidgetPredicate(
    (Widget w) =>
        w is Text &&
        (w.data ?? '').contains(
          RegExp(
            '${RegExp.escape(t.memberName)}|'
            '${RegExp.escape(t.notificationTitle)}|'
            '${RegExp.escape(t.templateName)}',
          ),
        ),
  );

  /// 트리를 내리고 컨테이너를 닫아 폴링 타이머를 정리한다.
  Future<void> tearDownShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('A → 로그아웃 → B: 콘솔에는 한 프레임도 A 의 데이터가 그려지지 않는다', (tester) async {
    await pumpShell(tester);
    expect(find.text('login-screen'), findsOneWidget);

    await act(
      tester,
      () => session.login(email: TestTrainer.a.email, password: 'pw'),
    );
    await pumpFrames(tester);
    expect(find.text('client:${TestTrainer.a.memberName}'), findsOneWidget);
    expect(find.text('managed:${TestTrainer.a.memberName}'), findsOneWidget);
    expect(find.text('priority:${TestTrainer.a.memberName}'), findsOneWidget);
    expect(
      find.text('notification:${TestTrainer.a.notificationTitle}'),
      findsOneWidget,
    );
    expect(find.text('template:${TestTrainer.a.templateName}'), findsOneWidget);

    await act(tester, session.signOut);
    await pumpFrames(tester);
    expect(find.text('login-screen'), findsOneWidget);
    expect(anyOf(TestTrainer.a), findsNothing);

    await act(
      tester,
      () => session.login(email: TestTrainer.b.email, password: 'pw'),
    );
    await pumpFrames(
      tester,
      eachFrame: () => expect(
        anyOf(TestTrainer.a),
        findsNothing,
        reason: 'B 의 콘솔에 A 의 데이터가 그려졌다',
      ),
    );
    expect(find.text('client:${TestTrainer.b.memberName}'), findsOneWidget);
    expect(find.text('managed:${TestTrainer.b.memberName}'), findsOneWidget);
    expect(find.text('priority:${TestTrainer.b.memberName}'), findsOneWidget);
    expect(
      find.text('notification:${TestTrainer.b.notificationTitle}'),
      findsOneWidget,
    );
    expect(find.text('template:${TestTrainer.b.templateName}'), findsOneWidget);

    await tearDownShell(tester);
  });

  testWidgets('B 가 로그아웃하고 A 가 다시 들어와도 B 의 데이터는 남지 않는다', (tester) async {
    await pumpShell(tester);

    await act(
      tester,
      () => session.login(email: TestTrainer.b.email, password: 'pw'),
    );
    await pumpFrames(tester);
    expect(find.text('client:${TestTrainer.b.memberName}'), findsOneWidget);

    await act(tester, session.signOut);
    await pumpFrames(tester);
    await act(
      tester,
      () => session.login(email: TestTrainer.a.email, password: 'pw'),
    );
    await pumpFrames(
      tester,
      eachFrame: () => expect(anyOf(TestTrainer.b), findsNothing),
    );
    expect(find.text('client:${TestTrainer.a.memberName}'), findsOneWidget);

    await tearDownShell(tester);
  });

  testWidgets('로그아웃하면 이전 계정의 데이터가 로그인 화면 뒤에도 남지 않는다', (tester) async {
    await pumpShell(tester);
    await act(
      tester,
      () => session.login(email: TestTrainer.a.email, password: 'pw'),
    );
    await pumpFrames(tester);
    expect(anyOf(TestTrainer.a), findsWidgets);

    await act(tester, session.signOut);
    await pumpFrames(tester);

    // 화면은 로그인 화면이고, 콘솔이 보던 값도 다음 로그인을 기다리지 않고
    // 버려져 있다.
    expect(find.text('login-screen'), findsOneWidget);
    expect(anyOf(TestTrainer.a), findsNothing);
    expect(container.exists(clientsProvider), isFalse);
    expect(container.exists(trainerNotificationsProvider), isFalse);
    expect(container.exists(programTemplatesProvider), isFalse);

    await tearDownShell(tester);
  });
}
