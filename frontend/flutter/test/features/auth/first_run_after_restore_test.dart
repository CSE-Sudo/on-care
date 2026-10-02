/// 세션 복구 뒤에도 첫 설정을 묻는다. (#2630)
///
/// #1927 은 "로그인·세션 복구 뒤" 첫 설정 여부를 보라고 했지만 연결된 것은
/// 로그인 화면뿐이었다. 가입 직후 첫 설정 폼에서 앱을 닫은 회원은 다시 켜면
/// 시작 화면 → 홈으로 곧장 가 빈 프로필로 남았다.
///
/// 여기서 고정하는 성질은 셋이다.
///
///  * 복구 전이(`unknown` → `authenticated`)만 골라낸다 — 로그인·데모는 아니다.
///  * 첫 설정이 남은 계정만 옮기고, 판단 사이 세션이 바뀌었으면 옮기지 않는다.
///  * 라우터 provider 가 실제 복구에 이 규칙을 붙인다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/first_run_route.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const UserProfile _done = UserProfile(
  id: 'u1',
  onboarded: true,
  name: '김민수',
  email: 'minsu@oncare.com',
  birthDate: '1990-01-01',
  gender: 'male',
);

const UserProfile _notDone = UserProfile(
  id: 'u2',
  name: '',
  email: 'new@oncare.com',
);

/// 첫 설정을 건너뛴 계정(#2855).
const UserProfile _skipped = UserProfile(
  id: 'u3',
  onboardingSkipped: true,
  name: '',
  email: 'skip@oncare.com',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Override> prefs({required bool seen}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (seen) 'onboarding_done': true,
    });
    return sharedPreferencesProvider.overrideWithValue(
      await SharedPreferences.getInstance(),
    );
  }

  ProviderContainer containerWith(List<Override> overrides) {
    final ProviderContainer container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  group('isSessionRestore', () {
    test('시작 화면에서 곧장 로그인 상태가 되면 복구다', () {
      expect(
        isSessionRestore(SessionStatus.unknown, SessionStatus.authenticated),
        isTrue,
      );
    });

    test('로그인 화면에서 들어온 것은 복구가 아니다 — 로그인 화면이 맡는다', () {
      expect(
        isSessionRestore(SessionStatus.signedOut, SessionStatus.authenticated),
        isFalse,
      );
    });

    test('데모는 계정이 없어 묻지 않는다', () {
      expect(
        isSessionRestore(SessionStatus.unknown, SessionStatus.demo),
        isFalse,
      );
      expect(
        isSessionRestore(SessionStatus.signedOut, SessionStatus.demo),
        isFalse,
      );
    });

    test('복구 실패·로그아웃·같은 상태 반복은 복구가 아니다', () {
      expect(
        isSessionRestore(SessionStatus.unknown, SessionStatus.unknown),
        isFalse,
      );
      expect(
        isSessionRestore(SessionStatus.unknown, SessionStatus.signedOut),
        isFalse,
      );
      expect(
        isSessionRestore(
          SessionStatus.authenticated,
          SessionStatus.authenticated,
        ),
        isFalse,
      );
      expect(isSessionRestore(null, SessionStatus.authenticated), isFalse);
    });
  });

  group('firstRunRoute', () {
    test('첫 설정을 안 한 계정은 첫 설정으로', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ]);
      expect(await firstRunRoute(container.read), AppRoutes.onboarding);
    });

    test('끝낸 계정은 홈으로 가고 이 기기에 기록을 남긴다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_done)),
      ]);
      expect(await firstRunRoute(container.read), AppRoutes.dashboard);
      expect(container.read(appPrefsProvider).onboardingDone, isTrue);
    });

    test('로그인 화면 판단과 같은 답을 낸다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ]);
      expect(
        await firstRouteAfterSignIn(container),
        await firstRunRoute(container.read),
      );
    });
  });

  group('openFirstRunAfterRestore', () {
    test('첫 설정이 남은 계정은 첫 설정으로 옮긴다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => true,
      );
      expect(moves, <String>[AppRoutes.onboarding]);
    });

    test('끝낸 계정은 옮기지 않는다 — 가드가 세운 홈을 다시 세우지 않는다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_done)),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => true,
      );
      expect(moves, isEmpty);
    });

    test('첫 설정을 건너뛴 계정은 앱을 다시 켜도 옮기지 않는다 (#2855)', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_skipped)),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => true,
      );
      expect(moves, isEmpty);
    });

    test('판단하는 사이 세션이 바뀌었으면 옮기지 않는다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => false,
      );
      expect(moves, isEmpty);
    });

    test('프로필을 못 받아 왔고 기기 기록도 없으면 첫 설정으로', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(_FailingProfile.new),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => true,
      );
      expect(moves, <String>[AppRoutes.onboarding]);
    });

    test('프로필을 못 받아 와도 이 세션 계정의 기록이 있으면 홈에 둔다', () async {
      final ProviderContainer container = containerWith(<Override>[
        await prefs(seen: true),
        profileProvider.overrideWith(_FailingProfile.new),
      ]);
      final List<String> moves = <String>[];
      await openFirstRunAfterRestore(
        read: container.read,
        go: moves.add,
        stillSameSession: () => true,
      );
      expect(moves, isEmpty);
    });
  });

  group('라우터 provider 연결', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      });
    });

    Future<GoRouter> restoreWith(UserProfile profile) async {
      final Dio dio = _okDio();
      addTearDown(dio.close);
      final ProviderContainer container = containerWith(<Override>[
        appConfigProvider.overrideWithValue(_config),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        dioProvider.overrideWithValue(dio),
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(profile)),
      ]);
      final GoRouter router = container.read(appRouterProvider);
      await _waitFor(
        () =>
            container.read(sessionControllerProvider).status ==
            SessionStatus.authenticated,
      );
      // 복구가 끝난 뒤 프로필을 읽고 옮기는 일은 비동기로 이어진다.
      for (var tick = 0; tick < 10; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      return router;
    }

    test('첫 설정을 안 한 계정의 세션이 복구되면 첫 설정으로 옮긴다', () async {
      final GoRouter router = await restoreWith(_notDone);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.onboarding,
      );
    });

    test('첫 설정을 끝낸 계정의 세션 복구는 옮기지 않는다', () async {
      final GoRouter router = await restoreWith(_done);
      expect(
        router.routeInformationProvider.value.uri.path,
        isNot(AppRoutes.onboarding),
      );
    });
  });
}

/// `/users/me` 를 포함해 모든 요청에 200 으로 답한다 — 복구 확인만 통과시킨다.
Dio _okDio() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: <String, Object?>{'id': 'u1'},
          ),
        );
      },
    ),
  );
  return dio;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('조건이 채워지지 않았다');
}

class _StubProfile extends ProfileController {
  _StubProfile(this._value);

  final UserProfile _value;

  @override
  Future<UserProfile> build() async => _value;
}

class _FailingProfile extends ProfileController {
  @override
  Future<UserProfile> build() async => throw Exception('offline');
}
