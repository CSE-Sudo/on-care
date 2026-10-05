/// 설정 화면 `버전 정보` 의 빌드 정보 해석(#3226).
///
/// 두 앱이 같은 규칙을 쓰므로 여기서 한 번 본다 — 빌드 번호 검사, UTC 배포 일시의 KST
/// 변환, 개발 빌드 판정, `0.4.0 (7032)` 묶음. 어떤 입력에도 예외 없이 그 칸만 비워야 한다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/build_info.dart';

void main() {
  group('parseBuildNumber', () {
    test('양의 정수를 읽는다', () {
      expect(parseBuildNumber('7032'), 7032);
      expect(parseBuildNumber('1'), 1);
    });

    test('앞뒤 공백·개행은 떼고 읽는다', () {
      expect(parseBuildNumber(' 7032\n'), 7032);
    });

    test('없거나 비었으면 null', () {
      expect(parseBuildNumber(null), isNull);
      expect(parseBuildNumber(''), isNull);
      expect(parseBuildNumber('   '), isNull);
    });

    test('양의 정수 모양이 아니면 null', () {
      for (final String raw in <String>[
        '0',
        '-3',
        '07',
        '1.5',
        '12a',
        'abc',
        '+4',
        '0.4.0+4',
      ]) {
        expect(parseBuildNumber(raw), isNull, reason: raw);
      }
    });

    test('열 자리를 넘으면 null', () {
      expect(parseBuildNumber('1234567890'), 1234567890);
      expect(parseBuildNumber('12345678901'), isNull);
    });
  });

  group('parseReleaseDateKst', () {
    test('UTC 시각을 KST 벽시계로 바꾼다', () {
      final DateTime? kst = parseReleaseDateKst('2026-10-05T05:30:00Z');
      expect(kst, DateTime(2026, 10, 5, 14, 30));
      // 로컬 DateTime(벽시계)이다 — 기기 시간대로 다시 바뀌지 않는다.
      expect(kst!.isUtc, isFalse);
    });

    test('KST 로 날짜가 넘어가는 시각은 다음 날이다', () {
      expect(parseReleaseDateKst('2026-12-31T15:00:00Z'), DateTime(2027));
    });

    test('소수 초가 붙어도 읽는다', () {
      expect(
        parseReleaseDateKst('2026-10-05T05:30:00.123Z'),
        DateTime(2026, 10, 5, 14, 30, 0, 123),
      );
    });

    test('앞뒤 공백은 떼고 읽는다', () {
      expect(
        parseReleaseDateKst(' 2026-10-05T05:30:00Z\n'),
        DateTime(2026, 10, 5, 14, 30),
      );
    });

    test('없거나 비었으면 null', () {
      expect(parseReleaseDateKst(null), isNull);
      expect(parseReleaseDateKst(''), isNull);
    });

    test('시간대가 없거나 UTC 가 아니면 null — KST 로 단정하지 않는다', () {
      for (final String raw in <String>[
        '2026-10-05T05:30:00',
        '2026-10-05T14:30:00+09:00',
        '2026-10-05',
        '2026-10-05 05:30:00Z',
        'yesterday',
        '2026-13-40T99:99:99Z',
      ]) {
        expect(parseReleaseDateKst(raw), isNull, reason: raw);
      }
    });
  });

  group('BuildInfo.fromDefines', () {
    test('배포 빌드는 세 칸이 모두 찬다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        buildNumber: '7032',
        releaseDate: '2026-10-05T05:30:00Z',
      );
      expect(info.version, '0.4.0');
      expect(info.buildNumber, 7032);
      expect(info.releasedAtKst, DateTime(2026, 10, 5, 14, 30));
      expect(info.isDevelopmentBuild, isFalse);
      expect(info.versionLabel, '0.4.0 (7032)');
    });

    test('define 이 없으면 개발 빌드이고 버전 이름만 남는다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        buildNumber: '',
        releaseDate: '',
      );
      expect(info.isDevelopmentBuild, isTrue);
      expect(info.buildNumber, isNull);
      expect(info.releasedAtKst, isNull);
      expect(info.versionLabel, '0.4.0');
    });

    test('시각만 있고 번호가 없으면 여전히 개발 빌드다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        releaseDate: '2026-10-05T05:30:00Z',
      );
      expect(info.isDevelopmentBuild, isTrue);
    });

    test('틀린 값은 그 칸만 비운다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        buildNumber: '7032',
        releaseDate: 'not-a-date',
      );
      expect(info.buildNumber, 7032);
      expect(info.releasedAtKst, isNull);
      expect(info.isDevelopmentBuild, isFalse);
    });

    test('버전 이름을 못 읽으면 번호만 괄호로 남긴다', () {
      expect(BuildInfo.fromDefines(buildNumber: '7032').versionLabel, '(7032)');
      expect(
        BuildInfo.fromDefines(version: '  ', buildNumber: '7032').version,
        isNull,
      );
    });

    test('아무것도 없으면 versionLabel 은 null', () {
      final BuildInfo info = BuildInfo.fromDefines();
      expect(info.versionLabel, isNull);
      expect(info.isDevelopmentBuild, isTrue);
    });

    test('같은 값이면 같다', () {
      expect(
        BuildInfo.fromDefines(version: '0.4.0', buildNumber: '7'),
        const BuildInfo(version: '0.4.0', buildNumber: 7),
      );
      expect(
        const BuildInfo(version: '0.4.0', buildNumber: 7).hashCode,
        const BuildInfo(version: '0.4.0', buildNumber: 7).hashCode,
      );
      expect(
        const BuildInfo(version: '0.4.0', buildNumber: 7),
        isNot(const BuildInfo(version: '0.4.0', buildNumber: 8)),
      );
    });
  });
}
