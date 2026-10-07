import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';

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

  group('routineOnlyAssignToJson — 정하지 않은 칸은 0 이 아니라 null', () {
    // `hold_seconds: 0` 을 서버가 버티는 운동으로 읽어 일반 근력 운동의
    // 횟수를 지웠다 — 회원은 `스쿼트 3세트 · 12회` 를 `스쿼트 3세트` 로 받았다.
    Map<String, Object?> exerciseOf(Map<String, Object?> body, int index) {
      final session =
          (body['sessions']! as List<Object?>)[index]! as Map<String, Object?>;
      return (session['exercises']! as List<Object?>).single!
          as Map<String, Object?>;
    }

    final body = routineOnlyAssignToJson(
      const <RoutineExercise>[
        RoutineExercise(name: '스쿼트', minutes: 0, type: '근력', sets: 3, reps: 12),
        RoutineExercise(
          name: '플랭크',
          minutes: 0,
          type: '근력',
          sets: 3,
          reps: 10,
          holdSeconds: 60,
          isHold: true,
        ),
        RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
      ],
      programName: '이번 주 개인운동',
      startDate: '2026-09-25',
      activeDays: 7,
    );

    test('횟수만 있는 근력 운동은 횟수 그대로, 초는 null', () {
      final squat = exerciseOf(body, 0);

      expect(squat['reps'], 12);
      expect(squat['sets'], 3);
      expect(squat['hold_seconds'], isNull);
      expect(squat['hold_seconds'], isNot(0));
    });

    test('버티는 운동은 초 그대로, 횟수는 null', () {
      final plank = exerciseOf(body, 1);

      expect(plank['hold_seconds'], 60);
      expect(plank['reps'], isNull);
      expect(plank['sets'], 3);
    });

    test('근력이 아닌 운동은 세트·횟수·초·중량이 모두 null', () {
      final walk = exerciseOf(body, 2);

      expect(walk['duration'], 30);
      expect(walk['sets'], isNull);
      expect(walk['reps'], isNull);
      expect(walk['hold_seconds'], isNull);
      expect(walk['weight'], isNull);
    });

    test('세트를 정하지 않은 근력 운동도 0 세트로 보내지 않는다', () {
      final sent = routineOnlyAssignToJson(
        const <RoutineExercise>[
          RoutineExercise(name: '런지', minutes: 0, type: '근력', reps: 10),
        ],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
      );
      final lunge = exerciseOf(sent, 0);

      expect(lunge['sets'], isNull);
      expect(lunge['reps'], 10);
      expect(lunge['hold_seconds'], isNull);
    });
  });

  group('AI 제안 종결 — `suggestion_ids` (#2747)', () {
    const RoutineExercise fromSuggestion = RoutineExercise(
      name: '걷기',
      minutes: 30,
      type: '유산소',
      source: 'ai',
      suggestionId: 'sug-walk',
    );
    const RoutineExercise typed = RoutineExercise(
      name: '계단 오르기',
      minutes: 15,
      type: '유산소',
    );

    test('제안에서 온 줄만 모으고, 겹친 id 는 한 번만 싣는다', () {
      expect(
        suggestionIdsOf(const <RoutineExercise>[
          fromSuggestion,
          typed,
          fromSuggestion,
          RoutineExercise(
            name: '자전거',
            minutes: 20,
            type: '유산소',
            suggestionId: '',
          ),
        ]),
        <String>['sug-walk'],
      );
    });

    test('편집해도 어느 제안에서 왔는지는 남는다', () {
      final RoutineExercise edited = fromSuggestion.copyWith(minutes: 40);

      expect(edited.minutes, 40);
      expect(edited.suggestionId, 'sug-walk');
    });

    test('개인운동만 본문에 제안 id 가 실린다', () {
      final body = routineOnlyAssignToJson(
        const <RoutineExercise>[fromSuggestion, typed],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
      );

      expect(body['suggestion_ids'], <String>['sug-walk']);
    });

    test('제안에서 온 줄이 없으면 키 자체를 싣지 않는다', () {
      final body = routineOnlyAssignToJson(
        const <RoutineExercise>[typed],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
      );

      expect(body.containsKey('suggestion_ids'), isFalse);
    });

    test('세션 운동 항목에는 제안 id 가 섞이지 않는다', () {
      final body = routineOnlyAssignToJson(
        const <RoutineExercise>[fromSuggestion],
        programName: '이번 주 개인운동',
        startDate: '2026-09-25',
        activeDays: 7,
      );
      final session =
          (body['sessions']! as List<Object?>).single! as Map<String, Object?>;
      final exercise =
          (session['exercises']! as List<Object?>).single!
              as Map<String, Object?>;

      expect(exercise.containsKey('suggestion_ids'), isFalse);
      expect(exercise.containsKey('suggestion_id'), isFalse);
    });

    test('PT 일정 추가 본문에도 제안 id 가 실린다', () {
      final body = programScheduleToJson(
        assignment: const <String, Object?>{'name': '하체 PT'},
        date: '2026-09-25',
        time: '10:00',
        durationMinutes: 50,
        clientName: '김민수',
        personalRoutines: personalRoutinesToJson(const <RoutineExercise>[
          fromSuggestion,
        ]),
        suggestionIds: const <String>['sug-walk'],
      );

      expect(body['suggestion_ids'], <String>['sug-walk']);
      expect(body['personal_routines'], hasLength(1));
    });

    test('이미 있는 PT 에 붙이는 본문에도 제안 id 가 실린다', () {
      final body = scheduledRoutinesUpdateToJson(const <RoutineExercise>[
        fromSuggestion,
        typed,
      ]);

      expect(body['suggestion_ids'], <String>['sug-walk']);
      expect(body['personal_routines'], hasLength(2));
      expect(
        scheduledRoutinesUpdateToJson(const <RoutineExercise>[
          typed,
        ]).containsKey('suggestion_ids'),
        isFalse,
      );
    });

    test('PT 일정 추가에 제안 id 가 없으면 옛 본문 그대로다', () {
      final body = programScheduleToJson(
        assignment: const <String, Object?>{'name': '하체 PT'},
        date: '2026-09-25',
        time: '10:00',
        durationMinutes: 50,
        clientName: '김민수',
      );

      expect(body.containsKey('suggestion_ids'), isFalse);
    });
  });
}
