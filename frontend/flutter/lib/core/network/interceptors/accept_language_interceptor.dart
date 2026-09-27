import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/shared/services/locale_provider.dart';

/// 모든 요청에 지금 화면 언어를 `Accept-Language` 로 싣는다(#2297).
///
/// 서버가 만드는 문장(리포트 요약·조언·라벨·AI 추천·알림)은 이 값으로 한국어와
/// 영어를 고른다. 언어는 요청을 보내는 순간 [resolvedLocaleProvider] 에서 읽으므로,
/// 언어가 바뀌면 `Dio` 를 새로 만들지 않아도 다음 요청부터 바로 새 언어가 나간다.
///
/// 호출부가 이미 `Accept-Language` 를 넣었으면 덮지 않는다 — 특정 언어의 응답이
/// 필요한 호출이 직접 고를 수 있게. 트레이너 웹의 같은 인터셉터와 같은 규칙이다.
class AcceptLanguageInterceptor extends Interceptor {
  AcceptLanguageInterceptor(this._ref);

  /// 헤더 이름.
  static const String headerName = 'Accept-Language';

  final Ref _ref;

  /// [locale] 을 헤더 값으로 바꾼다. 서버는 주 언어만 보므로 언어 코드만 보낸다.
  static String headerValue(Locale locale) => locale.languageCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Dio 의 헤더 맵은 대소문자를 가리지 않는다 — `accept-language` 로 넣어도 걸린다.
    if (!options.headers.containsKey(headerName)) {
      options.headers[headerName] = headerValue(
        _ref.read(resolvedLocaleProvider),
      );
    }
    handler.next(options);
  }
}
