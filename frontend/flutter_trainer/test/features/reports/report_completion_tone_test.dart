import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 리포트 작업대의 `이행 N%` 배지는 요약·회원 문구와 같은 세 구간으로 칠한다
// (#2345). 예전에는 80 미만을 모두 빨강으로 두어, 요약이 좋은 점으로 꼽던
// 75% 가 작업대에서는 경고였다.
void main() {
  test('60% 미만은 빨강', () {
    expect(completionTagTone(0), AppTagTone.danger);
    expect(completionTagTone(59), AppTagTone.danger);
  });

  test('60~79% 는 회색', () {
    expect(completionTagTone(60), AppTagTone.neutral);
    expect(completionTagTone(79), AppTagTone.neutral);
  });

  test('80% 이상은 초록', () {
    expect(completionTagTone(80), AppTagTone.success);
    expect(completionTagTone(100), AppTagTone.success);
  });
}
