/// 회원 피드백이 **무엇에 달린 말인지**와 기록 종류 이름. (#1453)
///
/// 배정된 개인 운동의 피드백은 그 운동 하나에 달린 말인데, 목록 아래에
/// `회원 피드백` 상자 하나로 그려 그날 전체의 소감처럼 읽혔다. 기록 종류
/// 이름도 옛 시드의 `AI 루틴 · 자율 운동` 이 그대로 보였다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

RoutineHistoryEntry _entry({
  required List<String> exercises,
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
    test('배정 개인 운동 하나면 그 운동 이름을 적는다', () {
      final String title = clientFeedbackTitle(
        _ko,
        _entry(exercises: <String>['런닝 25분 ✓'], assignedRoutineId: 'routine-1'),
      );

      expect(title, contains('런닝'));
      expect(title, contains('회원 피드백'));
      // 분량·완료 표시는 제목에 넣지 않는다.
      expect(title, isNot(contains('25분')));
      expect(title, isNot(contains('✓')));
    });

    test('운동이 여럿인 배정 기록은 개인 운동 전체로 말한다', () {
      final String title = clientFeedbackTitle(
        _ko,
        _entry(
          exercises: <String>['런닝 25분 ✓', '스쿼트 3세트 ✓'],
          assignedRoutineId: 'routine-1',
        ),
      );

      expect(title, _ko.clientFeedbackPersonal);
    });

    test('PT·프로그램 기록은 세션 전체에 달린 말이다', () {
      final String title = clientFeedbackTitle(
        _ko,
        _entry(
          exercises: <String>['벤치프레스 ✓', '데드리프트 ✓'],
          label: 'PT 세션 · 트레이너 지도',
        ),
      );

      // 배정 개인 운동이 아니면 운동 하나에 억지로 붙이지 않는다.
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
