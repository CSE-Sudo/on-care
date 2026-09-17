/// 회원 피드백이 **무엇에 달린 말인지**와 기록 종류 이름. (#1453)
///
/// 배정된 개인 운동의 피드백은 그 운동 하나에 달린 말인데, 목록 아래에
/// `회원 피드백` 상자 하나로 그려 그날 전체의 소감처럼 읽혔다. 기록 종류
/// 이름도 옛 시드의 `AI 루틴 · 자율 운동` 이 그대로 보였다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

RoutineHistoryEntry _entry({
  required List<ClientExerciseItem> exercises,
  String? assignedRoutineId,
  String label = 'AI 개인운동',
}) => RoutineHistoryEntry(
  id: 'h-1',
  dateLabel: '7/12',
  label: label,
  completionRate: 100,
  exercises: exercises,
  clientFeedback: '숨이 많이 찼어요',
  trainerNote: '',
  assignedRoutineId: assignedRoutineId,
);

void main() {
  group('clientFeedbackTitle', () {
    // 개인 운동의 회원 피드백은 없앴다(#1825). 제목은 세션 기록 하나다.
    test('PT·프로그램 기록은 세션 전체에 달린 말이다', () {
      final String title = clientFeedbackTitle(
        _ko,
        _entry(
          exercises: <ClientExerciseItem>[
            ClientExerciseItem.nameOnly('벤치프레스 ✓'),
            ClientExerciseItem.nameOnly('데드리프트 ✓'),
          ],
          label: 'PT 세션 · 트레이너 지도',
        ),
      );
      expect(title, _ko.clientFeedbackSession);
    });
  });

  group('routineKindLabel', () {
    test('옛 라벨은 그릴 때 새 용어로 바꿔 읽는다', () {
      expect(routineKindLabel(_ko, 'AI 루틴 · 자율 운동'), 'AI 개인운동');
    });

    test('그 밖의 라벨은 서버가 준 그대로 둔다', () {
      expect(routineKindLabel(_ko, 'PT 세션 · 트레이너 지도'), 'PT 세션 · 트레이너 지도');
      expect(routineKindLabel(_ko, 'AI 개인운동'), 'AI 개인운동');
    });
  });
}
