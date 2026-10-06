import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/core/storage/token_session_storage.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 트레이너 웹의 세션이 토큰을 탭 단위 저장소에만 두는지(#2828).
///
/// 트레이너 웹 토큰이 새면 담당 회원 전원의 기록을 볼 수 있다. 웹의 보안 저장소는
/// localStorage 라, 세션 컨트롤러가 거치는 저장소를 탭 단위로 바꿔도 로그인·복구·
/// 로그아웃이 그대로 돌고 영구 저장소에는 아무것도 남지 않아야 한다.
/// 모바일 경로는 `session_controller_test.dart` 가 본다.
const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const FlutterSecureStorage _secure = FlutterSecureStorage();

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

/// 이 앱의 토큰 키(#3054). 두 앱이 같은 탭 저장소를 써서 키에 앱 이름이 붙는다.
final String _access = TokenKeyspace.trainer.accessKey;
final String _refresh = TokenKeyspace.trainer.refreshKey;

/// 회원 앱이 옛 키에 남긴 토큰은 `/trainer/me` 가 거절한다(403 → [NotTrainerException]).
class _RoleCheckingRepository extends MockTrainerAuthRepository {
  const _RoleCheckingRepository();

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    if (accessToken.startsWith('member-')) throw const NotTrainerException();
    return super.fetchProfile(accessToken);
  }
}

void main() {
  late InMemoryTokenSessionStorage tab;

  ProviderContainer container({
    Map<String, String> persisted = const <String, String>{},
  }) {
    FlutterSecureStorage.setMockInitialValues(
      Map<String, String>.of(persisted),
    );
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        tokenSessionStorageProvider.overrideWithValue(tab),
        trainerAuthRepositoryProvider.overrideWithValue(
          const _RoleCheckingRepository(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => tab = InMemoryTokenSessionStorage());

  test('login keeps both tokens in the tab, not localStorage', () async {
    final ProviderContainer c = container();
    final SessionController controller = c.read(
      sessionControllerProvider.notifier,
    );
    await _settle();

    await controller.login(email: 'coach@example.test', password: 'pw');

    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(tab.read(_access), isNotNull);
    expect(tab.read(_refresh), isNotNull);
    expect(await _secure.readAll(), isEmpty);
  });

  test('restores a session kept in the same tab', () async {
    tab
      ..write(_access, 'demo-existing')
      ..write(_refresh, 'demo-existing-refresh');
    final ProviderContainer c = container();

    c.read(sessionControllerProvider.notifier);
    await _settle();

    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });

  test('a new tab does not pick up tokens an older build persisted', () async {
    final ProviderContainer c = container(
      persisted: <String, String>{
        'access_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      },
    );

    c.read(sessionControllerProvider.notifier);
    await _settle();

    expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
    // 남아 있던 30일짜리 refresh 토큰은 지워진다.
    expect(await _secure.readAll(), isEmpty);
  });

  test('sign-out empties the tab', () async {
    final ProviderContainer c = container();
    final SessionController controller = c.read(
      sessionControllerProvider.notifier,
    );
    await _settle();
    await controller.login(email: 'coach@example.test', password: 'pw');

    await controller.signOut();
    await _settle();

    expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
    expect(tab.read(_access), isNull);
    expect(tab.read(_refresh), isNull);
    expect(await c.read(secureTokenStoreProvider).readRefreshToken(), isNull);
  });

  group('same origin as the member app (#3054)', () {
    final String memberAccess = TokenKeyspace.member.accessKey;
    final String memberRefresh = TokenKeyspace.member.refreshKey;

    test('login leaves the member app tokens in the tab alone', () async {
      tab
        ..write(memberAccess, 'member-access')
        ..write(memberRefresh, 'member-refresh');
      final ProviderContainer c = container();
      final SessionController controller = c.read(
        sessionControllerProvider.notifier,
      );
      await _settle();

      await controller.login(email: 'coach@example.test', password: 'pw');

      expect(tab.read(_access), isNotNull);
      expect(tab.read(_access), isNot('member-access'));
      expect(tab.read(memberAccess), 'member-access');
      expect(tab.read(memberRefresh), 'member-refresh');
    });

    test('sign-out clears only the trainer keys', () async {
      tab
        ..write(memberAccess, 'member-access')
        ..write(memberRefresh, 'member-refresh');
      final ProviderContainer c = container();
      final SessionController controller = c.read(
        sessionControllerProvider.notifier,
      );
      await _settle();
      await controller.login(email: 'coach@example.test', password: 'pw');

      await controller.signOut();
      await _settle();

      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      expect(tab.read(memberAccess), 'member-access');
      expect(tab.read(memberRefresh), 'member-refresh');
    });

    test('a member session in the tab is not restored as a trainer', () async {
      tab
        ..write(memberAccess, 'member-access')
        ..write(memberRefresh, 'member-refresh');
      final ProviderContainer c = container();

      c.read(sessionControllerProvider.notifier);
      await _settle();

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(tab.read(memberAccess), 'member-access');
    });

    test('a pre-namespace tab session moves to the trainer keys', () async {
      tab
        ..write('access_token', 'demo-existing')
        ..write('refresh_token', 'demo-existing-refresh');
      final ProviderContainer c = container();

      c.read(sessionControllerProvider.notifier);
      await _settle();

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(tab.read(_access), 'demo-existing');
      expect(tab.read('access_token'), isNull);
      expect(tab.read('refresh_token'), isNull);
    });

    test('a pre-namespace member token is left for the member app', () async {
      // 회원 앱 옛 토큰이 남은 탭에서 트레이너 웹이 먼저 열린 순서다(#3260).
      tab
        ..write('access_token', 'member-old-access')
        ..write('refresh_token', 'member-old-refresh');
      final ProviderContainer c = container();

      c.read(sessionControllerProvider.notifier);
      await _settle();

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      expect(tab.read('access_token'), 'member-old-access');
      expect(tab.read('refresh_token'), 'member-old-refresh');
    });

    test(
      'sign-out drops the legacy keys so a reload stays signed out',
      () async {
        // 이 앱은 새 키로 로그인해 있고, 옛 키에는 확인하지 못한 토큰이 남은 탭이다.
        tab
          ..write(_access, 'demo-existing')
          ..write(_refresh, 'demo-existing-refresh')
          ..write('access_token', 'demo-old')
          ..write('refresh_token', 'demo-old-refresh');
        final ProviderContainer c = container();
        final SessionController controller = c.read(
          sessionControllerProvider.notifier,
        );
        await _settle();
        expect(
          c.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );

        await controller.signOut();
        await _settle();

        expect(tab.read(_access), isNull);
        expect(tab.read('access_token'), isNull);
        expect(tab.read('refresh_token'), isNull);

        // 새로 고침: 같은 탭 저장소로 앱을 다시 띄운다.
        final ProviderContainer reloaded = container();
        reloaded.read(sessionControllerProvider.notifier);
        await _settle();

        expect(
          reloaded.read(sessionControllerProvider).status,
          SessionStatus.signedOut,
        );
      },
    );
  });
}
