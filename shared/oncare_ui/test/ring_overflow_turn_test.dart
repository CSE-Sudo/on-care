/// 한 바퀴를 넘긴 도넛의 끝이 **어디에 서는지** (#1178).
///
/// 넘친 몫을 1 에서 자르면 209% 처럼 두 바퀴를 넘긴 값이 모두 끝을 12시로
/// 되돌려, 그 자리에 고정된 유형 기호 아래 캡 표시가 숨는다 — 도넛이 그냥
/// 꽉 찬 원으로만 보인다.
///
/// 회원 앱의 같은 이름 테스트와 짝이다 — 두 앱이 같은 그림을 그린다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_ui/oncare_ui.dart';

void main() {
  test('한 바퀴 안쪽은 비율 그대로', () {
    expect(ringOverflowTurn(0), 0);
    expect(ringOverflowTurn(0.25), closeTo(0.25, 1e-9));
    expect(ringOverflowTurn(0.99), closeTo(0.99, 1e-9));
  });

  test('딱 떨어지는 바퀴는 12시', () {
    expect(ringOverflowTurn(1), 0);
    expect(ringOverflowTurn(2), 0);
    expect(ringOverflowTurn(3), 0);
  });

  test('두 바퀴를 넘겨도 남은 조각만 다시 돈다', () {
    // 300kcal 목표에 627kcal = 209% → 두 번째 바퀴의 9% 지점.
    expect(ringOverflowTurn(627 / 300), closeTo(0.09, 1e-9));
    expect(ringOverflowTurn(2.5), closeTo(0.5, 1e-9));
    expect(ringOverflowTurn(12.75), closeTo(0.75, 1e-9));
  });

  test('돌려주는 값은 언제나 한 바퀴 안', () {
    for (final double ratio in <double>[0, 0.5, 1, 1.5, 2.09, 7.3, 100.4]) {
      final double turn = ringOverflowTurn(ratio);
      expect(turn, greaterThanOrEqualTo(0));
      expect(turn, lessThan(1));
    }
  });

  test('비율이 수가 아니면 12시', () {
    expect(ringOverflowTurn(double.infinity), 0);
    expect(ringOverflowTurn(double.nan), 0);
  });
}
