/// 소셜 로그인 데모 게이트(`AppConfig.socialDemoLoginEnabled`) — #1553.
///
/// 카카오·구글 버튼은 실 OAuth SDK 대신 고정 `demo-<provider>-token` 을 보낸다.
/// 계약은 하나다 — **그 토큰이 실서버로 나갈 수 있는 설정에서는 게이트가 닫힌다.**
/// 운영 설정에서 데모 동작이 켜지면 이 테스트가 먼저 깨져야 한다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';

AppConfig _config({
  Environment environment = Environment.dev,
  bool useMockApi = true,
  Set<String> realApi = const <String>{},
}) => AppConfig(
  environment: environment,
  apiBaseUrl: 'https://example.test/v1',
  useMockApi: useMockApi,
  realApiFeatures: realApi,
);

void main() {
  group('AppConfig.socialDemoLoginEnabled', () {
    test('목업이 소셜 교환을 받아 주는 데모 설정에서는 열린다', () {
      // 배포 데모가 이 경로다(ENV·USE_MOCK_API 모두 기본값).
      expect(_config().socialDemoLoginEnabled, isTrue);
      expect(
        _config(environment: Environment.staging).socialDemoLoginEnabled,
        isTrue,
      );
    });

    test('인증과 무관한 기능만 실서버로 돌려도 열려 있다', () {
      expect(
        _config(realApi: <String>{'ai-coach', 'diet'}).socialDemoLoginEnabled,
        isTrue,
      );
    });

    test('USE_MOCK_API=false 면 닫힌다', () {
      expect(_config(useMockApi: false).socialDemoLoginEnabled, isFalse);
    });

    test('REAL_API=auth 로 인증만 실서버로 돌려도 닫힌다', () {
      expect(
        _config(realApi: <String>{'auth'}).socialDemoLoginEnabled,
        isFalse,
      );
    });

    test('ENV=prod 에서는 목업 설정이어도 닫힌다', () {
      expect(
        _config(environment: Environment.prod).socialDemoLoginEnabled,
        isFalse,
      );
      expect(
        _config(
          environment: Environment.prod,
          useMockApi: false,
        ).socialDemoLoginEnabled,
        isFalse,
      );
    });
  });
}
