/// 오늘 할 일 체크의 복원 규칙. (#2763)
///
/// 저장 규칙(키 단위 변경)은 `daily_task_key_change_test.dart` 가 본다(#2886).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_tasks_card.dart';

void main() {
  group('restoreTaskMarks', () {
    const DailyTaskSnapshot today = DailyTaskSnapshot(
      total: 3,
      completedToday: 2,
      completedCarriedOver: 0,
      pendingKeys: <String>{'report-a'},
      completedKeys: <String>{'consultation-1', 'program-a'},
    );

    test('체크한 키를 저장해 둔 날은 그 키만 되살린다', () {
      final marks = restoreTaskMarks(
        keys: <String>{'consultation-1', 'report-a', 'feedback-x'},
        today: today,
        yesterday: null,
        dismissed: const <String>{},
      );
      expect(marks.checked, <String>{'consultation-1'});
      expect(marks.carriedOver, isEmpty);
    });

    test('늦게 나타난 키 하나만 넘겨도 같은 규칙이다', () {
      final marks = restoreTaskMarks(
        keys: <String>{'consultation-1'},
        today: today,
        yesterday: null,
        dismissed: const <String>{},
      );
      expect(marks.checked, <String>{'consultation-1'});
    });

    test('삭제한 키는 체크로 되살리지 않는다', () {
      final marks = restoreTaskMarks(
        keys: <String>{'consultation-1'},
        today: today,
        yesterday: null,
        dismissed: const <String>{'consultation-1'},
      );
      expect(marks.checked, isEmpty);
    });

    test('옛 기록(체크 키 없음)은 미완료 목록에서 추정한다', () {
      const DailyTaskSnapshot legacy = DailyTaskSnapshot(
        total: 2,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{'report-a'},
      );
      final marks = restoreTaskMarks(
        keys: <String>{'report-a', 'consultation-1'},
        today: legacy,
        yesterday: null,
        dismissed: const <String>{},
      );
      expect(marks.checked, <String>{'consultation-1'});
    });

    test('어제 끝내지 못한 키가 이월된다', () {
      const DailyTaskSnapshot yesterday = DailyTaskSnapshot(
        total: 2,
        completedToday: 0,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-2', 'report-gone'},
      );
      final marks = restoreTaskMarks(
        keys: <String>{'consultation-2', 'report-a'},
        today: null,
        yesterday: yesterday,
        dismissed: const <String>{},
      );
      expect(marks.checked, isEmpty);
      expect(marks.carriedOver, <String>{'consultation-2'});
    });
  });
}
