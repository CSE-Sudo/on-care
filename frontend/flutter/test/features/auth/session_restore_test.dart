/// 저장된 토큰으로 세션을 되살리는 경로 — #618.
///
/// 예전에는 토큰이 **있기만 하면** 인증 상태로 넘어갔다. 접근 토큰 수명이 하루라,
/// 다음 날 앱을 켜면 로그인된 화면이 뜨지만 모든 요청이 실패하고 수동 로그아웃 말고는
/// 빠져나갈 길이 없었다. 갱신 토큰은 저장만 하고 쓰지 않았다.
///
/// 여기서 고정하는 성질은 넷이다.
///
///  * 유효한지 확인하고 들어간다.
///  * 만료면 갱신 토큰으로 한 번 회전한다.
///  * 갱신까지 죽었으면 저장 토큰을 지우고 로그인 화면으로 보낸다.
///  * 네트워크가 잠깐 안 되는 것과 세션이 끝난 것을 구분한다 — 전자는 토큰을 지킨다.
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

/// 한 요청에 대한 답. 상태 코드나 예외 중 하나를 낸다.
class _Reply {
  const _Reply.ok(this.body) : status = 200, throwsConnection = false;
  const _Reply.status(this.status) : body = null, throwsConnection = false;
  const _Reply.connectionError()
    : status = 0,
      body = null,
      throwsConnection = true;

  final int status;
  final Map<String, Object?>? body;
  final bool throwsConnection;
}

/// `METHOD /path` → 순서대로 소비할 답 목록. 목록이 마르면 마지막 답을 반복한다.
class _ScriptedDio {
  _ScriptedDio(this._script);

  final Map<String, List<_Reply>> _script;

  /// 실제로 나간 요청 기록 — 어떤 토큰을 달고 갔는지까지 본다.
  final List<RequestOptions> requests = <RequestOptions>[];

  Dio build({Duration delay = Duration.zero}) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest:
            (RequestOptions options, RequestInterceptorHandler handler) async {
              requests.add(options);
              if (delay > Duration.zero) await Future<void>.delayed(delay);

              final String key = '${options.method.toUpperCase()} ${options.path}';
              final List<_Reply>? replies = _script[key];
              if (replies == null || replies.isEmpty) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response<Object?>(
                      requestOptions: options,
                      statusCode: 404,
                    ),
                  ),
                );
                return;
              }
              final _Reply reply = replies.length == 1
                  ? replies.first
                  : replies.removeAt(0);

              if (reply.throwsConnection) {
                handler.reject(
                  DioException.connectionError(
                    requestOptions: options,
                    reason: '연결 실패',
                  ),
                );
                return;
              }
              if (reply.status >= 400) {
                handler.reject(
                  DioException.badResponse(
                    statusCode: reply.status,
                    requestOptions: options,
                    response: Response<Object?>(
                      requestOptions: options,
                      statusCode: reply.status,
                    ),
                  ),
                );
                return;
              }
              handler.resolve(
                Response<Map<String, Object?>>(
                  requestOptions: options,
                  statusCode: reply.status,
                  data: reply.body ?? <String, Object?>{},
                ),
              );
            },
      ),
    );
    return dio;
  }

  /// 이 요청이 달고 간 Bearer 토큰.
  String? bearerOf(int index) {
    final Object? header = requests[index].headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }
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

