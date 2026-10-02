/// 공용 인증 인터셉터 — 헤더·401 재시도·갱신 경쟁. (#1546, #2907)
///
/// 두 앱은 이 인터셉터를 각자의 provider 로 조립한다(앱 쪽 조립 테스트는 각 앱의
/// `auth_interceptor_refresh_test.dart`). 여기서는 provider 없이 토큰·브리지를
/// 함수로 넘겨 인터셉터 자신의 판단만 본다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/network/auth_interceptor.dart';
import 'package:oncare_core/network/session_refresh.dart';

/// 받아 주는 토큰만 200, 나머지는 401 로 답하는 가짜 서버.
class _Backend implements HttpClientAdapter {
  final Set<String> validTokens = <String>{};
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 요청을 받을 때마다 불린다 — 응답 전에 세션이 바뀌는 상황을 만든다.
  void Function(RequestOptions options)? onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    onFetch?.call(options);
    final Object? auth = options.headers['Authorization'];
    final String? token = auth is String && auth.startsWith('Bearer ')
        ? auth.substring('Bearer '.length)
        : null;
    final bool ok = token != null && validTokens.contains(token);
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'token': token}),
      ok ? 200 : 401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 갱신을 흉내 낸다 — 성공이면 새 토큰을 서버와 세션에 함께 반영한다.
class _Refresher implements SessionTokenRefresher {
  _Refresher(this.harness);

  final _Harness harness;
  TokenRefreshStatus outcome = TokenRefreshStatus.refreshed;
  Completer<void>? gate;
  final List<String> calls = <String>[];
  int _n = 0;

  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) async {
    calls.add(staleToken);
    await gate?.future;
    switch (outcome) {
      case TokenRefreshStatus.refreshed:
        final String next = 'fresh-${++_n}';
        harness.backend.validTokens.add(next);
        harness.token = next;
        return TokenRefreshResult.refreshed(next);
      case TokenRefreshStatus.rejected:
        harness.token = null;
        return const TokenRefreshResult.rejected();
      case TokenRefreshStatus.unavailable:
        return const TokenRefreshResult.unavailable();
    }
  }
}

class _Harness {
  _Harness({bool withRetry = true}) {
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.test/v1',
        validateStatus: (int? s) => s != null && s < 400,
      ),
    )..httpClientAdapter = backend;
    dio.interceptors.add(
      AuthInterceptor(
        accessToken: () => token,
        refreshBridge: () => bridge,
        retryClient: withRetry ? dio : null,
      ),
    );
    refresher = _Refresher(this);
    bridge.attach(refresher);
  }

  final _Backend backend = _Backend();
  final SessionRefreshBridge bridge = SessionRefreshBridge();
  late final Dio dio;
  late final _Refresher refresher;
  String? token = 'stale';

  List<String?> bearers() => backend.requests
      .map((RequestOptions r) => r.headers['Authorization'] as String?)
      .toList();
}

