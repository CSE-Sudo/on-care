/// 가입은 됐는데 로그인만 실패한 경우를 가입 실패와 갈라 놓는다. (#1926)
///
/// 갈라 두지 않으면 회원은 "가입에 실패했어요" 를 보고 다시 가입을 눌러
/// "이미 사용 중인 이메일" 을 만난다 — 방금 실패했다던 계정이 있다는 뜻이라
/// 무엇이 맞는지 알 수 없게 된다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// `/auth/register` 는 받아 주고 `/auth/login` 만 실패시키는 대역.
class _RegisterOkLoginFails extends Interceptor {
  int registers = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/auth/register') {
      registers++;
      handler.resolve(
        Response<Map<String, Object?>>(
          requestOptions: options,
          statusCode: 201,
          data: const <String, Object?>{},
        ),
      );
      return;
    }
    if (options.path == '/auth/login') {
      handler.reject(
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('로그인만 실패하면 가입 실패가 아니라 계정 생성됨으로 알린다', () async {
    final _RegisterOkLoginFails backend = _RegisterOkLoginFails();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
      ],
    );
    addTearDown(container.dispose);
    container.read(dioProvider).interceptors.insert(0, backend);

    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .register(email: 'new@oncare.com', password: 'pw123456'),
      throwsA(isA<AccountCreatedSignInFailed>()),
    );

    // 계정은 실제로 만들어졌다 — 다시 가입하라고 하면 409 를 만난다.
    expect(backend.registers, 1);
    // 로그인은 되지 않았으므로 세션은 없다.
    expect(
      container.read(sessionControllerProvider).status,
      isNot(SessionStatus.authenticated),
    );
  });

  test('가입 자체가 실패하면 그 오류가 그대로 올라온다', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
      ],
    );
    addTearDown(container.dispose);
    container.read(dioProvider).interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.path == '/auth/register') {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<Object?>(
                  requestOptions: options,
                  statusCode: 409,
                ),
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    // 계정이 만들어지지 않았으니 `계정 생성됨` 으로 감싸지 않는다.
    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .register(email: 'taken@oncare.com', password: 'pw123456'),
      throwsA(
        allOf(
          isA<DioException>(),
          isNot(isA<AccountCreatedSignInFailed>()),
        ),
      ),
    );
  });
}
