import 'dart:async';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

const _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

/// Builds a container wired to fresh mock secure storage (in mock-API
/// mode) plus an optional [repoOverride] to inject a fake auth repository.
ProviderContainer _makeContainer({
  Map<String, String> tokens = const <String, String>{},
  Override? repoOverride,
  Override? tokenStoreOverride,
}) {
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.of(tokens));
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_mockConfig),
      ?repoOverride,
      ?tokenStoreOverride,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Lets the async restore / login microtask chain settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('SessionController restore', () {
    test('signed out when no token is persisted', () async {
      final container = _makeContainer();
      container.read(sessionControllerProvider.notifier);
      await _settle();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.signedOut);
      expect(state.profile, isNull);
    });

    test('authenticated with profile when a token is persisted', () async {
      final container = _makeContainer(
        tokens: <String, String>{'access_token': 'demo-existing'},
      );
      container.read(sessionControllerProvider.notifier);
      await _settle();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.authenticated);
      expect(state.profile?.name, kDemoTrainerName);
      expect(state.profile?.email, 'trainer@oncare.com');
    });

    test('rotates tokens when the access token is expired (401)', () async {
      final fake = _FakeAuthRepository()
        ..profileFailuresBeforeSuccess = 1; // first fetch 401, then ok
      final container = _makeContainer(
        tokens: <String, String>{
          'access_token': 'stale',
          'refresh_token': 'good-refresh',
        },
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle();

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(fake.refreshCalls, 1);
      // The rotated access token is now persisted.
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        'rotated-access',
      );
    });

    test(
      'a user action during restore is not clobbered by the late restore',
      () async {
        // Restore is in flight against a slow /me; the user picks demo before
        // it resolves. The late restore must not overwrite the demo session.
        final fake = _FakeAuthRepository()
          ..profileDelay = const Duration(milliseconds: 200);
        final container = _makeContainer(
          tokens: <String, String>{
            'access_token': 'stored',
            'refresh_token': 'r',
          },
          repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
        );
        final controller = container.read(sessionControllerProvider.notifier);

        // Do NOT settle — restore is still awaiting the token read + slow /me.
        controller.enterDemo();
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.demo,
        );

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.demo,
        );
      },
    );

    test('signs out when refresh also fails', () async {
      final fake = _FakeAuthRepository()
        ..profileFailuresBeforeSuccess = 1
        ..refreshThrows = true;
      final container = _makeContainer(
        tokens: <String, String>{
          'access_token': 'stale',
          'refresh_token': 'bad-refresh',
        },
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle();

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        isNull,
      );
    });

    // 갱신 요청 자체가 실패하는 갈래 — 예전에는 원인을 가리지 않고 만료로 처리해
    // 저장 토큰을 지웠다. 확인 요청과 같은 기준(명시적 거부만 만료)을 쓴다. (#641)
    for (final (String, AuthFailure) row in <(String, AuthFailure)>[
      ('연결 실패', AuthFailure.network),
      ('응답 본문 없음', AuthFailure.emptyResponse),
      ('알 수 없는 전송 실패', AuthFailure.unknown),
    ]) {
      final String name = row.$1;
      final AuthFailure failure = row.$2;
      test('갱신이 $name 로 끝나면 저장 토큰을 지우지 않는다', () async {
        final fake = _FakeAuthRepository()
          ..profileFailuresBeforeSuccess = 1
          ..refreshThrows = true
          ..refreshFailure = failure;
        final container = _makeContainer(
          tokens: <String, String>{
            'access_token': 'stale',
            'refresh_token': 'valid-refresh',
          },
          repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
        );
        container.read(sessionControllerProvider.notifier);
        await _settle();

        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.signedOut,
        );
        // 접근 토큰이 만료됐어도 갱신이 **거부된 것은 아니다.** 지우면 잠깐 끊긴
        // 사용자에게 재로그인을 요구하게 된다.
        final store = container.read(secureTokenStoreProvider);
        expect(await store.readAccessToken(), 'stale');
        expect(await store.readRefreshToken(), 'valid-refresh');
      });
    }

    test(
      'keeps the stored tokens on a transient network failure at restore',
      () async {
        final fake = _FakeAuthRepository()..profileThrowsNetwork = true;
        final container = _makeContainer(
          tokens: <String, String>{
            'access_token': 'valid',
            'refresh_token': 'valid-refresh',
          },
          repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
        );
        container.read(sessionControllerProvider.notifier);
        await _settle();

        // Transient failure → signed out, but the tokens survive so a later
        // relaunch can restore (not a forced sign-out that discards a valid
        // session).
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.signedOut,
        );
        final store = container.read(secureTokenStoreProvider);
        expect(await store.readAccessToken(), 'valid');
        expect(await store.readRefreshToken(), 'valid-refresh');
      },
    );

    test(
      'refresh keeps the existing refresh token when the response omits one',
      () async {
        final fake = _FakeAuthRepository()
          ..profileFailuresBeforeSuccess =
              1 // first fetch 401 → triggers refresh
          ..refreshReturnsEmptyRefresh = true;
        final container = _makeContainer(
          tokens: <String, String>{
            'access_token': 'stale',
            'refresh_token': 'keep-me',
          },
          repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
        );
        container.read(sessionControllerProvider.notifier);
        await _settle();

        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );
        final store = container.read(secureTokenStoreProvider);
        expect(await store.readAccessToken(), 'rotated-access');
        // Backend rotated only the access token → the old refresh is preserved.
        expect(await store.readRefreshToken(), 'keep-me');
      },
    );

    test('a user action during a slow refresh is not clobbered', () async {
      // stale access → 401 → refresh (slow); the user picks demo mid-refresh.
      final fake = _FakeAuthRepository()
        ..profileFailuresBeforeSuccess = 1
        ..refreshDelay = const Duration(milliseconds: 200);
      final container = _makeContainer(
        tokens: <String, String>{'access_token': 'stale', 'refresh_token': 'r'},
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
      );
      final controller = container.read(sessionControllerProvider.notifier);

      // Wait for the signal that refresh is GENUINELY in flight (not a timing
      // guess), then act — this guarantees the race the guard must win.
      await fake.onRefreshEntered.future;
      controller.enterDemo();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.demo,
      );

      // The late refresh resolves — it must NOT overwrite the demo session.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.demo,
      );
      expect(fake.refreshCalls, 1);
    });

    test('sign-out wins over an in-flight refresh token save', () async {
      final fake = _FakeAuthRepository()..profileFailuresBeforeSuccess = 1;
      final store = _BlockingTokenStore(<String, String>{
        'access_token': 'stale',
        'refresh_token': 'r',
      });
      final container = _makeContainer(
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
        tokenStoreOverride: secureTokenStoreProvider.overrideWithValue(store),
      );
      final controller = container.read(sessionControllerProvider.notifier);

      await fake.onRefreshEntered.future;
      await store.onSaveEntered.future;

      // The rotated-token save is paused. Sign-out must queue its clear after
      // that save so the late write cannot resurrect credentials on disk.
      final signOut = controller.signOut();
      store.releaseSave.complete();
      await store.onSaveFinished.future;
      await signOut;

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(fake.refreshCalls, 1);
    });
  });

  group('SessionController login', () {
    test('authenticates and persists tokens', () async {
      final container = _makeContainer();
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();

      await controller.login(email: 'trainer@oncare.com', password: 'pw');

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.authenticated);
      expect(state.profile, isNotNull);
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        isNotNull,
      );
    });

    test('empty credentials throw and stay signed out', () async {
      final container = _makeContainer();
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();

      await expectLater(
        controller.login(email: '   ', password: ''),
        throwsA(isA<AuthException>()),
      );
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
    });

    test('rejects a non-trainer account and clears tokens', () async {
      final fake = _FakeAuthRepository()..profileThrowsNotTrainer = true;
      final container = _makeContainer(
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(fake),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();

      await expectLater(
        controller.login(email: 'member@oncare.com', password: 'pw'),
        throwsA(isA<NotTrainerException>()),
      );
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        isNull,
      );
    });
  });

  group('SessionController demo & sign-out', () {
    test('enterDemo grants access without persisting a token', () async {
      final container = _makeContainer();
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();

      controller.enterDemo();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.demo);
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        isNull,
      );
    });

    test(
      'replaceProfile updates demo data without changing demo status',
      () async {
        final container = _makeContainer();
        final controller = container.read(sessionControllerProvider.notifier);
        await _settle();
        controller.enterDemo();
        final changed = seedTrainerProfile.copyWith(phone: '010-9999-0000');

        controller.replaceProfile(changed);

        final state = container.read(sessionControllerProvider);
        expect(state.status, SessionStatus.demo);
        expect(state.profile?.phone, '010-9999-0000');
      },
    );

    test('signOut revokes the stored refresh token server-side', () async {
      // 로컬 저장소만 지우면 그 갱신 토큰은 만료까지 살아 있다 — 새어 나갔다면
      // 로그아웃을 눌러도 세션이 그대로다(#966).
      final repo = _FakeAuthRepository();
      final container = _makeContainer(
        tokens: <String, String>{
          'access_token': 'stored-access',
          'refresh_token': 'stored-refresh',
        },
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(repo),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle();

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(repo.logoutTokens, <String>['stored-refresh']);
    });

    test('signOut completes even when the revoke call fails', () async {
      final repo = _FakeAuthRepository()..logoutThrows = true;
      final container = _makeContainer(
        tokens: <String, String>{
          'access_token': 'stored-access',
          'refresh_token': 'stored-refresh',
        },
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(repo),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle();

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(repo.logoutTokens, <String>['stored-refresh']);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(
        await container.read(secureTokenStoreProvider).readRefreshToken(),
        isNull,
      );
    });

    test('signOut without a stored refresh token skips the revoke', () async {
      // 데모 세션에는 저장된 토큰이 없다 — 끊을 서버 세션도 없다.
      final repo = _FakeAuthRepository();
      final container = _makeContainer(
        repoOverride: trainerAuthRepositoryProvider.overrideWithValue(repo),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();
      controller.enterDemo();

      await controller.signOut();

      expect(repo.logoutTokens, isEmpty);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
    });

    test('signOut clears tokens and returns to signed out', () async {
      final container = _makeContainer();
      final controller = container.read(sessionControllerProvider.notifier);
      await _settle();
      await controller.login(email: 'trainer@oncare.com', password: 'pw');
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );

      await controller.signOut();

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(
        await container.read(secureTokenStoreProvider).readAccessToken(),
        isNull,
      );
    });
  });
}

