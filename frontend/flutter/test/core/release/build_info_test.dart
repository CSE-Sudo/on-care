/// 설정 `버전 정보` 줄의 문구와 provider(#3226).
///
/// 해석 규칙 자체(빌드 번호 검사·KST 변환)는 `shared/oncare_core` 테스트가 본다. 여기서는
/// 회원 앱이 그 값을 화면 언어의 한 줄로 만드는지, define 이 없는 테스트 빌드가 개발
/// 빌드로 읽히는지 본다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/core/release/build_info.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_core/build_info.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

final BuildInfo _released = BuildInfo.fromDefines(
  version: '0.4.0',
  buildNumber: '7032',
  releaseDate: '2026-10-05T05:30:00Z',
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    await initializeDateFormatting('en');
  });

  group('formatReleaseDate', () {
    test('한국어는 연 월 일 시:분', () {
      expect(
        formatReleaseDate(DateTime(2026, 10, 5, 14, 30), 'ko'),
        '2026년 10월 5일 14:30',
      );
    });

    test('영어는 월 일, 연 시:분(24시간)', () {
      expect(
        formatReleaseDate(DateTime(2026, 10, 5, 14, 30), 'en'),
        'Oct 5, 2026 14:30',
      );
    });
  });

  group('buildInfoSummary', () {
    test('배포 빌드 — 버전(빌드 번호)과 KST 배포 일시', () {
      expect(
        buildInfoSummary(_ko, 'ko', _released),
        '0.4.0 (7032) · 2026년 10월 5일 14:30 KST 배포',
      );
      expect(
        buildInfoSummary(_en, 'en', _released),
        '0.4.0 (7032) · Deployed Oct 5, 2026 14:30 KST',
      );
    });

    test('UTC 자정 직전 배포는 KST 다음 날로 적는다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        buildNumber: '7040',
        releaseDate: '2026-10-05T23:10:00Z',
      );
      expect(
        buildInfoSummary(_ko, 'ko', info),
        '0.4.0 (7040) · 2026년 10월 6일 08:10 KST 배포',
      );
    });

    test('개발 빌드 — pubspec 버전과 개발 빌드', () {
      final BuildInfo info = BuildInfo.fromDefines(version: '0.4.0');
      expect(buildInfoSummary(_ko, 'ko', info), '0.4.0 · 개발 빌드');
      expect(buildInfoSummary(_en, 'en', info), '0.4.0 · Development build');
    });

    test('개발 빌드는 배포 일시가 있어도 적지 않는다', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        releaseDate: '2026-10-05T05:30:00Z',
      );
      expect(buildInfoSummary(_ko, 'ko', info), '0.4.0 · 개발 빌드');
    });

    test('버전 이름을 못 읽은 개발 빌드는 개발 빌드만', () {
      expect(buildInfoSummary(_ko, 'ko', const BuildInfo()), '개발 빌드');
    });

    test('배포 일시를 읽지 못한 배포 빌드는 버전(빌드 번호)만', () {
      final BuildInfo info = BuildInfo.fromDefines(
        version: '0.4.0',
        buildNumber: '7032',
        releaseDate: 'garbage',
      );
      expect(buildInfoSummary(_ko, 'ko', info), '0.4.0 (7032)');
    });
  });

  group('buildInfoProvider', () {
    test('테스트 빌드에는 define 이 없어 개발 빌드다', () {
      expect(kBuildNumber, isEmpty);
      expect(kReleaseDate, isEmpty);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appVersionProvider.overrideWith((ref) async => '0.4.0'),
        ],
      );
      addTearDown(c.dispose);
      // 버전을 읽기 전에도 예외 없이 개발 빌드다.
      expect(c.read(buildInfoProvider).isDevelopmentBuild, isTrue);
    });

    test('버전 이름을 읽으면 그 값을 담는다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appVersionProvider.overrideWith((ref) async => '0.4.0'),
        ],
      );
      addTearDown(c.dispose);
      c.listen(buildInfoProvider, (_, _) {});
      await c.read(appVersionProvider.future);
      expect(c.read(buildInfoProvider), const BuildInfo(version: '0.4.0'));
    });

    test('버전을 읽지 못해도 깨지지 않는다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appVersionProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(c.dispose);
      c.listen(buildInfoProvider, (_, _) {});
      await c.read(appVersionProvider.future);
      expect(c.read(buildInfoProvider), const BuildInfo());
    });
  });
}
