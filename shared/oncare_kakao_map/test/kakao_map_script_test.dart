/// 지도 문서·갱신 스크립트 만들기(#3043).
///
/// 헬스장 이름은 회원·업체가 정한 글자라 따옴표·한글·`</script>` 가 그대로
/// 들어올 수 있다. 스크립트가 거기서 끊기거나 다른 코드가 끼어들면 안 된다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_kakao_map/src/kakao_map_config.dart';
import 'package:oncare_kakao_map/src/kakao_map_platform_mobile.dart';
import 'package:oncare_kakao_map/src/kakao_map_script.dart';

/// `window.fn(<리터럴>);` 의 리터럴을 JSON 으로 되읽는다. 이스케이프가 JSON
/// 으로도 유효한 형태여야 같은 값이 나온다.
Object? _argOf(String script, String fn) {
  final String prefix = 'window.$fn(';
  expect(script, startsWith(prefix));
  expect(script, endsWith(');'));
  return jsonDecode('[${script.substring(prefix.length, script.length - 2)}]');
}

void main() {
  group('kakaoMapJsLiteral', () {
    test('따옴표·역슬래시·한글을 그대로 되살린다', () {
      const String name = '온케어 "신촌" 점 \'2층\' \\ 피트니스';
      final String literal = kakaoMapJsLiteral(name);
      expect(jsonDecode(literal), name);
    });

    test('</script> 로 문서가 끊기지 않는다', () {
      final String literal = kakaoMapJsLiteral('짐</script><script>alert(1)');
      expect(literal, isNot(contains('<')));
      expect(literal, isNot(contains('>')));
      expect(jsonDecode(literal), '짐</script><script>alert(1)');
    });

    test('줄 구분 문자와 & 도 이스케이프한다', () {
      final String literal = kakaoMapJsLiteral('a\u2028b\u2029c&d');
      expect(literal, isNot(contains('\u2028')));
      expect(literal, isNot(contains('\u2029')));
      expect(literal, isNot(contains('&')));
      expect(jsonDecode(literal), 'a\u2028b\u2029c&d');
    });
  });

  test('SDK 주소는 웹과 같고 appkey 를 인코딩해 붙인다', () {
    expect(kKakaoMapSdkUrl, 'https://dapi.kakao.com/v2/maps/sdk.js');
    expect(
      kakaoMapSdkSrc('abc123'),
      'https://dapi.kakao.com/v2/maps/sdk.js?appkey=abc123&autoload=false',
    );
    expect(kakaoMapSdkSrc('a&b c'), contains('appkey=a%26b+c&'));
  });

  group('마커 데이터', () {
    test('좌표·이름·id 를 옮기고 id 가 없으면 넣지 않는다', () {
      final List<Map<String, Object?>> data =
          kakaoMapMarkerData(const <KakaoMapMarker>[
            KakaoMapMarker(lat: 37.5, lng: 126.9, title: '헬스장 A', id: 'g1'),
            KakaoMapMarker(lat: 37.6, lng: 127.0, title: '헬스장 B'),
          ]);
      expect(data, <Map<String, Object?>>[
        <String, Object?>{
          'lat': 37.5,
          'lng': 126.9,
          'title': '헬스장 A',
          'id': 'g1',
        },
        <String, Object?>{'lat': 37.6, 'lng': 127.0, 'title': '헬스장 B'},
      ]);
    });

    test('좌표가 잘못된 핀은 뺀다 — 엉뚱한 자리에 찍지 않는다', () {
      final List<Map<String, Object?>> data =
          kakaoMapMarkerData(const <KakaoMapMarker>[
            KakaoMapMarker(lat: double.nan, lng: 126.9, title: 'x'),
            KakaoMapMarker(lat: 37.5, lng: double.infinity, title: 'y'),
            KakaoMapMarker(lat: 37.5, lng: 126.9, title: 'ok'),
          ]);
      expect(data.map((Map<String, Object?> m) => m['title']), <String>['ok']);
    });
  });

  group('갱신 스크립트', () {
    test('중심 옮기기', () {
      final String script = kakaoMapSetCenterScript(37.5559, 126.9368);
      expect(_argOf(script, 'onCareSetCenter'), <double>[37.5559, 126.9368]);
    });

    test('중심이 잘못된 값이면 아무것도 하지 않는다', () {
      expect(kakaoMapSetCenterScript(double.nan, 126.9), isEmpty);
    });

    test('마커 바꾸기 — 한글 이름과 따옴표가 그대로다', () {
      final String script = kakaoMapSetMarkersScript(const <KakaoMapMarker>[
        KakaoMapMarker(lat: 37.5, lng: 126.9, title: '온케어 "신촌"', id: 'g1'),
      ]);
      final Object? args = _argOf(script, 'onCareSetMarkers');
      expect(args, <Object?>[
        <Object?>[
          <String, Object?>{
            'lat': 37.5,
            'lng': 126.9,
            'title': '온케어 "신촌"',
            'id': 'g1',
          },
        ],
      ]);
    });

    test('마커가 없으면 빈 목록으로 지운다', () {
      expect(
        _argOf(
          kakaoMapSetMarkersScript(const <KakaoMapMarker>[]),
          'onCareSetMarkers',
        ),
        <Object?>[<Object?>[]],
      );
    });
  });

  group('지도 문서', () {
    String html({List<KakaoMapMarker> markers = const <KakaoMapMarker>[]}) =>
        kakaoMapHtml(
          appKey: 'test-key',
          centerLat: 37.5559,
          centerLng: 126.9368,
          level: 5,
          markers: markers,
        );

    test('SDK 를 appkey 와 autoload=false 로 부른다', () {
      expect(html(), isNot(contains('appkey=test-key&autoload')));
      expect(
        html(),
        // 문자열 리터럴 안의 & 는 \u0026 으로 옮겨 적는다 — JS 가 읽는 값은 같다.
        contains(kakaoMapJsLiteral(kakaoMapSdkSrc('test-key'))),
      );
    });

    test('처음 중심·확대 레벨·채널 이름이 들어 있다', () {
      final String doc = html();
      expect(doc, contains('"lat":37.5559'));
      expect(doc, contains('"lng":126.9368'));
      expect(doc, contains('level: 5'));
      expect(doc, contains('"$kKakaoMapChannel"'));
    });

    test('갱신 함수와 준비·실패·마커 소식을 둔다', () {
      final String doc = html();
      expect(doc, contains('window.onCareSetCenter'));
      expect(doc, contains('window.onCareSetMarkers'));
      expect(doc, contains("type: 'ready'"));
      expect(doc, contains("type: 'error'"));
      expect(doc, contains("type: 'marker'"));
    });

    test('헬스장 이름이 문서를 끊지 않는다', () {
      final String doc = html(
        markers: const <KakaoMapMarker>[
          KakaoMapMarker(lat: 37.5, lng: 126.9, title: '</script><b>짐'),
        ],
      );
      expect(
        '</script>'.allMatches(doc).length,
        1,
        reason: '문서 자체의 </script> 하나만 있어야 한다',
      );
      expect(doc, isNot(contains('<b>')));
    });
  });

  group('모바일 지원 타깃', () {
    test('WebView 가 있는 안드로이드·iOS 에서만 띄운다', () {
      for (final TargetPlatform p in TargetPlatform.values) {
        expect(
          kakaoMobileMapSupported(platform: p, hasWebView: true),
          p == TargetPlatform.android || p == TargetPlatform.iOS,
          reason: '$p',
        );
        expect(
          kakaoMobileMapSupported(platform: p, hasWebView: false),
          isFalse,
        );
      }
    });

    test('본 문서와 하위 프레임만 머무르고 다른 페이지로는 넘어가지 않는다', () {
      expect(
        kakaoMobileMapAllowsNavigation('http://localhost/', isMainFrame: true),
        isTrue,
      );
      expect(
        kakaoMobileMapAllowsNavigation('about:blank', isMainFrame: true),
        isTrue,
      );
      expect(
        kakaoMobileMapAllowsNavigation(
          'https://map.kakao.com/',
          isMainFrame: true,
        ),
        isFalse,
      );
      expect(
        kakaoMobileMapAllowsNavigation(
          'https://map.kakao.com/',
          isMainFrame: false,
        ),
        isTrue,
      );
    });
  });

  test('모바일 문서의 출처는 따로 주지 않으면 로컬 개발용 http://localhost 다', () {
    expect(kakaoMapMobileOrigin, 'http://localhost');
  });

  test('배포 출처를 주면 그 출처 안에서만 머문다', () {
    const String origin = 'https://member.example.org';
    expect(
      kakaoMobileMapAllowsNavigation(
        'https://member.example.org/',
        isMainFrame: true,
        origin: origin,
      ),
      isTrue,
    );
    expect(
      kakaoMobileMapAllowsNavigation(
        'http://localhost/',
        isMainFrame: true,
        origin: origin,
      ),
      isFalse,
    );
    expect(
      kakaoMobileMapAllowsNavigation(
        'https://member.example.org.evil.test/',
        isMainFrame: true,
        origin: origin,
      ),
      isFalse,
      reason: '접두어만 같은 다른 출처',
    );
    expect(
      kakaoMobileMapAllowsNavigation(
        'http://member.example.org/',
        isMainFrame: true,
        origin: origin,
      ),
      isFalse,
      reason: '스킴이 다르다',
    );
  });
}
