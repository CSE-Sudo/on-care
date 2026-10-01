/// 오늘 할 일 체크의 복원·저장 규칙. (#2763)
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

  group('composeTaskSnapshot', () {
    const DailyTaskSnapshot saved = DailyTaskSnapshot(
      total: 3,
      completedToday: 1,
      completedCarriedOver: 0,
      pendingKeys: <String>{'consultation-2', 'report-a'},
      dismissedKeys: <String>{'program-z'},
      completedKeys: <String>{'consultation-1'},
    );

    test('화면이 모르는 미션의 저장 상태를 그대로 옮긴다', () {
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'report-a'},
        checked: <String>{'report-a'},
        carriedOver: const <String>{},
        dismissed: const <String>{'program-z'},
        seen: const <String>{'report-a'},
        saved: saved,
      );
      expect(next.completedKeys, <String>{'report-a', 'consultation-1'});
      expect(next.pendingKeys, <String>{'consultation-2'});
      expect(next.total, 3);
      expect(next.completed, 2);
      expect(next.dismissedKeys, <String>{'program-z'});
    });

    test('화면에 나타났다 사라진 미션은 전처럼 뺀다', () {
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'report-a'},
        checked: <String>{'report-a'},
        carriedOver: const <String>{},
        dismissed: const <String>{},
        seen: const <String>{'report-a', 'consultation-1', 'consultation-2'},
        saved: saved,
      );
      expect(next.completedKeys, <String>{'report-a'});
      expect(next.pendingKeys, isEmpty);
      expect(next.total, 1);
    });

    test('화면이 아는 미션은 화면 상태가 이긴다', () {
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'consultation-1', 'report-a'},
        checked: const <String>{},
        carriedOver: const <String>{},
        dismissed: const <String>{},
        seen: const <String>{'consultation-1', 'report-a'},
        saved: saved,
      );
      // 트레이너가 체크를 해제했다 — 저장된 완료로 되돌리지 않는다.
      expect(next.completedKeys, isNot(contains('consultation-1')));
      expect(next.pendingKeys, contains('consultation-1'));
    });

    test('삭제한 키는 옮기지 않는다', () {
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'report-a'},
        checked: const <String>{},
        carriedOver: const <String>{},
        dismissed: const <String>{'consultation-1'},
        seen: const <String>{'report-a'},
        saved: saved,
      );
      expect(next.completedKeys, isNot(contains('consultation-1')));
      expect(next.dismissedKeys, contains('consultation-1'));
    });

    test('이월분 완료는 따로 센다', () {
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'consultation-2', 'report-a'},
        checked: <String>{'consultation-2', 'report-a'},
        carriedOver: const <String>{'consultation-2'},
        dismissed: const <String>{},
        seen: const <String>{'consultation-2', 'report-a'},
        saved: null,
      );
      expect(next.completedToday, 1);
      expect(next.completedCarriedOver, 1);
      expect(next.total, 2);
    });

    test('옛 기록의 완료는 알 수 없어 옮기지 않고 미완료만 옮긴다', () {
      const DailyTaskSnapshot legacy = DailyTaskSnapshot(
        total: 2,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-2'},
      );
      final DailyTaskSnapshot next = composeTaskSnapshot(
        allKeys: <String>{'report-a'},
        checked: const <String>{},
        carriedOver: const <String>{},
        dismissed: const <String>{},
        seen: const <String>{'report-a'},
        saved: legacy,
      );
      expect(next.completedKeys, isEmpty);
      expect(next.pendingKeys, <String>{'report-a', 'consultation-2'});
    });
  });
}
