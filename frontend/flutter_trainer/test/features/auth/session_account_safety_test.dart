/// 세션이 다른 계정·다른 기기와 엇갈릴 때의 규칙.
///
///  * #2764 — 같은 브라우저의 다른 탭이 다른 트레이너로 다시 로그인하면 저장소의
///    갱신 토큰은 그 계정의 것이다. 이 탭이 401 뒤 회전하면 남의 토큰을 받게 되므로,
///    주인을 확인하고 다르면 채택하지 않고 이 탭만 로그인 화면으로 보낸다.
///  * #2765 — 직접 로그아웃은 [signedOutByUserProvider] 를 켜고, 새 세션·만료는 끈다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/session_refresh.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const String _coachA = 'coach-a@oncare.test';
const String _coachB = 'coach-b@oncare.test';

/// 접근 토큰마다 주인이 정해진 인증 저장소.
///
/// 갱신은 받은 갱신 토큰의 접두어(`a`/`b`)로 그 계정의 새 쌍을 만든다 — 서버가
/// 갱신 토큰의 주인 명의로 새 토큰을 발급하는 것과 같다.
class _AccountsAuthRepository implements TrainerAuthRepository {
  /// 프로필 조회가 연결 실패로 끝나게 할 접근 토큰들.
  final Set<String> unreachable = <String>{};

  /// 트레이너가 아닌 계정의 접근 토큰들.
  final Set<String> notTrainer = <String>{};

  /// 이메일을 대문자·앞뒤 공백 섞어 돌려줄 접근 토큰들.
  final Set<String> loud = <String>{};

  final List<String> refreshed = <String>[];
  final List<String> loggedOut = <String>[];
  int _rotation = 0;

  static String _ownerOf(String token) =>
      token.startsWith('b') ? _coachB : _coachA;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async {
    refreshed.add(refreshToken);
    _rotation++;
    final String who = refreshToken.startsWith('b') ? 'b' : 'a';
    return TrainerAuthTokens(
      access: '$who-access-$_rotation',
      refresh: '$who-refresh-$_rotation',
    );
  }

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    if (unreachable.contains(accessToken)) {
      throw const NetworkError(message: 'offline');
    }
    if (notTrainer.contains(accessToken)) throw const NotTrainerException();
    final String email = _ownerOf(accessToken);
    return seedTrainerProfile.copyWith(
      email: loud.contains(accessToken) ? ' ${email.toUpperCase()} ' : email,
    );
  }

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => const TrainerAuthTokens(access: 'a-login', refresh: 'a-r-login');

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
  }) async => const TrainerAuthTokens(access: 'a-reg', refresh: 'a-r-reg');

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => const TrainerAuthTokens(access: 'a-social', refresh: 'a-r-soc');

  @override
  Future<void> logout(String refreshToken) async {
    loggedOut.add(refreshToken);
  }
}

class _Harness {
  _Harness(this.container, this.repo);

  final ProviderContainer container;
  final _AccountsAuthRepository repo;

  SessionController get controller =>
      container.read(sessionControllerProvider.notifier);
  SessionState get state => container.read(sessionControllerProvider);
  String? get access => container.read(authAccessTokenProvider);
  bool get notice => container.read(sessionExpiredNoticeProvider);
  bool get signedOutByUser => container.read(signedOutByUserProvider);
  SecureTokenStore get store => container.read(secureTokenStoreProvider);
}

