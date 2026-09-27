/// 실행 중 만료된 접근 토큰 — 인증 인터셉터 층. (#1546)
///
/// 세션 컨트롤러 대신 가짜 갱신기를 붙여 인터셉터의 판단만 본다: 언제 갱신을
/// 부르고, 몇 번 부르고, 무엇을 다시 보내고, 언제 원래 오류를 그대로 넘기는가.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/interceptors/auth_interceptor.dart';
import 'package:oncare/core/network/session_refresh.dart';

import '../../helpers/token_backend.dart';

/// 갱신을 흉내 낸다 — [outcome] 대로 답하고, 성공이면 새 토큰을 서버와 세션에
/// 함께 반영한다.
class _FakeRefresher implements SessionTokenRefresher {
  _FakeRefresher(this.container, this.backend);

  final ProviderContainer container;
  final TokenBackend backend;
  TokenRefreshStatus outcome = TokenRefreshStatus.refreshed;

  /// 거짓이면 서버가 새 토큰도 받아 주지 않는다.
  bool serverAccepts = true;
  Duration delay = Duration.zero;
  final List<String> staleTokens = <String>[];
  int _n = 0;

  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) async {
    staleTokens.add(staleToken);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    switch (outcome) {
      case TokenRefreshStatus.refreshed:
        final String next = 'fresh-${++_n}';
        if (serverAccepts) backend.validAccess.add(next);
        container.read(authAccessTokenProvider.notifier).state = next;
        return TokenRefreshResult.refreshed(next);
      case TokenRefreshStatus.rejected:
        container.read(authAccessTokenProvider.notifier).state = null;
        return const TokenRefreshResult.rejected();
      case TokenRefreshStatus.unavailable:
        return const TokenRefreshResult.unavailable();
    }
  }
}

class _Harness {
  _Harness({bool withRetry = true, Interceptor? before}) {
    // 'stale' 은 이미 만료된 토큰이다 — 받아 주는 토큰 목록에서 뺀다.
    backend = TokenBackend(access: 'stale')..expireAccessTokens();
    dioProvider = Provider<Dio>((ref) {
      final Dio dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.test/v1',
          validateStatus: (int? s) => s != null && s < 400,
        ),
      );
      dio.httpClientAdapter = backend;
      if (before != null) dio.interceptors.add(before);
      dio.interceptors.add(
        AuthInterceptor(ref, retryClient: withRetry ? dio : null),
      );
      return dio;
    });
    container = ProviderContainer();
    container.read(authAccessTokenProvider.notifier).state = 'stale';
    refresher = _FakeRefresher(container, backend);
    container.read(sessionRefreshBridgeProvider).attach(refresher);
  }

  late final TokenBackend backend;
  late final Provider<Dio> dioProvider;
  late final ProviderContainer container;
  late final _FakeRefresher refresher;

  Dio get dio => container.read(dioProvider);

  void dispose() => container.dispose();
}

/// 이 인터셉터가 [token] 을 붙여 내보낸 요청과 같은 모양.
Options _sentWith(String token) => Options(
  headers: <String, Object?>{'Authorization': 'Bearer $token'},
  extra: <String, Object?>{AuthInterceptor.sessionTokenExtra: token},
);

