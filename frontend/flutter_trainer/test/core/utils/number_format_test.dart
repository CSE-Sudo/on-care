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

  test('반올림해 정수가 되면 소수점을 적지 않는다 (#3250)', () {
    // 회원 앱 `#,##0.#` 는 17.96 을 `18` 로 적는다.
    expect(formatNumber(17.96), '18');
    expect(formatNumber(1999.97), '2,000');
    expect(formatNumber(-0.04), '0');
  });
}
