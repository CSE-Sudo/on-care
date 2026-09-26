import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

void main() {
  ProgramEditorState draftWith({required String name}) {
    return ProgramEditorState(
      name: '프로그램',
      sessions: <ProgramSessionDraft>[
        ProgramSessionDraft(
          id: 'session-1',
          name: '세션 A',
          exercises: <ProgramExerciseDraft>[
            ProgramExerciseDraft(id: 'exercise-1', name: name),
          ],
        ),
      ],
    );
  }

  test('flat routine support follows the backend item constraints', () {
    expect(draftWith(name: ' 스쿼트 ').supportsAssignment, isTrue);
    expect(draftWith(name: ' ').supportsAssignment, isFalse);
    expect(
      draftWith(name: List<String>.filled(101, '운동').join()).supportsAssignment,
      isFalse,
    );
  });

  test('flat routine support rejects structures the API cannot represent', () {
    const empty = ProgramEditorState(
      name: '프로그램',
      sessions: <ProgramSessionDraft>[
        ProgramSessionDraft(id: 'session-1', name: '세션 A', exercises: []),
      ],
    );
    final multiple = ProgramEditorState(
      name: '프로그램',
      sessions: <ProgramSessionDraft>[
        empty.sessions.single,
        empty.sessions.single,
      ],
    );

    expect(empty.supportsAssignment, isFalse);
    expect(multiple.supportsAssignment, isFalse);
  });

  test('버튼을 막는 이유가 실제 검사 조건과 같다 (#1582)', () {
    const empty = ProgramEditorState(
      name: '프로그램',
      sessions: <ProgramSessionDraft>[
        ProgramSessionDraft(id: 'session-1', name: '세션 A', exercises: []),
      ],
    );
    expect(empty.assignmentBlocker, ProgramAssignmentBlocker.noExercises);
    expect(
      draftWith(name: ' ').assignmentBlocker,
      ProgramAssignmentBlocker.invalidExerciseName,
    );
    expect(draftWith(name: '스쿼트').assignmentBlocker, isNull);
  });

  test('세션 12개·전체 운동 30개까지만 일정에 추가할 수 있다 (#1583)', () {
    ProgramEditorState sized(int sessionCount, int exerciseCount) =>
        ProgramEditorState(
          name: '프로그램',
          sessions: <ProgramSessionDraft>[
            for (var s = 0; s < sessionCount; s++)
              ProgramSessionDraft(
                id: 'session-$s',
                name: '세션 $s',
                exercises: <ProgramExerciseDraft>[
                  for (var e = 0; e < exerciseCount; e++)
                    if (e % sessionCount == s)
                      ProgramExerciseDraft(id: 'exercise-$e', name: '운동 $e'),
                ],
              ),
          ],
        );

    final atLimit = sized(12, 30);
    expect(atLimit.supportsAssignment, isTrue);
    expect(atLimit.canAddSession, isFalse);
    expect(atLimit.canAddExercise, isFalse);
    expect(sized(11, 29).canAddSession, isTrue);
    expect(sized(11, 29).canAddExercise, isTrue);

    for (final over in <ProgramEditorState>[sized(13, 30), sized(12, 31)]) {
      expect(over.exceedsSizeLimit, isTrue);
      expect(over.supportsAssignment, isFalse);
    }
  });

  test('근력은 세트에서 분을 환산하고, 그 외 유형은 시간을 그대로 쓴다 (#1276)', () {
    const strength = ProgramExerciseDraft(
      id: 'e1',
      name: '스쿼트',
      sets: 4,
      weight: 60,
    );
    const cardio = ProgramExerciseDraft(
      id: 'e2',
      name: '러닝머신',
      type: '유산소',
      minutes: 40,
    );

    // 세트당 벽시계 3분 — 회원 앱·서버와 같은 값이다.
    expect(strength.effectiveMinutes, 12);
    expect(cardio.effectiveMinutes, 40);

    // 유형을 한 축에서 견주는 값은 칼로리 하나다.
    expect(strength.calories?.calories, 72); // 12분 × 6kcal × 보통(1.0)
    expect(cardio.calories?.calories, 360); // 40분 × 9kcal × 보통(1.0)
    // 트레이너 폼은 수행할 회원의 체중을 모르므로 늘 어림값이다 (#1312).
    expect(strength.calories?.isRough, isTrue);
  });

  test('운동 이름이 비면 예상 소모 칼로리가 없다 (#1312)', () {
    const unnamed = ProgramExerciseDraft(id: 'e3', name: '   ');

    // 이름 없이 확정된 듯한 숫자를 띄우지 않는다 — 회원 앱과 같은 규약이다.
    expect(unnamed.calories, isNull);
  });
}