Future<void> _settle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    // 일시적 실패는 상태를 `unknown` 에 남겨 둔 채 끝난다(#1944) — 시작 화면이
    // 그 자리에서 다시 시도를 준다. 그것도 복구가 끝난 것이다.
    final SessionState session = container.read(sessionControllerProvider);
    if (session.status != SessionStatus.unknown || session.restoreFailed) {
      // 상태가 정해진 뒤에도 저장소 정리 같은 후속 작업이 남아 있을 수 있다.
      //
      // 한 틱만 기다리면 지금은 통과한다 — 만료가 지우기를 먼저, 상태 변경을 나중에
      // 하기 때문이다. 그 순서가 바뀌면 저장소를 확인하는 테스트가 간헐적으로
      // 깨진다. secure storage 는 MethodChannel 을 거쳐서 마이크로태스크 한 틱으로
      // 완료가 보장되지 않는다(리뷰).
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

  test('저장된 토큰이 유효하면 확인하고 들어간다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.ok(<String, Object?>{'id': 'u1'})],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    // 저장된 토큰이 그대로 세션에 올라간다.
    expect(container.read(authAccessTokenProvider), 'stored-access');
    // 확인 요청은 저장된 토큰을 달고 나간다 — 세션에 넣기 전에 찔러 봐야 한다.
    expect(script.bearerOf(0), 'stored-access');
  });

  test('토큰이 없으면 확인하지 않고 로그인 화면으로', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final script = _ScriptedDio(<String, List<_Reply>>{});
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    // 확인할 것이 없으므로 네트워크로 나가지 않는다.
    expect(script.requests, isEmpty);
  });

  test('만료된 접근 토큰은 갱신 토큰으로 한 번 회전한다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[
        const _Reply.status(401),
        const _Reply.ok(<String, Object?>{'id': 'u1'}),
      ],
      'POST /auth/refresh': <_Reply>[
        const _Reply.ok(<String, Object?>{
          'access_token': 'rotated-access',
          'refresh_token': 'rotated-refresh',
        }),
      ],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(container.read(authAccessTokenProvider), 'rotated-access');
    // 두 번째 확인은 회전한 토큰으로 나간다.
    expect(script.bearerOf(2), 'rotated-access');
    // 회전 결과가 저장돼야 다음 실행에서도 되살아난다.
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'rotated-access');
    expect(await store.readRefreshToken(), 'rotated-refresh');
  });

  test('갱신 토큰을 새로 주지 않으면 쓰던 것을 유지한다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[
        const _Reply.status(401),
        const _Reply.ok(<String, Object?>{'id': 'u1'}),
      ],
      'POST /auth/refresh': <_Reply>[
        // 접근 토큰만 회전시키는 서버. 갱신 토큰을 지워 버리면 다음 만료 때 되살릴
        // 방법이 없어진다.
        const _Reply.ok(<String, Object?>{'access_token': 'rotated-access'}),
      ],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readRefreshToken(), 'stored-refresh');
  });

  test('갱신까지 거부되면 저장 토큰을 지우고 로그인 화면으로', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      'POST /auth/refresh': <_Reply>[const _Reply.status(401)],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(container.read(authAccessTokenProvider), isNull);
    // 죽은 토큰을 남겨 두면 다음 실행에서도 같은 실패를 반복한다.
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('회전한 토큰마저 거부되면 다시 갱신하지 않는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      'POST /auth/refresh': <_Reply>[
        const _Reply.ok(<String, Object?>{'access_token': 'rotated-access'}),
      ],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    // 갱신은 한 번만 — 무한 회전에 빠지면 앱이 켜지지 않는다.
    final int refreshCalls = script.requests
        .where((RequestOptions r) => r.path == '/auth/refresh')
        .length;
    expect(refreshCalls, 1);
  });

  test('네트워크가 안 되면 시작 화면에 재시도를 띄우고 토큰은 지킨다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.connectionError()],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    // 세션이 끝난 것이 아니라 아직 모른다 — 시작 화면이 다시 시도를 준다(#1944).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unknown,
    );
    expect(container.read(sessionControllerProvider).restoreFailed, isTrue);
    // 지하철에서 앱을 켰다고 세션을 잃으면 안 된다 — 다음 실행에서 되살아나야 한다.
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'stored-access');
    expect(await store.readRefreshToken(), 'stored-refresh');
  });

  test('서버 오류도 세션 만료로 보지 않는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(500)],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    // 세션이 끝난 것이 아니라 아직 모른다 — 시작 화면이 다시 시도를 준다(#1944).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unknown,
    );
    expect(container.read(sessionControllerProvider).restoreFailed, isTrue);
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'stored-access');
  });

  test('갱신 요청이 연결 실패로 끝나면 저장 토큰을 지우지 않는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      'POST /auth/refresh': <_Reply>[const _Reply.connectionError()],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    // 세션이 끝난 것이 아니라 아직 모른다 — 시작 화면이 다시 시도를 준다(#1944).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unknown,
    );
    expect(container.read(sessionControllerProvider).restoreFailed, isTrue);
    // 접근 토큰이 만료됐어도 갱신이 **거부된 것은 아니다.** 네트워크가 잠깐 끊긴
    // 것을 만료로 처리하면 재로그인을 강요하게 된다(리뷰).
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'stored-access');
    expect(await store.readRefreshToken(), 'stored-refresh');
  });

  test('갱신 요청이 서버 오류로 끝나도 토큰을 남긴다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      'POST /auth/refresh': <_Reply>[const _Reply.status(500)],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    // 세션이 끝난 것이 아니라 아직 모른다 — 시작 화면이 다시 시도를 준다(#1944).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unknown,
    );
    expect(container.read(sessionControllerProvider).restoreFailed, isTrue);
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'stored-access');
    expect(await store.readRefreshToken(), 'stored-refresh');
  });

  test('갱신이 200 을 주고도 토큰을 빠뜨리면 세션을 끝내지 않는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      // 계약이 깨진 응답이지 세션이 끝난 것은 아니다.
      'POST /auth/refresh': <_Reply>[const _Reply.ok(<String, Object?>{})],
    });
    final container = _container(script.build());

    container.read(sessionControllerProvider.notifier);
    await _settle(container);

    // 세션이 끝난 것이 아니라 아직 모른다 — 시작 화면이 다시 시도를 준다(#1944).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unknown,
    );
    expect(container.read(sessionControllerProvider).restoreFailed, isTrue);
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'stored-access');
    // 갱신 토큰만 지우는 회귀는 접근 토큰 확인만으로는 잡히지 않는다 — 그 상태로는
    // 다음 만료 때 되살릴 방법이 없다(리뷰).
    expect(await store.readRefreshToken(), 'stored-refresh');
  });

  // 이 테스트가 고정하는 것은 **결과**다 — 복구가 만료로 흘러가는 도중에 로그인이
  // 끝나면, 끝난 뒤 저장소에 로그인 토큰이 남아 있어야 한다.
  //
  // 만료 직전 확인과 `clear()` 사이의 좁은 틈(가드를 지난 뒤 사용자가 로그인하는
  // 경우)까지는 이 테스트로 재현되지 않는다. 그 틈은 `_expire()` 가 지우기 전에도
  // 확인하도록 해서 좁혔고, 결정론적으로 재현할 방법이 없어 테스트로 못 박지 않았다.
  test('복구가 만료로 흘러가도 그 사이 끝난 로그인의 토큰이 남는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      // 복구는 만료 → 갱신 거부 순으로 흘러 결국 _expire 에 닿는다.
      'GET /users/me': <_Reply>[const _Reply.status(401)],
      'POST /auth/refresh': <_Reply>[const _Reply.status(401)],
      'POST /auth/login': <_Reply>[
        const _Reply.ok(<String, Object?>{
          'access_token': 'fresh-access',
          'refresh_token': 'fresh-refresh',
        }),
      ],
    });
    final container = _container(
      script.build(delay: const Duration(milliseconds: 30)),
    );

    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    // 복구가 아직 갱신 단계에 있는 사이 로그인이 끝난다.
    await controller.login(email: 'member@example.com', password: 'pw');
    // 뒤늦은 만료가 도착하고도 남을 만큼 기다린다.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    // 화면만 로그인 상태이고 저장소는 비어 있으면, 다음 실행에서 로그아웃된다.
    final store = container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'fresh-access');
    expect(await store.readRefreshToken(), 'fresh-refresh');
  });

  test('복구 중 사용자가 데모로 들어가면 복구가 그것을 덮지 않는다', () async {
    final script = _ScriptedDio(<String, List<_Reply>>{
      'GET /users/me': <_Reply>[const _Reply.ok(<String, Object?>{'id': 'u1'})],
    });
    // 복구가 아직 끝나지 않은 사이에 사용자가 버튼을 누르는 상황.
    final container = _container(
      script.build(delay: const Duration(milliseconds: 50)),
    );

    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    controller.enterDemo();
    // 복구가 끝나고도 남을 만큼 기다린다.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.demo,
    );
    // 데모는 토큰 없이 도는 경로다.
    expect(container.read(authAccessTokenProvider), isNull);
  });
}
