/// 트레이너 대화를 쪽 단위로 받고 합치는 규칙. (#2640)
///
/// 옛 쪽을 받아 둔 뒤 새 메시지가 오면, 폴링이 주는 최신 쪽이 앞으로 밀리면서
/// 두 쪽 경계의 메시지가 어느 쪽에도 없게 됐다. 여기서 보는 것은 그 경계가
/// 비지 않게 하는 규칙들이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

import '../../helpers/fake_member_coach_repository.dart';

List<String> _ids(Iterable<CoachMessage> messages) => <String>[
  for (final CoachMessage m in messages) m.id,
];

/// [from] 부터 [to] 전까지의 대화 한 줄씩.
List<CoachMessage> _lines(int from, int to) => <CoachMessage>[
  for (int i = from; i < to; i++) chatLine(i),
];

void main() {
  group('순서', () {
    test('시각이 먼저, 같은 시각이면 id 로 가른다', () {
      final DateTime at = DateTime(2026, 9, 1, 9);
      final CoachMessage b = chatLine(0, id: 'b', base: at);
      final CoachMessage a = chatLine(0, id: 'a', base: at);
      final CoachMessage later = chatLine(1, id: '0', base: at);

      final List<CoachMessage> sorted = <CoachMessage>[later, b, a]
        ..sort(compareCoachMessages);

      expect(_ids(sorted), <String>['a', 'b', '0']);
    });
  });

  group('합치기', () {
    test('겹치는 메시지는 하나만 남는다', () {
      final List<CoachMessage> merged = mergeCoachThread(
        _lines(0, 5),
        _lines(3, 8),
      );

      expect(_ids(merged), _ids(_lines(0, 8)));
    });

    test('받은 순서가 뒤바뀌어도 오래된 → 최신으로 선다', () {
      final List<CoachMessage> merged = mergeCoachThread(
        _lines(5, 10),
        _lines(0, 5).reversed,
      );

      expect(_ids(merged), _ids(_lines(0, 10)));
    });

    test('같은 id 는 나중에 받은 쪽을 쓴다', () {
      final CoachMessage before = chatLine(1);
      final CoachMessage after = CoachMessage(
        id: before.id,
        sender: before.sender,
        body: '고친 글',
        timeLabel: before.timeLabel,
        createdAt: before.createdAt,
      );

      final List<CoachMessage> merged = mergeCoachThread(
        <CoachMessage>[before],
        <CoachMessage>[after],
      );

      expect(merged.single.body, '고친 글');
    });

    test('빈 쪽과 합쳐도 그대로다', () {
      expect(
        _ids(mergeCoachThread(const <CoachMessage>[], _lines(0, 3))),
        _ids(_lines(0, 3)),
      );
      expect(
        _ids(mergeCoachThread(_lines(0, 3), const <CoachMessage>[])),
        _ids(_lines(0, 3)),
      );
    });

    test('옛 쪽을 받은 뒤 최신 쪽이 밀려도 경계 메시지가 남는다', () {
      // 대화 m[0..119]. 폴링은 m[70..119], 옛 쪽은 m[20..69] 를 받았다.
      final List<CoachMessage> older = _lines(20, 70);
      final List<CoachMessage> firstLatest = _lines(70, 120);
      // 받아 둔 것 = 옛 쪽 + 그때의 최신 쪽.
      final List<CoachMessage> kept = mergeCoachThread(older, firstLatest);
      // 새 메시지 하나 — 최신 쪽이 m[71..120] 으로 밀린다.
      final List<CoachMessage> nextLatest = _lines(71, 121);

      final List<CoachMessage> shown = mergeCoachThread(kept, nextLatest);

      expect(_ids(shown), _ids(_lines(20, 121)));
      // 예전 방식(옛 쪽 + 최신 쪽을 단순히 이어 붙이기)에서는 m[70] 이 빠진다.
      final List<String> naive = _ids(<CoachMessage>[...older, ...nextLatest]);
      expect(naive, isNot(contains(chatLine(70).id)));
      expect(_ids(shown), contains(chatLine(70).id));
    });
  });

  group('한 쪽 자르기', () {
    test('커서가 없으면 최신 한 쪽이다', () {
      final List<CoachMessage> page = pageCoachChat(_lines(0, 120));

      expect(page, hasLength(chatPageSize));
      expect(_ids(page), _ids(_lines(70, 120)));
    });

    test('커서가 있으면 그보다 앞선 한 쪽이다', () {
      final List<CoachMessage> page = pageCoachChat(
        _lines(0, 120),
        before: chatLine(70),
      );

      expect(_ids(page), _ids(_lines(20, 70)));
    });

    test('남은 것이 한 쪽보다 적으면 다 준다', () {
      final List<CoachMessage> page = pageCoachChat(
        _lines(0, 120),
        before: chatLine(20),
      );

      expect(_ids(page), _ids(_lines(0, 20)));
      expect(page.length, lessThan(chatPageSize));
    });

    test('커서 메시지 자신은 넣지 않는다', () {
      final List<CoachMessage> page = pageCoachChat(
        _lines(0, 10),
        before: chatLine(5),
      );

      expect(_ids(page), isNot(contains(chatLine(5).id)));
    });

    test('같은 시각의 메시지는 id 로 경계를 가른다', () {
      final DateTime at = DateTime(2026, 9, 1, 9);
      final List<CoachMessage> all = <CoachMessage>[
        chatLine(0, id: 'a', base: at),
        chatLine(0, id: 'b', base: at),
        chatLine(0, id: 'c', base: at),
      ];

      final List<CoachMessage> page = pageCoachChat(all, before: all[1]);

      expect(_ids(page), <String>['a']);
    });
  });

  group('데모 저장소', () {
    test('서버처럼 최신 한 쪽만 주고, 커서로 그 앞을 준다', () async {
      // 데모 대화에 메시지를 한 쪽이 넘게 쌓는다. 시각이 겹치지 않게 1분씩 민다.
      DateTime t = DateTime(2026, 9, 20, 9);
      debugNowKstOverride = () => t = t.add(const Duration(minutes: 1));
      addTearDown(() => debugNowKstOverride = null);
      final MemberCoachRepository repository = MockMemberCoachRepository();
      for (int i = 0; i < chatPageSize + 10; i++) {
        await repository.sendMessage('보낸 말 $i');
      }

      final List<CoachMessage> latest = await repository.fetchChat();
      expect(latest, hasLength(chatPageSize));
      expect(latest.last.body, '보낸 말 ${chatPageSize + 9}');

      final List<CoachMessage> older = await repository.fetchChat(
        before: latest.first,
      );
      expect(older, isNotEmpty);
      // 앞 쪽은 전부 커서보다 앞선다 — 겹치지 않는다.
      for (final CoachMessage m in older) {
        expect(compareCoachMessages(m, latest.first), lessThan(0));
      }
      expect(_ids(older).toSet().intersection(_ids(latest).toSet()), isEmpty);
    });
  });
}
