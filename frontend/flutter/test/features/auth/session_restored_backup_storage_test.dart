/// 백업·기기 이전으로 풀 수 없는 토큰 저장소가 넘어온 경우(#3049).
///
/// 새 기기에는 암호문만 오고 그것을 풀 Keystore 키가 없다. 첫 읽기는 예외를
/// 던지고(`resetOnError` 가 저장소를 비운다), 세션은 로그아웃 상태로 가야 한다.
/// 이어서 로그인하면 토큰을 다시 저장해, 다음 실행에도 로그인이 이어져야 한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// 첫 읽기만 복호화 실패처럼 던지고, 그 뒤로는 비워진 저장소처럼 동작한다.
class _RestoredFromBackupStore extends SecureTokenStore {
  _RestoredFromBackupStore() : super(const FlutterSecureStorage());

  bool _broken = true;
  int failedReads = 0;
  final List<(String, String)> saved = <(String, String)>[];
  String? _access;
  String? _refresh;

  Future<String?> _readOrThrow(String? value) async {
    if (_broken) {
      failedReads++;
      throw PlatformExceptionLike('BAD_DECRYPT');
    }
    return value;
  }

  @override
  Future<String?> readAccessToken() async {
    try {
      return await _readOrThrow(_access);
    } finally {
      // resetOnError 가 풀 수 없는 저장소를 비운 뒤라고 본다.
      _broken = false;
    }
  }

  @override
  Future<String?> readRefreshToken() => _readOrThrow(_refresh);

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    if (_broken) throw PlatformExceptionLike('BAD_DECRYPT');
    saved.add((access, refresh));
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}

class PlatformExceptionLike implements Exception {
  PlatformExceptionLike(this.code);
  final String code;
}

Dio _loginDio() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        if (options.method == 'POST' && options.path == '/auth/login') {
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{
                'access_token': 'new-access',
                'refresh_token': 'new-refresh',
              },
            ),
          );
          return;
        }
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

Future<void> _settle(ProviderContainer container) async {
  for (int i = 0; i < 40; i++) {
    if (container.read(sessionControllerProvider).status !=
        SessionStatus.unknown) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('세션 상태가 정해지지 않았다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('읽기가 실패하면 로그아웃 상태로 가고, 이어진 로그인은 토큰을 저장한다', () async {
    final _RestoredFromBackupStore store = _RestoredFromBackupStore();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(_loginDio()),
        secureTokenStoreProvider.overrideWithValue(store),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(store.failedReads, greaterThan(0));
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );

    await container
        .read(sessionControllerProvider.notifier)
        .login(email: 'member@example.test', password: 'pw');

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(store.saved, <(String, String)>[('new-access', 'new-refresh')]);
    expect(await store.readAccessToken(), 'new-access');
  });
}
