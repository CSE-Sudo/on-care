import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/src/google_button_scale.dart';

void main() {
  group('googleIconButtonScale (#3445)', () {
    test('소셜 버튼 자리(52)에 맞게 구글 아이콘 버튼(40)을 키운다', () {
      expect(googleIconButtonScale(52), closeTo(1.3, 1e-9));
      expect(googleIconButtonScale(52) * kGoogleIconButtonExtent, 52);
    });

    test('자리가 구글 버튼보다 크면 그 비율만큼 키운다', () {
      expect(googleIconButtonScale(80), 2);
      expect(googleIconButtonScale(60), 1.5);
    });

    test('자리가 구글 버튼과 같거나 작으면 줄이지 않는다', () {
      expect(googleIconButtonScale(kGoogleIconButtonExtent), 1);
      expect(googleIconButtonScale(32), 1);
      expect(googleIconButtonScale(0), 1);
    });

    test('유한하지 않은 자리 크기는 배율 1로 둔다', () {
      expect(googleIconButtonScale(double.infinity), 1);
      expect(googleIconButtonScale(double.nan), 1);
    });
  });
}
