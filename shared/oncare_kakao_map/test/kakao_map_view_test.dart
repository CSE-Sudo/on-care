import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_kakao_map/oncare_kakao_map.dart';

void main() {
  test('키를 주입하지 않은 빌드는 지도를 시도하지 않는다', () {
    // 테스트는 --dart-define 없이 돈다 — CI·로컬 빌드와 같은 조건이다.
    expect(kakaoJsKey, isEmpty);
    expect(isKakaoMapConfigured, isFalse);
  });

  testWidgets('지도를 띄울 수 없으면 폴백을 그대로 그린다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: KakaoMapView(
          centerLat: 37.5,
          centerLng: 126.9,
          markers: <KakaoMapMarker>[
            KakaoMapMarker(lat: 37.5, lng: 126.9, title: '헬스장', id: '1'),
          ],
          fallback: Text('fallback', key: ValueKey<String>('fallback')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('fallback')), findsOneWidget);
  });
}
