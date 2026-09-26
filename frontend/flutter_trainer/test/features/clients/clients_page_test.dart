import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_member_directory.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/roster_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_card.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// [ClientInviteRepository] 가 꺼진 빌드 — 신규 회원 등록 진입점 자체가
/// 없는 상태를 흉내낸다.
class _NoInviteClientInviteRepository implements ClientInviteRepository {
  const _NoInviteClientInviteRepository();

  @override
  bool get supportsInvites => false;

  @override
  bool get connectsImmediately => false;

  @override
  Future<PairedMember> previewPairingCode(String code) async =>
      throw const NotFoundError();

  @override
  Future<PairedMember> redeemPairingCode(String code) async =>
      throw const NotFoundError();

  @override
  Future<ClientInvite> invite(String memberId, {String? message}) async =>
      throw const ValidationError();

  @override
  Future<List<ClientInvite>> listSent({String status = 'pending'}) async =>
      const <ClientInvite>[];

  @override
  Future<void> cancel(String inviteId) async {}
}

class _ReadOnlyClientRepository extends DriftClientRepository {
  const _ReadOnlyClientRepository(super.db);

  @override
  bool get supportsRosterMutations => false;
}

class _RecordingRefreshClientRepository extends DriftClientRepository
    implements ClientDataRefresher {
  _RecordingRefreshClientRepository(super.db);

  var allRefreshes = 0;
  final List<String> clientRefreshes = <String>[];

  @override
  void refreshAllClientData() {
    allRefreshes += 1;
  }

  @override
  void refreshClientData(String clientId) {
    clientRefreshes.add(clientId);
  }
}

/// 로스터 목록을 [finder] 가 그려질 때까지 끌어 내린다.
///
/// 목록은 지연 생성이라 화면 밖 카드가 트리에 아예 없다. 아래쪽에 선 회원을
/// 단언하려면 먼저 그려지게 해야 한다 — `.last`·`.first` 를 붙인 finder 를
/// 그대로 넘기면 아직 한 건도 없는 동안 `Bad state: No element` 로 깨진다.
Future<void> scrollToClient(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  // 이행률 바가 붙은 카드는 일부만 보여도 이미 트리에 있다. 가운데를 눌러도
  // 화면 밖 좌표가 되지 않도록 카드 전체를 실제 viewport 안으로 맞춘다.
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
}

