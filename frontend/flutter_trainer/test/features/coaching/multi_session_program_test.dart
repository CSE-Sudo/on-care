// 다중 세션 프로그램의 배정·일정 등록·저장. (#709)
//
// 세션이 여럿이라는 이유로 버튼이 잠기지 않아야 하고, 세션 이름·순서와 세션별
// 운동 구성이 서버로 나가는 payload 까지 살아 있어야 한다.
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

ProgramExerciseDraft _exercise(
  String name, {
  int sets = 4,
  int duration = 15,
  String source = 'trainer',
  String type = '근력',
}) => ProgramExerciseDraft(
  id: 'exercise-$name',
  name: name,
  sets: sets,
  weight: 60,
  minutes: duration,
  type: type,
  source: source,
);

ProgramEditorState _twoSessionDraft() => ProgramEditorState(
  name: '주 2회 분할',
  goal: '근력 향상',
  sessions: <ProgramSessionDraft>[
    ProgramSessionDraft(
      id: 'session-1',
      name: '세션 A · 하체',
      exercises: <ProgramExerciseDraft>[_exercise('레그프레스'), _exercise('스쿼트')],
    ),
    ProgramSessionDraft(
      id: 'session-2',
      name: '세션 B · 유산소',
      exercises: <ProgramExerciseDraft>[
        _exercise('인터벌 러닝', type: '유산소', duration: 20, source: 'ai'),
      ],
    ),
  ],
);

void main() {
  group('supportsAssignment', () {
    test('세션이 여러 개라는 이유로 막지 않는다', () {
      expect(_twoSessionDraft().supportsAssignment, isTrue);
    });

    test('운동이 하나도 없으면 여전히 막는다', () {
      final empty = _twoSessionDraft().copyWith(
        sessions: <ProgramSessionDraft>[
          const ProgramSessionDraft(
            id: 'session-1',
            name: '세션 A',
            exercises: <ProgramExerciseDraft>[],
          ),
        ],
      );
      expect(empty.supportsAssignment, isFalse);
    });

    test('두 번째 세션의 값이 계약을 벗어나면 막는다', () {
      final draft = _twoSessionDraft();
      // 숫자 칸은 스테퍼가 범위 안으로 묶으므로, 남은 것은 빈 이름이다(#1276).
      final broken = draft.copyWith(
        sessions: <ProgramSessionDraft>[
          draft.sessions.first,
          draft.sessions.last.copyWith(
            exercises: <ProgramExerciseDraft>[_exercise('  ')],
          ),
        ],
      );
      expect(broken.supportsAssignment, isFalse);
    });
  });

  group('배정 payload', () {
    test('세션 이름·순서와 세션별 운동 구성이 그대로 실린다', () {
      final payload = programAssignToJson(
        _twoSessionDraft(),
        clientRequestId: 'req-1',
      );

      expect(payload['name'], '주 2회 분할');
      expect(payload['client_request_id'], 'req-1');
      final sessions = (payload['sessions']! as List<Object?>)
          .map((s) => s! as Map<String, Object?>)
          .toList();
      expect(sessions.map((s) => s['name']), <String>[
        '세션 A · 하체',
        '세션 B · 유산소',
      ]);
      final first = (sessions.first['exercises']! as List<Object?>)
          .map((e) => e! as Map<String, Object?>)
          .toList();
      expect(first.map((e) => e['name']), <String>['레그프레스', '스쿼트']);
      expect(first.first['weight'], 60.0);
      final second =
          (sessions.last['exercises']! as List<Object?>).single!
              as Map<String, Object?>;
      // AI 제안인지 트레이너가 넣은 것인지가 배정에도 남는다.
      expect(second['source'], 'ai');
      expect(second['type'], '유산소');
    });

    test('멱등키를 안 주면 키가 실리지 않는다', () {
      final payload = programAssignToJson(_twoSessionDraft());
      expect(payload.containsKey('client_request_id'), isFalse);
    });
  });

  group('초안 저장 payload', () {
    test('모든 세션이 편집기 순서 그대로 나간다', () {
      final payload = programDraftToJson(_twoSessionDraft());
      final sessions = (payload['sessions']! as List<Object?>)
          .map((s) => s! as Map<String, Object?>)
          .toList();
      expect(sessions, hasLength(2));
      expect(sessions.map((s) => s['id']), <String>['session-1', 'session-2']);
      expect((sessions.first['exercises']! as List<Object?>), hasLength(2));
    });
  });
}
