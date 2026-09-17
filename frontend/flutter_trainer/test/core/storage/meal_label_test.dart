/// 회원 앱이 보낸 `meal_type` → 트레이너 웹이 그리는 한국어 라벨. (#1988)
///
/// 회원 앱은 `MealType.name` 을 그대로 보낸다. 야식(`lateNight`)을 표에 적어
/// 두지 않으면 폴백이 낮의 간식으로 접어, 트레이너가 밤늦게 먹은 것을 갈라
/// 볼 수 없다 — 이 화면의 값이 코칭 근거라 조용히 틀리면 안 된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';

void main() {
  test('다섯 끼니가 모두 제 라벨로 온다', () {
    expect(mealLabel('breakfast'), '아침');
    expect(mealLabel('lunch'), '점심');
    expect(mealLabel('dinner'), '저녁');
    expect(mealLabel('snack'), '간식');
    expect(mealLabel('lateNight'), '야식');
  });

  test('야식이 간식으로 접히지 않는다', () {
    expect(mealLabel('lateNight'), isNot(mealLabel('snack')));
  });

  test('모르는 끼니는 간식으로 접는다', () {
    // 트레이너 웹은 저보다 새 회원 앱이 만든 기록을 볼 수 있다. 빈 칸이나
    // 영문 원문을 그리는 것보다 낫다.
    expect(mealLabel('brunch'), '간식');
    expect(mealLabel(''), '간식');
  });
}
