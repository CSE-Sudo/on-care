/// 배포 빌드 설정(`AppConfig.fromEnvironment`)과 `ENV=prod` 분기 — #2810.
///
/// 운영 웹 빌드는 `USE_MOCK_API=false`·`API_BASE_URL`·`ENV=prod` 를 넘긴다. 이
/// 테스트는 dart-define 없이 돌므로 **기본값**을 지킨다: 넘기지 않으면 목업·개발
/// 쪽으로 열리고, 주소는 회원 앱과 같은 `/v1` 규칙을 따른다. 그리고 `ENV=prod`
/// 일 때 API 로그 인터셉터가 빠지는지를 실제 `dioProvider` 로 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/network/interceptors/api_logging_interceptor.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppConfig _real(Environment environment) => AppConfig(
  environment: environment,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

Future<Dio> _dioFor(AppConfig config) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(config),
    ],
  );
  addTearDown(container.dispose);
  return container.read(dioProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.fromEnvironment 기본값 (dart-define 없음)', () {
    final AppConfig config = AppConfig.fromEnvironment();

    test('목업으로 열린다 — 실서버는 배포 빌드가 명시해서 켠다', () {
      expect(config.useMockApi, isTrue);
    });

    test('개발 환경이다 — 운영은 ENV=prod 로만 켜진다', () {
      expect(config.environment, Environment.dev);
      expect(config.isProd, isFalse);
    });

    test('API 주소 기본값은 회원 앱과 같이 /v1 로 끝난다', () {
      expect(config.apiBaseUrl, endsWith('/v1'));
      expect(config.apiBaseUrl, isNot(endsWith('/v1/')));
      expect(config.apiBaseUrl, startsWith('https://'));
    });

    test('데모 진입은 기본으로 숨겨진다', () {
      expect(config.showDemoEntry, isFalse);
    });
  });

  group('isProd 분기', () {
    test('prod 만 isProd 다', () {
      expect(_real(Environment.prod).isProd, isTrue);
      expect(_real(Environment.staging).isProd, isFalse);
      expect(_real(Environment.dev).isProd, isFalse);
    });
  });

  group('dioProvider — 운영 빌드의 요청 로그', () {
    test('ENV=prod 에서는 API 로그 인터셉터가 붙지 않는다', () async {
      final Dio dio = await _dioFor(_real(Environment.prod));
      expect(dio.interceptors.whereType<ApiLoggingInterceptor>(), isEmpty);
    });

    test('dev 에서는 API 로그 인터셉터가 붙는다', () async {
      final Dio dio = await _dioFor(_real(Environment.dev));
      expect(dio.interceptors.whereType<ApiLoggingInterceptor>(), hasLength(1));
    });

    test('실서버 빌드는 설정의 주소(/v1 포함)를 그대로 baseUrl 로 쓴다', () async {
      final Dio dio = await _dioFor(_real(Environment.prod));
      expect(dio.options.baseUrl, 'https://api.test/v1');
    });
  });
}
