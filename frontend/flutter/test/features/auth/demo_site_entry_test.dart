/// 운영 앱 `체험하기` → 데모 사이트 → 곧장 데모 진입 — #3437.
///
/// 운영 서버는 데모 폴백이 꺼져 있어 운영 빌드에서 앱 안 데모로 들어가면 화면이
/// 비었다. 운영 웹 빌드는 `DEMO_SITE_URL` 로 받은 데모 Pages 의 회원 앱으로 같은 탭을
/// 옮기고, 주소에 `?demo=1` 을 붙인다. 데모 Pages 는 그 표시를 보고 로그인 화면 대신
/// 데모로 들어간다. 여기서는 주소 만들기·표시 읽기·기동 판단·세션 복원을 고정한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/demo_site_entry.dart';

const AppConfig _demoPages = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
  showDemoEntry: true,
  demoBuild: true,
);

const AppConfig _production = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.oncare.test/v1',
  useMockApi: false,
  demoSiteUrl: 'https://cse-sudo.github.io/on-care/member/',
);

final Uri _arrived = Uri.parse(
  'https://cse-sudo.github.io/on-care/member/?demo=1#/',
);
final Uri _plainVisit = Uri.parse(
  'https://cse-sudo.github.io/on-care/member/#/sign-in',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('demoSiteEntryAddress', () {
    test('데모 사이트 주소에 진입 표시를 붙인다', () {
      expect(
        demoSiteEntryAddress('https://cse-sudo.github.io/on-care/member/'),
        Uri.parse('https://cse-sudo.github.io/on-care/member/?demo=1'),
      );
    });

    test('기존 질의는 남기고 조각은 버린다', () {
      expect(
        demoSiteEntryAddress('https://demo.oncare.test/member/?lang=ko#/x'),
        Uri.parse('https://demo.oncare.test/member/?lang=ko&demo=1'),
      );
    });

    test('비었거나 https 가 아니면 쓰지 않는다', () {
      expect(demoSiteEntryAddress(null), isNull);
      expect(demoSiteEntryAddress('   '), isNull);
      expect(demoSiteEntryAddress('http://cse-sudo.github.io/member/'), isNull);
      expect(demoSiteEntryAddress('/demo/member/'), isNull);
    });
  });

  group('isDemoEntryLink', () {
    test('진입 표시가 있는 주소만 참', () {
      expect(isDemoEntryLink(_arrived), isTrue);
      expect(isDemoEntryLink(_plainVisit), isFalse);
      expect(
        isDemoEntryLink(Uri.parse('https://a.test/member/?demo=0')),
        isFalse,
      );
    });
  });

  group('shouldEnterDemoOnLaunch', () {
    test('데모 진입이 열린 웹 빌드에 표시를 달고 오면 곧장 데모', () {
      expect(
        shouldEnterDemoOnLaunch(_demoPages, isWeb: true, page: _arrived),
        isTrue,
      );
    });

    test('표시 없이 오면 지금처럼 로그인 화면', () {
      expect(
        shouldEnterDemoOnLaunch(_demoPages, isWeb: true, page: _plainVisit),
        isFalse,
      );
    });

    test('운영 빌드는 표시가 붙어 와도 데모로 들이지 않는다', () {
      expect(
        shouldEnterDemoOnLaunch(_production, isWeb: true, page: _arrived),
        isFalse,
      );
    });

    test('데모 진입이 닫힌 빌드·웹이 아닌 빌드는 보지 않는다', () {
      const AppConfig closed = AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
      );
      expect(
        shouldEnterDemoOnLaunch(closed, isWeb: true, page: _arrived),
        isFalse,
      );
      expect(
        shouldEnterDemoOnLaunch(_demoPages, isWeb: false, page: _arrived),
        isFalse,
      );
    });
  });

  group('세션 복원', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    ProviderContainer container({required bool demoEntryLink}) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          // 네트워크로 나가면 안 된다 — 나가면 바로 실패시킨다.
          dioProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'https://example.test'))
              ..interceptors.add(
                InterceptorsWrapper(
                  onRequest: (RequestOptions o, RequestInterceptorHandler h) =>
                      h.reject(DioException(requestOptions: o)),
                ),
              ),
          ),
          sessionFeatureResetOverride(),
          demoEntryLinkProvider.overrideWithValue(demoEntryLink),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<SessionStatus> settle(ProviderContainer c) async {
      c.read(sessionControllerProvider.notifier);
      for (var i = 0; i < 40; i++) {
        final SessionStatus status = c.read(sessionControllerProvider).status;
        if (status != SessionStatus.unknown) return status;
        await Future<void>.delayed(Duration.zero);
      }
      return c.read(sessionControllerProvider).status;
    }

    test('진입 표시로 왔고 저장된 토큰이 없으면 곧장 데모', () async {
      expect(await settle(container(demoEntryLink: true)), SessionStatus.demo);
    });

    test('표시가 없으면 지금처럼 로그인 화면', () async {
      expect(
        await settle(container(demoEntryLink: false)),
        SessionStatus.signedOut,
      );
    });
  });
}
