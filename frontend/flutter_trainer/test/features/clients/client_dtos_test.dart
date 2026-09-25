import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

TrainerClient _client(
  String id, {
  required int sodiumMg,
  double sugarG = 0,
  bool flagged = false,
}) => TrainerClient(
      id: id,
      name: id,
      avatar: id.substring(0, 1),
      goal: '',
      lastMessage: '',
      lastTime: '',
      active: true,
      calories: 0,
      sodiumMg: sodiumMg,
      sugarG: sugarG,
      lastRoutine: '',
      weekCompletion: const <int>[],
      sodiumWeek: const <int>[],
      // 주의 회원 여부는 PT 관리 신호가 정한다(#2204) — 나트륨이 아니다.
      signals: flagged
          ? const <ClientSignal>[ClientSignal(ClientSignalKind.recordGap, days: 3)]
          : const <ClientSignal>[],
    );

void main() {
  group('trainerClientFromJson', () {
    test('maps a roster element (snake_case) into TrainerClient', () {
      final c = trainerClientFromJson(<String, Object?>{
        'id': 'm1',
        'name': '김민수',
        'avatar': '김',
        'gender': 'male',
        'age': 36,
        'goal': '혈압 관리',
        'last_message': '점심 등록했어요',
        'last_time': '방금',
        'last_message_at': '2026-08-23T09:30:00Z',
        'active': true,
        'calories': 1800,
        'sodium_mg': 2100,
        'sugar_g': 17.8,
        'carbs_g': 150.5,
        'protein_g': 90,
        'fat_g': 48.25,
        'last_routine': '오늘',
        'week_completion': <Object?>[100, 80, 0, 60, 90, 0, 0],
        'sodium_week': <Object?>[1900, 2200, 2100],
      });

      expect(c.id, 'm1');
      expect(c.name, '김민수');
      expect(c.rosterGender, 'male');
      expect(c.rosterAge, 36);
      expect(c.sodiumMg, 2100);
      expect(c.sugarG, 17.8);
      expect(c.carbsG, 150.5);
      expect(c.proteinG, 90);
      expect(c.fatG, 48.25);
      expect(c.sodiumOverBudget, isTrue); // 2100 > 2000 target
      expect(c.weekCompletion, <int>[100, 80, 0, 60, 90, 0, 0]);
      expect(c.sodiumWeek, <int>[1900, 2200, 2100]);
      expect(c.lastMessageAt, DateTime.utc(2026, 8, 23, 9, 30));
    });

    test('maps the PT 관리 신호 and skips kinds this app does not know', () {
      final c = trainerClientFromJson(<String, Object?>{
        'id': 'u1',
        'signals': <Object?>[
          <String, Object?>{'kind': 'calorie_off', 'percent': 22, 'direction': 'under'},
          <String, Object?>{'kind': 'future_signal'},
          <String, Object?>{'kind': 'record_gap', 'days': 4.0},
        ],
      });
      expect(c.signals.map((s) => s.kind).toList(), <ClientSignalKind>[
        ClientSignalKind.calorieOff,
        ClientSignalKind.recordGap,
      ]);
      expect(c.signals.first.percent, 22);
      expect(c.signals.first.over, isFalse);
      expect(c.signals.last.days, 4);
      expect(needsAttention(c), isTrue);
      // 옛 서버처럼 필드가 없으면 신호가 없다.
      expect(trainerClientFromJson(<String, Object?>{'id': 'u2'}).signals, isEmpty);
    });

    test('normalizes an integer sugar value to double', () {
      final c = trainerClientFromJson(<String, Object?>{'sugar_g': 17});

      expect(c.sugarG, 17.0);
    });

    test('tolerates double-encoded numbers and missing lists (web JSON)', () {
      final c = trainerClientFromJson(<String, Object?>{
        'id': 'm2',
        'name': '이지수',
        'calories': 1500.0, // web can decode ints as double
        'sodium_mg': 1800.0,
        'week_completion': <Object?>[100.0, 50.0],
        // sodium_week omitted
      });

      expect(c.calories, 1500);
      expect(c.sodiumMg, 1800);
      expect(c.weekCompletion, <int>[100, 50]);
      expect(c.sodiumWeek, isEmpty);
      expect(c.active, isFalse); // absent → false
      expect(c.rosterAge, inInclusiveRange(20, 39));
    });
  });

  group('clientDietEntryFromJson / routineHistoryEntryFromJson', () {
    test('maps a diet entry', () {
      final d = clientDietEntryFromJson(<String, Object?>{
        'id': 'diet-abc123',
        'meal': '점심',
        'items': '김치찌개, 공기밥',
        'calories': 720,
        'sodium_mg': 1400,
        'carbs_g': 40,
        'protein_g': 25.5,
        'fat_g': 15,
      });
      // 같은 끼니 라벨이 하루에 두 번 저장될 수 있어(#1285 리뷰), 목록 위젯
      // 키로는 meal 라벨이 아니라 이 id 를 쓴다.
      expect(d.id, 'diet-abc123');
      expect(d.meal, '점심');
      expect(d.items, '김치찌개, 공기밥');
      expect(d.sodiumMg, 1400);
      expect(d.carbsG, 40);
      expect(d.proteinG, 25.5);
      expect(d.fatG, 15);
      // 사진이 없는 끼니는 null — 사진 저장(#699) 이전 기록이 그렇다.
      expect(d.photoUrl, isNull);
    });

    test('maps the meal photo path when the member uploaded one', () {
      final d = clientDietEntryFromJson(<String, Object?>{
        'meal': '점심',
        'items': '비빔밥',
        'calories': 620,
        'sodium_mg': 900,
        'photo_url': '/trainer/clients/user-jisu/diet/photos/dietpic-abc123',
      });

      expect(
        d.photoUrl,
        '/trainer/clients/user-jisu/diet/photos/dietpic-abc123',
      );
    });

    test('an empty photo path reads as no photo', () {
      final d = clientDietEntryFromJson(<String, Object?>{
        'meal': '저녁',
        'items': '닭가슴살',
        'calories': 300,
        'sodium_mg': 400,
        'photo_url': '',
      });

      expect(d.photoUrl, isNull);
    });

    test('maps a history entry with exercises list', () {
      final h = routineHistoryEntryFromJson(<String, Object?>{
        'id': 'assigned-ex-r1',
        'date_label': '7/12 (오늘)',
        'label': 'PT 세션',
        'completion_rate': 80,
        'exercises': <Object?>['스쿼트 3세트', '✗ 런지'],
        'client_feedback': '무릎이 조금 아팠어요',
        'trainer_note': '강도 조절',
        'assigned_routine_id': 'r1',
        'completed_at': '2026-08-13T10:00:00Z',
      });
      expect(h.dateLabel, '7/12 (오늘)');
      expect(h.completionRate, 80);
      // 이름만 싣던 옛 응답도 읽는다 — 수행 표시(`✗`)는 이름에서 떼어 값으로
      // 든다(#1902).
      expect(
        h.exercises.map((ClientExerciseItem e) => e.name).toList(),
        <String>['스쿼트 3세트', '런지'],
      );
      expect(h.exercises.map((ClientExerciseItem e) => e.done).toList(), <bool>[
        true,
        false,
      ]);
      expect(h.trainerNote, '강도 조절');
      expect(h.id, 'assigned-ex-r1');
      expect(h.assignedRoutineId, 'r1');
      expect(h.completedAt, DateTime.utc(2026, 8, 13, 10));
    });
  });

  group('prioritizeClients', () {
    test('moves 주의 회원 (PT 관리 신호) first, keeping server order', () {
      final ordered = prioritizeClients(<TrainerClient>[
        _client('a', sodiumMg: 1500), // ok
        _client('b', sodiumMg: 2500, flagged: true), // over
        _client('c', sodiumMg: 1800), // ok
        _client('d', sodiumMg: 2100, flagged: true), // over
      ]);

      expect(ordered.map((c) => c.id).toList(), <String>['b', 'd', 'a', 'c']);
    });

    test('is a no-op ordering when nobody needs attention', () {
      final ordered = prioritizeClients(<TrainerClient>[
        _client('a', sodiumMg: 100),
        _client('b', sodiumMg: 200),
      ]);
      expect(ordered.map((c) => c.id).toList(), <String>['a', 'b']);
    });

    test('keeps server order within each priority group past the 32-item '
        'insertion-sort threshold (Dart TimSort only needs to prove stable '
        'above it — a smaller list can pass by accident, review)', () {
      // 40 clients, alternating over/under target, id = server position.
      final input = <TrainerClient>[
        for (var i = 0; i < 40; i++)
          _client('c$i', sodiumMg: i.isEven ? 2500 : 500, flagged: i.isEven),
      ];

      final ordered = prioritizeClients(input);

      final overIds = ordered
          .where((c) => needsAttention(c))
          .map((c) => int.parse(c.id.substring(1)))
          .toList();
      final underIds = ordered
          .where((c) => !needsAttention(c))
          .map((c) => int.parse(c.id.substring(1)))
          .toList();

      // Every flagged client precedes every unflagged client...
      expect(ordered.take(20).every((c) => needsAttention(c)), isTrue);
      expect(ordered.skip(20).every((c) => !needsAttention(c)), isTrue);
      // ...and each group is internally still in server (ascending) order.
      expect(overIds, List<int>.generate(20, (i) => i * 2));
      expect(underIds, List<int>.generate(20, (i) => i * 2 + 1));
    });

    test('a duplicate id does not corrupt the ordering (decorate-sort, '
        'not an id-keyed tie-breaker, review)', () {
      final ordered = prioritizeClients(<TrainerClient>[
        _client('dup', sodiumMg: 2500, flagged: true), // index 0, over
        _client('dup', sodiumMg: 500), // index 1, under — same id as above
        _client('c', sodiumMg: 2600, flagged: true), // index 2, over
      ]);

      expect(ordered.map((c) => c.sodiumMg).toList(), <int>[2500, 2600, 500]);
    });

    test(
      'uses the API chat timestamp when no source-side map is available',
      () {
        final old = _client('old', sodiumMg: 500);
        final recent = TrainerClient(
          id: 'recent',
          name: 'recent',
          avatar: 'r',
          goal: '',
          lastMessage: '',
          lastTime: '방금',
          lastMessageAt: DateTime.utc(2026, 8, 23),
          active: true,
          calories: 0,
          sodiumMg: 500,
          sugarG: 0,
          lastRoutine: '',
          weekCompletion: const <int>[],
          sodiumWeek: const <int>[],
        );

        expect(
          prioritizeClients(<TrainerClient>[old, recent]).map((c) => c.id),
          <String>['recent', 'old'],
        );
      },
    );
  });

  group('sugar warning threshold', () {
    test('keeps the existing strict greater-than rule for decimal values', () {
      expect(
        _client('under', sodiumMg: 0, sugarG: 49.9).sugarOverBudget,
        isFalse,
      );
      expect(
        _client('equal', sodiumMg: 0, sugarG: 50).sugarOverBudget,
        isFalse,
      );
      expect(
        _client('over', sodiumMg: 0, sugarG: 50.1).sugarOverBudget,
        isTrue,
      );
    });
  });
}
