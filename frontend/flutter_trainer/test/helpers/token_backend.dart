/// 접근 토큰 만료·갱신을 흉내 내는 가짜 서버. (#1546)
///
/// 실제 서버처럼 갱신 토큰은 **일회용**이다 — 이미 회전에 쓴 토큰이 다시 오면
/// 401 로 거부한다. 그래서 동시 401 이 갱신을 두 번 부르면 두 번째가 거부되어
/// 세션이 끝나는 회귀를 그대로 드러낸다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// `/auth/refresh` 가 답하는 방식.
enum RefreshMode {
  /// 새 접근·갱신 토큰을 준다.
  rotate,

  /// 새 접근 토큰만 주고 갱신 토큰은 주지 않는다.
  rotateAccessOnly,

  /// 200 인데 접근 토큰이 비었다.
  emptyAccess,

  /// 401 로 거부한다.
  reject401,

  /// 403 으로 거부한다.
  reject403,

  /// 500 으로 실패한다.
  serverError,

  /// 연결이 끊긴다.
  offline,
}

/// 요청 한 건의 기록.
class RecordedRequest {
  const RecordedRequest(this.method, this.path, this.bearer, this.extra);

  final String method;
  final String path;
  final String? bearer;
  final Map<String, Object?> extra;
}

class TokenBackend implements HttpClientAdapter {
  TokenBackend({
    String access = 'access-0',
    this.currentRefresh = 'refresh-0',
    this.profilePath = '/users/me',
    this.profileBody = const <String, Object?>{'id': 'u1'},
  }) {
    validAccess.add(access);
  }

  /// 세션 확인 경로(트레이너 웹 `/trainer/me`, 회원 앱 `/users/me`).
  final String profilePath;

  /// 세션 확인 응답 본문.
  final Map<String, Object?> profileBody;

  /// 지금 받아 주는 접근 토큰.
  final Set<String> validAccess = <String>{};

  /// 지금 유효한 갱신 토큰. 회전하면 바뀐다.
  String currentRefresh;

  RefreshMode refreshMode = RefreshMode.rotate;

  /// 갱신 응답을 늦춘다 — 동시 401 이 한 번의 갱신을 함께 기다리게.
  Duration refreshDelay = Duration.zero;

  /// 갱신이 끝나기 전에 테스트가 끼어들 수 있게 한다. 주면 이것이 끝나야 답한다.
  Completer<void>? refreshGate;

  /// `/auth/refresh` 가 불린 횟수(성공·실패 모두).
  int refreshCalls = 0;

  /// 갱신 요청이 서버에 도착했다.
  final StreamController<void> _refreshArrived =
      StreamController<void>.broadcast();
  Stream<void> get refreshArrived => _refreshArrived.stream;

  int _rotation = 0;

  /// 나간 요청 기록.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// 이 경로로 나간 요청들.
  List<RecordedRequest> requestsTo(String path) =>
      requests.where((RecordedRequest r) => r.path == path).toList();

  /// 지금 받아 주는 접근 토큰을 모두 만료시킨다.
  void expireAccessTokens() => validAccess.clear();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      // 본문을 끝까지 읽는다 — 다시 보낸 multipart 가 온전한지 본다.
      await requestStream.drain<void>();
    }
    final String path = options.uri.path.replaceFirst(RegExp('^/v1'), '');
    final Object? header = options.headers['Authorization'];
    final String? bearer = header is String && header.startsWith('Bearer ')
        ? header.substring('Bearer '.length)
        : null;
    requests.add(
      RecordedRequest(
        options.method.toUpperCase(),
        path,
        bearer,
        Map<String, Object?>.of(options.extra),
      ),
    );

    if (path == '/auth/refresh') return _handleRefresh(options);
    if (path == '/auth/login') {
      return _json(<String, Object?>{'detail': 'bad credentials'}, 401);
    }
    if (path == '/auth/logout') return _json(null, 204);

    final bool authorized = bearer != null && validAccess.contains(bearer);
    if (!authorized) return _json(<String, Object?>{'detail': 'expired'}, 401);
    if (path == profilePath) return _json(profileBody);
    if (path.endsWith('/missing')) {
      return _json(<String, Object?>{'detail': 'not found'}, 404);
    }
    if (path.endsWith('/broken')) {
      return _json(<String, Object?>{'detail': 'boom'}, 500);
    }
    return _json(<String, Object?>{'path': path, 'token': bearer});
  }

  Future<ResponseBody> _handleRefresh(RequestOptions options) async {
    refreshCalls++;
    _refreshArrived.add(null);
    final Completer<void>? gate = refreshGate;
    if (gate != null) await gate.future;
    if (refreshDelay > Duration.zero) await Future<void>.delayed(refreshDelay);
    final Object? data = options.data;
    final Object? presented = data is Map ? data['refresh_token'] : null;
    switch (refreshMode) {
      case RefreshMode.reject401:
        return _json(<String, Object?>{'detail': 'invalid'}, 401);
      case RefreshMode.reject403:
        return _json(<String, Object?>{'detail': 'forbidden'}, 403);
      case RefreshMode.serverError:
        return _json(<String, Object?>{'detail': 'boom'}, 500);
      case RefreshMode.offline:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      case RefreshMode.emptyAccess:
        return _json(<String, Object?>{'access_token': ''});
      case RefreshMode.rotate:
      case RefreshMode.rotateAccessOnly:
        break;
    }
    // 일회용 — 이미 쓴(또는 모르는) 갱신 토큰은 거부한다.
    if (presented != currentRefresh) {
      return _json(<String, Object?>{'detail': 'reused'}, 401);
    }
    _rotation++;
    final String access = 'access-$_rotation';
    validAccess.add(access);
    if (refreshMode == RefreshMode.rotateAccessOnly) {
      return _json(<String, Object?>{'access_token': access});
    }
    currentRefresh = 'refresh-$_rotation';
    return _json(<String, Object?>{
      'access_token': access,
      'refresh_token': currentRefresh,
    });
  }

  ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {
    unawaited(_refreshArrived.close());
  }
}
