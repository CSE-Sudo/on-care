import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

/// The dashboard's aggregation rules. These decide what the trainer is
/// told to do first, so they're worth pinning down without a widget.
const ClientSignal _gap = ClientSignal(ClientSignalKind.recordGap, days: 4);

void main() {
  group('buildDashboardSummary', () {
    test('counts active clients separately from the roster size', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(id: 'a'),
          makeClient(id: 'b'),
          makeClient(id: 'c', active: false),
        ],
        unread: const <String, int>{},
      );

      expect(summary.totalClients, 3);
      expect(summary.activeClients, 2);
    });

    test('sums unread messages and the clients waiting on them', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(id: 'a'),
          makeClient(id: 'b'),
          makeClient(id: 'c'),
        ],
        unread: const <String, int>{'a': 2, 'b': 3},
      );

      // 5 messages, but only 2 people are waiting — the KPI says
      // "3건" while the hint says "회원 2명".
      expect(summary.unreadTotal, 5);
      expect(summary.unreadClients, 2);
    });

    test('주의 회원 수는 PT 관리 신호로 센다 — 회원 목록과 같은 규칙 (#2204)', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          // 나트륨이 넘어도 신호가 없으면 주의 회원이 아니다.
          makeClient(id: 'sodium', sodiumMg: 2500),
          makeClient(
            id: 'gap',
            signals: const <ClientSignal>[
              ClientSignal(ClientSignalKind.recordGap, days: 4),
            ],
          ),
          // 답장 대기는 주의가 아니다.
          makeClient(id: 'waiting'),
        ],
        unread: const <String, int>{'waiting': 1},
      );

      expect(summary.healthAttentionCount, 1);
    });

    test('an unanswered client stays in the list but is not counted 주의', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(id: 'gap', signals: const <ClientSignal>[_gap]),
          makeClient(id: 'waiting'),
        ],
        unread: const <String, int>{'waiting': 1},
      );

      // The trainer still owes 'waiting' a reply, so the row stays…
      expect(summary.attention.map((a) => a.client.id), <String>[
        'gap',
        'waiting',
      ]);
      // …but 주의 means the member's own state, and 'waiting' has none.
      expect(summary.healthAttentionCount, 1);
      expect(summary.attention.last.needsAttention, isFalse);
    });

    test('a PT signal outranks an unanswered one on the same client', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(id: 'both', signals: const <ClientSignal>[_gap]),
        ],
        unread: const <String, int>{'both': 3},
      );

      // 답장 대기가 앞에 서면, 답장 필요 카드가 이미 알린 메시지 뒤에 회원의
      // 상태가 숨는다.
      expect(summary.attention.single.primary.kind, ClientSignalKind.recordGap);
      expect(
        summary.attention.single.signals.map((s) => s.kind),
        <ClientSignalKind>[ClientSignalKind.recordGap, ClientSignalKind.unanswered],
      );
    });

    test('가장 급한 신호를 든 회원이 앞에 온다 — 회원 목록과 같은 순서 (#2244)', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(
            id: 'protein',
            signals: const <ClientSignal>[
              ClientSignal(ClientSignalKind.proteinLow, percent: 60),
            ],
          ),
          makeClient(
            id: 'pain',
            signals: const <ClientSignal>[
              ClientSignal(ClientSignalKind.discomfort),
            ],
          ),
          makeClient(id: 'gap', signals: const <ClientSignal>[_gap]),
        ],
        unread: const <String, int>{},
      );

      expect(summary.attention.map((a) => a.client.id), <String>[
        'pain',
        'gap',
        'protein',
      ]);
    });

    test('같은 신호면 들어온 순서를 지킨다', () {
      // `List.sort` 는 안정 정렬이 아니다 — 동점의 순서가 실행마다 달라지면
      // 대시보드가 새로고침마다 다르게 보인다.
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(id: 'first', signals: const <ClientSignal>[_gap]),
          makeClient(id: 'second', signals: const <ClientSignal>[_gap]),
        ],
        unread: const <String, int>{},
      );

      expect(summary.attention.map((a) => a.client.id), <String>[
        'first',
        'second',
      ]);
    });

    test('나트륨·당류·이행률은 더 이상 주의가 아니다 (#2244)', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(
            id: 'old-rules',
            sodiumMg: 3000,
            sugarG: 90,
            weekCompletion: List<int>.filled(7, 20),
          ),
        ],
        unread: const <String, int>{},
      );

      expect(summary.attention, isEmpty);
      expect(summary.healthAttentionCount, 0);
    });

    test('a healthy roster raises nothing', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[makeClient(id: 'a')],
        unread: const <String, int>{},
      );

      expect(summary.attention, isEmpty);
    });

    test('weekly completion is the mean across clients, per weekday', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(
            id: 'a',
            weekCompletion: const <int>[100, 0, 50, 0, 0, 0, 0],
          ),
          makeClient(
            id: 'b',
            weekCompletion: const <int>[0, 100, 50, 0, 0, 0, 0],
          ),
        ],
        unread: const <String, int>{},
      );

      expect(summary.weeklyCompletion, <int>[50, 50, 50, 0, 0, 0, 0]);
    });

    test('a client with no week data is skipped, not averaged as zero', () {
      final summary = buildDashboardSummary(
        clients: <TrainerClient>[
          makeClient(
            id: 'a',
            weekCompletion: const <int>[60, 60, 60, 60, 60, 60, 60],
          ),
          // Newly registered: no week array at all.
          makeClient(id: 'b', weekCompletion: const <int>[]),
        ],
        unread: const <String, int>{},
      );

      expect(summary.weeklyCompletion.first, 60);
    });
  });

  group('isLowCompletion', () {
    test('flags a recorded week averaging under the threshold', () {
      expect(
        isLowCompletion(
          makeClient(weekCompletion: const <int>[40, 30, 50, 0, 0, 0, 0]),
        ),
        isTrue,
      );
    });

    test('does NOT flag a client who has logged nothing yet', () {
      // A client registered this morning must not read as failing —
      // that trains the trainer to ignore the badge.
      expect(
        isLowCompletion(
          makeClient(weekCompletion: const <int>[0, 0, 0, 0, 0, 0, 0]),
        ),
        isFalse,
      );
      expect(
        isLowCompletion(makeClient(weekCompletion: const <int>[])),
        isFalse,
      );
    });

    test('averages only the days that were recorded', () {
      // 90% on the one day they trained is not a 13% week.
      expect(
        isLowCompletion(
          makeClient(weekCompletion: const <int>[90, 0, 0, 0, 0, 0, 0]),
        ),
        isFalse,
      );
    });
  });
}
