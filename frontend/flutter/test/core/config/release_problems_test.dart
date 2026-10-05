/// 릴리스 기본값 가드 — `AppConfig.releaseProblems` 판정(#3022).
///
/// 컴파일 타임 기본값(ENV=dev·USE_MOCK_API=true·예시 주소)을 그대로 둔 릴리스 빌드는
/// 기동 시 기능 화면 대신 구성 오류 안내를 띄운다. 여기서는 어느 조합이 문제인지를
/// 경우별로 고정한다. 데모 Pages 빌드(`DEMO_BUILD=true` + 목업 + ENV=dev)는 통과해야 한다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';

const String _realUrl = 'https://api.oncare.kr/v1';

AppConfig _config({
  Environment environment = Environment.prod,
  String apiBaseUrl = _realUrl,
  bool useMockApi = false,
  bool demoBuild = false,
  bool showDemoEntry = false,
  Set<String> realApiFeatures = const <String>{},
}) => AppConfig(
  environment: environment,
  apiBaseUrl: apiBaseUrl,
  useMockApi: useMockApi,
  demoBuild: demoBuild,
  showDemoEntry: showDemoEntry,
  realApiFeatures: realApiFeatures,
);

void main() {
  group('releaseProblems — 정상 릴리스', () {
    test('운영(prod·실서버·https 주소)은 문제없다', () {
      expect(_config().releaseProblems(), isEmpty);
    });

    test('staging 도 릴리스로 낼 수 있다', () {
      expect(
        _config(environment: Environment.staging).releaseProblems(),
        isEmpty,
      );
    });

    test('데모 Pages 빌드(목업 + DEMO_BUILD + ENV=dev)는 문제없다', () {
      expect(
        _config(
          environment: Environment.dev,
          apiBaseUrl: 'https://dev.api.oncare.example.com/v1',
          useMockApi: true,
          demoBuild: true,
        ).releaseProblems(),
        isEmpty,
      );
    });

    test('데모 사이트의 실서버 빌드(DEMO_BUILD + staging)도 문제없다', () {
      expect(
        _config(
          environment: Environment.staging,
          demoBuild: true,
        ).releaseProblems(),
        isEmpty,
      );
    });
  });

  group('releaseProblems — 잘못된 조합', () {
    test('ENV 를 넘기지 않으면(dev) 개발 환경 문제다', () {
      expect(
        _config(environment: Environment.dev).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.devEnvironment],
      );
    });

    test('ENV=prod 인데 USE_MOCK_API 를 빠뜨리면 목업 문제다', () {
      expect(_config(useMockApi: true).releaseProblems(), <ReleaseProblem>[
        ReleaseProblem.mockWithoutDemoBuild,
      ]);
    });

    test('define 을 하나도 넘기지 않은 기본값은 개발·목업 둘 다 문제다', () {
      expect(AppConfig.fromEnvironment().releaseProblems(), <ReleaseProblem>[
        ReleaseProblem.devEnvironment,
        ReleaseProblem.mockWithoutDemoBuild,
      ]);
    });

    test('DEMO_BUILD 만으로는 실서버 dev 빌드를 허용하지 않는다', () {
      expect(
        _config(
          environment: Environment.dev,
          demoBuild: true,
        ).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.devEnvironment],
      );
    });

    test('코드 기본값의 예시 주소는 자리표시자 문제다', () {
      expect(
        _config(
          apiBaseUrl: 'https://dev.api.oncare.example.com/v1',
        ).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.placeholderApiUrl],
      );
    });

    test('http 주소는 보안 문제다', () {
      expect(
        _config(apiBaseUrl: 'http://api.oncare.kr/v1').releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.insecureApiUrl],
      );
    });

    test('http 로컬 주소는 두 문제가 함께 잡힌다', () {
      expect(
        _config(apiBaseUrl: 'http://localhost:8000/v1').releaseProblems(),
        <ReleaseProblem>[
          ReleaseProblem.insecureApiUrl,
          ReleaseProblem.placeholderApiUrl,
        ],
      );
    });

    test('읽을 수 없는 주소는 보안 문제다', () {
      expect(
        _config(apiBaseUrl: 'api.oncare.kr/v1').releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.insecureApiUrl],
      );
    });

    test('목업 데모라도 REAL_API 로 실서버를 부르면 주소를 본다', () {
      expect(
        _config(
          environment: Environment.dev,
          apiBaseUrl: 'https://dev.api.oncare.example.com/v1',
          useMockApi: true,
          demoBuild: true,
          realApiFeatures: const <String>{'ai-coach'},
        ).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.placeholderApiUrl],
      );
    });
  });

  // 운영 로그인 화면에 데모 진입이 보이거나, 데모 전용 부분 실연동 스위치가 실서버
  // 빌드에 남으면 기동 가드가 멈춘다(#3147). 데모 Pages 빌드는 지금처럼 뜬다.
  group('releaseProblems — 데모 전용 값 (#3147)', () {
    test('운영 빌드에 SHOW_DEMO_ENTRY=true 면 데모 진입 문제다', () {
      expect(_config(showDemoEntry: true).releaseProblems(), <ReleaseProblem>[
        ReleaseProblem.demoEntryWithoutDemoBuild,
      ]);
    });

    test('staging 빌드에도 데모 진입은 허용하지 않는다', () {
      expect(
        _config(
          environment: Environment.staging,
          showDemoEntry: true,
        ).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.demoEntryWithoutDemoBuild],
      );
    });

    test('목업을 빠뜨린 빌드의 데모 진입은 두 문제로 함께 잡힌다', () {
      expect(
        _config(useMockApi: true, showDemoEntry: true).releaseProblems(),
        <ReleaseProblem>[
          ReleaseProblem.mockWithoutDemoBuild,
          ReleaseProblem.demoEntryWithoutDemoBuild,
        ],
      );
    });

    test('데모 Pages 빌드(목업 + DEMO_BUILD)는 데모 진입이 켜져도 문제없다', () {
      expect(
        _config(
          environment: Environment.dev,
          apiBaseUrl: 'https://dev.api.oncare.example.com/v1',
          useMockApi: true,
          demoBuild: true,
          showDemoEntry: true,
        ).releaseProblems(),
        isEmpty,
      );
    });

    test('데모 사이트의 실서버 빌드(DEMO_BUILD + staging)도 데모 진입을 열 수 있다', () {
      expect(
        _config(
          environment: Environment.staging,
          demoBuild: true,
          showDemoEntry: true,
        ).releaseProblems(),
        isEmpty,
      );
    });

    test('SHOW_DEMO_ENTRY 기본값은 꺼짐이라 운영 빌드에 걸리지 않는다', () {
      expect(AppConfig.fromEnvironment().showDemoEntry, isFalse);
    });

    test('운영 빌드에 REAL_API 가 남으면 부분 실연동 문제다', () {
      expect(
        _config(realApiFeatures: const <String>{'ai-coach'}).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.realApiWithoutDemoBuild],
      );
    });

    test('REAL_API 에 여러 기능이 있어도 문제 하나로 짚는다', () {
      expect(
        _config(
          environment: Environment.staging,
          realApiFeatures: const <String>{'ai-coach', 'auth'},
        ).releaseProblems(),
        <ReleaseProblem>[ReleaseProblem.realApiWithoutDemoBuild],
      );
    });

    test('운영 빌드에 두 값이 함께 남으면 둘 다 짚는다', () {
      expect(
        _config(
          showDemoEntry: true,
          realApiFeatures: const <String>{'ai-coach'},
        ).releaseProblems(),
        <ReleaseProblem>[
          ReleaseProblem.demoEntryWithoutDemoBuild,
          ReleaseProblem.realApiWithoutDemoBuild,
        ],
      );
    });

    test('데모 Pages 빌드는 REAL_API·데모 진입이 함께 있어도 문제없다', () {
      expect(
        _config(
          environment: Environment.dev,
          useMockApi: true,
          demoBuild: true,
          showDemoEntry: true,
          realApiFeatures: const <String>{'ai-coach', 'auth'},
        ).releaseProblems(),
        isEmpty,
      );
    });

    test('REAL_API 기본값은 비어 있어 운영 빌드에 걸리지 않는다', () {
      expect(AppConfig.fromEnvironment().realApiFeatures, isEmpty);
    });
  });

  group('isPlaceholderHost', () {
    test('예약·로컬 호스트를 잡는다', () {
      for (final String host in <String>[
        'example.com',
        'dev.api.oncare.example.com',
        'API.EXAMPLE.ORG',
        'x.example.net',
        'api.oncare.test',
        'foo.invalid',
        'thing.example',
        'localhost',
        'app.localhost',
        '127.0.0.1',
      ]) {
        expect(isPlaceholderHost(host), isTrue, reason: host);
      }
    });

    test('실제 도메인은 지나간다', () {
      for (final String host in <String>[
        'api.oncare.kr',
        'abc.ap-southeast-1.elb.amazonaws.com',
        'notexample.com',
        'example.com.evil.kr',
        'testing.oncare.kr',
      ]) {
        expect(isPlaceholderHost(host), isFalse, reason: host);
      }
    });
  });

  group('releaseGuardProblems — 빌드 모드', () {
    final AppConfig defaults = AppConfig.fromEnvironment();

    test('릴리스 모드가 아니면(flutter run·테스트) 기본값도 통과한다', () {
      // 테스트에서는 기본값도 false 지만, 무엇을 보는지 드러나게 적는다.
      // ignore: avoid_redundant_argument_values
      expect(releaseGuardProblems(defaults, releaseMode: false), isEmpty);
    });

    test('릴리스 모드면 releaseProblems 를 그대로 쓴다', () {
      expect(
        releaseGuardProblems(defaults, releaseMode: true),
        defaults.releaseProblems(),
      );
    });

    test('테스트 실행은 릴리스 모드가 아니다 — 기본 인자로는 가드가 꺼져 있다', () {
      expect(releaseGuardProblems(defaults), isEmpty);
    });
  });

  test('DEMO_BUILD 기본값은 꺼짐이다', () {
    expect(AppConfig.fromEnvironment().demoBuild, isFalse);
  });
}
