import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 로그인한 채로 승인 상태를 다시 읽는다 (#3010).
///
/// 운영자가 승인·반려하면 서버의 `/trainer/me` 가 바뀐다. 전에는 로그인할 때 받은
/// 프로필을 끝까지 들고 있어, 다시 로그인해야 배너가 바뀌었다.
const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const TrainerProfile _base = TrainerProfile(
  name: '승인 트레이너',
  email: 'coach@oncare.com',
  phone: '',
  specialty: '',
  careerYears: 3,
  intro: '',
  certifications: <String>[],
  gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
  verification: TrainerVerification(status: TrainerVerificationStatus.pending),
);

class _Repo implements TrainerAuthRepository {
  _Repo(this.profile);

  TrainerProfile profile;
  int profileCalls = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    profileCalls++;
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    if (fail) throw const NetworkError(message: 'offline');
    return profile;
  }

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => const TrainerAuthTokens(access: 'a', refresh: 'r');

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    List<String>? consents,
  }) async => const TrainerAuthTokens(access: 'a', refresh: 'r');

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => const TrainerAuthTokens(access: 'a', refresh: 'r');

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async =>
      const TrainerAuthTokens(access: 'a2', refresh: 'r2');

  @override
  Future<void> logout(String refreshToken) async {}
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

Future<(ProviderContainer, _Repo)> _signedIn() async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'access_token': 'stored',
    'refresh_token': 'stored-r',
  });
  final _Repo repo = _Repo(_base);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      trainerAuthRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionControllerProvider.notifier);
  await _settle();
  expect(
    container.read(sessionControllerProvider).status,
    SessionStatus.authenticated,
  );
  return (container, repo);
}

void main() {
  test('승인되면 다시 로그인하지 않아도 프로필이 승인으로 바뀐다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    repo.profile = _base.copyWith(
      verification: TrainerVerification.approved,
      isAdmin: true,
    );

    await container.read(sessionControllerProvider.notifier).refreshProfile();

    final TrainerProfile? profile = container
        .read(sessionControllerProvider)
        .profile;
    expect(profile?.verification.isApproved, isTrue);
    expect(profile?.isAdmin, isTrue);
  });

  test('반려 사유도 함께 들어온다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    repo.profile = _base.copyWith(
      verification: const TrainerVerification(
        status: TrainerVerificationStatus.rejected,
        note: '서류 보완',
      ),
    );

    await container.read(sessionControllerProvider.notifier).refreshProfile();

    final TrainerVerification? v = container
        .read(sessionControllerProvider)
        .profile
        ?.verification;
    expect(v?.status, TrainerVerificationStatus.rejected);
    expect(v?.note, '서류 보완');
  });

  test('계정 경계가 아니라 계정 범위 provider 를 다시 만들지 않는다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    final int scope = container.read(accountScopeProvider);
    repo.profile = _base.copyWith(verification: TrainerVerification.approved);

    await container.read(sessionControllerProvider.notifier).refreshProfile();

    expect(container.read(accountScopeProvider), scope);
  });

  test('읽기 실패는 조용히 넘기고 들고 있던 프로필을 둔다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    repo.fail = true;

    await container.read(sessionControllerProvider.notifier).refreshProfile();

    final SessionState state = container.read(sessionControllerProvider);
    expect(state.status, SessionStatus.authenticated);
    expect(
      state.profile?.verification.status,
      TrainerVerificationStatus.pending,
    );
  });

  test('겹친 신호는 한 번만 읽는다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    final int before = repo.profileCalls;
    repo.gate = Completer<void>();
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );

    final Future<void> first = controller.refreshProfile();
    final Future<void> second = controller.refreshProfile();
    repo.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(repo.profileCalls - before, 1);
  });

  test('다른 계정의 프로필이 오면 버린다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    repo.profile = _base.copyWith(
      email: 'other@oncare.com',
      verification: TrainerVerification.approved,
    );

    await container.read(sessionControllerProvider.notifier).refreshProfile();

    expect(
      container.read(sessionControllerProvider).profile?.email,
      'coach@oncare.com',
    );
  });

  test('읽는 사이 로그아웃했으면 결과를 버린다', () async {
    final (ProviderContainer container, _Repo repo) = await _signedIn();
    repo
      ..gate = Completer<void>()
      ..profile = _base.copyWith(verification: TrainerVerification.approved);
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );

    final Future<void> pending = controller.refreshProfile();
    await controller.signOut();
    repo.gate!.complete();
    await pending;

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
  });

  test('데모 세션에서는 아무것도 읽지 않는다', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final _Repo repo = _Repo(_base);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        trainerAuthRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    await _settle();
    controller.enterDemo();
    final int before = repo.profileCalls;

    await controller.refreshProfile();

    expect(repo.profileCalls, before);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.demo,
    );
  });
}