/// A configurable fake for controller-level tests (role gate, refresh).
class _FakeAuthRepository implements TrainerAuthRepository {
  int profileFailuresBeforeSuccess = 0;
  bool profileThrowsNotTrainer = false;
  bool profileThrowsNetwork = false;
  bool refreshThrows = false;

  /// `refreshThrows` 일 때 던질 실패 코드. 기본은 실제 만료.
  AuthFailure refreshFailure = AuthFailure.sessionExpired;
  bool refreshReturnsEmptyRefresh = false;
  Duration profileDelay = Duration.zero;
  Duration refreshDelay = Duration.zero;

  /// Completes the moment `refresh()` is entered (before its delay), so a
  /// test can deterministically act while a refresh is genuinely in flight.
  final Completer<void> onRefreshEntered = Completer<void>();
  int refreshCalls = 0;
  int _profileCalls = 0;

  /// `logout()` 이 받은 갱신 토큰들. 로그아웃이 서버 폐기를 부르는지 본다(#966).
  final List<String> logoutTokens = <String>[];
  bool logoutThrows = false;

  TrainerAuthTokens _tokens(String tag) =>
      TrainerAuthTokens(access: '$tag-access', refresh: '$tag-refresh');

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens('login');

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String inviteCode,
  }) async => _tokens('register');

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens('social');

  @override
  Future<void> logout(String refreshToken) async {
    logoutTokens.add(refreshToken);
    if (logoutThrows) throw const AuthException(AuthFailure.network);
  }

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async {
    refreshCalls++;
    if (!onRefreshEntered.isCompleted) onRefreshEntered.complete();
    if (refreshDelay > Duration.zero) await Future<void>.delayed(refreshDelay);
    if (refreshThrows) throw AuthException(refreshFailure);
    return TrainerAuthTokens(
      access: 'rotated-access',
      refresh: refreshReturnsEmptyRefresh ? '' : 'rotated-refresh',
    );
  }

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    _profileCalls++;
    if (profileDelay > Duration.zero) await Future<void>.delayed(profileDelay);
    if (profileThrowsNotTrainer) throw const NotTrainerException();
    if (profileThrowsNetwork) throw const NetworkError(message: 'net down');
    if (_profileCalls <= profileFailuresBeforeSuccess) {
      throw const UnauthorizedError(message: '401');
    }
    return seedTrainerProfile;
  }
}

/// Secure-token fake that pauses one save after it has entered storage.
/// Without serialized save/clear mutations, sign-out can clear first and this
/// late save will put the rotated credentials back on disk.
class _BlockingTokenStore extends SecureTokenStore {
  _BlockingTokenStore(Map<String, String> initialValues)
    : _values = Map<String, String>.of(initialValues),
      super(const FlutterSecureStorage());

  final Map<String, String> _values;
  final Completer<void> onSaveEntered = Completer<void>();
  final Completer<void> releaseSave = Completer<void>();
  final Completer<void> onSaveFinished = Completer<void>();

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    onSaveEntered.complete();
    await releaseSave.future;
    _values['access_token'] = access;
    _values['refresh_token'] = refresh;
    onSaveFinished.complete();
  }

  @override
  Future<String?> readAccessToken() async => _values['access_token'];

  @override
  Future<String?> readRefreshToken() async => _values['refresh_token'];

  @override
  Future<void> clear() async => _values.clear();
}
