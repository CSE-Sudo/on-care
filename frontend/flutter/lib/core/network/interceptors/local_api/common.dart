// 경로 묶음이 함께 쓰는 응답·요청·날짜 헬퍼와 서버 상태 경로(/ping, /healthz, /version).

part of '../local_api_interceptor.dart';

extension _LocalApiCommon on LocalApiInterceptor {
  Response<Object?> _created(RequestOptions options, Object? body) =>
      Response<Object?>(requestOptions: options, statusCode: 201, data: body);

  Future<Response<Object?>> _ping(RequestOptions options) async {
    return _ok(options, <String, Object?>{'message': 'pong (local)'});
  }

  Future<Response<Object?>> _healthz(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'status': 'ok',
      'backend': 'drift-local',
      // 서버 응답과 같은 키(#3029). 목업 빌드에는 배포 커밋이 없다.
      'commit_sha': 'unknown',
    });
  }

  /// 실서버 `/version` 과 같은 모양(#3045). 데모에는 최소 지원 버전이 없다 —
  /// 데모 빌드는 업데이트 화면으로 막지 않는다. `app_version` 은 서버 버전
  /// 자리라 데모 백엔드 이름을 둔다(예전의 앱 버전 같은 고정 숫자는 걷었다).
  Future<Response<Object?>> _version(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'api_version': 'v1',
      'app_version': '0.2.0+2',
      'min_app_version': null,
      'commit_sha': 'unknown',
    });
  }

  String _todayDateString() {
    return wireDate(nowKst());
  }

  bool _isDateString(String value) => parseWireDate(value) != null;

  /// `?from=`·`?to=` 의 날짜. 없거나 형식이 깨지면 null.
  DateTime? _queryDate(RequestOptions options, String key) {
    final Object? raw = options.queryParameters[key];
    if (raw is! String || !_isDateString(raw)) return null;
    final DateTime parsed = DateTime.parse(raw);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _mondayOfThisWeekString() => _mondayOf(nowKst());

  /// `YYYY-MM-DD` 가 속한 주의 월요일. FastAPI `monday_of_str` 과 같은 규칙이다.
  /// 형식은 호출 전에 검사한다([_isDateString]).
  String _mondayOfString(String date) => _mondayOf(DateTime.parse(date));

  String _mondayOf(DateTime d) => wireDate(mondayOf(d));

  /// Parse a request body (JSON Map or raw String) into a Map.
  Map<String, Object?> _jsonBody(RequestOptions options) {
    final body = options.data;
    if (body is Map) return body.cast<String, Object?>();
    if (body is String && body.isNotEmpty) {
      return (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  /// Build a 200 OK response carrying [body]. Subclasses of handlers
  /// will build their bodies as plain Map/List structures (snake_case)
  /// before passing in.
  Response<Object?> _ok(RequestOptions options, Object? body) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: body,
    );
  }

  Response<Object?> _badRequest(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 400,
      data: <String, Object?>{'code': 'bad_request', 'message': message},
    );
  }

  /// 형식이 잘못된 값. FastAPI 의 검증 실패와 같은 422 를 쓴다 — 두 구현이
  /// 같은 요청에 다른 상태 코드를 주면 클라이언트가 갈린다.
  Response<Object?> _unprocessable(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 422,
      data: <String, Object?>{'code': 'unprocessable', 'message': message},
    );
  }

  /// 서버 전체 AI 하루 상한(#3032) — 실서버 `ai_call_errors` 와 같은 503 본문.
  /// 다음 자정까지 남은 초 대신 고정 값을 싣는다(목업은 시각을 흉내 내지 않는다).
  Response<Object?> _aiCapacity(RequestOptions options) {
    final bool english = _prefersEnglish(options);
    return Response<Object?>(
      requestOptions: options,
      statusCode: 503,
      headers: Headers.fromMap(<String, List<String>>{
        'retry-after': <String>['3600'],
      }),
      data: <String, Object?>{
        'detail': <String, Object?>{
          'code': 'ai_capacity',
          'message': english
              ? 'AI features are taking a break due to high demand. Please try again tomorrow.'
              : '지금은 AI 기능 이용이 많아 잠시 쉬어요. 내일 다시 이용해 주세요.',
        },
      },
    );
  }

  Response<Object?> _notFound(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 404,
      data: <String, Object?>{'code': 'not_found', 'message': message},
    );
  }
}

/// 요청의 화면 언어 — `Accept-Language` 가 영어면 `en`, 아니면 `ko`.
/// 서버 `core.locale` 처럼 지원하지 않는 언어는 한국어로 떨어진다.
String _requestLang(RequestOptions options) {
  final Object? header = options.headers['Accept-Language'];
  return header is String && header.trim().toLowerCase().startsWith('en')
      ? 'en'
      : 'ko';
}

const List<String> _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 요청 몸통을 Map 으로. dio 는 Map 으로도 JSON 문자열로도 준다.
Map<String, Object?> _payloadOf(Object? body) {
  if (body is Map) return body.cast<String, Object?>();
  if (body is String && body.isNotEmpty) {
    return (jsonDecode(body) as Map<Object?, Object?>).cast<String, Object?>();
  }
  return <String, Object?>{};
}

/// 요청 언어가 영어인가 — 실서버가 `Accept-Language` 로 고르는 것과 같다.
bool _prefersEnglish(RequestOptions options) {
  final Object? lang = options.headers['Accept-Language'];
  return lang is String && lang.toLowerCase().startsWith('en');
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _minDate(DateTime a, DateTime b) => a.isAfter(b) ? b : a;
