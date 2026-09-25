import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

/// PT 에 붙이는 개인운동이 서버로 나가는 모양. (#2223)
void main() {
  test('AI 추천 사유는 회원에게 보내지 않는다', () {
    // 그 글은 트레이너가 이 제안을 그대로 둘지 판단하는 재료다 — 회원 화면에는
    // 운동 이름·유형·양만 서야 한다.
    final sent = personalRoutinesToJson(const <RoutineExercise>[
      RoutineExercise(
        name: '걷기',
        minutes: 30,
        type: '유산소',
        reason: '혈압 관리 목표에 맞춘 회복 유산소',
        source: 'ai',
      ),
    ]);

    expect(sent.single.containsKey('reason'), isFalse);
    expect(sent.single['name'], '걷기');
    expect(sent.single['minutes'], 30);
    expect(sent.single['source'], 'ai');
  });

  test('유형에 맞지 않는 칸은 싣지 않는다', () {
    final sent = personalRoutinesToJson(const <RoutineExercise>[
      // 근력은 세트·횟수·중량으로 재고 시간은 쓰지 않는다(#1276, #1310).
      RoutineExercise(
        name: '힙 브리지',
        minutes: 12,
        type: '근력',
        sets: 3,
        reps: 15,
      ),
      // 버티는 운동은 초가 횟수 자리를 대신한다(#1969).
      RoutineExercise(
        name: '플랭크',
        minutes: 0,
        type: '근력',
        sets: 3,
        reps: 10,
        holdSeconds: 60,
        isHold: true,
      ),
      // 그 외 유형은 시간 한 칸으로 잰다.
      RoutineExercise(name: '걷기', minutes: 30, type: '유산소', sets: 3),
    ]);

    expect(sent[0]['minutes'], 0);
    expect(sent[0]['sets'], 3);
    expect(sent[0]['reps'], 15);
    expect(sent[0].containsKey('hold_seconds'), isFalse);

    expect(sent[1]['hold_seconds'], 60);
    expect(sent[1].containsKey('reps'), isFalse);

    expect(sent[2]['minutes'], 30);
    expect(sent[2].containsKey('sets'), isFalse);
    expect(sent[2].containsKey('weight'), isFalse);
  });

  test('직접 넣은 줄과 AI 제안은 출처로 구분된다', () {
    final sent = personalRoutinesToJson(const <RoutineExercise>[
      RoutineExercise(name: '걷기', minutes: 30, type: '유산소', source: 'ai'),
      RoutineExercise(name: '계단 오르기', minutes: 15, type: '유산소'),
      // 서버가 받는 값이 아닌 출처는 트레이너로 접는다.
      RoutineExercise(name: '자전거', minutes: 20, type: '유산소', source: '??'),
    ]);

    expect(sent.map((e) => e['source']).toList(), <String>[
      'ai',
      'trainer',
      'trainer',
    ]);
  });

  group('routineOnlyAssignToJson — `개인운동만` 전송 본문 (#2223)', () {
    test('운동 하나가 세션 하나다', () {
      // 회원이 `걷기는 했고 플랭크는 안 했다` 를 하나씩 표시할 수 있어야 한다.
      final body = routineOnlyAssignToJson(
        const <RoutineExercise>[
          RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
          RoutineExercise(
            name: '플랭크',
            minutes: 0,
            type: '근력',
            sets: 3,
            holdSeconds: 60,
            isHold: true,
          ),
        ],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
        clientRequestId: 'req-1',
      );

      final sessions = body['sessions']! as List<Object?>;
      expect(sessions, hasLength(2));
      expect(
        sessions.map((s) => (s! as Map<String, Object?>)['name']).toList(),
        <String>['걷기', '플랭크'],
      );
      expect(body['name'], '이번 주 개인운동');
      expect(body['delivery_kind'], 'routine_only');
      expect(body['start_date'], '2026-09-25');
      expect(body['active_days'], 7);
      expect(body['client_request_id'], 'req-1');
    });

    test('운동이 하나뿐이면 그 운동 이름이 회원 카드 제목이 된다', () {
      // 배정이 한 건이면 프로그램 이름이 곧 제목이다 — 만든 말(`이번 주
      // 개인운동`)이 운동 이름 자리에 서면 안 된다.
      final body = routineOnlyAssignToJson(
        const <RoutineExercise>[
          RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
        ],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
      );

      expect(body['name'], '걷기');
      expect(body.containsKey('client_request_id'), isFalse);
    });
  });
}
