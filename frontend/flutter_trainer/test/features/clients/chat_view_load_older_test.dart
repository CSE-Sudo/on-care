/// 회원 메시지 화면에서 위로 올리면 이전 메시지가 이어서 보인다. (#2749)
///
/// 서버는 최신 50건만 주고 폴링도 그 쪽만 다시 받는다. 화면은 맨 위에서 이전
/// 쪽을 받아 앞에 붙이고, 보던 자리를 지키며, 처음 메시지까지 받으면 멈춘다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/chat_thread_history.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

import '../../helpers/paged_chat_repository.dart';

final Finder _loadOlder = find.byKey(
  const ValueKey<String>('trainer-chat-load-older'),
);
final Finder _retry = find.byKey(
  const ValueKey<String>('trainer-chat-older-retry'),
);

Future<PagedChatRepository> _pump(
  WidgetTester tester,
  int count, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final PagedChatRepository repo = PagedChatRepository(pagedChatThread(count));
  addTearDown(repo.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: true,
          ),
        ),
        chatRepositoryProvider.overrideWithValue(repo),
        trainerMemosProvider.overrideWith(
          (ref, clientId) async => const <TrainerMemo>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ChatView(clientId: 'm1', clientAvatar: '김', clientName: '김민수'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

ScrollController _controller(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

/// 사용자 스크롤이 아니라 코드로 맨 위에 둔다 — 자동 받기는 걸리지 않는다.
Future<void> _jumpToTop(WidgetTester tester) async {
  _controller(tester).jumpTo(0);
  await tester.pumpAndSettle();
}

List<ClientChatMessage> _visible(WidgetTester tester) {
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(ChatView)),
  );
  return visibleChatThread(
    container.read(chatThreadHistoryProvider('m1')),
    container.read(chatThreadProvider('m1')).valueOrNull ??
        const <ClientChatMessage>[],
  );
}

void main() {
  testWidgets('열면 최신 50건과 맨 아래가 보이고, 이전 쪽은 아직 받지 않는다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 120);

    expect(find.text('body-m119'), findsOneWidget);
    expect(repo.olderCursors, isEmpty, reason: '맨 아래로 내리는 동안 받지 않는다');
    expect(_visible(tester), hasLength(50));

    await _jumpToTop(tester);
    expect(_loadOlder, findsOneWidget);
    expect(find.text('이전 메시지 더 보기'), findsOneWidget);
  });

  testWidgets('위로 끝까지 올리면 이전 메시지를 받아 앞에 붙인다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 120);

    await tester.fling(find.byType(ListView), const Offset(0, 4000), 4000);
    await tester.pumpAndSettle();
    if (repo.olderCursors.isEmpty) {
      // 한 번에 끝까지 닿지 않았다면 한 번 더 올린다.
      await tester.drag(find.byType(ListView), const Offset(0, 4000));
      await tester.pumpAndSettle();
    }

    expect(repo.olderCursors.first.id, 'm070');
    expect(_visible(tester), hasLength(100));
    expect(_visible(tester).first.id, 'm020');
  });

  testWidgets('이전 쪽이 붙어도 보던 메시지가 그 자리에 있다', (tester) async {
    await _pump(tester, 120);
    await _jumpToTop(tester);
    final double before = tester.getTopLeft(find.text('body-m070')).dy;

    await tester.tap(_loadOlder);
    await tester.pumpAndSettle();

    expect(_visible(tester).first.id, 'm020');
    expect(find.text('body-m070'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('body-m070')).dy,
      moreOrLessEquals(before, epsilon: 1),
    );
  });

  testWidgets('처음 메시지까지 받은 뒤에는 더 받지 않고 자리도 사라진다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 120);
    await _jumpToTop(tester);
    await tester.tap(_loadOlder);
    await tester.pumpAndSettle();
    await _jumpToTop(tester);
    await tester.tap(_loadOlder);
    await tester.pumpAndSettle();

    expect(_visible(tester), hasLength(120));
    expect(repo.olderCursors, hasLength(2));

    await _jumpToTop(tester);
    expect(find.text('body-m000'), findsOneWidget);
    expect(_loadOlder, findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(repo.olderCursors, hasLength(2));
  });

  testWidgets('폴링 뒤에도 불러온 이전 메시지가 남고 중복되지 않는다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 120);
    await _jumpToTop(tester);
    await tester.tap(_loadOlder);
    await tester.pumpAndSettle();

    repo.thread = <ClientChatMessage>[...repo.thread, pagedChatMessage(120)];
    repo.poll();
    await tester.pumpAndSettle();

    final List<ClientChatMessage> thread = _visible(tester);
    expect(thread, hasLength(101));
    expect(thread.first.id, 'm020');
    expect(thread.map((m) => m.id).toSet(), hasLength(101));
    // 새 메시지가 왔으니 맨 아래로 내려 보여 준다.
    expect(find.text('body-m120'), findsOneWidget);
  });

  testWidgets('대화가 한 쪽보다 짧으면 이전 쪽 자리가 없다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 12);
    await _jumpToTop(tester);

    expect(_loadOlder, findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(repo.olderCursors, isEmpty);
  });

  testWidgets('받지 못하면 같은 자리에 다시 시도가 뜨고, 누르면 다시 받는다', (tester) async {
    final PagedChatRepository repo = await _pump(tester, 120);
    repo.failOlder = true;
    await _jumpToTop(tester);
    await tester.tap(_loadOlder);
    await tester.pumpAndSettle();

    expect(_retry, findsOneWidget);
    expect(find.text('이전 메시지를 불러오지 못했어요 · 다시 시도'), findsOneWidget);
    expect(_visible(tester), hasLength(50));

    repo.failOlder = false;
    await tester.tap(_retry);
    await tester.pumpAndSettle();

    expect(_visible(tester), hasLength(100));
    expect(repo.olderCursors.map((m) => m.id), <String>['m070', 'm070']);
  });

  testWidgets('영어 화면에서도 문구가 나온다', (tester) async {
    await _pump(tester, 120, locale: const Locale('en'));
    await _jumpToTop(tester);

    expect(find.text('Load earlier messages'), findsOneWidget);
  });
}
