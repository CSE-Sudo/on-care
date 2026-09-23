import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';

/// 수치 표기 — 회원 앱 식단 탭의 `#,###` / `#,##0.#` 와 같은 결과여야 한다.
void main() {
  test('정수는 천 단위 콤마만 붙는다', () {
    expect(formatNumber(1800), '1,800');
    expect(formatNumber(2000.0), '2,000');
    expect(formatNumber(950), '950');
  });

  test('소수는 첫째 자리까지, 정수 부분에는 콤마가 붙는다 (#2156)', () {
    expect(formatNumber(2058.5), '2,058.5');
    expect(formatNumber(1830.24), '1,830.2');
    expect(formatNumber(17.8), '17.8');
  });
}
