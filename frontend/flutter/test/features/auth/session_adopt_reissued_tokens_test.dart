/// 비밀번호 변경 뒤 새 토큰으로 이 기기의 세션을 이어 가는가(#2824).
///
/// 서버는 변경과 함께 토큰 세대를 올려 옛 토큰을 모두 끊는다(#2766). 요청한
/// 기기가 응답의 새 토큰을 저장소·메모리에 넣지 않으면 바로 다음 요청에서
/// 로그아웃된다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

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

ProviderContainer _container() {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      dioProvider.overrideWithValue(_okDio()),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(ProviderContainer container) async {
  for (int attempt = 0; attempt < 40; attempt++) {
    if (container.read(sessionControllerProvider).status !=
        SessionStatus.unknown) {
      for (int tick = 0; tick < 5; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('세션 상태가 정해지지 않았다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('로그인 상태면 새 토큰을 저장소와 메모리에 넣고 세션을 유지한다', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'access_token': 'old-access',
      'refresh_token': 'old-refresh',
    });
    final ProviderContainer c = _container();
    c.read(sessionControllerProvider.notifier);
    await _settle(c);
    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );

    await c
        .read(sessionControllerProvider.notifier)
        .adoptReissuedTokens(access: 'new-access', refresh: 'new-refresh');

    expect(c.read(authAccessTokenProvider), 'new-access');
    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    final SecureTokenStore store = c.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'new-access');
    expect(await store.readRefreshToken(), 'new-refresh');
  });

  test('로그아웃 상태에서는 뒤늦은 토큰으로 세션을 되살리지 않는다', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final ProviderContainer c = _container();
    c.read(sessionControllerProvider.notifier);
    await _settle(c);
    expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);

    await c
        .read(sessionControllerProvider.notifier)
        .adoptReissuedTokens(access: 'late-access', refresh: 'late-refresh');

    expect(c.read(authAccessTokenProvider), isNull);
    expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
    expect(await c.read(secureTokenStoreProvider).readAccessToken(), isNull);
  });

  test('빈 접근 토큰은 받지 않는다', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'access_token': 'old-access',
      'refresh_token': 'old-refresh',
    });
    final ProviderContainer c = _container();
    c.read(sessionControllerProvider.notifier);
    await _settle(c);

    await expectLater(
      c
          .read(sessionControllerProvider.notifier)
          .adoptReissuedTokens(access: '', refresh: 'r'),
      throwsStateError,
    );
    expect(c.read(authAccessTokenProvider), 'old-access');
  });
}
