/// 로그아웃이 서버 쪽 세션까지 끊는가 — #966.
///
/// 예전에는 로그아웃이 이 기기의 저장소를 비우는 일이었다. 갱신 토큰은 만료
/// (기본 30일)까지 살아 있어서, 어딘가로 새어 나갔다면 로그아웃을 눌러도 그
/// 세션은 그대로였다. 이제 지우기 전에 `POST /auth/logout` 으로 그 토큰을
/// 폐기한다 — 다만 **그 호출이 실패해도 로그아웃은 끝까지 간다.**
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// 나간 요청을 기록하는 Dio. `failLogout` 이면 로그아웃 호출만 연결 실패로 답한다.
class _RecordingDio {
  _RecordingDio({this.failLogout = false});

  final bool failLogout;
  final List<RequestOptions> requests = <RequestOptions>[];

  Dio build() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          if (failLogout && options.path == '/auth/logout') {
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: '연결 실패',
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

  List<RequestOptions> get logoutCalls =>
      requests.where((r) => r.path == '/auth/logout').toList();
}

ProviderContainer _container(Dio dio) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      dioProvider.overrideWithValue(dio),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 세션 상태가 정해질 때까지(그리고 뒤따르는 저장소 작업까지) 기다린다.
Future<void> _settle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (container.read(sessionControllerProvider).status !=
        SessionStatus.unknown) {
      for (var tick = 0; tick < 5; tick++) {
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

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'access_token': 'stored-access',
      'refresh_token': 'stored-refresh',
    });
  });

  test('로그아웃은 저장된 갱신 토큰을 서버에서 폐기한다', () async {
    final recorder = _RecordingDio();
    final container = _container(recorder.build());
    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(recorder.logoutCalls, hasLength(1));
    expect(
      (recorder.logoutCalls.single.data as Map<String, Object?>)['refresh_token'],
      'stored-refresh',
    );
    // 폐기는 지우기 전에 나가야 한다 — 지운 뒤에는 보낼 토큰이 없다.
    expect(
      await container.read(secureTokenStoreProvider).readRefreshToken(),
      isNull,
    );
  });

  test('폐기 호출이 실패해도 로그아웃 상태가 된다', () async {
    final recorder = _RecordingDio(failLogout: true);
    final container = _container(recorder.build());
    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(recorder.logoutCalls, hasLength(1));
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(
      await container.read(secureTokenStoreProvider).readAccessToken(),
      isNull,
    );
    expect(
      await container.read(secureTokenStoreProvider).readRefreshToken(),
      isNull,
    );
  });

  test('저장된 갱신 토큰이 없으면 부르지 않는다', () async {
    // 데모 세션에는 토큰이 없다 — 끊을 서버 세션도 없다.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final recorder = _RecordingDio();
    final container = _container(recorder.build());
    final controller = container.read(sessionControllerProvider.notifier);
    await _settle(container);
    controller.enterDemo();

    await controller.signOut();

    expect(recorder.logoutCalls, isEmpty);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
  });
}
