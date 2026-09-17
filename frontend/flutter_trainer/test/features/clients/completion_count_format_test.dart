/// 완료 개수 표기와 이행률의 기준. (#1484)
///
/// `3개 중 3개 완료` 한 문장을 왼쪽에 두던 것을 오른쪽 퍼센트 옆의 `3/3` 로
/// 줄인다. 개수와 퍼센트는 같은 사실을 말해야 한다 — 개수는 `✗` 를 세어
/// 만들고 퍼센트만 서버 필드를 쓰면 둘이 갈릴 수 있다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';

RoutineHistoryEntry _entry({
  required List<ClientExerciseItem> exercises,
  int completionRate = 0,
}) => RoutineHistoryEntry(
  id: 'h-1',
  dateLabel: '7/12',
  label: 'AI 개인운동',
  completionRate: completionRate,
  exercises: exercises,
  clientFeedback: '',
  trainerNote: '',
);

void main() {
  test('완료 개수는 완료/전체로 줄여 적는다', () {
    final RoutineHistoryEntry all = _entry(
      exercises: <ClientExerciseItem>[
        ClientExerciseItem.nameOnly('런닝 ✓'),
        ClientExerciseItem.nameOnly('스쿼트 ✓'),
        ClientExerciseItem.nameOnly('플랭크 ✓'),
      ],
    );
    final RoutineHistoryEntry some = _entry(
      exercises: <ClientExerciseItem>[
        ClientExerciseItem.nameOnly('런닝 ✓'),
        ClientExerciseItem.nameOnly('스쿼트 ✓'),
        ClientExerciseItem.nameOnly('플랭크 ✗'),
      ],
    );

    expect(all.completionCountLabel, '3/3');
    expect(some.completionCountLabel, '2/3');
  });

  test('하나도 못 한 날은 0/3 이다', () {
    final RoutineHistoryEntry none = _entry(
      exercises: <ClientExerciseItem>[
        ClientExerciseItem.nameOnly('런닝 ✗'),
        ClientExerciseItem.nameOnly('스쿼트 ✗'),
        ClientExerciseItem.nameOnly('플랭크 ✗'),
      ],
    );

    expect(none.completionCountLabel, '0/3');
    expect(none.displayRate, 0);
  });

  test('퍼센트는 개수와 같은 사실을 말한다', () {
    // 서버 값이 100 이어도 줄이 둘 중 하나만 마쳤다면 화면은 50% 다.
    final RoutineHistoryEntry mismatched = _entry(
      exercises: <ClientExerciseItem>[
        ClientExerciseItem.nameOnly('런닝 ✓'),
        ClientExerciseItem.nameOnly('스쿼트 ✗'),
      ],
      completionRate: 100,
    );

    expect(mismatched.completionCountLabel, '1/2');
    expect(mismatched.displayRate, 50);
  });

  test('운동 줄이 없는 옛 기록은 서버 이행률을 그대로 쓴다', () {
    final RoutineHistoryEntry legacy = _entry(
      exercises: <ClientExerciseItem>[],
      completionRate: 67,
    );

    expect(legacy.totalCount, 0);
    expect(legacy.displayRate, 67);
  });
}
