import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/follow_up_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';

import '../clients/follow_up_fake_repository.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  FollowUpTaskRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        followUpTaskRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: FollowUpCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('오늘 예정과 기한이 지난 항목이 함께 뜨고, 앞으로의 할 일은 빠진다', (
    tester,
  ) async {
    final today = todayKst();
    final repository = FakeFollowUpRepository()
      ..seed(
        id: 'task-overdue',
        title: '지난 주 식단 확인',
        dueDate: today.subtract(const Duration(days: 3)),
        memberName: '김민수',
      )
      ..seed(id: 'task-today', title: '오늘 메시지 답변 확인', dueDate: today)
      ..seed(
        id: 'task-future',
        title: '다음 주 프로그램 점검',
        dueDate: today.add(const Duration(days: 7)),
      );
    await _pumpCard(tester, repository);

    expect(find.text('지난 주 식단 확인'), findsOneWidget);
    expect(find.text('오늘 메시지 답변 확인'), findsOneWidget);
    // 앞으로의 할 일까지 오늘 목록에 세우면 "오늘 처리할 일"이 아니게 된다.
    expect(find.text('다음 주 프로그램 점검'), findsNothing);
    // 지난 항목은 날짜 대신 늦었다는 사실을 먼저 말한다.
    expect(find.text('기한 지남'), findsOneWidget);
    // 회원 이름이 함께 보인다 — 누구의 할 일인지 카드에서 바로 읽힌다.
    expect(find.text('김민수'), findsOneWidget);
  });

  testWidgets('완료를 누르면 그 줄이 오늘 목록에서 사라진다', (tester) async {
    final repository = FakeFollowUpRepository()
      ..seed(id: 'task-1', title: '나트륨 다시 확인', dueDate: todayKst());
    await _pumpCard(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('follow-up-complete-task-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('나트륨 다시 확인'), findsNothing);
    expect(find.text('오늘 처리할 후속 관리가 없어요.'), findsOneWidget);
    expect(repository.tasks.single.isCompleted, isTrue);
  });

  testWidgets('할 일이 없으면 빈 상태를 보여 준다', (tester) async {
    await _pumpCard(tester, FakeFollowUpRepository());
    expect(find.text('오늘 처리할 후속 관리가 없어요.'), findsOneWidget);
  });

  testWidgets('조회 실패는 이 카드 안에서만 다루고 다시 시도할 수 있다', (tester) async {
    final repository = FakeFollowUpRepository()..failReads = true;
    await _pumpCard(tester, repository);

    expect(find.text('후속 관리를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);

    repository
      ..failReads = false
      ..seed(id: 'task-1', title: '다시 불러온 할 일', dueDate: todayKst());
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('다시 불러온 할 일'), findsOneWidget);
  });

  group('followUpTarget', () {
    test('갈래마다 이미 있는 화면으로 보낸다', () {
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.message.wire),
        AppRoutes.messagesFor('m1'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.program.wire),
        AppRoutes.coachingFor('m1'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.diet.wire),
        AppRoutes.clientDetail('m1', section: 'diet'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.exercise.wire),
        AppRoutes.clientDetail('m1', section: 'workout'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.schedule.wire),
        AppRoutes.scheduleAt(),
      );
    });

    test('앱이 모르는 갈래는 회원 상세로 데려간다', () {
      // 서버가 새 값을 먼저 내보내도 목록이 죽지 않고, 적어도 그 회원 화면까지는
      // 간다.
      expect(
        AppRoutes.followUpTarget('m1', 'billing'),
        AppRoutes.clientDetail('m1'),
      );
      expect(
        FollowUpContext.fromWire('billing'),
        FollowUpContext.general,
      );
    });
  });
}
