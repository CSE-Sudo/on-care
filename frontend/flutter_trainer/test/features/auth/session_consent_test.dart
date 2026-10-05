/// 트레이너 세션이 서버의 `consent_required` 를 들고 다니는 경로 — #2819.
///
/// 동의가 남은 세션은 동의를 마칠 때까지 토큰을 저장하지 않는다. 저장해 두면
/// 동의 화면에서 새로고침만 해도 복구가 동의 없이 들여보낸다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/consent_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

class _AuthRepository implements TrainerAuthRepository {
  _AuthRepository({required this.consentRequired});

  final bool consentRequired;
  List<String>? registeredConsents;

  TrainerAuthTokens _tokens(String tag) => TrainerAuthTokens(
    access: '$tag-access',
    refresh: '$tag-refresh',
    consentRequired: consentRequired,
  );

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
    required String emailCode,
    List<String>? consents,
  }) async {
    registeredConsents = consents;
    return _tokens('register');
  }

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens('social');

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async =>
      _tokens('rotated');

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      const TrainerProfile(
        name: '트레이너',
        email: 'trainer@example.com',
        phone: '',
        specialty: '',
        careerYears: null,
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

/// 동의 저장 페이크. [stillRequired] 를 돌려주거나 [error] 를 던진다.
class _ConsentRepository implements ConsentRepository {
  bool stillRequired = false;
  Object? error;
  Completer<void>? gate;
  final List<List<String>> submitted = <List<String>>[];

  @override
  Future<bool> submit(List<String> consents) async {
    submitted.add(consents);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return stillRequired;
  }
}

({
  ProviderContainer container,
  _AuthRepository auth,
  _ConsentRepository consent,
})
_make({
  bool consentRequired = true,
  Map<String, String> stored = const <String, String>{},
}) {
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.of(stored));
  final auth = _AuthRepository(consentRequired: consentRequired);
  final consent = _ConsentRepository();
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_realConfig),
      trainerAuthRepositoryProvider.overrideWithValue(auth),
      consentRepositoryProvider.overrideWithValue(consent),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, consent: consent);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

Future<String?> _storedAccess(ProviderContainer c) =>
    c.read(secureTokenStoreProvider).readAccessToken();

