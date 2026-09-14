import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_follow_up_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';

import 'follow_up_fake_repository.dart';

Future<void> _pumpDialog(
  WidgetTester tester,
  FollowUpTaskRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        followUpTaskRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        // 행이 규격 컴포넌트(#1703)라 앱 테마(OnCareTokens)가 있어야 그린다.
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ClientFollowUpDialog(clientId: 'm1', clientName: '이지수'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('등록한 할 일이 목록에 남고 다시 열어도 그대로다', (tester) async {
    final repository = FakeFollowUpRepository();
    await _pumpDialog(tester, repository);

    expect(find.text('남은 후속 관리가 없어요.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('client-follow-up-input')),
      '최근 식단 나트륨 다시 확인',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('client-follow-up-add')),
    );
    await tester.pumpAndSettle();

    expect(find.text('최근 식단 나트륨 다시 확인'), findsOneWidget);
    expect(find.text('남은 후속 관리가 없어요.'), findsNothing);

    // 새 다이얼로그(새 provider container)는 저장소에서 다시 읽는다 — 위젯
    // 상태에 들고 있는 값이 아니다.
    await _pumpDialog(tester, repository);
    expect(find.text('최근 식단 나트륨 다시 확인'), findsOneWidget);
  });

  testWidgets('저장이 실패하면 입력한 내용과 목록이 그대로 남는다', (tester) async {
    final repository = FakeFollowUpRepository()
      ..seed(id: 'task-1', title: '이미 있던 할 일', dueDate: todayKst());
    await _pumpDialog(tester, repository);

    repository.failWrites = true;
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-follow-up-input')),
      '저장 실패할 내용',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('client-follow-up-add')),
    );
    await tester.pumpAndSettle();

    // 실패한 저장을 다시 누르는 데 다시 타이핑이 필요하면 안 된다.
    expect(find.text('저장 실패할 내용'), findsOneWidget);
    expect(find.text('이미 있던 할 일'), findsOneWidget);
    expect(repository.tasks.length, 1);

    // 재시도는 **같은 멱등키**로 나간다 — 앞선 시도가 서버에 닿았더라도 할 일이
    // 두 개가 되지 않는다.
    repository.failWrites = false;
    await tester.tap(
      find.byKey(const ValueKey<String>('client-follow-up-add')),
    );
    await tester.pumpAndSettle();
    expect(repository.seenRequestIds.length, 2);
    expect(repository.seenRequestIds.first, repository.seenRequestIds.last);
    expect(repository.tasks.length, 2);
  });

  testWidgets('완료한 할 일은 남은 목록에서 빠진다', (tester) async {
    final repository = FakeFollowUpRepository()
      ..seed(id: 'task-1', title: '무릎 통증 확인', dueDate: todayKst());
    await _pumpDialog(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('follow-up-complete-task-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('무릎 통증 확인'), findsNothing);
    expect(find.text('남은 후속 관리가 없어요.'), findsOneWidget);
    // 지운 것이 아니라 완료로 남는다 — 이력은 유지된다.
    expect(repository.tasks.single.isCompleted, isTrue);
  });

  testWidgets('조회가 실패하면 다이얼로그 안에서 다시 시도한다', (tester) async {
    final repository = FakeFollowUpRepository()..failReads = true;
    await _pumpDialog(tester, repository);

    expect(find.text('후속 관리를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);

    repository
      ..failReads = false
      ..seed(id: 'task-1', title: '다시 불러온 할 일', dueDate: todayKst());
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('다시 불러온 할 일'), findsOneWidget);
  });
}
