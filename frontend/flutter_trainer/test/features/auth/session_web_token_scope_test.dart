import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/core/storage/token_session_storage.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';

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
    expect(tab.read('access_token'), isNotNull);
    expect(tab.read('refresh_token'), isNotNull);
    expect(await _secure.readAll(), isEmpty);
  });

  test('restores a session kept in the same tab', () async {
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
    expect(tab.read('access_token'), isNull);
    expect(tab.read('refresh_token'), isNull);
    expect(await c.read(secureTokenStoreProvider).readRefreshToken(), isNull);
  });
}
