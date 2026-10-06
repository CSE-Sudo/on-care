/// 운동 기록의 강도를 읽는다 — 처방과 다르게 한 개인운동에 `수행 …` 이 붙는
/// 재료다. (#3249)
///
/// 서버 `build_current_week` 는 `sessions` 줄마다 `intensity` 를 보내는데 앱이
/// 읽지 않아, 펼친 날의 `row?.intensity` 가 늘 비어 있었다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';

ClientExerciseWeek _week(List<Map<String, Object?>> sessions) =>
    ClientExerciseWeek.fromJson(<String, Object?>{
      'day_labels': <String>['월', '화', '수', '목', '금', '토', '일'],
      'daily_minutes': <int>[30, 0, 0, 0, 0, 0, 0],
      'daily_calories': <int>[200, 0, 0, 0, 0, 0, 0],
      'sessions': sessions,
    });

void main() {
  test('줄마다 회원이 한 강도를 담는다', () {
    final ClientExerciseWeek week = _week(<Map<String, Object?>>[
      <String, Object?>{
        'day_label': '월',
        'name': '스쿼트',
        'type': 'strength',
        'minutes': 20,
        'calories': 120,
        'intensity': 'high',
      },
      <String, Object?>{
        'day_label': '월',
        'name': '걷기',
        'type': 'cardio',
        'minutes': 10,
        'calories': 80,
        'intensity': 'light',
      },
    ]);

    final List<ClientExerciseItem> items = week.itemsByDayLabel['월']!;
    expect(items.map((ClientExerciseItem i) => i.intensity), <String?>[
      'high',
      'light',
    ]);
  });

  test('강도가 없거나 빈 줄은 모름(null)이다', () {
    final ClientExerciseWeek week = _week(<Map<String, Object?>>[
      <String, Object?>{'day_label': '월', 'name': '플랭크', 'minutes': 5},
      <String, Object?>{
        'day_label': '월',
        'name': '런지',
        'minutes': 5,
        'intensity': '',
      },
    ]);

    expect(
      week.itemsByDayLabel['월']!.map((ClientExerciseItem i) => i.intensity),
      everyElement(isNull),
    );
  });

  test('이름이 여럿인 옛 합계 행은 강도를 나눠 붙이지 않는다', () {
    final ClientExerciseWeek week = _week(<Map<String, Object?>>[
      <String, Object?>{
        'day_label': '월',
        'items': <String>['스쿼트', '런지'],
        'minutes': 30,
        'intensity': 'high',
      },
    ]);

    expect(
      week.itemsByDayLabel['월']!.map((ClientExerciseItem i) => i.intensity),
      everyElement(isNull),
    );
  });
}
