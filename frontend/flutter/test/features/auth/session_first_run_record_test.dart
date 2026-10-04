/// 첫 설정 기기 기록은 지금 세션 계정의 것이다. (#2630)
///
/// `onboarding_done` 은 프로필을 못 받아 왔을 때 "이미 끝낸 회원" 으로 보는
/// 보조 기록인데, 기기 전체에 하나로 남아 탈퇴 말고는 지우는 곳이 없었다.
/// 회원 A 가 로그아웃하고 새 회원 B 가 로그인했는데 프로필 조회가 실패하면,
/// A 의 기록을 보고 첫 설정을 안 한 B 도 홈으로 갔다.
///
/// 여기서는 세션 컨트롤러가 계정 경계(로그인·로그아웃·만료)에서 그 기록을
/// 지우고, 같은 토큰으로 되살아나는 복구에서는 남기는지를 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 첫 설정과 홈 가이드를 모두 끝낸 기기. 언어도 골라 두었다.
  Future<SharedPreferences> seenDevice() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_done': true,
      'home_guide_done': true,
      'locale_code': 'ko',
    });
    return SharedPreferences.getInstance();
  }

  Future<(ProviderContainer, AppPrefs)> start({
    required Map<String, int> statusByPath,
  }) async {
    final SharedPreferences shared = await seenDevice();
    final Dio dio = _scriptedDio(statusByPath);
    addTearDown(dio.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(shared),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionControllerProvider.notifier);
    return (container, container.read(appPrefsProvider));
  }

  group('계정 경계에서 지운다', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('새로 로그인하면 앞 계정의 첫 설정 기록을 넘기지 않는다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/auth/login': 200},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.signedOut,
      );
      expect(prefs.onboardingDone, isTrue);

      await container
          .read(sessionControllerProvider.notifier)
          .login(email: 'next@oncare.com', password: 'password');

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(prefs.onboardingDone, isFalse);
    });

    test('로그아웃하면 지운다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.signedOut,
      );

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(prefs.onboardingDone, isFalse);
    });

    test('로그아웃은 홈 가이드 기록도 지우고, 언어는 남긴다 (#3154)', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.signedOut,
      );

      await container.read(sessionControllerProvider.notifier).signOut();

      // 다음에 들어올 계정이 같은 사람이라는 보장이 없다 — 첫 사용 안내를
      // 앞 계정 기록 때문에 건너뛰지 않게 한다.
      expect(prefs.homeGuideDone, isFalse);
      expect(prefs.localeCode, 'ko');
    });

    test('데모 진입은 계정이 아니라 기록을 건드리지 않는다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.signedOut,
      );

      container.read(sessionControllerProvider.notifier).enterDemo();

      expect(prefs.onboardingDone, isTrue);
    });
  });

  group('세션 복구', () {
    setUp(() {
      // 갱신 토큰이 없다 — 접근 토큰이 거부되면 곧바로 만료다.
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
      });
    });

    test('같은 토큰으로 되살아나면 기록을 이어 쓴다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 200},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.authenticated,
      );

      expect(prefs.onboardingDone, isTrue);
    });

    test('저장된 세션이 만료로 끝나면 지운다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 401},
      );
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.signedOut,
      );

      expect(prefs.onboardingDone, isFalse);
    });

    test('일시적 실패는 세션의 끝이 아니다 — 기록을 남긴다', () async {
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 503},
      );
      await _waitFor(
        () => container.read(sessionControllerProvider).restoreFailed,
      );

      expect(prefs.onboardingDone, isTrue);
    });
  });

  test('설정 저장소가 없어도 로그인은 막히지 않는다', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final Dio dio = _scriptedDio(<String, int>{'/auth/login': 200});
    addTearDown(dio.close);
    // sharedPreferencesProvider 를 주지 않는다 — 읽으면 예외다.
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[dioProvider.overrideWithValue(dio)],
    );
    addTearDown(container.dispose);
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    await _waitFor(
      () =>
          container.read(sessionControllerProvider).status ==
          SessionStatus.signedOut,
    );

    await controller.login(email: 'member@oncare.com', password: 'password');

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });
}

/// 경로별 상태 코드로 답한다. 적지 않은 경로는 404. 200 이면 토큰 한 벌을 준다.
Dio _scriptedDio(Map<String, int> statusByPath) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final int status = statusByPath[options.path] ?? 404;
        if (status >= 400) {
          handler.reject(
            DioException.badResponse(
              statusCode: status,
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: status,
              ),
            ),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: status,
            data: <String, Object?>{
              'access_token': 'next-access',
              'refresh_token': 'next-refresh',
            },
          ),
        );
      },
    ),
  );
  return dio;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (condition()) {
      // 상태가 바뀐 뒤 남은 저장소 정리가 끝나도록 몇 틱 더 기다린다.
      for (var tick = 0; tick < 5; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('조건이 채워지지 않았다');
}
