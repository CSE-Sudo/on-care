import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

import '../../helpers/pump_app.dart';

/// 대화 목록을 [finder] 가 나올 때까지 [step] 만큼씩 끈다.
///
/// `ListView` 는 보이는 만큼만 만들기 때문에, 스크롤 밖 메시지는 트리에 아예
/// 없다. 고정된 픽셀 수로 한 번 끄는 방식은 스레드 길이가 바뀌면 곧바로
/// 깨진다 — 실제로 대화가 3일치로 늘자 그렇게 깨졌다. (#543)
Future<void> dragUntil(
  WidgetTester tester,
  Finder finder,
  double step, {
  int maxDrags = 40,
}) async {
  for (int i = 0; i < maxDrags && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), Offset(0, step));
    await tester.pump();
  }
}

/// Delays every insert so tests can act while a send is in flight.
class _SlowChatRepository extends DriftChatRepository {
  const _SlowChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return super.sendTrainerMessage(
      clientId: clientId,
      text: text,
      reportWeekStart: reportWeekStart,
    );
  }
}

/// Blocks on a caller-controlled future so the test can decide exactly
/// when (and whether) the send fails — used to fail AFTER the widget is
/// disposed, deterministically exercising the catch path.
class _ControllableChatRepository extends DriftChatRepository {
  const _ControllableChatRepository(super.db, this.gate);

  final Future<void> gate;

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) => gate;
}

/// Stands in for the memo source the chat view reads to mark already-saved
/// insights. Without it this test's real-API config would send the memo GET
/// to a Dio with no server behind it.
class _NoMemoRepository implements TrainerMemoRepository {
  const _NoMemoRepository();

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async =>
      const <TrainerMemo>[];
  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
  }) async => throw UnsupportedError('not used');
  @override
  Future<TrainerMemo> update(String clientId, String memoId, String body) =>
      throw UnsupportedError('not used');
  @override
  Future<void> delete(String clientId, String memoId) async {}
}

class _StaticLiveChatRepository implements ChatRepository {
  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream<List<ClientChatMessage>>.value(<ClientChatMessage>[
        ClientChatMessage(
          id: 'live-1',
          sender: ChatSender.client,
          body: '실제 회원 답장',
          timeLabel: '금 09:00',
          createdAt: DateTime.utc(2026, 7, 31, 9),
        ),
      ]);

  @override
  Future<void> markThreadRead(String clientId) async {}

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});
}

class _ThreadFailsOnceRepository extends _StaticLiveChatRepository {
  int watchCalls = 0;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) {
    watchCalls++;
    if (watchCalls == 1) {
      return Stream<List<ClientChatMessage>>.error(
        StateError('chat transport detail'),
      );
    }
    return super.watchThread(clientId);
  }
}

