/// 운영 앱 `체험하기` → 데모 사이트 → 곧장 데모 진입 — #3437.
///
/// 운영 서버는 데모 폴백이 꺼져 있어 운영 빌드에서 앱 안 데모로 들어가면 화면이
/// 비었다. 운영 웹 빌드는 `DEMO_SITE_URL` 로 받은 데모 Pages 의 회원 앱으로 같은 탭을
/// 옮기고, 주소에 `?demo=1` 을 붙인다. 데모 Pages 는 그 표시를 보고 로그인 화면 대신
/// 데모로 들어간다. 데모 Pages 목업 빌드는 `DEMO_AUTO_ENTER=true` 로 표시 없이도
/// 방문마다 곧장 데모로 들어간다. 여기서는 주소 만들기·표시 읽기·기동 판단·세션
/// 복원을 고정한다.
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
          demoEntryOnLaunchProvider.overrideWithValue(demoEntryLink),
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

    test('곧장 들어간 데모에서 로그아웃하면 같은 페이지에서는 다시 들이지 않는다', () async {
      final ProviderContainer c = container(demoEntryLink: true);
      expect(await settle(c), SessionStatus.demo);

      await c.read(sessionControllerProvider.notifier).signOut();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
    });
  });

  group('곧장 데모(DEMO_AUTO_ENTER)', () {
    const AppConfig autoEnter = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'https://dev.api.test',
      useMockApi: true,
      showDemoEntry: true,
      demoBuild: true,
      demoAutoEnter: true,
    );

    test('데모 Pages 목업 빌드는 표시 없이 방문해도 곧장 데모', () {
      expect(autoEnter.autoEntersDemo, isTrue);
      expect(
        shouldEnterDemoOnLaunch(autoEnter, isWeb: true, page: _plainVisit),
        isTrue,
      );
    });

    test('데모 Pages 의 local·real 빌드는 값이 섞여 와도 로그인 화면', () {
      const AppConfig localBackend = AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'http://localhost:8000/v1',
        useMockApi: false,
        showDemoEntry: true,
        demoBuild: true,
        demoAutoEnter: true,
      );
      expect(localBackend.autoEntersDemo, isFalse);
      expect(
        shouldEnterDemoOnLaunch(localBackend, isWeb: true, page: _plainVisit),
        isFalse,
      );
      // 운영 앱의 체험하기로 왔으면 그 빌드에서도 데모로 들인다.
      expect(
        shouldEnterDemoOnLaunch(localBackend, isWeb: true, page: _arrived),
        isTrue,
      );
    });

    test('데모 빌드 표시가 없거나 웹이 아니면 따르지 않는다', () {
      const AppConfig noDemoBuild = AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
        demoAutoEnter: true,
      );
      expect(noDemoBuild.autoEntersDemo, isFalse);
      expect(
        shouldEnterDemoOnLaunch(noDemoBuild, isWeb: true, page: _plainVisit),
        isFalse,
      );
      expect(
        shouldEnterDemoOnLaunch(autoEnter, isWeb: false, page: _plainVisit),
        isFalse,
      );
    });
  });
}
