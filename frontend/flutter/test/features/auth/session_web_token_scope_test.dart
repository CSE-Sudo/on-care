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
import 'package:oncare_core/storage/token_keys.dart';

/// 이 앱의 토큰 키(#3054). 두 앱이 같은 탭 저장소를 써서 키에 앱 이름이 붙는다.
final String _access = TokenKeyspace.member.accessKey;
final String _refresh = TokenKeyspace.member.refreshKey;

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
      ..write(_access, 'tab-access')
      ..write(_refresh, 'tab-refresh');
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
      ..write(_access, 'expired-access')
      ..write(_refresh, 'tab-refresh');
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
    expect(tab.read(_access), 'rotated-access');
    expect(tab.read(_refresh), 'rotated-refresh');
    expect(await secure.readAll(), isEmpty);
  });

  test('a dead refresh token clears the tab', () async {
    tab
      ..write(_access, 'expired-access')
      ..write(_refresh, 'dead-refresh');
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
    expect(tab.read(_access), isNull);
    expect(tab.read(_refresh), isNull);
  });

  group('same origin as the trainer web (#3054)', () {
    final String trainerAccess = TokenKeyspace.trainer.accessKey;
    final String trainerRefresh = TokenKeyspace.trainer.refreshKey;

    void seedTrainer() => tab
      ..write(trainerAccess, 'trainer-access')
      ..write(trainerRefresh, 'trainer-refresh');

    test('a trainer role on /users/me ends the session', () async {
      tab
        ..write(_access, 'tab-access')
        ..write(_refresh, 'tab-refresh');
      seedTrainer();
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (200, <String, Object?>{'id': 'u1', 'role': 'trainer'}),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      // 트레이너 웹의 세션은 그대로다.
      expect(tab.read(trainerAccess), 'trainer-access');
      expect(tab.read(trainerRefresh), 'trainer-refresh');
    });

    test('a member role restores the session', () async {
      tab
        ..write(_access, 'tab-access')
        ..write(_refresh, 'tab-refresh');
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (200, <String, Object?>{'id': 'u1', 'role': 'member'}),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
    });

    test('403 clears this app only and never rotates', () async {
      tab
        ..write(_access, 'tab-access')
        ..write(_refresh, 'tab-refresh');
      seedTrainer();
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (403, <String, Object?>{}),
          ],
          'POST /auth/refresh': <(int, Map<String, Object?>)>[
            (
              200,
              <String, Object?>{
                'access_token': 'should-not-happen',
                'refresh_token': 'should-not-happen',
              },
            ),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(calls, isNot(contains('POST /auth/refresh')));
      expect(tab.read(_access), isNull);
      expect(tab.read(trainerAccess), 'trainer-access');
      expect(tab.read(trainerRefresh), 'trainer-refresh');
    });

    test('a pre-namespace tab session moves to the member keys', () async {
      tab
        ..write('access_token', 'old-access')
        ..write('refresh_token', 'old-refresh');
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (200, <String, Object?>{'id': 'u1', 'role': 'member'}),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(tab.read(_access), 'old-access');
      expect(tab.read(_refresh), 'old-refresh');
      expect(tab.read('access_token'), isNull);
      expect(tab.read('refresh_token'), isNull);
    });

    test('a pre-namespace trainer token is not let in', () async {
      tab
        ..write('access_token', 'trainer-old-access')
        ..write('refresh_token', 'trainer-old-refresh');
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (403, <String, Object?>{}),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(calls, isNot(contains('POST /auth/refresh')));
      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      // 옛 키는 원래 주인(트레이너 웹)이 가져가게 남긴다(#3260).
      expect(tab.read('access_token'), 'trainer-old-access');
      expect(tab.read('refresh_token'), 'trainer-old-refresh');
    });

    test('an expired pre-namespace token is never rotated', () async {
      // 옛 키는 어느 앱 것인지 모른다 — 일회용 갱신 토큰을 돌리면 주인 앱이 그
      // 세션을 잃는다(#3260). 새 키만 비우고 옛 키는 남긴다.
      tab
        ..write('access_token', 'old-access')
        ..write('refresh_token', 'old-refresh');
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (401, <String, Object?>{}),
          ],
          'POST /auth/refresh': <(int, Map<String, Object?>)>[
            (
              200,
              <String, Object?>{
                'access_token': 'should-not-happen',
                'refresh_token': 'should-not-happen',
              },
            ),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(calls, isNot(contains('POST /auth/refresh')));
      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      expect(tab.read('access_token'), 'old-access');
      expect(tab.read('refresh_token'), 'old-refresh');
    });

    test('a trainer role keeps the legacy keys for the trainer web', () async {
      tab
        ..write('access_token', 'trainer-old-access')
        ..write('refresh_token', 'trainer-old-refresh');
      final ProviderContainer c = container(
        <String, List<(int, Map<String, Object?>)>>{
          'GET /users/me': <(int, Map<String, Object?>)>[
            (200, <String, Object?>{'id': 't1', 'role': 'trainer'}),
          ],
        },
      );

      c.read(sessionControllerProvider.notifier);
      await _settle(c);

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(tab.read(_access), isNull);
      expect(tab.read(_refresh), isNull);
      expect(tab.read('access_token'), 'trainer-old-access');
      expect(tab.read('refresh_token'), 'trainer-old-refresh');
    });

    test(
      'sign-out drops the legacy keys so a reload stays signed out',
      () async {
        // 이 앱은 새 키로 로그인해 있고, 옛 키에는 확인하지 못한 토큰이 남은 탭이다.
        tab
          ..write(_access, 'tab-access')
          ..write(_refresh, 'tab-refresh')
          ..write('access_token', 'old-access')
          ..write('refresh_token', 'old-refresh');
        final ProviderContainer c = container(
          <String, List<(int, Map<String, Object?>)>>{
            'GET /users/me': <(int, Map<String, Object?>)>[
              (200, <String, Object?>{'id': 'u1', 'role': 'member'}),
            ],
            'POST /auth/logout': <(int, Map<String, Object?>)>[
              (204, <String, Object?>{}),
            ],
          },
        );
        c.read(sessionControllerProvider.notifier);
        await _settle(c);
        expect(
          c.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );

        await c.read(sessionControllerProvider.notifier).signOut();

        expect(tab.read(_access), isNull);
        expect(tab.read('access_token'), isNull);
        expect(tab.read('refresh_token'), isNull);

        // 새로 고침: 같은 탭 저장소로 앱을 다시 띄운다.
        calls.clear();
        final ProviderContainer reloaded = container(
          <String, List<(int, Map<String, Object?>)>>{
            'GET /users/me': <(int, Map<String, Object?>)>[
              (200, <String, Object?>{'id': 'u1', 'role': 'member'}),
            ],
          },
        );
        reloaded.read(sessionControllerProvider.notifier);
        await _settle(reloaded);

        expect(
          reloaded.read(sessionControllerProvider).status,
          SessionStatus.signedOut,
        );
        expect(calls, isNot(contains('GET /users/me')));
      },
    );
  });
}