void main() {
  group('DriftChatRepository', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test(
      'watchThread returns a client thread in chronological order',
      () async {
        final thread = await DriftChatRepository(
          db,
        ).watchThread('seed-client-1').first;
        expect(thread, isNotEmpty);
        // 시드 스레드는 닷새 전 트레이너의 이행률 질문으로 시작한다. 본문·순서 전체는
        // test/core/storage/demo_chat_thread_test.dart 가 고정한다.
        expect(thread.first.sender, ChatSender.trainer);
        expect(thread.first.body, contains('지난주 기록 정리해 봤는데'));
        // Sorted ascending by createdAt.
        for (var i = 1; i < thread.length; i++) {
          expect(
            thread[i].createdAt.isBefore(thread[i - 1].createdAt),
            isFalse,
          );
        }
      },
    );

    test(
      'sendTrainerMessage appends a trainer message that sorts last',
      () async {
        final repo = DriftChatRepository(db);
        await repo.sendTrainerMessage(
          clientId: 'seed-client-1',
          text: '  안녕하세요  ',
        );

        final thread = await repo.watchThread('seed-client-1').first;
        final last = thread.last;
        expect(last.sender, ChatSender.trainer);
        expect(last.body, '안녕하세요'); // trimmed
        expect(last.id.startsWith('seed-'), isFalse); // survives re-seed
      },
    );

    test('sendTrainerMessage refreshes the client list preview', () async {
      final repo = DriftChatRepository(db);
      await repo.sendTrainerMessage(clientId: 'seed-client-2', text: '내일 봬요!');
      final row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-2'))).getSingle();
      expect(row.lastMessage, '내일 봬요!');
      expect(row.lastTime, '방금');
    });

    test(
      'watchUnreadCounts counts client messages until marked read',
      () async {
        final repo = DriftChatRepository(db);

        // 오세라 · 배준혁 are waiting on a reply — their threads end with
        // a member message (오세라's with two in a row). 김민수 · 이지수 ·
        // 박성호 end with the trainer's reply, so the seed marks them read
        // and they have no badge.
        var counts = await repo.watchUnreadCounts().first;
        expect(counts.containsKey('seed-client-1'), isFalse);
        expect(counts.containsKey('seed-client-2'), isFalse);
        expect(counts.containsKey('seed-client-3'), isFalse);
        expect(counts['seed-client-8'], 2);
        expect(counts['seed-client-9'], 1);

        // Opening 오세라's thread clears her badge only.
        await repo.markThreadRead('seed-client-8');
        counts = await repo.watchUnreadCounts().first;
        expect(counts.containsKey('seed-client-8'), isFalse);
        expect(counts['seed-client-9'], 1);

        // A trainer message never counts as unread.
        await repo.sendTrainerMessage(clientId: 'seed-client-8', text: '확인!');
        counts = await repo.watchUnreadCounts().first;
        expect(counts.containsKey('seed-client-8'), isFalse);

        // A NEW client reply after the marker counts again.
        await db
            .into(db.clientChatMessages)
            .insert(
              ClientChatMessagesCompanion.insert(
                id: 'chat-reply-1',
                clientId: 'seed-client-8',
                sender: 'client',
                body: '네 감사합니다!',
                timeLabel: '09:00',
                createdAt: nowKst().add(const Duration(seconds: 2)),
              ),
            );
        counts = await repo.watchUnreadCounts().first;
        expect(counts['seed-client-8'], 1);
      },
    );

    test('markThreadRead is idempotent and skips redundant writes', () async {
      final repo = DriftChatRepository(db);

      Future<String?> marker() => db.readValue('chat_read_seed-client-2');

      // First call stores the newest client message's rowid.
      await repo.markThreadRead('seed-client-2');
      final first = await marker();
      expect(first, isNotNull);
      expect((await repo.watchUnreadCounts().first)['seed-client-2'], isNull);

      // Repeat calls must produce the SAME value — an unconditional
      // write would emit on app_key_values and rebuild the list, which
      // is what the write→watch→build concern was about (review PR 241).
      for (var i = 0; i < 3; i++) {
        await repo.markThreadRead('seed-client-2');
      }
      expect(await marker(), first);

      // A trainer message doesn't move the marker (only client messages
      // can be unread).
      await repo.sendTrainerMessage(clientId: 'seed-client-2', text: '확인!');
      await repo.markThreadRead('seed-client-2');
      expect(await marker(), first);

      // A NEW client reply advances it exactly once.
      await db
          .into(db.clientChatMessages)
          .insert(
            ClientChatMessagesCompanion.insert(
              id: 'chat-reply-x',
              clientId: 'seed-client-2',
              sender: 'client',
              body: '넵!',
              timeLabel: '09:00',
              createdAt: nowKst().add(const Duration(seconds: 5)),
            ),
          );
      await repo.markThreadRead('seed-client-2');
      final second = await marker();
      expect(second, isNot(first));
      await repo.markThreadRead('seed-client-2');
      expect(await marker(), second);
    });

    test(
      'a same-second reply after markThreadRead still counts as unread',
      () async {
        final repo = DriftChatRepository(db);
        // A fresh client with no seeded messages, so the count is only
        // what this test inserts.
        const cid = 'rowid-test-client';
        final sameSecond = DateTime(2026, 1, 1, 9);

        // First client message, then mark the thread read.
        await db
            .into(db.clientChatMessages)
            .insert(
              ClientChatMessagesCompanion.insert(
                id: 'chat-ss-1',
                clientId: cid,
                sender: 'client',
                body: '첫 메시지',
                timeLabel: '09:00',
                createdAt: sameSecond,
              ),
            );
        await repo.markThreadRead(cid);
        expect((await repo.watchUnreadCounts().first)[cid], isNull);

        // A SECOND reply lands in the very same second. An epoch-second
        // marker (created_at > marker) would miss it because both share
        // the same second; the rowid marker still flags it (review 241).
        await db
            .into(db.clientChatMessages)
            .insert(
              ClientChatMessagesCompanion.insert(
                id: 'chat-ss-2',
                clientId: cid,
                sender: 'client',
                body: '같은 초에 온 두 번째 메시지',
                timeLabel: '09:00',
                createdAt: sameSecond,
              ),
            );
        expect((await repo.watchUnreadCounts().first)[cid], 1);
      },
    );

    test(
      'markThreadRead on a thread with no client message writes nothing',
      () async {
        await DriftChatRepository(db).markThreadRead('no-such-client');
        expect(await db.readValue('chat_read_no-such-client'), isNull);
      },
    );

    test('sendTrainerMessage ignores empty/whitespace input', () async {
      final repo = DriftChatRepository(db);
      final before = (await repo.watchThread('seed-client-1').first).length;
      await repo.sendTrainerMessage(clientId: 'seed-client-1', text: '   ');
      final after = (await repo.watchThread('seed-client-1').first).length;
      expect(after, before);
    });
  });

  group('Messages workspace chat', () {
    testWidgets('a failed thread retries without leaving messages', (
      tester,
    ) async {
      final repository = _ThreadFailsOnceRepository();
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.messagesFor('seed-client-1'),
        extraOverrides: <Override>[
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );

      expect(find.text('대화를 불러오지 못했어요'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-retry-seed-client-1')),
      );
      await settle(tester);

      final context = tester.element(find.byType(Navigator).first);
      expect(
        GoRouter.of(context).routeInformationProvider.value.uri.toString(),
        AppRoutes.messagesFor('seed-client-1'),
      );
      expect(repository.watchCalls, 2);
      expect(find.text('실제 회원 답장'), findsOneWidget);
    });

    testWidgets('legacy client chat deep-link redirects to messages', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'chat'),
      );
      final context = tester.element(find.byType(Navigator).first);
      expect(
        GoRouter.of(context).routeInformationProvider.value.uri.toString(),
        AppRoutes.messagesFor('seed-client-1'),
      );
    });

    testWidgets('real chat omits demo-only analysis and sent banners', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(
              const AppConfig(
                environment: Environment.dev,
                apiBaseUrl: 'http://localhost/v1',
                useMockApi: false,
              ),
            ),
            chatRepositoryProvider.overrideWithValue(
              _StaticLiveChatRepository(),
            ),
            trainerMemoRepositoryProvider.overrideWithValue(
              const _NoMemoRepository(),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatView(
                clientId: 'user-7d4e9a2c5f18',
                clientAvatar: '김',
                clientName: '김민수',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('실제 회원 답장'), findsOneWidget);
      expect(find.text('2026년 7월 31일 금요일'), findsOneWidget);
      expect(find.textContaining('AI가 김민수님의 식단'), findsNothing);
      expect(find.textContaining('개인 추천운동'), findsNothing);

      final bubble = find.byKey(
        const ValueKey<String>('trainer-message-bubble-live-1'),
      );
      final time = find.byKey(
        const ValueKey<String>('trainer-message-time-live-1'),
      );
      expect(tester.widget<Text>(time).data, '09:00');
      expect(find.text('금 09:00'), findsNothing);
      expect(
        tester.getTopLeft(time).dx,
        greaterThan(tester.getTopRight(bubble).dx),
      );
    });

    Future<void> openMessages(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1024);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.messagesFor('seed-client-1'),
      );
    }

    testWidgets('shows the conversation list and seeded thread', (
      tester,
    ) async {
      await openMessages(tester);
      expect(find.text('김민수'), findsWidgets);
      final reply = find.text('찌개 먹을 때 국물을 많이 마셨나봐요 😅');
      await dragUntil(tester, reply, -300);
      expect(reply, findsOneWidget);
    });

    testWidgets('shows dates and places each time outside its bubble', (
      tester,
    ) async {
      await openMessages(tester);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(
                r'^\d{4}년 \d{1,2}월 \d{1,2}일 [월화수목금토일]요일$',
              ).hasMatch(widget.data ?? ''),
        ),
        findsAtLeastNWidgets(1),
      );

      // 스레드의 마지막 메시지(트레이너 발신). 17번은 리포트 등록 안내라
      // 말풍선이 아니다 — 시각도 붙지 않는다(#1605).
      final sentBubble = find.byKey(
        const ValueKey<String>('trainer-message-bubble-seed-chat-1-18'),
      );
      final sentTime = find.byKey(
        const ValueKey<String>('trainer-message-time-seed-chat-1-18'),
      );
      expect(
        tester.getTopLeft(sentTime).dx,
        lessThan(tester.getTopLeft(sentBubble).dx),
      );
    });

    testWidgets('sending a message appends it to the thread', (tester) async {
      await openMessages(tester);
      await tester.enterText(find.byType(TextField).last, '다음 세션 때 봐요!');
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);
      // The sent message appears in both the thread and the conversation
      // preview, keeping the two-pane workspace in sync.
      expect(find.text('다음 세션 때 봐요!'), findsWidgets);
    });

    testWidgets('김민수 데모 시드에 리포트 등록 카드가 있다 (#1605)', (tester) async {
      await openMessages(tester);

      expect(find.text('리포트가 등록되었어요'), findsOneWidget);
      expect(find.text('리포트 탭으로 가기'), findsOneWidget);
      // 카드로 그리므로 본문은 말풍선으로 나타나지 않는다.
      expect(find.text('이번 주 리포트 등록해 뒀어요. 확인해 보세요'), findsNothing);
    });

    testWidgets(
      '리포트 전송 메시지는 일반 말풍선이 아니라 카드로 뜨고, 누르면 리포트로 이동한다 (#1378)',
      (tester) async {
        final container = await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.messagesFor('seed-client-1'),
        );
        // 데모/드리프트는 PDF를 저장하지 못한다 — reportWeekStart만 실어
        // 보내도 채팅이 카드로 구분해 그려야 한다.
        await container
            .read(chatRepositoryProvider)
            .sendTrainerMessage(
              clientId: 'seed-client-1',
              text: '김민수님, 8월 18일 – 8월 24일 주간 리포트 정리해서 보내드려요.',
              reportWeekStart: DateTime(2026, 8, 18),
            );
        await settle(tester);

        // 시드에도 리포트 등록 안내가 하나 있다(#1605). 방금 보낸 것은 대상
        // 주로 갈라 짚는다 — 시드가 가리키는 주는 언제나 이번 주라, 지나간
        // 이 주와 겹치지 않는다.
        final card = find.ancestor(
          of: find.text('8월 18일 – 8월 24일'),
          matching: find.byType(ReportRegisteredCard),
        );
        expect(card, findsOneWidget);
        // 회원 앱과 같은 정보 구조 — 상태 문구, 대상 주, 다음 행동.
        final notice = find.descendant(
          of: card,
          matching: find.text('리포트가 등록되었어요'),
        );
        final goToReports = find.descendant(
          of: card,
          matching: find.text('리포트 탭으로 가기'),
        );
        expect(notice, findsOneWidget);
        expect(goToReports, findsOneWidget);
        // 본문 그대로의 일반 말풍선은 그려지지 않는다.
        expect(
          find.text('김민수님, 8월 18일 – 8월 24일 주간 리포트 정리해서 보내드려요.'),
          findsNothing,
        );

        // 안내는 대화 가운데에 선다 — 트레이너가 보낸 말풍선처럼 오른쪽에
        // 붙지 않는다(#1600). 왼쪽 여백과 오른쪽 여백이 같은지로 본다.
        final Rect box = tester.getRect(card);
        final Rect thread = tester.getRect(find.byType(ListView).last);
        expect(
          (box.left - thread.left - (thread.right - box.right)).abs(),
          lessThan(1.0),
        );

        await tester.tap(goToReports);
        await settle(tester);

        final ctx = tester.element(find.byType(Navigator).first);
        final location = GoRouter.of(
          ctx,
        ).routerDelegate.currentConfiguration.uri.toString();
        // 카드가 가리키는 주가 리포트 화면에도 그대로 실린다 — 트레이너가
        // 카드를 누르고도 어느 주였는지 다시 찾게 두지 않는다(#1421).
        expect(
          location,
          AppRoutes.reportFor('seed-client-1', weekStart: DateTime(2026, 8, 18)),
        );
        expect(location, contains('week=2026-08-18'));
      },
    );

    testWidgets('a sent message lands below the routine-sent banner', (
      tester,
    ) async {
      await openMessages(tester);
      await tester.enterText(find.byType(TextField).last, '다음 세션 때 봬요!');
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);

      // 배너는 그날의 분석 → 대화 → 루틴 전송이라는 하루의 **끝**을 표시한다.
      // 목록 맨 아래에 고정돼 있으면 방금 보낸 답장이 그 앞으로 들어가,
      // 화면에서는 "내가 보낸 말이 루틴 전송보다 먼저" 로 읽힌다.
      // 배너는 날이 바뀌는 자리마다 한 번씩 더 있다 — 닫는 배너는 맨 뒤다.
      final banner = find.textContaining('개인 추천운동이').last;
      final sent = find.text('다음 세션 때 봬요!').last;
      expect(banner, findsOneWidget);
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(sent).dy),
      );
    });

    testWidgets(
      'mashing send while an insert is in flight stores one message',
      (tester) async {
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.messagesFor('seed-client-1'),
          extraOverrides: <Override>[
            chatRepositoryProvider.overrideWith(
              (ref) => _SlowChatRepository(ref.watch(appDatabaseProvider)),
            ),
          ],
        );
        await tester.enterText(find.byType(TextField).last, '중복 방지 확인');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byIcon(Icons.send), warnIfMissed: false);
        await settle(tester);
        expect(find.text('중복 방지 확인'), findsOneWidget);
      },
    );

    testWidgets('leaving messages during a slow send does not throw', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.messagesFor('seed-client-1'),
        extraOverrides: <Override>[
          chatRepositoryProvider.overrideWith(
            (ref) => _SlowChatRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );
      await tester.enterText(find.byType(TextField).last, '이탈 중 전송');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump(const Duration(milliseconds: 50));
      await goTo(tester, AppRoutes.dashboard);
      await settle(tester);
      expect(find.text('대시보드'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a failed send after leaving does not touch a disposed messenger',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.messagesFor('seed-client-1'),
          extraOverrides: <Override>[
            chatRepositoryProvider.overrideWith(
              (ref) => _ControllableChatRepository(
                ref.watch(appDatabaseProvider),
                gate.future,
              ),
            ),
          ],
        );
        await tester.enterText(find.byType(TextField).last, '이탈 중 실패');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.completeError(Exception('send failed'));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('메시지 전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
      },
    );

    testWidgets('client detail separates diet and workout evidence into tabs', (
      tester,
    ) async {
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
    });
  });
}