Matcher _statusIs(int code) => isA<DioException>().having(
  (DioException e) => e.response?.statusCode,
  'status',
  code,
);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('헤더', () {
    test('세션 토큰을 붙이고 그 토큰을 extra 에 적는다', () async {
      h.backend.validTokens.add('stale');
      await h.dio.get<Object?>('/data');

      final RequestOptions sent = h.backend.requests.single;
      expect(sent.headers['Authorization'], 'Bearer stale');
      expect(sent.extra[AuthInterceptor.sessionTokenExtra], 'stale');
      expect(h.refresher.calls, isEmpty);
    });

    test('토큰이 없거나 비었으면 헤더를 붙이지 않는다', () async {
      for (final String? t in <String?>[null, '']) {
        h.token = t;
        await expectLater(h.dio.get<Object?>('/data'), throwsA(_statusIs(401)));
        expect(h.backend.requests.last.headers['Authorization'], isNull);
      }
      expect(h.refresher.calls, isEmpty);
    });

    test('호출부가 넣은 Authorization 은 덮지 않고, 그 401 은 갱신하지 않는다', () async {
      await expectLater(
        h.dio.get<Object?>(
          '/me',
          options: Options(
            headers: <String, Object?>{'Authorization': 'Bearer probe'},
          ),
        ),
        throwsA(_statusIs(401)),
      );
      expect(h.bearers(), <String?>['Bearer probe']);
      expect(h.refresher.calls, isEmpty);
    });

    test('isAuthEndpoint 는 /auth/ 경로만 고른다', () {
      expect(
        AuthInterceptor.isAuthEndpoint(
          RequestOptions(baseUrl: 'https://api.test/v1', path: '/auth/refresh'),
        ),
        isTrue,
      );
      expect(
        AuthInterceptor.isAuthEndpoint(
          RequestOptions(baseUrl: 'https://api.test/v1', path: '/users/me'),
        ),
        isFalse,
      );
    });
  });

  group('401 재시도', () {
    test('만료된 토큰이면 한 번 갱신하고 새 토큰으로 한 번 다시 보낸다', () async {
      final Response<Object?> res = await h.dio.get<Object?>('/data');

      expect((res.data! as Map<String, Object?>)['token'], 'fresh-1');
      expect(h.refresher.calls, <String>['stale']);
      expect(h.bearers(), <String?>['Bearer stale', 'Bearer fresh-1']);
      expect(
        h.backend.requests.last.extra[AuthInterceptor.retriedExtra],
        isTrue,
      );
    });

    test('다시 보낸 요청이 또 401 이면 더 시도하지 않는다', () async {
      // 갱신은 성공했다고 답하지만 서버는 새 토큰도 받지 않는다.
      h.bridge
        ..detach(h.refresher)
        ..attach(_RejectingServerRefresher(h));

      await expectLater(h.dio.get<Object?>('/data'), throwsA(_statusIs(401)));
      expect(h.backend.requests, hasLength(2));
    });

    test('갱신이 거부되면 원래 401 을 그대로 넘긴다', () async {
      h.refresher.outcome = TokenRefreshStatus.rejected;

      await expectLater(h.dio.get<Object?>('/data'), throwsA(_statusIs(401)));
      expect(h.backend.requests, hasLength(1));
      expect(h.token, isNull);
    });

    test('갱신하지 못하면(unavailable) 토큰을 지우지 않고 원래 401 을 넘긴다', () async {
      h.refresher.outcome = TokenRefreshStatus.unavailable;

      await expectLater(h.dio.get<Object?>('/data'), throwsA(_statusIs(401)));
      expect(h.token, 'stale');
    });

    test('그 사이 다른 요청이 이미 갱신했으면 갱신 없이 지금 토큰으로 보낸다', () async {
      h.backend.validTokens.add('newer');
      // 요청이 'stale' 로 나간 뒤, 응답이 오기 전에 세션 토큰이 바뀐다.
      h.backend.onFetch = (_) {
        h.token = 'newer';
        h.backend.onFetch = null;
      };
      final Response<Object?> res = await h.dio.get<Object?>('/data');

      expect((res.data! as Map<String, Object?>)['token'], 'newer');
      expect(h.bearers(), <String?>['Bearer stale', 'Bearer newer']);
      expect(h.refresher.calls, isEmpty);
    });

    test('/auth/* 의 401 은 갱신하지 않는다', () async {
      await expectLater(
        h.dio.post<Object?>('/auth/login'),
        throwsA(_statusIs(401)),
      );
      expect(h.backend.requests, hasLength(1));
      expect(h.refresher.calls, isEmpty);
    });

    test('retryClient 가 없으면 헤더만 붙이고 갱신하지 않는다', () async {
      final _Harness plain = _Harness(withRetry: false);

      await expectLater(
        plain.dio.get<Object?>('/data'),
        throwsA(_statusIs(401)),
      );
      expect(plain.refresher.calls, isEmpty);
    });
  });

  group('갱신 경쟁', () {
    test('동시에 여러 요청이 401 이어도 갱신은 한 번이고 모두 새 토큰으로 다시 보낸다', () async {
      h.refresher.gate = Completer<void>();
      final List<Future<Response<Object?>>> calls =
          <Future<Response<Object?>>>[
            h.dio.get<Object?>('/a'),
            h.dio.get<Object?>('/b'),
            h.dio.get<Object?>('/c'),
          ];
      // 세 요청이 모두 401 을 받고 브리지 앞에서 기다릴 때까지 흘려보낸다.
      while (h.backend.requests.length < 3 || h.refresher.calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      h.refresher.gate!.complete();
      final List<Response<Object?>> results = await Future.wait(calls);

      expect(h.refresher.calls, <String>['stale']);
      expect(
        results.map((Response<Object?> r) => (r.data! as Map)['token']),
        everyElement('fresh-1'),
      );
    });
  });
}

/// 갱신은 성공이라고 답하지만 서버가 새 토큰을 받아 주지 않는 경우.
class _RejectingServerRefresher implements SessionTokenRefresher {
  _RejectingServerRefresher(this.harness);

  final _Harness harness;

  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) async {
    harness.token = 'fresh-but-unknown';
    return const TokenRefreshResult.refreshed('fresh-but-unknown');
  }
}
