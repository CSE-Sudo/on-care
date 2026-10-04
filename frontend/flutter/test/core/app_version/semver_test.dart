/// 앱 버전 이름 비교(#3045).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/app_version/semver.dart';

void main() {
  AppSemver v(String raw) => AppSemver.tryParse(raw)!;

  group('tryParse', () {
    test('MAJOR.MINOR.PATCH 를 읽는다', () {
      expect(v('1.2.3'), const AppSemver(1, 2, 3));
      expect(v(' 0.4.0 '), const AppSemver(0, 4, 0));
    });

    test('빌드 번호(+N)는 버린다', () {
      expect(v('0.4.0+4'), const AppSemver(0, 4, 0));
      expect(v('1.2.3+99'), v('1.2.3'));
    });

    test('형식이 다르면 null', () {
      for (final String raw in <String>[
        '',
        '1',
        '1.2',
        '1.2.3.4',
        'v1.2.3',
        '1.2.x',
        '1.2.3-beta',
        '1.2.3+',
        'latest',
      ]) {
        expect(AppSemver.tryParse(raw), isNull, reason: raw);
      }
      expect(AppSemver.tryParse(null), isNull);
    });
  });

  group('비교', () {
    test('같음', () {
      expect(v('1.2.3').compareTo(v('1.2.3')), 0);
      expect(v('1.2.3') < v('1.2.3'), isFalse);
    });

    test('낮음·높음', () {
      expect(v('1.2.3') < v('1.2.4'), isTrue);
      expect(v('1.2.9') < v('1.3.0'), isTrue);
      expect(v('1.9.9') < v('2.0.0'), isTrue);
      expect(v('2.0.0') < v('1.9.9'), isFalse);
    });

    test('자리마다 숫자로 비교한다 — 1.10.0 이 1.9.0 보다 높다', () {
      expect(v('1.9.0') < v('1.10.0'), isTrue);
      expect(v('1.10.0') < v('1.9.0'), isFalse);
      expect(v('0.10.0').compareTo(v('0.9.12')), greaterThan(0));
    });

    test('빌드 번호가 달라도 같은 버전이다', () {
      expect(v('1.2.3+1').compareTo(v('1.2.3+50')), 0);
    });

    test('toString 은 빌드 번호 없는 이름', () {
      expect(v('1.2.3+7').toString(), '1.2.3');
    });
  });
}