void main() {
  group('TrainerAuthTokens.fromJson', () {
    test('consent_required 가 참일 때만 참이다', () {
      expect(
        TrainerAuthTokens.fromJson(<String, Object?>{
          'access_token': 'a',
          'consent_required': true,
        }).consentRequired,
        isTrue,
      );
      expect(
        TrainerAuthTokens.fromJson(<String, Object?>{
          'access_token': 'a',
        }).consentRequired,
        isFalse,
        reason: '칸이 없는 옛 서버 응답',
      );
      expect(
        TrainerAuthTokens.fromJson(<String, Object?>{
          'access_token': 'a',
          'consent_required': 'true',
        }).consentRequired,
        isFalse,
      );
    });
  });

  group('동의가 남은 로그인', () {
    test('세션은 들어가되 동의 요구를 들고, 토큰은 아직 저장하지 않는다', () async {
      final m = _make();
      await _settle();

      await m.container
          .read(sessionControllerProvider.notifier)
          .login(email: 't@example.com', password: 'pw-12345678');

      final SessionState s = m.container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isTrue);
      expect(await _storedAccess(m.container), isNull);
    });

    test('앞 계정이 저장해 둔 토큰도 지운다 — 새로고침이 그 계정으로 돌아가지 않게', () async {
      final m = _make(
        stored: <String, String>{
          'access_token': 'old-access',
          'refresh_token': 'old-refresh',
        },
      );
      await _settle();

      await m.container
          .read(sessionControllerProvider.notifier)
          .login(email: 't@example.com', password: 'pw-12345678');

      expect(await _storedAccess(m.container), isNull);
    });

    test('동의를 마친 계정은 예전처럼 곧장 저장한다', () async {
      final m = _make(consentRequired: false);
      await _settle();

      await m.container
          .read(sessionControllerProvider.notifier)
          .login(email: 't@example.com', password: 'pw-12345678');

      expect(
        m.container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
      expect(await _storedAccess(m.container), 'login-access');
    });

    test('소셜 첫 로그인도 같은 규칙을 따른다', () async {
      final m = _make();
      await _settle();

      await m.container
          .read(sessionControllerProvider.notifier)
          .socialLogin(provider: 'kakao', token: 'demo-kakao-token');

      expect(
        m.container.read(sessionControllerProvider).consentRequired,
        isTrue,
      );
      expect(await _storedAccess(m.container), isNull);
    });
  });

  group('동의 저장', () {
    test('서버가 풀어 주면 그제야 토큰을 저장하고 동의 요구를 내린다', () async {
      final m = _make();
      await _settle();
      final controller = m.container.read(sessionControllerProvider.notifier);
      await controller.login(email: 't@example.com', password: 'pw-12345678');

      await controller.submitConsents(<String>['terms', 'privacy', 'age14']);

      expect(m.consent.submitted.single, <String>['terms', 'privacy', 'age14']);
      final SessionState s = m.container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isFalse);
      expect(s.profile?.name, '트레이너');
      expect(await _storedAccess(m.container), 'login-access');
    });

    test('서버가 아직 남았다고 하면 동의 요구도, 미저장도 그대로다', () async {
      final m = _make();
      await _settle();
      final controller = m.container.read(sessionControllerProvider.notifier);
      await controller.login(email: 't@example.com', password: 'pw-12345678');
      m.consent.stillRequired = true;

      await controller.submitConsents(<String>['terms', 'privacy', 'age14']);

      expect(
        m.container.read(sessionControllerProvider).consentRequired,
        isTrue,
      );
      expect(await _storedAccess(m.container), isNull);
    });

    test('실패는 던지고 상태를 바꾸지 않는다', () async {
      final m = _make();
      await _settle();
      final controller = m.container.read(sessionControllerProvider.notifier);
      await controller.login(email: 't@example.com', password: 'pw-12345678');
      m.consent.error = StateError('422');

      await expectLater(
        controller.submitConsents(<String>['terms']),
        throwsA(isA<StateError>()),
      );
      expect(
        m.container.read(sessionControllerProvider).consentRequired,
        isTrue,
      );
      expect(await _storedAccess(m.container), isNull);
    });

    test('저장하는 사이 로그아웃했다면 결과로 세션을 되살리지 않는다', () async {
      final m = _make();
      await _settle();
      final controller = m.container.read(sessionControllerProvider.notifier);
      await controller.login(email: 't@example.com', password: 'pw-12345678');
      m.consent.gate = Completer<void>();

      final Future<void> saving = controller.submitConsents(<String>[
        'terms',
        'privacy',
        'age14',
      ]);
      await controller.signOut();
      m.consent.gate!.complete();
      await saving;

      expect(
        m.container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(await _storedAccess(m.container), isNull);
    });

    test('로그아웃하면 들고 있던 토큰도 버린다 — 다음 동의가 앞 토큰을 저장하지 않는다', () async {
      final m = _make();
      await _settle();
      final controller = m.container.read(sessionControllerProvider.notifier);
      await controller.login(email: 't@example.com', password: 'pw-12345678');
      await controller.signOut();

      // 로그아웃 뒤의 저장 호출은 아무것도 되살리지 않는다.
      await controller.submitConsents(<String>['terms', 'privacy', 'age14']);

      expect(await _storedAccess(m.container), isNull);
      expect(
        m.container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
    });
  });

  test('가입은 체크한 동의를 저장소에 넘긴다', () async {
    final m = _make(consentRequired: false);
    await _settle();

    await m.container
        .read(sessionControllerProvider.notifier)
        .register(
          email: 'new@example.com',
          password: 'pw-12345678',
          name: '김신규',
          emailCode: '000000',
          consents: <String>['terms', 'privacy', 'age14'],
        );

    expect(m.auth.registeredConsents, <String>['terms', 'privacy', 'age14']);
    expect(await _storedAccess(m.container), 'register-access');
  });
}
