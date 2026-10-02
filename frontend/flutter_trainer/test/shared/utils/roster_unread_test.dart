import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/roster_unread.dart';

import '../../helpers/client_factory.dart';

/// 안읽음 합계는 명단 회원만 센다 — 해제 회원 몫이 배지에 고착되지 않게. (#2868)
void main() {
  group('rosterUnreadOf', () {
    test('명단 밖 id 의 안읽음은 세지 않는다', () {
      final totals = rosterUnreadOf(
        rosterIds: const <String>['a', 'b'],
        unread: const <String, int>{'a': 2, 'released': 5},
      );

      expect(totals, const RosterUnread(messages: 2, conversations: 1));
    });

    test('명단 회원이 여럿이면 메시지 수와 대화 수를 따로 센다', () {
      final totals = rosterUnreadOf(
        rosterIds: const <String>['a', 'b', 'c'],
        unread: const <String, int>{'a': 2, 'b': 3},
      );

      expect(totals.messages, 5);
      expect(totals.conversations, 2);
    });

    test('0 이하 값은 대화 수에 들어가지 않는다', () {
      final totals = rosterUnreadOf(
        rosterIds: const <String>['a', 'b'],
        unread: const <String, int>{'a': 0, 'b': -1},
      );

      expect(totals, RosterUnread.none);
    });

    test('명단에 같은 id 가 두 번 있어도 한 번만 센다', () {
      final totals = rosterUnreadOf(
        rosterIds: const <String>['a', 'a'],
        unread: const <String, int>{'a': 4},
      );

      expect(totals, const RosterUnread(messages: 4, conversations: 1));
    });

    test('명단이 비면 안읽음 맵이 있어도 0', () {
      final totals = rosterUnreadOf(
        rosterIds: const <String>[],
        unread: const <String, int>{'released': 9},
      );

      expect(totals, RosterUnread.none);
    });
  });

  group('rosterUnreadProvider', () {
    ProviderContainer containerWith({
      required List<TrainerClient> roster,
      required Map<String, int> unread,
    }) {
      final container = ProviderContainer(
        overrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(roster),
          ),
          unreadCountsProvider.overrideWith(
            (ref) => Stream<Map<String, int>>.value(unread),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('명단과 안읽음이 오기 전에는 null', () {
      final container = containerWith(
        roster: <TrainerClient>[makeClient(id: 'a')],
        unread: const <String, int>{'a': 1},
      );

      expect(container.read(rosterUnreadProvider), isNull);
    });

    test('둘 다 오면 명단 회원 몫만 더한다', () async {
      final container = containerWith(
        roster: <TrainerClient>[
          makeClient(id: 'a'),
          makeClient(id: 'b'),
        ],
        unread: const <String, int>{'a': 1, 'b': 2, 'released': 7},
      );
      final sub = container.listen(rosterUnreadProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(clientsProvider.future);
      await container.read(unreadCountsProvider.future);

      expect(
        container.read(rosterUnreadProvider),
        const RosterUnread(messages: 3, conversations: 2),
      );
    });
  });

  group('buildDashboardSummary', () {
    test('명단 밖 id 가 섞인 안읽음 맵에서 사이드바 도우미와 같은 값을 낸다', () {
      final roster = <TrainerClient>[
        makeClient(id: 'a', name: '가'),
        makeClient(id: 'b', name: '나'),
      ];
      const unread = <String, int>{'a': 2, 'released': 5, 'other': 1};

      final summary = buildDashboardSummary(clients: roster, unread: unread);
      final totals = rosterUnreadOf(
        rosterIds: roster.map((client) => client.id),
        unread: unread,
      );

      expect(summary.unreadTotal, 2);
      expect(summary.unreadClients, 1);
      expect(summary.unreadTotal, totals.messages);
      expect(summary.unreadClients, totals.conversations);
    });
  });
}