void main() {
  group('ClientRepository', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('watchClients returns the seeded clients in sortOrder', () async {
      final clients = await DriftClientRepository(db).watchClients().first;
      // Unprioritised order is the seeded order, so the first three are
      // still the original roster the rest of these tests address.
      expect(clients.take(3).map((c) => c.name).toList(), <String>[
        '김민수',
        '이지수',
        '박성호',
      ]);
      expect(clients.length, 15);
    });

    test('sodiumOverBudget flags only clients above 2000mg', () async {
      final clients = await DriftClientRepository(db).watchClients().first;
      // The rule, not a name list — the roster is a fixture that grows.
      for (final c in clients) {
        expect(c.sodiumOverBudget, c.sodiumMg > 2000, reason: c.name);
      }
      // …and the fixture must keep exercising both sides of it.
      expect(clients.where((c) => c.sodiumOverBudget), isNotEmpty);
      expect(clients.where((c) => !c.sodiumOverBudget), isNotEmpty);
    });

    test('addClient appends a fresh profile after the seeded roster', () async {
      final repo = DriftClientRepository(db);
      final seeded = (await repo.watchClients().first).length;
      await repo.addClient(name: '  최수진  ', goal: '체중 감량');

      final clients = await repo.watchClients().first;
      expect(clients.length, seeded + 1);
      final added = clients.last; // large sortOrder appends
      expect(added.name, '최수진'); // trimmed
      expect(added.avatar, '최');
      expect(added.goal, '체중 감량');
      expect(added.active, isTrue);
      expect(added.sodiumMg, 0);
      expect(added.weekCompletion, List<int>.filled(7, 0));
      expect(added.id.startsWith('seed-'), isFalse); // survives re-seed
    });

    test(
      'addClient ignores an empty name and defaults an empty goal',
      () async {
        final repo = DriftClientRepository(db);
        final seeded = (await repo.watchClients().first).length;
        expect(await repo.addClient(name: '   ', goal: '아무거나'), isFalse);
        expect((await repo.watchClients().first).length, seeded);

        expect(await repo.addClient(name: '박도윤', goal: '  '), isTrue);
        final clients = await repo.watchClients().first;
        // 목표는 회원 건강 목표만 남는다 — 고르지 않았으면 비어 있다(#1818).
        expect(clients.last.goal, isEmpty);
      },
    );

    test('addClient rejects a duplicate name', () async {
      final repo = DriftClientRepository(db);
      final seeded = (await repo.watchClients().first).length;

      // Schedules resolve their client by NAME, so a second 김민수 could
      // receive the first one's chat/운동기록 (review PR 243).
      expect(await repo.addClient(name: '김민수', goal: '중복'), isFalse);
      expect(await repo.addClient(name: '  김민수  ', goal: '공백 차이'), isFalse);
      expect(await repo.addClient(name: '김민수 ', goal: '후행 공백'), isFalse);
      expect((await repo.watchClients().first).length, seeded); // nothing added

      // A genuinely new name still registers, and is then itself taken.
      expect(await repo.addClient(name: '최수진', goal: '체중 감량'), isTrue);
      expect(await repo.addClient(name: '최수진', goal: '또'), isFalse);
      expect((await repo.watchClients().first).length, seeded + 1);

      expect(await repo.clientNameExists('김민수'), isTrue);
      expect(await repo.clientNameExists('없는사람'), isFalse);
    });

    test('concurrent addClient of the same name inserts exactly one', () async {
      final repo = DriftClientRepository(db);

      // Fire both adds without awaiting between them: the check and the
      // insert share one transaction, so only one can pass the duplicate
      // guard even when they race (review PR 243).
      final results = await Future.wait(<Future<bool>>[
        repo.addClient(name: '한지민', goal: 'A'),
        repo.addClient(name: '한지민', goal: 'B'),
      ]);

      expect(results.where((r) => r).length, 1); // exactly one succeeded
      final matches = (await repo.watchClients().first)
          .where((c) => c.name == '한지민')
          .toList();
      expect(matches.length, 1); // and only one row exists
    });

    test('setClientActive flips the 활성/휴면 state', () async {
      final repo = DriftClientRepository(db);
      expect(repo.supportsRosterMutations, isTrue);
      await repo.setClientActive('seed-client-1', false);
      var clients = await repo.watchClients().first;
      expect(clients.firstWhere((c) => c.name == '김민수').active, isFalse);

      await repo.setClientActive('seed-client-1', true);
      clients = await repo.watchClients().first;
      expect(clients.firstWhere((c) => c.name == '김민수').active, isTrue);
    });

    test(
      'removeClient marks the client 미등록 without dropping it from the roster',
      () async {
        final repo = DriftClientRepository(db);
        await repo.removeClient('seed-client-1');

        final clients = await repo.watchClients().first;
        expect(
          clients.firstWhere((c) => c.id == 'seed-client-1').registered,
          isFalse,
        );
      },
    );

    test(
      'removeClient keeps 운동 기록·채팅·스케줄 원본 — 트레이너 화면에서만 사라진다 (#1623)',
      () async {
        final repo = DriftClientRepository(db);
        final schedule = DriftScheduleRepository(db);
        final chat = DriftChatRepository(db);

        final histBefore = await (db.select(
          db.clientRoutineHistory,
        )..where((t) => t.clientId.equals('seed-client-1'))).get();
        expect(histBefore, isNotEmpty); // seed fixture keeps this honest

        await repo.removeClient('seed-client-1');

        // 원본 행은 그대로다 — 지워지지 않는다.
        final histAfter = await (db.select(
          db.clientRoutineHistory,
        )..where((t) => t.clientId.equals('seed-client-1'))).get();
        expect(histAfter.length, histBefore.length);

        // 카드의 캐시된 주간 이행률도 그 원본과 여전히 맞아떨어진다 — 지워진
        // 기록을 근거로 한 숫자를 보여주지 않는다.
        final client = (await repo.watchClients().first).firstWhere(
          (c) => c.id == 'seed-client-1',
        );
        expect(client.weekCompletion, isNotEmpty);

        // 채팅 원본도 지워지지 않지만, 안읽음 배지·오늘 일정에는 더는
        // 잡히지 않는다 — 트레이너 화면에서만 사라진다는 약속.
        final thread = await chat.watchThread('seed-client-1').first;
        expect(thread, isNotEmpty);
        final counts = await chat.watchUnreadCounts().first;
        expect(counts.containsKey('seed-client-1'), isFalse);

        final range = await schedule
            .watchRange('2000-01-01', '2099-12-31')
            .first;
        expect(range.any((s) => s.clientId == 'seed-client-1'), isFalse);
        // 원본 슬롯은 지워지지 않았다 — 걸러졌을 뿐이다.
        final rowsAfter = await (db.select(
          db.trainerScheduleEntries,
        )..where((t) => t.clientId.equals('seed-client-1'))).get();
        expect(rowsAfter, isNotEmpty);
      },
    );

    test('재등록하면 걸러졌던 채팅·일정 노출이 그대로 돌아온다 (#1623)', () async {
      final repo = DriftClientRepository(db);
      final invites = DemoClientInviteRepository(db);
      final chat = DriftChatRepository(db);
      final schedule = DriftScheduleRepository(db);

      // 미읽은 회원 메시지를 하나 만들어 둔다 — 삭제 중 사라지지 않고,
      // 재등록 후 다시 배지에 잡히는지까지 확인한다.
      await db
          .into(db.clientChatMessages)
          .insert(
            ClientChatMessagesCompanion.insert(
              id: 'chat-1623-check',
              clientId: 'seed-client-1',
              sender: 'client',
              body: '다음 세션 언제예요?',
              timeLabel: '09:00',
              createdAt: nowKst(),
            ),
          );

      await repo.removeClient('seed-client-1');
      expect(
        (await chat.watchUnreadCounts().first).containsKey('seed-client-1'),
        isFalse,
      );
      expect(
        (await schedule.watchRange('2000-01-01', '2099-12-31').first).any(
          (s) => s.clientId == 'seed-client-1',
        ),
        isFalse,
      );

      await invites.invite(demoAlreadyLinkedMemberId);

      expect(
        (await chat.watchUnreadCounts().first)['seed-client-1'],
        greaterThan(0),
      );
      expect(
        (await schedule.watchRange('2000-01-01', '2099-12-31').first).any(
          (s) => s.clientId == 'seed-client-1',
        ),
        isTrue,
      );
    });

    test('미등록 회원은 새 회원 등록과 같은 lookup·invite 로 같은 행을 되살린다', () async {
      final repo = DriftClientRepository(db);
      final invites = DemoClientInviteRepository(db);
      await repo.removeClient('seed-client-1');

      // 실 계정 id(demoAlreadyLinkedMemberId)로 찾아야 한다 — 회원 관리
      // 화면의 행 id(seed-client-1)를 그대로 입력하는 것이 아니다.
      final found = await invites.lookup(demoAlreadyLinkedMemberId);
      expect(found.name, '김민수');
      expect(found.canInvite, isTrue); // 미등록이라 다시 연결할 수 있다

      await invites.invite(demoAlreadyLinkedMemberId);

      final clients = await repo.watchClients().first;
      final revived = clients.firstWhere((c) => c.id == 'seed-client-1');
      expect(revived.registered, isTrue);
      expect(revived.name, '김민수'); // 새 프로필이 아니라 같은 행이 되살아났다
      expect(clients.length, 15); // 새 행이 추가되지 않았다
    });

    test('실 계정 id 매핑이 없는 회원도 행 id 자체로 다시 등록할 수 있다', () async {
      final repo = DriftClientRepository(db);
      final invites = DemoClientInviteRepository(db);
      await repo.removeClient('seed-client-3');

      final found = await invites.lookup('seed-client-3');
      expect(found.canInvite, isTrue);

      await invites.invite('seed-client-3');

      final clients = await repo.watchClients().first;
      expect(
        clients.firstWhere((c) => c.id == 'seed-client-3').registered,
        isTrue,
      );
      expect(clients.length, 15);
    });

    // 예약 수는 이제 로스터가 아니라 오늘 스케줄에서 파생된다(#387).
    // 배지 계산은 todayReservationCountProvider 테스트가 덮고, 날짜 필터링은
    // ScheduleRepository.watchToday 테스트(schedule_page_test)가 덮는다.
    test('오늘 스케줄에서 공백을 뺀 수가 예약 수가 된다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWithValue(
            DriftScheduleRepository(db),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(todayScheduleProvider.future);
      expect(container.read(todayReservationCountProvider).value, 4);
    });

    // 배지는 '남은 일감' 을 말한다. 시드의 오늘은 완료 2 · 공백 2 · 예정 2 라
    // 예약 수(4)와 배지 수(2)는 서로 달라야 맞다(#860).
    test('사이드바 배지는 완료한 세션을 세지 않는다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWithValue(
            DriftScheduleRepository(db),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sessions = await container.read(todayScheduleProvider.future);
      expect(sessions.where((s) => s.isDone).length, 2, reason: '시드 전제');

      expect(container.read(todayPendingSessionCountProvider).value, 2);
      expect(container.read(todayReservationCountProvider).value, 4);
    });

    test('스케줄을 못 읽으면 배지도 값 없음으로 남는다', () async {
      // 예약 수와 같은 규약 — 0 을 내보내면 "남은 일정 없음" 이라는 틀린
      // 사실이 되고, 화면은 배지를 감추는 대신 0 을 그린다.
      final container = ProviderContainer(
        overrides: <Override>[
          todayScheduleProvider.overrideWith(
            (ref) => Stream<List<ScheduleSession>>.error(
              StateError('schedule unavailable'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(todayScheduleProvider.future),
        throwsStateError,
      );
      expect(
        container.read(todayPendingSessionCountProvider).valueOrNull,
        isNull,
      );
    });

    test('스케줄을 못 읽으면 0 이 아니라 값 없음으로 남는다', () async {
      // 0 을 내보내면 "오늘 예약 0건" 이라는 틀린 사실이 된다 — 배지를 숨겨야 한다.
      final container = ProviderContainer(
        overrides: <Override>[
          todayScheduleProvider.overrideWith(
            (ref) => Stream<List<ScheduleSession>>.error(
              StateError('schedule unavailable'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(todayScheduleProvider.future),
        throwsStateError,
      );
      expect(container.read(todayReservationCountProvider).valueOrNull, isNull);
    });
  });

  group('ClientsPage', () {
    for (final entry in <(String, AsyncValue<List<TrainerClient>>)>[
      ('loading', const AsyncLoading<List<TrainerClient>>()),
      (
        'error',
        AsyncError<List<TrainerClient>>(
          StateError('roster unavailable'),
          StackTrace.empty,
        ),
      ),
    ]) {
      testWidgets('${entry.$1} 상태에서도 회원 상세 route를 유지한다', (tester) async {
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
          extraOverrides: <Override>[
            prioritizedClientsProvider.overrideWithValue(entry.$2),
          ],
        );

        expect(find.byType(ClientSearchBar), findsOneWidget);
        expect(find.text('회원 관리'), findsOneWidget);
      });
    }

    testWidgets('re-entering the client branch requests a data refresh', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      late _RecordingRefreshClientRepository repository;

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith((ref) {
            repository = _RecordingRefreshClientRepository(
              ref.watch(appDatabaseProvider),
            );
            return repository;
          }),
        ],
      );
      expect(find.text('오세라'), findsOneWidget);

      await goTo(tester, AppRoutes.dashboard);
      await goTo(tester, AppRoutes.clients);

      expect(repository.allRefreshes, 1);
      expect(find.text('오세라'), findsOneWidget);
    });

    testWidgets('the detail refresh action targets the selected client', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      late _RecordingRefreshClientRepository repository;

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith((ref) {
            repository = _RecordingRefreshClientRepository(
              ref.watch(appDatabaseProvider),
            );
            return repository;
          }),
        ],
      );
      expect(find.text('오늘 섭취 칼로리'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('client-data-refresh')),
      );
      await settle(tester);

      expect(repository.clientRefreshes, <String>['seed-client-1']);
      expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
    });

    testWidgets('renders the roster with its size and priority order', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      // The roster header states the size. 활성 수는 적지 않는다 — 활성·휴면은
      // 목록에서 없앴다(#2204).
      expect(find.text('회원 관리'), findsWidgets);
      expect(find.text('15명'), findsWidgets);
      expect(find.textContaining('활성'), findsNothing);

      // Priority order: 가장 급한 신호(통증·불편)를 든 오세라가 맨 위고, 신호가
      // 없는 회원(박성호·이지수)은 길고 지연 생성되는 목록의 아래에 선다.
      expect(
        tester
            .widget<ClientCard>(find.byType(ClientCard).first)
            .client
            .name,
        '오세라',
      );
      expect(
        find.byKey(const ValueKey<String>('clients-roster-search')),
        findsNothing,
      );
      expect(find.byType(ClientSearchBar), findsOneWidget);
      // 목록 차례대로 내려간다 — 이지수가 박성호보다 위라, 박성호까지 내린 뒤에는
      // 이지수가 이미 화면 위로 지나가 아래로 찾아서는 닿지 않는다.
      await scrollToClient(tester, find.text('이지수'));
      expect(find.text('이지수'), findsWidgets);
      await scrollToClient(tester, find.text('박성호'));
      expect(find.text('박성호'), findsOneWidget);
    });

    testWidgets('전체 보기 clears the URL and local search filters', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientsFiltered('attention'),
      );

      // 걸러져 있다는 표시는 목록 위 상자가 아니라 정렬 옆 글자다(#2205).
      expect(find.text('전체 보기'), findsNothing);
      final clear = find.byKey(const ValueKey<String>('clients-preset-clear'));
      expect(
        find.descendant(of: clear, matching: find.text('주의 회원')),
        findsOneWidget,
      );
      // 신호가 없는 이지수는 주의 회원이 아니다.
      expect(find.byKey(const ValueKey<String>('client-seed-client-2')), findsNothing);
      // 주의 회원으로 들어오면 막대 아래에 가장 급한 주의 신호 하나가 붙는다.
      expect(
        tester
            .widgetList<AppTag>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>('client-signals-seed-client-8'),
                ),
                matching: find.byType(AppTag),
              ),
            )
            .map((t) => t.label)
            .toList(),
        <String>['통증·불편'],
      );

      await tester.tap(clear);
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.clients);
      expect(clear, findsNothing);
      // 필터가 풀리면 걸린 이유도 사라지고 막대만 남는다.
      expect(find.byType(AppTag), findsNothing);
      await scrollToClient(tester, find.text('이지수'));
      expect(find.text('이지수'), findsOneWidget);
    });

    testWidgets('회원 목록은 메시지 미리보기와 안 읽은 배지를 노출하지 않는다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await scrollToClient(tester, find.text('박성호'));
      final sunghoCard = find.ancestor(
        of: find.text('박성호'),
        matching: find.byType(ClientCard),
      );
      expect(
        find.descendant(of: sunghoCard, matching: find.text('1')),
        findsNothing,
      );
      expect(
        find.descendant(of: sunghoCard, matching: find.text('이번 주 운동 못했어요...')),
        findsNothing,
      );
      expect(
        find.descendant(of: sunghoCard, matching: find.textContaining('세')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a client card opens the detail screen', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(find.text('오세라'));
      await settle(tester);

      // Detail opened — both evidence tabs and the quick actions are
      // unique to it. 신체·목표 now lives in the merged dialog, not a
      // button of its own (#1024), and 메모 is icon-only.
      expect(find.text('식단'), findsOneWidget);
      expect(find.text('운동'), findsOneWidget);
      expect(find.text('리포트'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('client-detail-open-memo')),
        findsOneWidget,
      );
    });

    /// 회원이 자기 앱 MY 탭에 띄운 6자리를 트레이너가 입력한다. (#1634)
    Future<void> enterSyncCode(WidgetTester tester, String code) async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('client-connect-code')),
        code,
      );
      await settle(tester);
    }

    testWidgets('신규 회원 등록 — 6자리 동기화 코드로 회원과 연결한다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(find.text('신규 회원 등록'));
      await settle(tester);

      // 이수아가 자기 앱에 띄운 코드다. 여섯 자리가 다 차면 바로 연결된다 —
      // 코드를 불러 준 것이 회원 본인이라 한 번 더 수락받지 않는다.
      await enterSyncCode(tester, '308214');

      // 결과 카드는 회원이 이미 등록해 둔 값을 보여준다 — 트레이너가 여기서
      // 성별·나이를 입력하는 것이 아니다.
      expect(find.text('이수아'), findsWidgets);
      expect(find.textContaining('여성'), findsWidgets);

      // 바로 잇지 않는다 — 이름·성별·나이를 확인하고 누른다.
      expect(find.text('이 회원이 맞나요?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('client-connect-register')),
      );
      await settle(tester);

      // 연결 성공 후 회원 리스트가 (재시작 없이) 즉시 반영된다 — 실제
      // repository/drift 스트림 결과이지, 화면에 끼워 넣은 값이 아니다.
      final card = find.byKey(
        const ValueKey<String>('client-user-8f2a41c9d6e3'),
      );
      await scrollToClient(tester, card);
      expect(
        find.descendant(of: card, matching: find.text('이수아')),
        findsOneWidget,
      );
      // 연결된 프로필은 데모 명부가 가진 실제 성별·나이를 그대로 쓴다 —
      // 회원 id 해시로 지어낸 값이 아니다(#960 과 같은 폴백을 타지 않는다).
      expect(
        find.descendant(of: card, matching: find.textContaining('여성')),
        findsOneWidget,
      );
    });

    testWidgets('담당 종료한 회원도 동기화 코드로 같은 행을 되살린다', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );
      // 회원 관리에서 담당을 종료한 것과 같다 — 명단에서 사라지고, 다시
      // 잡으려면 여기(회원 탭)에서 회원의 코드를 받아 새로 연결해야 한다.
      await container
          .read(clientRepositoryProvider)
          .removeClient('seed-client-1');
      await settle(tester);
      expect(find.text('김민수'), findsNothing);

      await tester.tap(find.text('신규 회원 등록'));
      await settle(tester);

      await enterSyncCode(tester, demoAlreadyLinkedPairingCode);

      expect(find.text('김민수'), findsWidgets);
      expect(find.text('이미 담당하고 있는 회원이에요.'), findsNothing);

      // 바로 잇지 않는다 — 이름·성별·나이를 확인하고 누른다.
      expect(find.text('이 회원이 맞나요?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('client-connect-register')),
      );
      await settle(tester);

      // 새 행이 아니라 같은 회원(seed-client-1)이 되살아난다 — 지난
      // 스케줄·기록이 새 카드로 갈라지지 않는다.
      final card = find.byKey(const ValueKey<String>('client-seed-client-1'));
      await scrollToClient(tester, card);
      expect(
        find.descendant(of: card, matching: find.text('김민수')),
        findsOneWidget,
      );
      final roster = await container
          .read(clientRepositoryProvider)
          .watchClients()
          .first;
      expect(roster.length, 15);
    });

    testWidgets('이미 담당 중인 회원의 코드는 중복 안내가 뜬다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(find.text('신규 회원 등록'));
      await settle(tester);

      // 김민수(seed-client-1)는 이미 담당 중이다.
      await enterSyncCode(tester, demoAlreadyLinkedPairingCode);

      expect(find.text('이미 담당하고 있는 회원이에요.'), findsOneWidget);
      // 이유만 보여 주고 끝낸다 — 연결된 회원 카드가 뜨지 않는다.
      expect(
        find.byKey(const ValueKey<String>('client-connect-result')),
        findsNothing,
      );
    });

    testWidgets('모르는 코드는 왜인지 갈라 말하지 않는다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(find.text('신규 회원 등록'));
      await settle(tester);

      await enterSyncCode(tester, '000000');

      // 틀렸는지·만료됐는지·이미 쓰였는지를 갈라 주면 어떤 코드가 존재하기는
      // 했는지를 알려 주는 셈이다.
      expect(find.textContaining('새 코드를 받아'), findsOneWidget);
    });

    testWidgets('the detail header chip toggles 활성/휴면', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      final minsu = find.byKey(const ValueKey<String>('client-seed-client-1'));
      await scrollToClient(tester, minsu);
      await tester.tap(minsu.last);
      await settle(tester);
      expect(find.text('활성'), findsOneWidget);

      await tester.tap(find.text('활성'));
      await settle(tester);
      expect(find.text('휴면'), findsOneWidget);

      await tester.tap(find.text('휴면'));
      await settle(tester);
      expect(find.text('활성'), findsOneWidget);
    });

    testWidgets('a source that cannot add clients still allows 활성/휴면', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
        extraOverrides: [
          clientRepositoryProvider.overrideWith(
            (ref) => _ReadOnlyClientRepository(ref.watch(appDatabaseProvider)),
          ),
          clientInviteRepositoryProvider.overrideWithValue(
            const _NoInviteClientInviteRepository(),
          ),
        ],
      );

      final clientCard = find.byKey(
        const ValueKey<String>('client-seed-client-3'),
      );
      await scrollToClient(tester, clientCard);
      expect(find.text('신규 회원 등록'), findsNothing);

      await tester.tap(clientCard.last);
      await settle(tester);

      // 신규 회원 등록과 활성/휴면은 다른 권한이다 (#707) — 백엔드 로스터에는
      // 회원을 더하는 경로가 없지만 관리 상태 전환은 있다. 한 플래그로 묶여
      // 있던 동안에는 이 배지가 실 API 에서 계속 읽기 전용이었다.
      final statusInkWell = find.byKey(
        const ValueKey<String>('client-status-toggle'),
      );
      expect(statusInkWell, findsOneWidget);
      expect(tester.widget<InkWell>(statusInkWell).onTap, isNotNull);
    });

    /// 필터 패널을 열어 [filter] 칩을 누르고 닫는다.
    Future<void> toggleFilter(
      WidgetTester tester,
      RosterManagementFilter filter,
    ) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('management-filter-${filter.name}')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
    }

    // #1026: 툴바 관리 필터가 단일 선택 팝업에서 복수 선택 chip 으로 바뀌었다.
    // #2204: 칩은 관리 필요 + PT 관리 신호 여덟 가지다.
    testWidgets('통증·불편 필터를 고르면 그 신호를 든 회원만 남는다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await toggleFilter(tester, RosterManagementFilter.discomfort);
      // 오세라는 대화에서 허리가 아프다고 했다. 이지수는 신호가 없다.
      expect(find.byKey(const ValueKey<String>('client-seed-client-8')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('client-seed-client-2')), findsNothing);
      expect(find.byType(ClientCard), findsOneWidget);

      // 필터로 좁힌 동안에는 막대 아래에 **걸린 이유만** 보인다(#2258) —
      // 오세라의 다른 신호(운동 목표·칼로리)와 답장 대기는 붙지 않는다.
      final reasons = find.byKey(
        const ValueKey<String>('client-signals-seed-client-8'),
      );
      expect(
        tester
            .widgetList<AppTag>(
              find.descendant(of: reasons, matching: find.byType(AppTag)),
            )
            .map((t) => t.label)
            .toList(),
        <String>['통증·불편'],
      );
      expect(
        find.byKey(
          const ValueKey<String>('client-weekly-adherence-seed-client-8'),
        ),
        findsOneWidget,
      );

      // 같은 chip 을 다시 누르면 선택이 풀린다 — 다중 선택의 개별 제거.
      await toggleFilter(tester, RosterManagementFilter.discomfort);
      expect(find.text('필터 1'), findsNothing);
      await scrollToClient(tester, find.text('이지수'));
      expect(find.text('이지수'), findsOneWidget);
    });

    testWidgets('칼로리 목표 이탈 필터는 배지와 같은 신호를 쓴다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await toggleFilter(tester, RosterManagementFilter.calorieOff);
      final seoyeon = find.byKey(const ValueKey<String>('client-seed-client-6'));
      await scrollToClient(tester, seoyeon);
      expect(seoyeon, findsOneWidget);
      expect(find.byKey(const ValueKey<String>('client-seed-client-2')), findsNothing);
      // 나트륨·당류·이행률·활성·휴면 칩은 없다.
      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      for (final gone in <String>[
        'sodiumOver',
        'sugarOver',
        'lowCompletion',
        'active',
        'dormant',
      ]) {
        expect(
          find.byKey(ValueKey<String>('management-filter-$gone')),
          findsNothing,
        );
      }
    });

    testWidgets('답장 대기 배지 필터는 실제 안 읽은 메시지 수를 쓴다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
        seedClock: DateTime(2026, 8, 16),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('management-filter-unanswered')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();

      final unansweredCard = find.byKey(
        const ValueKey<String>('client-seed-client-8'),
      );
      await scrollToClient(tester, unansweredCard);
      expect(unansweredCard, findsOneWidget); // 오세라: 회원이 마지막으로 보냄
      expect(
        find.byKey(const ValueKey<String>('client-seed-client-3')),
        findsNothing,
      ); // 박성호: 트레이너가 답장함
    });

    testWidgets('모든 필터는 서로 해제하지 않고 독립적으로 선택된다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      for (final filter in RosterManagementFilter.values) {
        await tester.tap(
          find.byKey(ValueKey<String>('management-filter-${filter.name}')),
        );
        await settle(tester);
      }
      expect(find.text('필터 9'), findsOneWidget);

      // 한 조건만 다시 누르면 나머지 선택은 그대로 유지된다.
      await tester.tap(
        find.byKey(const ValueKey<String>('management-filter-attention')),
      );
      await settle(tester);
      expect(find.text('필터 8'), findsOneWidget);
    });

    testWidgets('복수 필터는 OR 로 합쳐지고 전체 초기화로 한 번에 풀린다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      // 기록 끊김 + 노쇼·취소 반복을 함께 고르면 둘 중 하나라도 든 회원이 남는다
      // — 두 신호를 다 든 회원은 없어서, AND 였다면 아무도 안 남았을 것이다.
      await tester.tap(
        find.byKey(const ValueKey<String>('management-filter-recordGap')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('management-filter-noShow')),
      );
      await settle(tester);

      expect(find.text('필터 2'), findsOneWidget);
      expect(find.text('전체 초기화'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('client-seed-client-7')),
        findsOneWidget,
      ); // 임도현: 기록 끊김
      final junhyeokCard = find.byKey(
        const ValueKey<String>('client-seed-client-9'),
      );
      await scrollToClient(tester, junhyeokCard);
      expect(junhyeokCard, findsOneWidget); // 배준혁: 노쇼·취소 반복
      expect(
        find.byKey(const ValueKey<String>('client-seed-client-2')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('clients-filter-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 초기화'));
      await settle(tester);

      // 초기화 버튼은 선택이 없을 때는 그려지지 않는다.
      expect(find.text('전체 초기화'), findsNothing);
    });
  });
}
