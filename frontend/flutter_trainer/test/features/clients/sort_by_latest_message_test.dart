import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 메시지 탭 차례(#3011). 데모는 채팅 표의 시각([lastChatAt])을, 실서버는
/// 로스터의 `last_message_at`([TrainerClient.lastMessageAt])을 준다.
TrainerClient _client(String id, {DateTime? lastMessageAt}) => TrainerClient(
  id: id,
  name: id,
  avatar: id.substring(0, 1),
  goal: '',
  lastMessage: '',
  lastTime: '',
  lastMessageAt: lastMessageAt,
  active: true,
  calories: 0,
  sodiumMg: 0,
  sugarG: 0,
  lastRoutine: '',
  weekCompletion: const <int>[],
  sodiumWeek: const <int>[],
);

List<String> _ids(List<TrainerClient> clients) => <String>[
  for (final TrainerClient c in clients) c.id,
];

void main() {
  final DateTime morning = DateTime.utc(2026, 10, 3);
  final DateTime noon = DateTime.utc(2026, 10, 3, 3);
  final DateTime evening = DateTime.utc(2026, 10, 3, 9);

  group('sortByLatestMessage', () {
    test('lastChatAt 이 비어도 lastMessageAt 으로 최신순이 된다', () {
      final List<TrainerClient> sorted = sortByLatestMessage(<TrainerClient>[
        _client('a', lastMessageAt: morning),
        _client('b', lastMessageAt: evening),
        _client('c', lastMessageAt: noon),
      ]);

      expect(_ids(sorted), <String>['b', 'c', 'a']);
    });

    test('lastChatAt 이 있으면 그 값이 로스터 값보다 우선한다', () {
      // 데모의 채팅 표가 더 새로운 사실이다 — 로스터 값은 폴백일 뿐이다.
      final List<TrainerClient> sorted = sortByLatestMessage(
        <TrainerClient>[
          _client('a', lastMessageAt: evening),
          _client('b', lastMessageAt: morning),
        ],
        lastChatAt: <String, DateTime>{
          'b': evening.add(const Duration(hours: 1)),
        },
      );

      expect(_ids(sorted), <String>['b', 'a']);
    });

    test('두 신호가 섞여 있어도 한 기준으로 비교한다', () {
      final List<TrainerClient> sorted = sortByLatestMessage(
        <TrainerClient>[
          _client('roster-noon', lastMessageAt: noon),
          _client('chat-evening'),
          _client('roster-morning', lastMessageAt: morning),
        ],
        lastChatAt: <String, DateTime>{'chat-evening': evening},
      );

      expect(_ids(sorted), <String>[
        'chat-evening',
        'roster-noon',
        'roster-morning',
      ]);
    });

    test('대화가 없는 회원은 뒤로 간다', () {
      final List<TrainerClient> sorted = sortByLatestMessage(<TrainerClient>[
        _client('none'),
        _client('talked', lastMessageAt: morning),
      ]);

      expect(_ids(sorted), <String>['talked', 'none']);
    });

    test('같은 시각과 신호 없음은 들어온 차례를 지킨다', () {
      final List<TrainerClient> sorted = sortByLatestMessage(<TrainerClient>[
        _client('x1'),
        _client('same1', lastMessageAt: noon),
        _client('x2'),
        _client('same2', lastMessageAt: noon),
      ]);

      expect(_ids(sorted), <String>['same1', 'same2', 'x1', 'x2']);
    });

    test('빈 목록은 빈 목록이다', () {
      expect(sortByLatestMessage(const <TrainerClient>[]), isEmpty);
    });
  });

  group('prioritizeClients 와 같은 폴백', () {
    test('주의 신호가 같으면 둘 다 lastMessageAt 최신순으로 동점을 푼다', () {
      final List<TrainerClient> roster = <TrainerClient>[
        _client('a', lastMessageAt: morning),
        _client('b', lastMessageAt: evening),
      ];

      expect(_ids(prioritizeClients(roster)), <String>['b', 'a']);
      expect(_ids(sortByLatestMessage(roster)), <String>['b', 'a']);
    });
  });
}