Matcher _statusIs(int code) => isA<DioException>().having(
  (DioException e) => e.response?.statusCode,
  'status',
  code,
);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('정상 요청', () {
    test('세션 토큰을 붙이고, 유효하면 갱신하지 않는다', () async {
      h.backend.validAccess.add('stale');
      final Response<Object?> res = await h.dio.get<Object?>('/data/1');

      expect(res.statusCode, 200);
      expect(h.backend.requests.single.bearer, 'stale');
      expect(
        h.backend.requests.single.extra[AuthInterceptor.sessionTokenExtra],
        'stale',
      );
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('401 이 아닌 실패(403·404·500)는 갱신하지 않고 그대로 넘긴다', () async {
      h.backend.validAccess.add('stale');
      await expectLater(
        h.dio.get<Object?>('/data/missing'),
        throwsA(_statusIs(404)),
      );
      await expectLater(
        h.dio.get<Object?>('/data/broken'),
        throwsA(_statusIs(500)),
      );
      expect(h.refresher.staleTokens, isEmpty);
    });
  });

  group('401 → 갱신 → 재시도', () {
    test('만료된 토큰이면 한 번 갱신하고 새 토큰으로 원 요청을 다시 보낸다', () async {
      final Response<Object?> res = await h.dio.get<Object?>('/data/1');

      expect(res.statusCode, 200);
      expect((res.data! as Map<String, Object?>)['token'], 'fresh-1');
      expect(h.refresher.staleTokens, <String>['stale']);
      final List<RecordedRequest> sent = h.backend.requestsTo('/data/1');
      expect(sent.map((RecordedRequest r) => r.bearer), <String?>[
        'stale',
        'fresh-1',
      ]);
      expect(sent.last.extra[AuthInterceptor.retriedExtra], isTrue);
    });

    test('POST 본문과 쿼리도 그대로 다시 보낸다', () async {
      final Response<Object?> res = await h.dio.post<Object?>(
        '/data/save',
        data: <String, Object?>{'kcal': 420},
        queryParameters: <String, Object?>{'day': '2026-09-27'},
      );
      expect(res.statusCode, 200);
      final List<RecordedRequest> sent = h.backend.requestsTo('/data/save');
      expect(sent, hasLength(2));
      expect(sent.every((RecordedRequest r) => r.method == 'POST'), isTrue);
    });

    test('multipart 본문은 복제해 다시 보낸다', () async {
      final FormData form = FormData.fromMap(<String, Object?>{
        'note': '점심',
        'photo': MultipartFile.fromBytes(<int>[1, 2, 3], filename: 'a.jpg'),
      });
      final Response<Object?> res = await h.dio.post<Object?>(
        '/data/upload',
        data: form,
      );
      expect(res.statusCode, 200);
      expect(h.backend.requestsTo('/data/upload'), hasLength(2));
    });

    test('동시에 401 을 받은 요청들은 갱신을 한 번만 부른다', () async {
      h.refresher.delay = const Duration(milliseconds: 30);
      final List<Response<Object?>> all = await Future.wait(
        <Future<Response<Object?>>>[
          for (int i = 0; i < 5; i++) h.dio.get<Object?>('/data/$i'),
        ],
      );

      expect(h.refresher.staleTokens, <String>['stale']);
      for (final Response<Object?> res in all) {
        expect((res.data! as Map<String, Object?>)['token'], 'fresh-1');
      }
    });

    test('다른 요청이 이미 회전했다면 갱신 없이 지금 토큰으로 다시 보낸다', () async {
      // 옛 토큰으로 나간 요청의 401 이 회전이 끝난 뒤에 도착한 경우.
      h.backend.validAccess.add('already-fresh');
      h.container.read(authAccessTokenProvider.notifier).state =
          'already-fresh';
      final Response<Object?> res = await h.dio.get<Object?>(
        '/data/late',
        options: _sentWith('stale'),
      );

      expect((res.data! as Map<String, Object?>)['token'], 'already-fresh');
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('다시 보낸 요청이 또 401 이면 멈춘다 — 루프하지 않는다', () async {
      // 회전은 성공했는데 서버가 새 토큰도 받지 않는다.
      h.refresher.serverAccepts = false;

      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));
      expect(h.backend.requestsTo('/data/1'), hasLength(2));
      expect(h.refresher.staleTokens, hasLength(1));
    });

    test('다시 보낸 요청의 다른 실패(404)는 그 실패로 끝난다', () async {
      final Future<Response<Object?>> call = h.dio.get<Object?>(
        '/data/missing',
      );
      await expectLater(call, throwsA(_statusIs(404)));
      expect(h.refresher.staleTokens, hasLength(1));
    });
  });

  group('갱신하지 못했을 때', () {
    test('갱신이 거부되면 원래 401 을 넘기고 다시 보내지 않는다', () async {
      h.refresher.outcome = TokenRefreshStatus.rejected;
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));

      expect(h.backend.requestsTo('/data/1'), hasLength(1));
      expect(h.container.read(authAccessTokenProvider), isNull);
    });

    test('연결 실패·5xx 로 갱신 못 하면 토큰을 두고 원래 401 을 넘긴다', () async {
      h.refresher.outcome = TokenRefreshStatus.unavailable;
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));

      expect(h.backend.requestsTo('/data/1'), hasLength(1));
      expect(h.container.read(authAccessTokenProvider), 'stale');
    });

    test('갱신기가 붙어 있지 않으면 원래 오류를 그대로 넘긴다', () async {
      h.container.read(sessionRefreshBridgeProvider).detach(h.refresher);
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));
      expect(h.backend.requestsTo('/data/1'), hasLength(1));
    });

    test('그 사이 로그아웃해 토큰이 없으면 갱신하지 않는다', () async {
      h.container.read(authAccessTokenProvider.notifier).state = null;
      await expectLater(
        h.dio.get<Object?>('/data/1', options: _sentWith('stale')),
        throwsA(_statusIs(401)),
      );
      expect(h.refresher.staleTokens, isEmpty);
    });
  });

  group('손대지 않는 요청', () {
    test('/auth/login·/auth/refresh 의 401 은 갱신을 부르지 않는다', () async {
      await expectLater(
        h.dio.post<Object?>('/auth/login', data: <String, Object?>{}),
        throwsA(_statusIs(401)),
      );
      h.backend.refreshMode = RefreshMode.reject401;
      await expectLater(
        h.dio.post<Object?>(
          '/auth/refresh',
          data: <String, Object?>{'refresh_token': 'x'},
        ),
        throwsA(_statusIs(401)),
      );
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('호출부가 직접 헤더를 넣은 요청(복구의 확인 등)은 갱신하지 않는다', () async {
      await expectLater(
        h.dio.get<Object?>(
          '/users/me',
          options: Options(
            headers: <String, Object?>{'Authorization': 'Bearer probe'},
          ),
        ),
        throwsA(_statusIs(401)),
      );
      expect(h.backend.requests.single.bearer, 'probe');
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('세션 토큰이 없으면 헤더도 갱신도 없다', () async {
      h.container.read(authAccessTokenProvider.notifier).state = null;
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));
      expect(h.backend.requests.single.bearer, isNull);
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('스트림 본문은 다시 보낼 수 없어 그대로 넘긴다', () async {
      await expectLater(
        h.dio.post<Object?>(
          '/data/stream',
          data: Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2],
          ]),
          options: Options(headers: <String, Object?>{'Content-Length': 2}),
        ),
        throwsA(_statusIs(401)),
      );
      expect(h.refresher.staleTokens, isEmpty);
    });
  });

  group('기존 동작 유지', () {
    test('다시 보낼 Dio 가 없으면 헤더만 붙인다', () async {
      h.dispose();
      h = _Harness(withRetry: false);
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));
      expect(h.backend.requests.single.bearer, 'stale');
      expect(h.refresher.staleTokens, isEmpty);
    });

    test('목업 인터셉터가 먼저 끝낸 요청의 401 은 갱신하지 않는다', () async {
      // LocalApiInterceptor 처럼 인증 인터셉터보다 앞에서 요청을 끝내는 경우 —
      // 세션 토큰을 붙이기 전이라 이 인터셉터가 붙인 토큰에 대한 401 이 아니다.
      h.dispose();
      h = _Harness(
        before: InterceptorsWrapper(
          onRequest: (RequestOptions o, RequestInterceptorHandler handler) {
            handler.reject(
              DioException.badResponse(
                statusCode: 401,
                requestOptions: o,
                response: Response<Object?>(requestOptions: o, statusCode: 401),
              ),
              true,
            );
          },
        ),
      );
      await expectLater(h.dio.get<Object?>('/data/1'), throwsA(_statusIs(401)));
      expect(h.backend.requests, isEmpty);
      expect(h.refresher.staleTokens, isEmpty);
    });
  });
}