/// 계정 A 로 로그인해 둔 탭 하나.
Future<_Harness> _signedInAsA({
  String access = 'a-access-0',
  String refresh = 'a-refresh-0',
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'access_token': access,
    'refresh_token': refresh,
  });
  final repo = _AccountsAuthRepository();
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      trainerAuthRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  final h = _Harness(container, repo);
  h.controller;
  await _settle();
  expect(h.state.status, SessionStatus.authenticated);
  expect(h.state.profile?.email, _coachA);
  return h;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('#2764 — 회전 결과의 주인 확인', () {
    test('다른 탭이 다른 계정으로 로그인했으면 그 토큰을 채택하지 않는다', () async {
      final h = await _signedInAsA();
      // 다른 탭이 B 로 다시 로그인했다 — 같은 출처라 저장소를 같이 쓴다.
      await h.store.saveTokens(access: 'b-access-x', refresh: 'b-refresh-x');

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(h.repo.refreshed, <String>['b-refresh-x']);
      expect(result.status, TokenRefreshStatus.rejected);
      expect(result.accessToken, isNull);
      // 이 탭만 로그인 화면으로 — 만료 안내와 함께, 원래 자리를 잇는 쪽으로.
      expect(h.state.status, SessionStatus.signedOut);
      expect(h.access, isNull);
      expect(h.notice, isTrue);
      expect(h.signedOutByUser, isFalse);
    });

    test('남의 회전 결과는 저장소에 남겨 다른 탭이 끊기지 않는다', () async {
      final h = await _signedInAsA();
      await h.store.saveTokens(access: 'b-access-x', refresh: 'b-refresh-x');

      await h.controller.refreshAfterUnauthorized('a-access-0');

      // 갱신 토큰은 일회용이다 — 방금 쓴 b-refresh-x 는 서버에서 폐기됐으니
      // 회전 결과가 저장소에 있어야 B 탭이 다음 회전을 할 수 있다.
      expect(await h.store.readAccessToken(), 'b-access-1');
      expect(await h.store.readRefreshToken(), 'b-refresh-1');
      // B 의 세션을 서버에서 폐기하지도 않는다.
      expect(h.repo.loggedOut, isEmpty);
    });

    test('같은 계정이면 지금처럼 채택한다', () async {
      final h = await _signedInAsA();

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(result.status, TokenRefreshStatus.refreshed);
      expect(result.accessToken, 'a-access-1');
      expect(h.access, 'a-access-1');
      expect(h.state.status, SessionStatus.authenticated);
      expect(await h.store.readRefreshToken(), 'a-refresh-1');
      expect(h.notice, isFalse);
    });

    test('이메일의 대소문자·공백 차이는 같은 계정이다', () async {
      final h = await _signedInAsA();
      h.repo.loud.add('a-access-1');

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(result.status, TokenRefreshStatus.refreshed);
      expect(h.access, 'a-access-1');
    });

    test('확인이 연결 실패로 끝나면 채택도 로그아웃도 하지 않는다', () async {
      final h = await _signedInAsA();
      h.repo.unreachable.add('a-access-1');

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(result.status, TokenRefreshStatus.unavailable);
      expect(h.state.status, SessionStatus.authenticated);
      expect(h.access, 'a-access-0');
      expect(h.notice, isFalse);
      // 회전 결과는 저장돼 다음 401 에서 그것으로 다시 회전한다.
      expect(await h.store.readRefreshToken(), 'a-refresh-1');
    });

    test('트레이너가 아닌 계정의 토큰이면 다른 계정으로 본다', () async {
      final h = await _signedInAsA();
      await h.store.saveTokens(access: 'b-access-x', refresh: 'b-refresh-x');
      h.repo.notTrainer.add('b-access-1');

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(result.status, TokenRefreshStatus.rejected);
      expect(h.state.status, SessionStatus.signedOut);
      expect(h.notice, isTrue);
    });
  });

  group('#2765 — 직접 로그아웃 표시', () {
    test('직접 로그아웃하면 켜지고, 다시 로그인하면 꺼진다', () async {
      final h = await _signedInAsA();
      expect(h.signedOutByUser, isFalse);

      await h.controller.signOut();
      expect(h.state.status, SessionStatus.signedOut);
      expect(h.signedOutByUser, isTrue);

      await h.controller.login(email: _coachA, password: 'pw-12345');
      await _settle();
      expect(h.state.status, SessionStatus.authenticated);
      expect(h.signedOutByUser, isFalse);
    });

    test('데모로 들어가도 꺼진다', () async {
      final h = await _signedInAsA();
      await h.controller.signOut();
      expect(h.signedOutByUser, isTrue);

      h.controller.enterDemo();
      expect(h.state.status, SessionStatus.demo);
      expect(h.signedOutByUser, isFalse);
    });

    test('만료로 끝난 세션은 직접 로그아웃이 아니다', () async {
      final h = await _signedInAsA(refresh: '');

      final TokenRefreshResult result = await h.controller
          .refreshAfterUnauthorized('a-access-0');

      expect(result.status, TokenRefreshStatus.rejected);
      expect(h.state.status, SessionStatus.signedOut);
      expect(h.signedOutByUser, isFalse);
    });
  });
}
