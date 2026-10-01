/// 웹 빌드의 세션 복구·회전이 토큰을 탭 단위 저장소에만 두는지(#2828).
///
/// 웹의 보안 저장소는 localStorage 다. 세션 컨트롤러가 거치는 저장소가 탭 단위
/// 저장소로 바뀌어도 복구·회전·로그아웃이 그대로 돌고, refresh 토큰이 영구
/// 저장소로 새지 않는지 확인한다. 모바일 경로는 `session_restore_test.dart` 가 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/token_session_storage.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// `METHOD /path` → 순서대로 줄 (상태 코드, 본문). 마지막 답은 반복한다.
Dio _scriptedDio(
  Map<String, List<(int, Map<String, Object?>)>> script,
  List<String> calls,
) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final String key = '${options.method.toUpperCase()} ${options.path}';
        calls.add(key);
        final List<(int, Map<String, Object?>)>? replies = script[key];
        final (int, Map<String, Object?>) reply =
            replies == null || replies.isEmpty
            ? (404, <String, Object?>{})
            : (replies.length == 1 ? replies.first : replies.removeAt(0));
        final Response<Map<String, Object?>> response =
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: reply.$1,
              data: reply.$2,
            );
        if (reply.$1 >= 400) {
          handler.reject(
            DioException.badResponse(
              statusCode: reply.$1,
              requestOptions: options,
              response: response,
            ),
          );
          return;
        }
        handler.resolve(response);
      },
    ),
  );
  return dio;
}

Future<void> _settle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final SessionState session = container.read(sessionControllerProvider);
    if (session.status != SessionStatus.unknown || session.restoreFailed) {
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

  const FlutterSecureStorage secure = FlutterSecureStorage();
  late InMemoryTokenSessionStorage tab;
  late List<String> calls;

  ProviderContainer container(
    Map<String, List<(int, Map<String, Object?>)>> script,
  ) {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(_scriptedDio(script, calls)),
        tokenSessionStorageProvider.overrideWithValue(tab),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    tab = InMemoryTokenSessionStorage();
    calls = <String>[];
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('restores a session kept in the tab', () async {
    tab
      ..write('access_token', 'tab-access')
      ..write('refresh_token', 'tab-refresh');
    final ProviderContainer c = container(
      <String, List<(int, Map<String, Object?>)>>{
        'GET /users/me': <(int, Map<String, Object?>)>[
          (200, <String, Object?>{'id': 'u1'}),
        ],
      },
    );

    c.read(sessionControllerProvider.notifier);
    await _settle(c);

    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(await secure.readAll(), isEmpty);
  });

  test(
    'ignores and purges tokens an older build left in localStorage',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      });
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{},
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      // 예전 토큰으로 서버를 찌르지 않는다.
      expect(calls, isEmpty);
      expect(await secure.readAll(), isEmpty);
    },
  );

  test('rotation stores the new pair in the tab only', () async {
    tab
      ..write('access_token', 'expired-access')
      ..write('refresh_token', 'tab-refresh');
    final ProviderContainer c = container(
      <String, List<(int, Map<String, Object?>)>>{
        'GET /users/me': <(int, Map<String, Object?>)>[
          (401, <String, Object?>{}),
          (200, <String, Object?>{'id': 'u1'}),
        ],
        'POST /auth/refresh': <(int, Map<String, Object?>)>[
          (
            200,
            <String, Object?>{
              'access_token': 'rotated-access',
              'refresh_token': 'rotated-refresh',
            },
          ),
        ],
      },
    );

    c.read(sessionControllerProvider.notifier);
    await _settle(c);

    expect(
      c.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(tab.read('access_token'), 'rotated-access');
    expect(tab.read('refresh_token'), 'rotated-refresh');
    expect(await secure.readAll(), isEmpty);
  });

  test('a dead refresh token clears the tab', () async {
    tab
      ..write('access_token', 'expired-access')
      ..write('refresh_token', 'dead-refresh');
    final ProviderContainer c = container(
      <String, List<(int, Map<String, Object?>)>>{
        'GET /users/me': <(int, Map<String, Object?>)>[
          (401, <String, Object?>{}),
        ],
        'POST /auth/refresh': <(int, Map<String, Object?>)>[
          (401, <String, Object?>{}),
        ],
      },
    );

    c.read(sessionControllerProvider.notifier);
    await _settle(c);

    expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
    expect(tab.read('access_token'), isNull);
    expect(tab.read('refresh_token'), isNull);
  });
}
